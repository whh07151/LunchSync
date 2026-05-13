# LunchSync 제출용 캡처 모음

**총 104장** · 생성 2026-05-13 16:39

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
