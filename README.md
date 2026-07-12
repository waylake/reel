# Reel — macOS YouTube Downloader

클립보드 링크를 감지하는 메뉴바 다운로더. yt-dlp + ffmpeg 기반.

## 기능

- **클립보드 자동 감지** — 브라우저에서 링크를 복사하면 메뉴바가 인식한다. 수동 입력 불필요.
- **동시 다운로드** — 최대 6개까지 병렬 처리. 저전력 프로필로 배터리 사용량을 줄일 수 있다.
- **오디오 추출** — MP3, M4A 프리셋. 팟캐스트, 음악, 강의 영상 모두 지원.
- **1,800개 이상 사이트 지원** — YouTube, Vimeo, TikTok, X, Instagram, Reddit 등 yt-dlp가 지원하는 모든 플랫폼.
- **SponsorBlock** — 스폰서·자기홍보 구간을 자동으로 건너뛴다.
- **자막 임베드** — 다국어 자막과 자동 생성 자막을 영상에 포함한다.
- **진행률 표시** — 속도, 남은 시간, 파일 크기를 실시간으로 보여준다.
- **큐 영속화** — 앱을 재시작해도 대기 중이던 항목을 그대로 복원한다.
- **재생목록(Playlist) 지원** — 단일 영상뿐만 아니라 재생목록 전체를 한 번에 다운로드할 수 있다.
- **앱 내 자체 엔진 업데이트** — 최신 사이트 변경에 대응하기 위해 앱 내에서 yt-dlp 버전을 확인하고 업데이트할 수 있다.
- **다운로드 통계 및 자동 정리** — 다운로드 통계를 제공하고 설정한 기간이 지난 완료 항목을 자동으로 정리한다.

## 시스템 요구사항

- macOS 14 이상 (Sonoma)
- Apple Silicon 또는 Intel (Rosetta 2)

## 설치

Github Releases에서 최신 `Reel.app.zip`을 다운로드하거나 직접 소스에서 빌드할 수 있다.

1. 압축 해제 후 `Reel.app`을 Applications 폴더로 이동
2. 실행 — 메뉴바에 ↓ 아이콘이 나타난다

## 사용법

1. 브라우저에서 영상 링크 복사 (⌘C)
2. 메뉴바 Reel 아이콘 클릭 — 감지된 링크가 자동으로 표시된다
3. 추가 버튼을 누르거나 텍스트 필드에 직접 붙여넣기
4. 완료 시 알림

## 프리셋

| 프리셋 | 설명 |
|--------|------|
| 최고 화질 (MP4) | 원본 최고 화질, 무손실 MP4 리먹싱 |
| 1080p (호환성) | 1080p 제한, H.264 우선 |
| 오디오 · MP3 | 오디오만 추출, MP3 인코딩 |
| 오디오 · M4A | 오디오만 추출, AAC 원본 유지 |
| 원본 그대로 | 포맷 변환 없음 |

## 개발

```bash
brew install yt-dlp ffmpeg
xcodegen generate
open Reel.xcodeproj
```

## 배포 및 자동 업데이트 (CI/CD)

Reel은 **Sparkle 2** 프레임워크를 통해 앱 내 자동 업데이트를 지원하며, 배포 파이프라인은 GitHub Actions로 완전히 자동화되어 있습니다.

1. `v1.x.x` 형식의 태그를 Push하면 `.github/workflows/release.yml` 파이프라인이 실행됩니다.
2. `scripts/build-release.sh`를 통해 릴리즈 빌드 및 `.app.zip` 압축본을 생성합니다.
3. Sparkle의 `generate_appcast`를 사용해 EdDSA 서명된 `appcast.xml` 피드를 자동 생성합니다.
4. 생성된 바이너리와 피드 파일이 GitHub Releases에 업로드되며, 기존 설치된 앱에 자동으로 업데이트가 푸시됩니다.

> **참고**: Sparkle 자동 업데이트 서명에 사용되는 개인키는 GitHub Repository Secrets의 `SPARKLE_PRIVATE_KEY`에 저장되어 안전하게 관리됩니다.

## 개인정보

Reel은 모든 데이터를 기기 내에서만 보관한다. 외부 서버로 데이터를 전송하지 않는다.
자세한 내용은 [PRIVACY.md](PRIVACY.md) 참고.

## 라이선스

Reel은 MIT 라이선스를 따르는 오픈소스 소프트웨어다.
자세한 내용은 [LICENSE.md](LICENSE.md) 참고.

© 2026 waylake
