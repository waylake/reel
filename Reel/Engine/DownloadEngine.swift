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
