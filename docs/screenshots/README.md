# LunchSync 주요 화면 5개 — 캡처 가이드

이 폴더에 아래 5개 파일명으로 스크린샷을 저장해주세요.

## 캡처 방법 (Windows)

- **단축키**: `Win + Shift + S` → 영역 선택 → 클립보드에 저장 → 그림판/PowerPoint 등에 붙여넣어 `.png`로 저장
- **Snipping Tool**: 시작 메뉴 → "캡처 도구" → 새로 캡처 → 저장
- **브라우저 전체 화면**: `F12` (DevTools) → `Ctrl+Shift+P` → "Capture full size screenshot" 검색
- **앱 주소**: 현재 실행 중인 Flutter 앱은 http://localhost:8080

## 5개 화면 목록

| 번호 | 파일명 | 화면 | 설명 |
|---|---|---|---|
| 1 | `01_home.png` | 고객 홈 화면 | 진입점 — 진행 중인 세션 / 추천 / 알림 |
| 2 | `02_session_create.png` | 세션 생성 | 같이 먹을 사람·시간·위치 설정하는 핵심 액션 |
| 3 | `03_recommendation_map.png` | 추천 지도 | GPS 기반 식당 추천 (서비스 차별점) |
| 4 | `04_order_review.png` | 주문/결제 화면 | Toss Payments 결제 흐름 |
| 5 | `05_pos_owner_home.png` | 사장 POS 화면 | 주문 상태 변경 · 매출 · 메뉴 관리 |

## 파일 위치

```
docs/screenshots/
├── README.md            (이 파일)
├── 01_home.png          ← 여기에 저장
├── 02_session_create.png
├── 03_recommendation_map.png
├── 04_order_review.png
└── 05_pos_owner_home.png
```

## 캡처 팁

- **해상도**: 가로 800px 이상 권장 (발표 자료에 들어갈 때 흐릿하지 않게)
- **브라우저 창**: F12 DevTools에서 모바일 시뮬레이션(`Ctrl+Shift+M`) 사용하면 모바일 비율로 깔끔하게 나옴 (iPhone 14: 390x844)
- **민감 정보 제거**: 실제 사용자 이름/전화번호 등이 보이면 모자이크 처리

캡처 완료 후 알려주시면, docs/ 안에 인덱스 파일 만들어 정리하겠습니다.
