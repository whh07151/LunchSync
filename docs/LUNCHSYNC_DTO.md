# LunchSync DTO 명세서
**작성일:** 2026-04-08 / **최종 수정:** 2026-04-14
**버전:** 1.3
**기준:** 프론트 친화적 구조 (Flutter가 가공 없이 바로 사용 가능)
**네이밍:** camelCase (Flutter Dart 컨벤션)

> ⚠️ 이견 있을 시 3일 내 팀 카톡으로 전달. 이후 이 구조로 확정.

---

## 목차
1. [공통 응답 구조](#1-공통-응답-구조)
2. [인증 (Auth)](#2-인증)
3. [유저 (Users)](#3-유저)
4. [세션 (Sessions)](#4-세션)
5. [초대 (Invitations)](#5-초대)
6. [식당 (Restaurants)](#6-식당)
7. [추천 (Recommendations)](#7-추천)
8. [투표 (Votes)](#8-투표)
9. [장바구니 (Cart)](#9-장바구니)
10. [주문 (Orders)](#10-주문)
11. [결제 (Payments)](#11-결제)
12. [POS/점주 (POS)](#12-pos점주)
13. [알림 (Notifications)](#13-알림)

---

## 1. 공통 응답 구조

### 성공
```json
{
  "success": true,
  "data": { ... }
}
```

### 실패
```json
{
  "success": false,
  "error": {
    "code": "DUPLICATE_VOTE",
    "message": "이미 투표하셨습니다."
  }
}
```

### 에러 코드 목록
| code | HTTP | 설명 |
|---|---|---|
| UNAUTHORIZED | 401 | JWT 토큰 없음/만료 |
| FORBIDDEN | 403 | 권한 없음 (세션 비참여자 등) |
| NOT_FOUND | 404 | 리소스 없음 |
| DUPLICATE_VOTE | 409 | 중복 투표 |
| DUPLICATE_MEMBER | 409 | 이미 세션 참여 중 |
| PAYMENT_FAILED | 402 | 결제 실패 |
| VALIDATION_ERROR | 400 | 요청값 오류 |

---

## 2. 인증

### POST /auth/kakao
카카오 토큰 검증 후 JWT 발급

**Request:**
```json
{
  "kakaoAccessToken": "카카오_액세스_토큰"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "accessToken": "jwt_토큰",
    "isNewUser": true,
    "user": {
      "id": "uuid",
      "name": "지효",
      "profileImage": "https://...",
      "role": "CUSTOMER"
    }
  }
}
```

> Flutter 처리:
> - `isNewUser == true` → ProfileSetupScreen
> - `isNewUser == false` → HomeScreen

---

## 3. 유저

### POST /users
온보딩 프로필 생성

**Request:**
```json
{
  "name": "김지효",
  "org": "개발팀",
  "profileImage": "https://...",
  "radius": "500m"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "name": "김지효",
    "org": "개발팀",
    "profileImage": "https://...",
    "radius": "500m"
  }
}
```

---

### GET /users/me
내 프로필 조회 (홈 대시보드 상단 이름 표시용)

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "name": "김지효",
    "org": "개발팀",
    "profileImage": "https://...",
    "radius": "500m",
    "budget": 10000,
    "speed": "NORMAL"
  }
}
```

---

### PATCH /users/me
프로필/조건 수정 (JWT에서 user_id 추출, 클라이언트는 ID 전달 불필요)

**Request:**
```json
{
  "name": "김지효",
  "org": "개발팀",
  "radius": "1km",
  "budget": 12000,
  "speed": "FAST"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "name": "김지효",
    "org": "개발팀",
    "radius": "1km",
    "budget": 12000,
    "speed": "FAST"
  }
}
```

---

### GET /users
멤버 선택 화면용 전체 유저 목록

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "name": "김지효",
      "org": "개발팀",
      "profileImage": "https://..."
    },
    {
      "id": "uuid2",
      "name": "우현호",
      "org": "개발팀",
      "profileImage": "https://..."
    }
  ]
}
```

---

## 4. 세션

### POST /sessions
세션 생성
> 방장 본인이 자동으로 session_members에 추가됨. 다른 멤버는 초대코드로 참가.

**Request:**
```json
{
  "name": "개발팀 점심",
  "scheduledAt": "2026-04-08T12:00:00"
}
```
> `scheduledAt` 선택 항목

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "session_uuid",
    "name": "개발팀 점심",
    "status": "WAITING",
    "scheduledAt": "2026-04-08T12:00:00",
    "memberCount": 1,
    "createdBy": {
      "id": "uuid",
      "name": "김지효"
    }
  }
}
```

---

### GET /sessions/today
홈 대시보드 오늘 내가 속한 세션 목록

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "session_uuid",
      "name": "개발팀 점심",
      "status": "VOTING",
      "statusLabel": "투표 중",
      "memberCount": 4,
      "scheduledAt": "2026-04-08T12:00:00",
      "createdBy": {
        "id": "uuid",
        "name": "김지효"
      }
    }
  ]
}
```
> 빈 배열이면 오늘 세션 없음

---

### GET /sessions/:id
세션 상세

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "session_uuid",
    "name": "개발팀 점심",
    "status": "WAITING",
    "winnerRestaurantId": null,
    "scheduledAt": "2026-04-08T12:00:00",
    "createdAt": "2026-04-08T11:00:00",
    "createdBy": {
      "id": "uuid",
      "name": "김지효"
    }
  }
}
```

---

### GET /sessions/:id/members
세션 멤버 목록 (폴링용)

**Response:**
```json
{
  "success": true,
  "data": {
    "totalCount": 4,
    "joinedCount": 3,
    "members": [
      {
        "id": "uuid",
        "name": "김지효",
        "profileImage": "https://...",
        "isHost": true,
        "joinedAt": "2026-04-08T11:30:00"
      },
      {
        "id": "uuid2",
        "name": "우현호",
        "profileImage": "https://...",
        "org": "개발팀",
        "isHost": false,
        "joinedAt": "2026-04-08T11:31:00"
      }
    ]
  }
}
```

---

### PATCH /sessions/:id/status
세션 상태 전이 (방장만 가능)

**Request:**
```json
{
  "status": "VOTING"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "session_uuid",
    "status": "VOTING"
  }
}
```

---

## 5. 초대

### POST /invitations
초대 코드 생성 (8자리 hex, 24시간 유효)

**Request:**
```json
{
  "sessionId": "session_uuid"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "invitation_uuid",
    "sessionId": "session_uuid",
    "inviteCode": "a1b2c3d4",
    "expiresAt": "2026-04-09T12:00:00",
    "createdAt": "2026-04-08T12:00:00"
  }
}
```

---

### GET /invitations/:code
초대 코드 유효성 확인 + 세션 정보 반환

**Response (유효):**
```json
{
  "success": true,
  "data": {
    "inviteCode": "a1b2c3d4",
    "session": {
      "id": "session_uuid",
      "name": "개발팀 점심",
      "status": "WAITING",
      "createdBy": { "id": "uuid", "name": "김지효" }
    }
  }
}
```

**Response (만료/없음):** 400 또는 404

---

### POST /invitations/:code/accept
초대 수락 → session_members에 본인 추가

**Response:**
```json
{
  "success": true,
  "data": {
    "success": true,
    "sessionId": "session_uuid"
  }
}
```

> 이미 참가한 멤버이면 409 DUPLICATE_MEMBER

---

## 6. 식당

### GET /restaurants
AI 추천 식당 목록 (조건 필터링)

**Query Params:**
```
?sessionId=session_uuid
```
> sessionId로 세션 참여자들의 반경/예산/속도 조건을 종합해서 필터링

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "restaurant_uuid",
      "name": "한솥도시락",
      "category": "한식",
      "distance": 320,
      "distanceLabel": "도보 5분",
      "priceRange": 7000,
      "priceLabel": "7,000원대",
      "rating": 4.2,
      "imageUrl": "https://...",
      "address": "서울시 강남구..."
    }
  ]
}
```

---

### GET /restaurants/:id
식당 상세

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "restaurant_uuid",
    "name": "한솥도시락",
    "category": "한식",
    "distance": 320,
    "distanceLabel": "도보 5분",
    "priceRange": 7000,
    "rating": 4.2,
    "imageUrl": "https://...",
    "address": "서울시 강남구...",
    "lat": 37.123456,
    "lng": 127.123456
  }
}
```

---

### GET /restaurants/:id/menus
메뉴 목록 (카테고리별 그룹핑)

**Response:**
```json
{
  "success": true,
  "data": {
    "categories": ["전체", "도시락", "국밥", "세트"],
    "menus": [
      {
        "id": "menu_uuid",
        "name": "제육볶음 도시락",
        "price": 6500,
        "priceLabel": "6,500원",
        "category": "도시락",
        "description": "매콤한 제육볶음과 밥",
        "imageUrl": "https://..."
      }
    ]
  }
}
```

---

## 7. 추천

### GET /recommendations
그룹 추천 (점수화, 최근 7일 중복 회피)

**Query Params:**
```
?sessionId=session_uuid
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "restaurant_uuid",
      "name": "한솥도시락",
      "category": "한식",
      "score": 87,
      "priceRange": 7000,
      "address": "서울시 강남구...",
      "lat": 37.123456,
      "lng": 127.123456
    }
  ]
}
```

---

## 8. 투표

### POST /votes
투표

**Request:**
```json
{
  "sessionId": "session_uuid",
  "restaurantId": "restaurant_uuid"
}
```

**Response (성공):**
```json
{
  "success": true,
  "data": {
    "message": "투표가 완료되었습니다."
  }
}
```

**Response (중복 투표):**
```json
{
  "success": false,
  "error": {
    "code": "DUPLICATE_VOTE",
    "message": "이미 투표하셨습니다."
  }
}
```

---

### GET /sessions/:id/votes
투표 현황 (폴링용)

**Response:**
```json
{
  "success": true,
  "data": {
    "isFinished": false,
    "totalMembers": 4,
    "votedCount": 3,
    "results": [
      {
        "restaurant": {
          "id": "restaurant_uuid",
          "name": "한솥도시락",
          "imageUrl": "https://..."
        },
        "voteCount": 2,
        "percentage": 67
      },
      {
        "restaurant": {
          "id": "restaurant_uuid2",
          "name": "김밥천국",
          "imageUrl": "https://..."
        },
        "voteCount": 1,
        "percentage": 33
      }
    ],
    "winner": null
  }
}
```
> `isFinished == true` 이면 `winner`에 최다 득표 식당 포함

---

## 9. 장바구니

### POST /cart
메뉴 담기

**Request:**
```json
{
  "sessionId": "session_uuid",
  "menuItemId": "menu_uuid",
  "quantity": 1
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "cart_uuid",
    "menuItem": {
      "id": "menu_uuid",
      "name": "제육볶음 도시락",
      "price": 6500,
      "imageUrl": "https://..."
    },
    "quantity": 1,
    "subtotal": 6500,
    "subtotalLabel": "6,500원"
  }
}
```

---

### GET /cart/:sessionId
장바구니 조회

**Response:**
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "cart_uuid",
        "menuItem": {
          "id": "menu_uuid",
          "name": "제육볶음 도시락",
          "price": 6500,
          "imageUrl": "https://..."
        },
        "quantity": 2,
        "subtotal": 13000,
        "subtotalLabel": "13,000원"
      }
    ],
    "totalCount": 2,
    "totalPrice": 13000,
    "totalPriceLabel": "13,000원"
  }
}
```

