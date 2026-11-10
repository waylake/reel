# Reel 소개 페이지

`site/`는 빌드 없는 정적 파일이다. 외부 폰트·스크립트·이미지·분석 도구를 하나도 불러오지 않는다.
이 페이지의 "쿠키도 분석도 없다"는 문장이 사실이려면 그 상태를 유지해야 한다.

## 구조

| 파일 | 역할 |
|---|---|
| `site/index.html` | 홈 (영어) |
| `site/ko/index.html` | 홈 (한국어). 같은 CSS를 쓰고 문구만 다르다 |
| `site/docs.html` | 문제 해결 — 첫 실행, 403, 봇 감지, 쿠키, 엔진, 파일 위치, 삭제 |
| `site/changelog.html` | 릴리스 노트 |
| `site/privacy.html` | 앱·사이트 개인정보 |
| `site/licenses.html` | MIT + yt-dlp/ffmpeg/Sparkle/아이콘 고지, GPL 소스 제공 안내 |
| `site/assets/site.css` | 전부. 디자인 토큰은 파일 맨 위 `:root` |
| `site/assets/site.js` | 60줄. 스티키 내비, 복사 버튼, 탭, 최신 버전 표시 |
| `site/llms.txt` | AI 답변이 인용할 수 있는 사실 요약 |
| `site/robots.txt`, `site/sitemap.xml` | 크롤러용 |

스크린샷과 아이콘은 저장소에 중복 커밋하지 않는다. `docs/screenshots/`와
`icon-source/reel-icon-1024.png`를 빌드 때 복사한다.

## 로컬에서 보기

```sh
./scripts/preview-site.sh          # http://localhost:4321/
```

`.preview/`에 GitHub Actions와 같은 구성으로 조립한 뒤 정적 서버를 띄운다.

## 배포

`.github/workflows/pages.yml`이 `main`의 `site/**` 변경을 GitHub Pages로 올린다.
저장소 Settings → Pages → Source가 **GitHub Actions**인지 확인한다.

커스텀 도메인을 붙일 때:

1. Cloudflare DNS에 `reel` → `waylake.github.io` **CNAME**, 프록시는 DNS only(회색 구름).
   GitHub가 인증서를 직접 발급받으려면 프록시를 끄고 있어야 한다.
2. `site/CNAME` 파일에 `reel.waylake.com` 한 줄을 추가하고 함께 커밋한다.
3. Pages 설정에 도메인을 입력하고 "Enforce HTTPS"를 켠다.

`reel.waylake.com`은 현재 `*.waylake.com` 와일드카드로 dev1을 가리키고 있으므로,
CNAME을 GitHub Pages로 바꾸기 전까지는 `waylake.github.io/reel/`에서 확인한다.

## 최신 버전 표시

홈·문서·푸터의 `v1.3.2`와 `59 MB`는 `assets/site.js`가 GitHub API
(`repos/waylake/reel/releases/latest`)에서 읽어 덮어쓴다. 실패하면 마크업의 정적 값이 남는다.
버전을 하드코딩해 고치지 않아도 되지만, **릴리스 때마다 정적 값도 같이 올려두면** API가 막혀도
표시가 오래되지 않는다. 다운로드 링크는 `releases/latest/download/Reel.app.zip` 고정 URL이다.

## OG 이미지

`site/og.png` (1200×630). 아이콘·제목·버전을 얹은 정적 이미지 하나뿐이므로 필요할 때 다시 만든다.
현재 파일은 `og.html`을 브라우저로 1200×630에 렌더해 캡처한 것이다.

## URL과 canonical

지금 배포 주소는 **https://waylake.github.io/reel/** 이고, canonical·OG·sitemap·llms.txt가 모두 이 주소를 쓴다.
`reel.waylake.com`은 아직 `*.waylake.com` 와일드카드로 dev1을 가리키므로 연결하지 않았다.

커스텀 도메인을 붙인 뒤에는 아래를 한 번에 바꾸고, `site/CNAME`을 추가한다.

```sh
cd site
grep -rl 'https://waylake.github.io/reel' . | xargs sed -i '' 's|https://waylake.github.io/reel|https://reel.waylake.com|g'
printf 'reel.waylake.com\n' > CNAME
```

## 남은 일

- **공증(notarization)**: 앱은 아직 ad-hoc 서명이라 첫 실행에 우클릭 → 열기가 필요하다.
  Developer ID 인증서와 `notarytool`이 준비되면 `scripts/notarize.sh`를 릴리스 워크플로에 넣고,
  이 페이지의 "notarized" 관련 문구(설치 탭 안내, FAQ, `llms.txt`)를 갱신한다.
- **Homebrew cask**: `waylake/homebrew-tap`에 `Casks/reel.rb`가 있어야
  `brew install --cask waylake/tap/reel`이 동작한다.
