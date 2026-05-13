"""
LunchSync 제출용 캡처 인덱스 생성기
- INDEX.md (마크다운, 깃허브/문서에 그대로 붙이기 가능)
- index.html (브라우저로 열면 썸네일 갤러리)

실행: python generate_index.py
"""

from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).parent
SHOTS = ROOT / "screenshots"

# 카테고리: (폴더명, 한국어 제목, 설명)
CATEGORIES = [
    ("01-auth", "1. 인증 / 회원가입 / 로그인",
     "스플래시, 온보딩, 로그인 화면, 회원가입 폼(손님/사장), 이메일 OTP, 휴대폰 인증, 카카오 로그인 버튼"),
    ("02-customer-home", "2. 손님 홈 화면 / 탭",
     "홈 화면, 알림, 네 개 탭(점심세션·주문현황·내역·내정보), 카카오맵 영역"),
    ("03-session", "3. 점심 세션 (생성·로비·AI 추천·투표)",
     "세션 생성 3단계, 로비, 멤버 입장, AI 추천 카드, 점수, 투표 시작, 결과, 경로 안내"),
    ("04-restaurant-menu", "4. 식당 / 메뉴 화면",
     "식당 목록·상세, 메뉴 화면"),
    ("05-payment-order", "5. 결제 / 주문",
     "토스 위젯, 결제 성공/실패 콜백, Flutter 초기화면"),
    ("06-owner", "6. 사장 화면",
     "사장 홈, 매출 통계, 주문 관리, 메뉴 편집, 승인 대기"),
    ("07-pos", "7. POS 단말 (LunchSync-LSPOS)",
     "POS 로그인, 대시보드, 주방 모드, 메뉴, 좌석, 주문, 매출, 예약"),
    ("99-misc", "9. 기타 (반응형 / 부팅 / 임시)",
     "반응형(데스크톱/태블릿/모바일), 부팅 화면, 임시 캡처"),
]


def list_pngs(folder: Path):
    """폴더에서 PNG 파일을 정렬해 반환 (하위 1단계 폴더 포함)."""
    if not folder.exists():
        return []
    items = []
    for p in sorted(folder.iterdir()):
        if p.is_file() and p.suffix.lower() == ".png":
            items.append((p.name, p.relative_to(SHOTS).as_posix(), False))
        elif p.is_dir():
            for sub in sorted(p.iterdir()):
                if sub.is_file() and sub.suffix.lower() == ".png":
                    items.append((f"{p.name}/{sub.name}",
                                  sub.relative_to(SHOTS).as_posix(), True))
    return items


# ── 마크다운 인덱스 ──────────────────────────────────────
md_lines = [
    "# LunchSync 캡처 모음 (제출용)",
    "",
    f"_생성 시각: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}_",
    "",
    "Flutter + NestJS 기반 점심 약속 통합 앱.",
    "손님앱 / 사장앱 / POS 단말 세 가지 모두 캡처 포함.",
    "",
    "## 📂 카테고리 목차",
    "",
]
total = 0
for folder, title, desc in CATEGORIES:
    items = list_pngs(SHOTS / folder)
    md_lines.append(f"- [{title}](#{folder.replace('-', '')}) — {len(items)}장")
    total += len(items)

md_lines.append("")
md_lines.append(f"**총 {total}장**")
md_lines.append("")
md_lines.append("---")
md_lines.append("")

for folder, title, desc in CATEGORIES:
    anchor = folder.replace('-', '')
    md_lines.append(f"## {title}  <a id='{anchor}'></a>")
    md_lines.append("")
    md_lines.append(f"_{desc}_")
    md_lines.append("")
    items = list_pngs(SHOTS / folder)
    if not items:
        md_lines.append("> ⚠️ (캡처 누락 — 추후 보충)")
        md_lines.append("")
        continue
    for name, rel, _ in items:
        md_lines.append(f"### {name}")
        md_lines.append("")
        md_lines.append(f"![{name}](screenshots/{rel})")
        md_lines.append("")
    md_lines.append("---")
    md_lines.append("")

(ROOT / "INDEX.md").write_text("\n".join(md_lines), encoding="utf-8")

