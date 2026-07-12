#!/bin/bash
# Reel 릴리즈 빌드
# Developer ID 없이도 GitHub Releases 배포 가능 (zip → Gatekeeper 우회)
#
# 2026.06 기준: ad-hoc 서명(--sign -)이 필수입니다.
# 서명 없이 빌드하면 macOS 14+에서 "손상됨" 오류가 나며 우회 불가합니다.
# ad-hoc 서명은 무료이며 Apple Developer 계정이 필요 없습니다.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🏗️ Reel 릴리즈 빌드 시작..."

# 1) XcodeGen으로 프로젝트 재생성
echo "  ① 프로젝트 생성 중..."
xcodegen generate

# 2) Release 빌드 (ad-hoc 서명 — Xcode가 기본 Mach-O 서명)
echo "  ② Release 빌드 중..."
xcodebuild clean build \
    -project Reel.xcodeproj \
    -scheme Reel \
    -configuration Release \
    -derivedDataPath DerivedData \
    CODE_SIGN_IDENTITY="-" \
    ENABLE_HARDENED_RUNTIME=NO \
    CODE_SIGNING_REQUIRED=NO

# 3) 빌드 결과 위치
APP_PATH="DerivedData/Build/Products/Release/Reel.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ 빌드 실패: $APP_PATH를 찾을 수 없습니다."
    exit 1
fi

# 4) 바이너리 번들
echo "  ③ 바이너리 번들 중..."
./scripts/bundle-binaries.sh

# 5) ad-hoc 서명 (번들 전체 sealed — Gatekeeper 우회 핵심)
echo "  ④ ad-hoc 서명 중..."
# yt-dlp/ffmpeg를 번들한 후 번들 전체를 다시 서명해야 합니다.
# --deep: 내재된 모든 Mach-O 재서명
# --force: 기존 서명 덮어쓰기
# --timestamp=none: Apple 타임스탬프 서버 불필요 (ad-hoc)
codesign --force --deep --sign - --timestamp=none "$APP_PATH"

# 서명 검증
codesign --verify --deep --strict "$APP_PATH" 2>&1 && echo "  ✓ 서명 검증 통과"

# 6) quarantine/provenance 속성 제거
echo "  ⑤ 속성 정리 중..."
xattr -rd com.apple.quarantine "$APP_PATH" 2>/dev/null || true
xattr -rd com.apple.provenance "$APP_PATH" 2>/dev/null || true

# 7) zip 압축
echo "  ⑥ 배포 패키지 생성 중..."
rm -f Reel.app.zip
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "Reel.app.zip"

# 8) 크기 확인
APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
ZIP_SIZE=$(du -sh Reel.app.zip | cut -f1)

echo ""
echo "✅ 릴리즈 빌드 완료!"
echo "   앱: $APP_PATH ($APP_SIZE)"
echo "   배포: Reel.app.zip ($ZIP_SIZE)"
echo ""
echo "📋 다음 단계:"
echo "   1. Reel.app.zip을 GitHub Releases에 업로드"
echo "   2. 설치 가이드: '압축 해제 후 Reel.app 실행'"
echo ""
echo "💡 ad-hoc 서명된 앱의 첫 실행:"
echo "   - 우클릭 → 열기 → 확인 (한 번만 필요)"
echo "   - 또는 터미널: xattr -cr /Applications/Reel.app"
echo ""
echo "🔮 추후 Apple Developer 계정 (\$99/년) 구매 시:"
echo "   ./scripts/notarize.sh $APP_PATH → dmg 배포 + Gatekeeper 없음"