---

### PATCH /cart/:id
수량 수정 (디바운싱 1초 적용)

**Request:**
```json
{
  "quantity": 3
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "cart_uuid",
    "quantity": 3,
    "subtotal": 19500,
    "subtotalLabel": "19,500원"
  }
}
```

---

### DELETE /cart/:id
항목 삭제

**Response:**
```json
{
  "success": true,
  "data": {
    "message": "장바구니에서 삭제되었습니다."
  }
}
```

---

## 10. 주문

### POST /orders
주문 생성 (메뉴 충돌 검증 포함 — 같은 식당 메뉴만 허용)

**Request:**
```json
{
  "sessionId": "session_uuid",
  "items": [
    { "menuItemId": "menu_uuid", "quantity": 2 },
    { "menuItemId": "menu_uuid2", "quantity": 1 }
  ],
  "paymentMethod": "TOSS"
}
```
> `paymentMethod`: `TOSS` | `CARD` | `CASH` | `SIMULATE`
> `SIMULATE` / `CASH` 는 서버에서 즉시 PAID 처리, `TOSS`는 결제위젯 흐름으로 진행

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "order_uuid",
    "sessionId": "session_uuid",
    "status": "PAID",
    "totalPrice": 13000,
    "paymentMethod": "SIMULATE",
    "paymentKey": "sim_order_uuid_timestamp",
    "items": [
      { "menuItemId": "menu_uuid", "quantity": 2, "price": 6500 }
    ],
    "createdAt": "2026-04-08T12:00:00"
  }
}
```

---

### GET /orders/:id
주문 상태 조회 (폴링용)

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "order_uuid",
    "status": "PREPARING",
    "statusLabel": "조리 중",
    "statusStep": 3,
    "restaurant": {
      "name": "한솥도시락"
    },
    "totalPrice": 13000,
    "totalPriceLabel": "13,000원",
    "updatedAt": "2026-04-08T12:05:00"
  }
}
```
> `statusStep`: PENDING=1, PAID=2, PREPARING=3, READY=4, COMPLETED=5, CANCELLED=0