# ── HTML 갤러리 ──────────────────────────────────────────
html_head = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8" />
<title>LunchSync 캡처 모음</title>
<style>
  :root { --bg:#fff; --fg:#1a1a1a; --muted:#6b6b6b; --accent:#ff6b35; --card:#f5f5f7; }
  * { box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Pretendard', system-ui, sans-serif;
         margin: 0; padding: 0 24px 80px; color: var(--fg); background: var(--bg); }
  header { padding: 40px 0 16px; border-bottom: 2px solid var(--accent); margin-bottom: 32px; }
  h1 { margin: 0; font-size: 28px; }
  .meta { color: var(--muted); margin-top: 8px; font-size: 14px; }
  .toc { display: flex; flex-wrap: wrap; gap: 12px; margin: 24px 0; }
  .toc a { background: var(--card); padding: 8px 14px; border-radius: 999px;
           text-decoration: none; color: var(--fg); font-size: 14px; }
  .toc a:hover { background: var(--accent); color: #fff; }
  section { margin-bottom: 56px; }
  h2 { font-size: 22px; margin-bottom: 4px; border-left: 4px solid var(--accent);
       padding-left: 12px; }
  .desc { color: var(--muted); margin: 6px 0 18px; font-size: 14px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
          gap: 16px; }
  .item { background: var(--card); border-radius: 10px; padding: 8px;
          transition: transform .1s; }
  .item:hover { transform: translateY(-2px); }
  .item img { width: 100%; height: 160px; object-fit: cover; border-radius: 6px;
              cursor: zoom-in; background:#fff; }
  .item .name { font-size: 12px; color: var(--muted); margin-top: 6px;
                word-break: break-all; text-align: center; }
  .empty { color: var(--muted); font-style: italic; padding: 12px; }
  /* lightbox */
  #lb { display: none; position: fixed; inset: 0; background: rgba(0,0,0,.92);
        z-index: 999; align-items: center; justify-content: center;
        flex-direction: column; padding: 24px; cursor: zoom-out; }
  #lb.on { display: flex; }
  #lb img { max-width: 95vw; max-height: 88vh; object-fit: contain; }
  #lb .cap { color: #ccc; margin-top: 12px; font-size: 14px; }
  .count { background: var(--accent); color: #fff; font-size: 12px;
           padding: 2px 8px; border-radius: 999px; margin-left: 8px; vertical-align: middle; }
</style>
</head>
<body>
"""

html_body = []
html_body.append('<header>')
html_body.append('<h1>🍱 LunchSync 캡처 모음 (제출용)</h1>')
html_body.append(f'<div class="meta">생성: {datetime.now().strftime("%Y-%m-%d %H:%M")} · 총 ')
html_body.append(f'<span class="count">{total}장</span></div>')
html_body.append('<div class="toc">')
for folder, title, _ in CATEGORIES:
    items = list_pngs(SHOTS / folder)
    html_body.append(
        f'<a href="#{folder}">{title} ({len(items)})</a>')
html_body.append('</div>')
html_body.append('</header>')

for folder, title, desc in CATEGORIES:
    items = list_pngs(SHOTS / folder)
    html_body.append(f'<section id="{folder}">')
    html_body.append(f'<h2>{title}<span class="count">{len(items)}장</span></h2>')
    html_body.append(f'<p class="desc">{desc}</p>')
    if not items:
        html_body.append('<div class="empty">⚠️ 캡처 누락 — 추후 보충</div>')
    else:
        html_body.append('<div class="grid">')
        for name, rel, _ in items:
            esc = name.replace('"', '&quot;')
            html_body.append(
                f'<div class="item"><img src="screenshots/{rel}" alt="{esc}" '
                f'loading="lazy" data-cap="{esc}" />'
                f'<div class="name">{esc}</div></div>')
        html_body.append('</div>')
    html_body.append('</section>')

html_body.append('<div id="lb"><img src="" /><div class="cap"></div></div>')
html_body.append("""
<script>
  const lb = document.getElementById('lb');
  const lbImg = lb.querySelector('img');
  const lbCap = lb.querySelector('.cap');
  document.querySelectorAll('.item img').forEach(img => {
    img.addEventListener('click', e => {
      e.stopPropagation();
      lbImg.src = img.src;
      lbCap.textContent = img.dataset.cap;
      lb.classList.add('on');
    });
  });
  lb.addEventListener('click', () => lb.classList.remove('on'));
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') lb.classList.remove('on');
  });
</script>
</body>
</html>
""")

(ROOT / "index.html").write_text(html_head + "\n".join(html_body), encoding="utf-8")

# ── README 안내 ────────────────────────────────────────
readme = f"""# LunchSync 제출용 캡처 모음

**총 {total}장** · 생성 {datetime.now().strftime('%Y-%m-%d %H:%M')}

## 📦 폴더 구조
```
submission/
├── index.html          ← 브라우저로 열면 갤러리 (썸네일 클릭=확대)
├── INDEX.md            ← 마크다운 인덱스 (PDF 변환·문서 첨부용)
├── README.md           ← (이 파일)
├── generate_index.py   ← 캡처 추가 후 재생성 시 실행
└── screenshots/        ← 카테고리별 PNG (85장)
    ├── 01-auth/                   인증/회원가입/로그인
    ├── 02-customer-home/          손님 홈/탭
    ├── 03-session/                점심 세션/AI 추천/투표
    ├── 04-restaurant-menu/        식당/메뉴
    ├── 05-payment-order/          결제/주문
    ├── 06-owner/                  사장 화면
    ├── 07-pos/                    POS 단말
    └── 99-misc/                   반응형/기타
```

## 🚀 보는 법
1. **권장: 갤러리** — `index.html` 더블클릭 → 기본 브라우저로 열림
2. **마크다운** — `INDEX.md` 를 VSCode/Typora/깃허브에서 미리보기
3. **개별 PNG** — `screenshots/` 폴더 직접 탐색

## 🔄 캡처 추가 후 재생성
```bash
cd D:/LunchSyncFr/LunchSync/submission
python generate_index.py
```

## ⚠️ 알려진 누락
- `06-owner/` — 사장 화면 정식 캡처 미수집 (사장 계정 로그인 시연 필요)
- 회원가입 폼 입력 변화 캡처는 Flutter CanvasKit 한계로 동일 화면처럼 보일 수 있음
"""

(ROOT / "README.md").write_text(readme, encoding="utf-8")

import sys
try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass
print(f"[OK] index files generated - total {total} images")
print(f"  - {ROOT / 'INDEX.md'}")
print(f"  - {ROOT / 'index.html'}")
print(f"  - {ROOT / 'README.md'}")
