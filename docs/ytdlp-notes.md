# yt-dlp 운영 노트 — Reel 엔진 설계 근거

> 2026-08-22 리서치 기준. yt-dlp 공식 README/Wiki/FAQ(고정 이슈 #3766) 및 주요 이슈(#16212, #17389)를
> 정리한 것으로, Reel이 yt-dlp를 감싸는 방식(프로세스 실행·인자 설계·오류 재시도)의 판단 근거가 된다.
> 관련 이슈: #7, #11 / 관련 코드: `ArgumentBuilder`, `QueueStore.isRetryableError`, `BinaryResolver`

## 1. 오류 분류와 재시도 정책

Reel은 yt-dlp의 stderr를 그대로 오류 메시지로 받아 `QueueStore.isRetryableError`로 분기한다.
공식 문서와 이슈 트래커의 실제 사례를 분류하면:

| 오류 메시지 | 성격 | Reel의 대응 |
|---|---|---|
| `The page needs to be reloaded` | 봇 감지(signatureTimestamp·TVHTML5 JS 챌린지 파손). **일시적으로 발생/해제를 반복** | ✅ 재시도 + yt-dlp 자동 업데이트 |
| `HTTP Error 403: Forbidden` | 봇 감지/URL 만료. 재시도·엔진 최신화로 해결되는 경우 다수 | ✅ 재시도 + yt-dlp 자동 업데이트 |
| `unable to download video data` | 위 403의 상위 래퍼 | ✅ 재시도 |
| `Sign in to confirm you're not a bot` | **IP 기반 봇 판정** — 재시도로 안 풀림 | ❌ 재시도 안 함(수동 조치 필요: 쿠키·PO 토큰·IP) |
| `age-restricted` / `geo restricted` / `private video` / `members-only` | 영구 실패 | ❌ 재시도 안 함 |
| 429 / 502 / 503 / 504 / timeout / connection / reset by peer | 일시적 네트워크 | ✅ 지수 백오프 재시도 (기존) |

**근거**: yt-dlp #17389 — 같은 클라이언트·같은 영상이 시점에 따라 재로드 오류가 나타났다 사라짐.
#16212 — 원인은 유튜브가 고정한 signatureTimestamp(STS) 무효화로, yt-dlp 업데이트로만 완전 해결.
따라서 봇 감지 계열 = "재시도로 버티면서 엔진을 최신화"가 공식 커뮤니티의 정석 대응이다.

## 2. player_client — 절대 기본값을 믿는다

2026-08 기준 공식 문서의 클라이언트 매트릭스:

| 클라이언트 | PO 토큰 필요 | 비고 |
|---|---|---|
| `android_vr` | 불필요 | 키즈 영상 불가. JS 런타임 없을 때 유일한 기본값 |
| `web_safari` | GVS* | HLS 제공 — PO 토큰 없이도 동작하는 경로 있음 |
| `tv` | 불필요 | 쿠키 없으면 DRM/SABR 제한 |
| `web_embedded` | 불필요 | 임베드 금지 영상 불가 |
| `tv_downgraded` | — | **2026-08 현재 일부 사용자에게 파손** (#17389) |
| `mweb` / `android` / `ios` | 필요 | 단독 지정 시 403 위험 |
| `web` | Subs, GVS | SABR 전용 |

- 기본 조합: `android_vr,web_safari` (로그인 쿠키 전달 시 `tv_downgraded` 추가 — 파손 시 `default,web_embedded` 회피책이 커뮤니티 권장)
- **공식 입장: "기본값을 유지하라. 유튜브가 바뀌면 yt-dlp 기본값이 따라잡는다."**
  커스텀 `player_client`는 PO 토큰·임베드 제한 등 부작용을 감수하는 최후 수단이다.

**Reel의 결정**: `--extractor-args`로 클라이언트를 지정하지 않는다(기본값 유지).
대신 엔진 최신화(BinaryResolver 관리본 우선 + 자동 업데이트)로 유튜브 변화를 추격한다.

## 3. 인자 설계 근거 (ArgumentBuilder)

| 인자 | 이유 |
|---|---|
| `--ignore-config` | 사용자 전역 설정(`~/.config/yt-dlp/config`)의 간섭 배제 — 결정론 보장. 특히 `--download-archive`가 재다운로드를 막는 사고 방지 |
| `--newline --progress` | 파이프(非tty) 환경에서도 진행률 강제 출력 |
| `--progress-template` | stdout 스크래핑 대신 sentinel 접두어로 구조화 — 화면 폭 변화에 파서가 깨지지 않음 |
| `--print after_move:FILE|%(filepath)s` | 최종 파일 경로 확보 (이동 완료 후 시점) |
| `--flat-playlist --print` (플레이리스트 열거) | `--dump-single-json`은 큰 채널에서 entries가 잘리는 버그(#8) — 줄 기반이 안정적 |
| `-N 4` | 단편 병렬 다운로드. 단편별 progress 라인이 교차 출력되므로 UI는 스로틀+이동평균로 처리(#9) |

## 4. 버전 관리 전략 (BinaryResolver)

```
0순위  ~/Library/Application Support/Reel/bin/yt-dlp   ← 런타임 업데이트가 설치
1순위  Reel.app/Contents/Resources/yt-dlp               ← 빌드 시 bundle-binaries.sh가 최신 릴리스로 고정
2순위  /opt/homebrew/bin 등 PATH                         ← 개발 머신
```

- 유튜브 추출기는 앱 릴리즈 주기보다 빨리 망가진다 → 관리본(0순위)이 항상 번들본을 이기도록 설계
- 업데이트 소스: GitHub `releases/latest/download/yt-dlp_macos` (macOS Universal 단독 바이너리, ~37MB)
- 설치 후 `--version` 실행 검증 → 실패 시 롤백 (고장 난 바이너리로 앱이 죽는 사고 방지)
- #11부터: 봇 감지 오류 반복 시 이 경로를 **자동**으로 밟는다 (세션 1회)

## 5. PO 토큰 — 알지만 하지 않는다

- GVS(구글 비디오 서버) 요청에 PO 토큰이 없으면 403이 난다(클라이언트별 차이 있음)
- 토큰은 이제 **영상 ID에 귀속**되어 매 영상마다 새로 발급 필요 → 수동 관리 불가능
- 공식 권장은 PO 토큰 **프로바이더 플러그인**(bgutil HTTP 서버 등)인데, 이는 사용자에게 상시 대기 서버를 요구한다
- **Reel의 결정**: 메뉴바 다운로더의 복잡도 예산을 넘는다. 기본 클라이언트(토큰 불필요 계열) + 엔진 최신화 + 재시도로 커버하고, 필요한 사용자에게만 `--cookies-from-browser`(설정에 있음)을 안내한다. 필요해지면 별도 이슈로 재검토.

## 6. 참조

- README(옵션 전문): https://github.com/yt-dlp/yt-dlp#readme
- PO Token Guide: https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide
- Extractors Wiki: https://github.com/yt-dlp/yt-dlp/wiki/Extractors
- 고정 FAQ 이슈 #3766 (KNOWN ISSUES/FAQ)
- 봇 감지 사례: #16212 (playability UNPLAYABLE), #17389 (page needs to be reloaded), #12561 (403 workaround)
