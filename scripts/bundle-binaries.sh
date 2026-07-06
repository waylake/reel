#!/bin/bash
# yt-dlp + ffmpeg 바이너리를 Reel.app/Contents/Resources/에 번들
#
# 사용법:
#   ./scripts/bundle-binaries.sh                  (DerivedData 자동 탐색)
#   BUILT_PRODUCTS_DIR=... ./scripts/bundle-binaries.sh
#
# 이 스크립트는 배포 빌드 후 실행합니다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

APP_DIR="${BUILT_PRODUCTS_DIR:-}"
if [[ -z "$APP_DIR" ]]; then
    # DerivedData에서 탐색 (프로젝트 상대 경로 우선)
    if [[ -d "$PROJECT_DIR/DerivedData" ]]; then
        APP_DIR=$(find "$PROJECT_DIR/DerivedData" -name "Reel.app" \( -path "*/Products/Release/*" -o -path "*/Products/Debug/*" \) 2>/dev/null | head -1)
    fi
    # 없으면 전역 DerivedData 탐색
    if [[ -z "$APP_DIR" ]]; then
        APP_DIR=$(find ~/Library/Developer/Xcode/DerivedData -name "Reel.app" \( -path "*/Products/Release/*" -o -path "*/Products/Debug/*" \) 2>/dev/null | head -1)
    fi
    if [[ -z "$APP_DIR" ]]; then
        echo "❌ Reel.app을 찾을 수 없습니다. 먼저 빌드하세요."
        exit 1
    fi
fi

RESOURCES_DIR="$APP_DIR/Contents/Resources"
mkdir -p "$RESOURCES_DIR"

echo "📦 바이너리 번들 → $RESOURCES_DIR"

# ─── yt-dlp (macOS 스탠드얼론 Universal 바이너리) ───
echo "  ⏳ yt-dlp_macos 다운로드 중..."
curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
    -o "$RESOURCES_DIR/yt-dlp"
chmod +x "$RESOURCES_DIR/yt-dlp"
YTDLP_VER=$("$RESOURCES_DIR/yt-dlp" --version 2>/dev/null || echo "unknown")
echo "  ✓ yt-dlp $YTDLP_VER (standalone universal)"

# ─── ffmpeg (macOS arm64 정적 빌드) ───
echo "  ⏳ ffmpeg 다운로드 중..."

FFMPEG_OK=false

# 1) eugeneware/ffmpeg-static (npm/GitHub releases — 가장 안정적)
if curl -fsSL "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-arm64" \
    -o "$RESOURCES_DIR/ffmpeg" 2>/dev/null; then
    chmod +x "$RESOURCES_DIR/ffmpeg"
    if "$RESOURCES_DIR/ffmpeg" -version &>/dev/null; then
        FFMPEG_OK=true
    fi
fi

# 2) fallback: shinnn/ffmpeg-static
if [[ "$FFMPEG_OK" != "true" ]]; then
    for URL in \
        "https://github.com/shinnn/ffmpeg-static/releases/latest/download/ffmpeg-macos-arm64"; do
        if curl -fsSL "$URL" -o "$RESOURCES_DIR/ffmpeg" 2>/dev/null; then
            chmod +x "$RESOURCES_DIR/ffmpeg"
            if "$RESOURCES_DIR/ffmpeg" -version &>/dev/null; then
                FFMPEG_OK=true
                break
            fi
        fi
    done
fi

# 3) fallback: Homebrew ffmpeg (동적 의존성 — 로컬 개발용)
if [[ "$FFMPEG_OK" != "true" ]]; then
    echo "  ⚠ 정적 ffmpeg 다운로드 실패. Homebrew ffmpeg 복사 (동적 의존성 있음)"
    if command -v ffmpeg &>/dev/null; then
        FFMPEG_PATH=$(which ffmpeg)
        cp "$FFMPEG_PATH" "$RESOURCES_DIR/ffmpeg"
        chmod +x "$RESOURCES_DIR/ffmpeg"

        # 의존 라이브러리도 복사
        LIB_DIR="$RESOURCES_DIR/lib"
        mkdir -p "$LIB_DIR"
        otool -L "$RESOURCES_DIR/ffmpeg" 2>/dev/null | \
            grep -E "\.dylib" | awk '{print $1}' | \
            grep -v "^$" | while read -r lib; do
            if [[ -f "$lib" ]]; then
                cp -n "$lib" "$LIB_DIR/" 2>/dev/null || true
            fi
        done
        # @loader_path 수정
        if command -v install_name_tool &>/dev/null; then
            otool -L "$RESOURCES_DIR/ffmpeg" 2>/dev/null | \
                grep -E "\.dylib" | awk '{print $1}' | \
                grep -v "^$" | while read -r lib; do
                base=$(basename "$lib")
                if [[ -f "$LIB_DIR/$base" ]]; then
                    install_name_tool -change "$lib" "@loader_path/lib/$base" "$RESOURCES_DIR/ffmpeg" 2>/dev/null || true
                fi
            done
        fi
    else
        echo "  ❌ ffmpeg를 찾을 수 없습니다. brew install ffmpeg"
        exit 1
    fi
fi

FF_VER=$("$RESOURCES_DIR/ffmpeg" -version 2>/dev/null | head -1 || echo "unknown")
echo "  ✓ $FF_VER"

echo ""
echo "✅ 번들 완료:"
ls -lh "$RESOURCES_DIR/yt-dlp" "$RESOURCES_DIR/ffmpeg"
echo ""
echo "   BinaryResolver가 번들본을 우선 사용합니다."
