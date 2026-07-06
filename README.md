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

## 시스템 요구사항

- macOS 14 이상 (Sonoma)
- Apple Silicon 또는 Intel (Rosetta 2)

## 설치

1. [Gumroad](https://gumroad.com/l/reel)에서 `Reel.app.zip` 다운로드
2. 압축 해제 후 `Reel.app`을 Applications 폴더로 이동
3. 실행 — 메뉴바에 ↓ 아이콘이 나타난다

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

## 릴리즈 빌드

```bash
./scripts/build-release.sh
# → Reel.app.zip
```

## 개인정보

Reel은 모든 데이터를 기기 내에서만 보관한다. 외부 서버로 데이터를 전송하지 않는다.
자세한 내용은 [PRIVACY.md](PRIVACY.md) 참고.

## 라이선스

Reel은 클로즈드 소스 상용 소프트웨어다. 소스 코드는 개발 참고용으로 공개된다.
자세한 내용은 [LICENSE.md](LICENSE.md) 참고.

© 2026 waylake