---

### GET /orders/today
오늘 주문 목록 (점주앱용)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "order_uuid",
      "status": "PENDING",
      "statusLabel": "수락 대기",
      "customer": {
        "name": "김지효",
        "org": "개발팀"
      },
      "items": [
        {
          "name": "제육볶음 도시락",
          "quantity": 2
        }
      ],
      "totalPrice": 13000,
      "totalPriceLabel": "13,000원",
      "createdAt": "2026-04-08T12:00:00"
    }
  ]
}
```

---

### PATCH /orders/:id/status
주문 상태 변경 (점주: ACCEPTED/CANCELLED, POS: PREPARING/DONE)

**Request:**
```json
{
  "status": "ACCEPTED"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "order_uuid",
    "status": "ACCEPTED",
    "statusLabel": "수락됨"
  }
}
```

---

## 11. 결제

### POST /payments/confirm
토스 결제 최종 승인 (결제위젯 successUrl 리다이렉트 후 호출)

**Request:**
```json
{
  "paymentKey": "toss_payment_key",
  "orderId": "order_uuid",
  "amount": 13000
}
```
> `amount` 위변조 검증: DB의 `total_price`와 다르면 400 반환

**Response (성공):**
```json
{
  "success": true,
  "data": {
    "alreadyPaid": false,
    "orderId": "order_uuid",
    "status": "PAID",
    "paymentKey": "toss_payment_key",
    "method": "카드",
    "approvedAt": "2026-04-08T12:00:00",
    "totalAmount": 13000
  }
}
```

**Response (중복 호출 — 이미 결제됨):**
```json
{
  "success": true,
  "data": {
    "alreadyPaid": true,
    "orderId": "order_uuid",
    "status": "PAID"
  }
}
```

---

## 12. POS/점주

### GET /pos/orders/:restaurantId
점주용 주문 목록 (선택적 status 필터)

**Query Params:**
```
?status=PAID
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "order_uuid",
      "sessionId": "session_uuid",
      "userId": "user_uuid",
      "status": "PAID",
      "totalPrice": 13000,
      "paymentKey": "toss_key",
      "createdAt": "2026-04-08T12:00:00",
      "updatedAt": "2026-04-08T12:00:00"
    }
  ]
}
```

---

### GET /pos/orders/:restaurantId/stats
결제 상태별 통계

**Response:**
```json
{
  "success": true,
  "data": {
    "total": 10,
    "pending": 2,
    "paid": 3,
    "preparing": 3,
    "ready": 1,
    "completed": 1,
    "cancelled": 0,
    "totalRevenue": 78000
  }
}
```

---

### PATCH /pos/orders/:orderId/status
점주 주문 상태 변경

**Request:**
```json
{ "status": "PREPARING" }
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "order_uuid",
    "status": "PREPARING",
    "updatedAt": "2026-04-08T12:05:00"
  }
}
```

---

### POST /pos/orders/:orderId/cancel
취소/환불
> ⚠️ Toss 실제 환불 API 미연결 (TODO: POS-13)

**Request:**
```json
{ "reason": "고객 요청" }
```

**Response:**
```json
{
  "success": true,
  "data": { "success": true, "orderId": "order_uuid" }
}
```

---

## 13. 알림

### GET /notifications
알림 목록 (CU-22 알림함)

**Response:**
```json
{
  "success": true,
  "data": {
    "unreadCount": 2,
    "notifications": [
      {
        "id": "notif_uuid",
        "type": "ORDER_ACCEPTED",
        "title": "주문이 수락되었습니다",
        "message": "한솥도시락에서 주문을 수락했습니다.",
        "isRead": false,
        "createdAt": "2026-04-08T12:05:00",
        "createdAtLabel": "방금 전"
      },
      {
        "id": "notif_uuid2",
        "type": "VOTE_RESULT",
        "title": "투표 결과가 나왔습니다",
        "message": "한솥도시락이 선택되었습니다.",
        "isRead": true,
        "createdAt": "2026-04-08T11:45:00",
        "createdAtLabel": "20분 전"
      }
    ]
  }
}
```

---

### PATCH /notifications/:id/read
읽음 처리

**Response:**
```json
{
  "success": true,
  "data": {
    "message": "읽음 처리되었습니다."
  }
}
```

---

## 공통 헤더

모든 API 요청 시 포함:
```
Authorization: Bearer {accessToken}
Content-Type: application/json
If-Modified-Since: {마지막 응답 시각}  ← 폴링 요청 시만
```
