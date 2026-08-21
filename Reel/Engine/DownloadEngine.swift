import Foundation

/// yt-dlp 프로세스를 실행/관리하는 actor. 실행 중인 프로세스를 id로 추적해 취소/일시정지한다.
actor DownloadEngine {
    private var processes: [UUID: Process] = [:]

    // MARK: - 메타데이터 프리페치

    func fetchMetadata(url: String) async throws -> MediaMetadata {
        guard let bin = BinaryResolver.ytdlp else { throw EngineError.ytdlpNotFound }
        let result = try await runCapturing(bin: bin, args: ArgumentBuilder.metadataArgs(url: url))
        guard result.code == 0 else {
            let msg = result.stderr.isEmpty ? "종료 코드 \(result.code)" : result.stderr
            throw EngineError.metadataFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let data = result.stdout.data(using: .utf8),
              let meta = MediaMetadata(jsonData: data) else {
            throw EngineError.metadataFailed("JSON 파싱 실패")
        }
        return meta
    }

    // MARK: - 플레이리스트 정보

    /// 링크가 플레이리스트인지 판별하고, 항목 목록을 가져온다.
    /// 단일 영상이면 isPlaylist == false, entries는 비어 있다.
    func fetchPlaylistInfo(url: String) async throws -> MediaMetadata.PlaylistInfo {
        guard let bin = BinaryResolver.ytdlp else { throw EngineError.ytdlpNotFound }
        let result = try await runCapturing(bin: bin, args: ArgumentBuilder.playlistArgs(url: url))
        guard result.code == 0, let data = result.stdout.data(using: .utf8) else {
            let msg = result.stderr.isEmpty ? "종료 코드 \(result.code)" : result.stderr
            throw EngineError.metadataFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let info = MediaMetadata.playlistInfo(from: data) else {
            throw EngineError.metadataFailed("플레이리스트 정보 파싱 실패")
        }
        return info
    }

    // MARK: - yt-dlp 버전 / 업데이트

    /// 현재 yt-dlp 버전 문자열 (첫 줄). 없으면 nil.
    func ytdlpVersion() async -> String? {
        guard let bin = BinaryResolver.ytdlp else { return nil }
        guard let result = try? await runCapturing(bin: bin, args: ["--version"]) else { return nil }
        return result.stdout.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    /// yt-dlp 자체 업데이트.
    /// - Homebrew 등 쓰기 가능한 설치: `yt-dlp -U` 시도
    /// - 앱 번들 포함본 또는 `-U` 실패: GitHub 최신 릴리스를 받아
    ///   Application Support/Reel/bin 에 자체 관리본으로 설치.
    ///   BinaryResolver가 관리본을 최우선 사용하므로 재시작 없이 즉시 적용된다.
    /// - Returns: (성공 여부, 사용자에게 보여줄 메시지)
    func updateYtdlp() async -> (ok: Bool, message: String) {
        guard let bin = BinaryResolver.ytdlp else {
            return (false, "yt-dlp를 찾을 수 없습니다.")
        }
        if !BinaryResolver.isBundled {
            let result = try? await runCapturing(bin: bin, args: ["-U"])
            if let result, result.code == 0 {
                let out = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
                let ok = out.contains("up to date") || out.contains("Updated")
                let message = out.isEmpty ? (ok ? "최신 상태입니다." : "종료 코드 \(result.code)") : out
                if ok { return (true, message) }
            }
            // -U 실패(패키지 관리자 설치 등) — 관리본 설치로 폴백
        }
        return await installManagedYtdlp()
    }

    /// GitHub 최신 yt-dlp(macOS Universal)를 받아 자체 관리 경로에 설치.
    /// 유튜브 추출기는 앱 릴리즈 주기보다 빨리 낡기 때문에(봇 방지 대응),
    /// 번들본이 구버전이어도 이 경로로 즉시 최신화한다.
    private func installManagedYtdlp() async -> (ok: Bool, message: String) {
        guard let releaseURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos") else {
            return (false, "다운로드 URL 구성 실패")
        }
        let dest = BinaryResolver.managedDir.appending(path: "yt-dlp")
        do {
            let (data, response) = try await URLSession.shared.data(from: releaseURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw EngineError.updateFailed("다운로드 실패 (HTTP \(code))")
            }
            try FileManager.default.createDirectory(at: BinaryResolver.managedDir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest) // 기존 관리본 교체
            try data.write(to: dest, options: .atomic) // 단독 바이너리(~37MB)라도 일괄 수신 후 원자적 기록
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)

            // 정상 실행 검증 — 실패하면 롤백해 기존 바이너리를 지킨다
            guard let check = try? await runCapturing(bin: dest, args: ["--version"]), check.code == 0 else {
                try? FileManager.default.removeItem(at: dest)
                return (false, "내려받은 yt-dlp가 정상 실행되지 않아 설치를 되돌렸습니다.")
            }
            let ver = check.stdout.split(whereSeparator: \.isNewline).first.map(String.init) ?? "?"
            return (true, "yt-dlp \(ver)(으)로 업데이트했어요. 바로 적용됩니다.")
        } catch {
            return (false, "업데이트 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - 지원 사이트(추출기) 목록

    /// 설치된 yt-dlp가 지원하는 추출기 ID 목록. 항상 현재 버전 기준.
    func listExtractors() async -> [String] {
        guard let bin = BinaryResolver.ytdlp else { return [] }
        guard let result = try? await runCapturing(bin: bin, args: ["--ignore-config", "--list-extractors"]) else {
            return []
        }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - 다운로드 이벤트 스트림

    func events(id: UUID, url: String, options: DownloadOptions) -> AsyncStream<EngineEvent> {
        AsyncStream { continuation in
            guard let bin = BinaryResolver.ytdlp else {
                continuation.yield(.failed(EngineError.ytdlpNotFound.localizedDescription))
                continuation.finish()
                return
            }

            let process = Process()
            process.executableURL = bin
            process.arguments = ArgumentBuilder.downloadArgs(url: url, options: options)
            process.qualityOfService = .userInitiated

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let errTail = ErrorTail()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.split(whereSeparator: \.isNewline) {
                    for event in ProgressParser.parse(line: String(line)) {
                        continuation.yield(event)
                    }
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    errTail.append(text)
                }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // 남은 출력 드레인
                let rest = outPipe.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: rest, encoding: .utf8) {
                    for line in text.split(whereSeparator: \.isNewline) {
                        for event in ProgressParser.parse(line: String(line)) {
                            continuation.yield(event)
                        }
                    }
                }
                _ = errPipe.fileHandleForReading.readDataToEndOfFile()

                switch proc.terminationReason {
                case .exit where proc.terminationStatus == 0:
                    continuation.yield(.completed)
                case .uncaughtSignal:
                    continuation.yield(.cancelled)
                default:
                    let tail = errTail.value
                    continuation.yield(.failed(tail.isEmpty ? "종료 코드 \(proc.terminationStatus)" : tail))
                }
                continuation.finish()
            }

            self.storeProcess(process, for: id)
            do {
                try process.run()
                continuation.yield(.started)
            } catch {
                continuation.yield(.failed(error.localizedDescription))
                continuation.finish()
                return
            }

            continuation.onTermination = { reason in
                if case .cancelled = reason, process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    // MARK: - 제어

    func cancel(id: UUID) {
        if let p = processes[id], p.isRunning { p.terminate() }
        processes[id] = nil
    }

    func pause(id: UUID) {
        if let p = processes[id], p.isRunning { kill(p.processIdentifier, SIGSTOP) }
    }

    func resume(id: UUID) {
        if let p = processes[id], p.isRunning { kill(p.processIdentifier, SIGCONT) }
    }

    // MARK: - 내부

    private func storeProcess(_ process: Process, for id: UUID) {
        processes[id] = process
        // 종료 시 자동 정리
        let previous = process.terminationHandler
        process.terminationHandler = { [weak self] proc in
            previous?(proc)
            Task { await self?.clear(id: id) }
        }
    }

    private func clear(id: UUID) {
        processes[id] = nil
    }

    /// 짧은 실행(메타데이터 등)의 전체 출력을 캡처. 파이프 버퍼 교착을 피하려 동시 드레인.
    private func runCapturing(bin: URL, args: [String]) async throws
        -> (code: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = bin
            process.arguments = args
            process.qualityOfService = .userInitiated

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let sink = DataSink()
            let queue = DispatchQueue(label: "reel.capture")

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                queue.async { sink.appendOut(d) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                queue.async { sink.appendErr(d) }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let restOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let restErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                queue.async {
                    sink.appendOut(restOut)
                    sink.appendErr(restErr)
                    continuation.resume(returning: (proc.terminationStatus, sink.outString, sink.errString))
                }
            }

            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

/// stderr 마지막 부분만 보관(에러 메시지용). 스레드 안전.
private final class ErrorTail: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    var value: String { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        storage = String((storage + s).suffix(2000))
    }
}

/// 캡처 버퍼. 항상 단일 직렬 큐 위에서만 호출된다.
private final class DataSink: @unchecked Sendable {
    private var out = Data()
    private var err = Data()
    func appendOut(_ d: Data) { out.append(d) }
    func appendErr(_ d: Data) { err.append(d) }
    var outString: String { String(data: out, encoding: .utf8) ?? "" }
    var errString: String { String(data: err, encoding: .utf8) ?? "" }
}
