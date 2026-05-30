// ══════════════════════════════════════════════════════════
// 파일 역할: POS — 내 식당(매장) 메타데이터 API 클라이언트
//
// 2026-05-31 WOW#1 "사장님 오늘의 한 줄":
//   사장이 영업 중 한 줄(예: "비 오니까 얼큰순두부 강추 🌧") 을 입력하면
//   손님 추천 카드 상단에 노란 띠로 노출 + 추천 점수 +5점 가중.
//
// 백엔드 매핑 (NestJS PosController, 2026-05-31 신설):
//   PATCH /api/pos/restaurants/:id/todays-note
//     body: { note: string | null }
//     · note === null         → DB todays_note = NULL (노출 중단)
//     · note (1~200자, trim)  → 그대로 저장 + 손님 즉시 노출
//
// 권한:
//   · JWT 토큰의 매장 ID 와 path 식당 ID 가 일치해야만 변경 허용.
//   · 일치하지 않으면 400/403 에러 — POS 단말은 다른 매장 한 줄을 못 만짐.
//
// 응답 (성공):
//   { restaurantId, todaysNote, updatedAt }
// ══════════════════════════════════════════════════════════

import { apiRequest } from "@/lib/api/client";

export interface UpdateTodaysNoteResponse {
  restaurantId: string;
  todaysNote: string | null;
  updatedAt: string | null;
}

/**
 * 사장님 "오늘의 한 줄" 업데이트.
 *
 * @param restaurantId 변경 대상 식당 ID (POS 로그인된 매장과 동일해야 함)
 * @param note 200자 이하 문자열 또는 null (비우려면 null 전달)
 */
export async function updateTodaysNote(
  restaurantId: string,
  note: string | null,
): Promise<UpdateTodaysNoteResponse> {
  return apiRequest<UpdateTodaysNoteResponse>(
    `/pos/restaurants/${restaurantId}/todays-note`,
    {
      method: "PATCH",
      body: { note },
    },
  );
}

// ──────────────────────────────────────────────────────────
// 식당 단건 조회 — 현재 todays_note 를 화면 초기값으로 불러올 때 사용.
// 손님 측과 같은 엔드포인트(GET /restaurants/:id) 를 그대로 쓰고
// 응답에 포함된 todaysNote 만 사용한다.
// ──────────────────────────────────────────────────────────
export interface RestaurantSummary {
  id: string;
  name: string;
  category: string | null;
  todaysNote: string | null;
}

export async function getRestaurantSummary(
  restaurantId: string,
): Promise<RestaurantSummary> {
  return apiRequest<RestaurantSummary>(`/restaurants/${restaurantId}`);
}
