# 앱 아이콘 출처

Reel 앱 아이콘의 글리프는 **Lucide**의 `clapperboard` 아이콘을 사용했습니다.

- 출처: <https://lucide.dev/icons/clapperboard>
- 라이선스: **ISC License** (Lucide) — 상업적 사용·수정·재배포 자유, 저작권 고지만 유지
- 원본 저작권: © Lucide Contributors (<https://github.com/lucide-icons/lucide/blob/main/LICENSE>)

## 가공

- 스트로크 색을 흰색으로 변경, stroke-width 2 → 2.25
- Reel 틸(teal) 그라디언트 스퀘어클(초타원) 배경 위에 합성 (`scratchpad/makeicon.swift`)
- macOS 아이콘 그리드 근사(여백 ~9.4%), 은은한 광택·드롭 섀도 추가
- 16~1024px 전 사이즈 생성 → `Reel/Assets.xcassets/AppIcon.appiconset`

파일: `clapperboard.svg`(원본), `clapperboard-white.svg`(가공), `reel-icon-1024.png`(최종 마스터)
