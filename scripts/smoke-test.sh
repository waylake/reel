#!/bin/bash
# 스모크 테스트 — 빌드된 Reel.app이 실제로 켜지고 산 채로 있는지 검증. (#12)
#
# XCUITest 대신 권한(TCC 접근성 승인) 없이 돌리는 방식:
#   1. 앱을 open으로 실행
#   2. N초 후 프로세스 생존 확인
#   3. 정상 종료(SIGTERM) 후 종료 확인
#
# 사용법:
#   ./scripts/smoke-test.sh [앱경로]   (기본: DerivedData Release/Debug 자동 탐색)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-}"

# 앱 경로 자동 탐색
if [[ -z "$APP_PATH" ]]; then
    for CAND in \
        "$PROJECT_DIR/DerivedData/Build/Products/Release/Reel.app" \
        "$PROJECT_DIR/DerivedData/Build/Products/Debug/Reel.app"; do
        if [[ -d "$CAND" ]]; then APP_PATH="$CAND"; break; fi
    done
    if [[ -z "$APP_PATH" ]]; then
        APP_PATH=$(find "$PROJECT_DIR/DerivedData" -name "Reel.app" -path "*/Products/*" 2>/dev/null | head -1 || true)
    fi
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "❌ Reel.app을 찾을 수 없음 — 먼저 빌드하세요."
    exit 1
fi

echo "🧪 스모크 테스트: $APP_PATH"

# 1) 실행
open "$APP_PATH"
echo "  ① 앱 실행됨"

# 2) 부팅 대기 + 생존 확인
sleep 4
PID=$(pgrep -x Reel | head -1 || true)
if [[ -z "$PID" ]]; then
    echo "❌ 4초 후 프로세스가 없음 — 부팅 크래시"
    exit 1
fi
echo "  ② 프로세스 생존 (pid=$PID)"

# 3) 메모리 점유가 비정상(>2GB)이 아닌지 — 누수·폭주 방어
MEM=$(ps -o rss= -p "$PID" | tr -d ' ')
if [[ "$MEM" -gt 2097152 ]]; then
    echo "❌ RSS ${MEM}KB — 메모리 폭주 의심"
    kill "$PID" 2>/dev/null || true
    exit 1
fi
echo "  ③ 메모리 정상 (RSS ${MEM}KB)"

# 4) 추가 생존 확인 (안정성 — 3초 더)
sleep 3
if ! ps -p "$PID" > /dev/null; then
    echo "❌ 7초 차에 프로세스 사망 — 런타임 크래시"
    exit 1
fi
echo "  ④ 런타임 안정 (7초 생존)"

# 5) 정상 종료
kill "$PID" 2>/dev/null || true
sleep 2
if ps -p "$PID" > /dev/null 2>&1; then
    echo "⚠️ TERM 후에도 생존 — 강제 종료"
    kill -9 "$PID" 2>/dev/null || true
fi
echo "  ⑤ 정상 종료"

echo ""
echo "✅ 스모크 테스트 통과"
