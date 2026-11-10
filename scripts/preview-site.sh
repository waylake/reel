#!/bin/sh
# Reel 소개 페이지를 로컬에서 본다. 빌드 단계 없음 — GitHub Actions가 하는 조립을 그대로 흉내낸다.
# 사용법: ./scripts/preview-site.sh   (PORT=5000 ./scripts/preview-site.sh 로 포트 변경)
set -eu
cd "$(dirname "$0")/.."

OUT=".preview"
PORT="${PORT:-4321}"

rm -rf "$OUT"
mkdir -p "$OUT/screenshots"
cp -R site/. "$OUT/"
cp docs/screenshots/*.png "$OUT/screenshots/"
cp icon-source/reel-icon-1024.png "$OUT/icon.png"

printf 'Reel site → http://localhost:%s/  (Ctrl-C to stop)\n' "$PORT"
exec python3 -m http.server "$PORT" --directory "$OUT"
