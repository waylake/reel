# Reel — macOS YouTube Downloader

> 클립보드 링크를 감지하는 메뉴바 YouTube 다운로더. yt-dlp + ffmpeg 기반.

## 핵심 기능

- **📋 클립보드 자동 감지** — 링크만 복사하면 메뉴바에서 감지
- **⚡ 빠른 다운로드** — yt-dlp 기반, 동시 최대 6개 다운로드
- **🎵 오디오 추출** — MP3, M4A 프리셋 지원
- **🌐 1,800+ 사이트** — YouTube, Vimeo, TikTok, Twitter, Instagram 등
- **🔇 SponsorBlock** — 스폰서/자기홍보 구간 자동 제거
- **🌙 자막 임베드** — 다국어 자막 + 자동 생성 자막 지원
- **📊 진행률 표시** — 속도, 남은 시간, 용량 실시간 표시
- **💾 큐 영속화** — 앱 재시작 시 대기 항목 자동 복원

## 시스템 요구사항

- macOS 14+ (Sonoma 이상)
- Apple Silicon (M1/M2/M3/M4) 또는 Intel (Rosetta 2)

## 설치

1. [Gumroad](https://gumroad.com/l/reel)에서 Reel.app.zip 다운로드
2. zip 압축 해제
3. Reel.app을 Applications 폴더로 이동
4. Reel.app 실행 (메뉴바에 ↓ 아이콘 나타남)

## 사용법

1. 브라우저에서 영상 링크 복사 (⌘C)
2. 메뉴바 Reel 아이콘 클릭 → 감지된 링크가 자동으로 나타남
3. "추가" 클릭 또는 텍스트 필드에 직접 붙여넣기
4. 다운로드 완료 시 알림

## 프리셋

| 프리셋 | 설명 |
|--------|------|
| 최고 화질 (MP4) | 원본 최고 화질, 무손실 MP4 리메이크 |
| 1080p (호환성) | 1080p 제한, H.264 우선 |
| 오디오만 · MP3 | 오디오만 추출, MP3 인코딩 |
| 오디오만 · M4A | 오디오만 추출, 원본 AAC 유지 |
| 원본 그대로 | 포맷 변환 없음 |

## 개발

```bash
# 의존성 설치
brew install yt-dlp ffmpeg

# 프로젝트 생성
xcodegen generate

# 빌드
open Reel.xcodeproj
```

## 릴리즈 빌드

```bash
./scripts/build-release.sh
# → Reel.app.zip 생성
```

## 개인정보 처리방침

Reel은 모든 데이터를 로컬에서만 보관합니다. 외부 서버로 데이터를 전송하지 않습니다.
자세한 내용: [PRIVACY.md](PRIVACY.md)

## 라이선스

Reel은闭源 상용 소프트웨어입니다. 소스 코드는 개발 참고용으로만 공개됩니다.

© 2026 waylake
