#!/bin/bash
# Reel.app notarization 스크립트
# 사용법: ./scripts/notarize.sh <path-to-Reel.app>
#
# 사전 준비:
#   1. Apple Developer 계정 (Developer ID 인증서 필요)
#   2. keychain에 "Developer ID Application: waylake" 인증서 추가
#   3. 애플리케이션 패스워드 생성: https://appleid.apple.com → App-Specific Passwords
#   4. 환경변수 설정:
#      export ASC_PROVIDER_KEY="your-team-id"
#      export ASC_API_KEY="your-api-key-id"
#      export ASC_API_KEY_SECRET="your-api-key-secret"
#      또는: export APPLE_ID="email@domain.com" APPLE_ID_PASSWORD="app-specific-password"

set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "❌ 사용법: $0 <path-to-Reel.app>"
    exit 1
fi

echo "🔐 Reel.app 서명 및 노타리제이션 중..."

# 1) 코드 서명 (Developer ID Application)
echo "  ① 코드 서명 중..."
codesign --force --deep --sign "Developer ID Application: waylake" \
    --options runtime \
    --timestamp \
    "$APP_PATH"

echo "  ✓ 서명 완료"

# 2) .zip 압축 (notarytool 요구사항)
ZIP_PATH="${APP_PATH%.app}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "  ② 압축 완료: $ZIP_PATH"

# 3) 노타리제이션 제출
echo "  ③ 노타리제이션 제출 중..."

if [[ -n "${ASC_API_KEY:-}" && -n "${ASC_API_KEY_SECRET:-}" ]]; then
    # API 키 방식 (권장)
    xcrun notarytool submit "$ZIP_PATH" \
        --key "$ASC_API_KEY" \
        --key-id "${ASC_API_KEY_ID:-}" \
        --issuer "${ASC_ISSUER:-}" \
        --wait
else
    # Apple ID + 패스워드 방식
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "${ASC_PROVIDER_KEY:-}" \
        --wait
fi

echo "  ✓ 노타리제이션 통과"

# 4) 스탬프 찍기
echo "  ④ 노타리제이션 스탬프 적용 중..."
xcrun stapler staple "$APP_PATH"
echo "  ✓ 스탬프 완료"

# 5) 검증
echo "  ⑤ 최종 검증..."
codesign -vv --deep --strict "$APP_PATH"
echo ""
echo "✅ Reel.app 배포 준비 완료!"
echo "   → GitHub Releases / 웹사이트에 $APP_PATH를 업로드하세요."
