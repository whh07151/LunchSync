import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: CORE-09 메뉴 알레르기 충돌 검증 서비스
//
// 한 줄 요약:
//   사용자가 회피하고자 등록한 알레르기(users.allergens) 와
//   메뉴별 알레르기(menu_items.allergens) 의 교집합을 계산해
//   "이 메뉴엔 ⚠️ 알레르기 성분이 있어요" 라고 알려준다.
//
// 매칭 규칙 (정확 매칭):
//   - 두 배열 모두 TEXT[] — DB 에 들어간 키워드 문자열 그대로.
//   - 사용자가 'nuts' 라고 저장했고 메뉴엔 'Nuts'/'견과류'/'땅콩' 처럼
//     다른 표기로 저장돼 있으면 정확 매칭이라 안 잡힌다.
//     → 안전망: 양쪽 모두 소문자 + trim 으로 정규화한 뒤 비교.
//     → 한국어 키워드와 영어 키워드를 동시에 운영해도 양쪽이 같은 표기를
//       쓰면 깨지지 않도록 단순 case-insensitive 정규화만 적용.
//
// 사용처:
//   - GET /api/menus/restaurant/:restaurantId/check-allergens?userId=
//   - 손님앱 메뉴 화면 진입 시 1회 호출 (메뉴 카드 ⚠️ 배지)
//
// 안전성:
//   - users.allergens 가 비어있으면 빈 conflicts 즉시 반환 (DB 추가 호출 X)
//   - 메뉴 0개여도 빈 conflicts 반환 (NotFound 아님 — 식당 자체는 존재)
//   - 식당이 진짜 없을 때만 NotFoundException
// ══════════════════════════════════════════════════════════

/// 단일 메뉴 충돌 정보 — 컨트롤러 응답 DTO 와 1:1.
export interface MenuAllergenConflict {
  menuId: string;
  name: string;
  /// 사용자 알레르기와 메뉴 알레르기의 교집합(정규화된 소문자 키워드).
  matchedAllergens: string[];
}

/// checkAllergens 전체 응답 형태.
export interface CheckAllergensResult {
  conflicts: MenuAllergenConflict[];
}

@Injectable()
export class MenusService {
  constructor(private readonly supabase: SupabaseService) {}

  /// 식당 id 와 사용자 id 를 받아 메뉴 충돌 목록을 반환.
  ///
  /// 흐름:
  ///   1) users.allergens 조회 — 비어있으면 즉시 빈 결과 반환.
  ///   2) menu_items (id, name, allergens) 조회 — 식당의 메뉴 전체.
  ///   3) 양쪽 배열을 소문자+trim 으로 정규화한 뒤 교집합 계산.
  ///   4) 교집합이 1개 이상인 메뉴만 conflicts 에 포함.
  async checkAllergens(
    restaurantId: string,
    userId: string,
  ): Promise<CheckAllergensResult> {
    // ── 1) 사용자 알레르기 조회 ─────────────────────────────
    // users.allergens 는 CU-04 + CORE-09 마이그레이션으로 추가된 TEXT[] 컬럼.
    // 누락된 사용자는 PostgREST 가 PGRST116(no rows) 또는 null 을 돌려줄 수 있음.
    const { data: userRow, error: userError } = await this.supabase.client
      .from('users')
      .select('allergens')
      .eq('id', userId)
      .maybeSingle();

    if (userError) {
      throw new Error('MENU_USER_ALLERGY_LOOKUP_FAILED');
    }
    if (!userRow) {
      // 사용자 자체가 없는 경우 — 컨트롤러 단에서 토큰 검증을 통과한 상태이므로
      // 이론상 발생하기 어렵지만 방어적으로 NotFound.
      throw new NotFoundException('사용자를 찾을 수 없습니다.');
    }

    const userAllergens = this.normalizeAllergens(
      (userRow.allergens as string[] | null) ?? [],
    );

    // 사용자가 알레르기를 등록하지 않았으면 메뉴 조회조차 생략 (불필요한 DB 호출 차단).
    if (userAllergens.length === 0) {
      return { conflicts: [] };
    }

    // ── 2) 메뉴 전체 조회 (해당 식당) ───────────────────────
    // is_available 여부와 무관하게 알레르기는 알려준다 — 품절 토글 외에도
    // "사장님이 등록은 했지만 잠시 품절" 메뉴를 손님이 다음에 보더라도
    // ⚠️ 배지가 일관되어야 하기 때문.
    const { data: menus, error: menuError } = await this.supabase.client
      .from('menu_items')
      .select('id, name, allergens, restaurant_id')
      .eq('restaurant_id', restaurantId);

    if (menuError) {
      throw new Error('MENU_ALLERGY_LOOKUP_FAILED');
    }

    // 메뉴가 1개도 없다 — 식당 자체가 진짜 없을 수도 있으므로 한 번 더 확인.
    if (!menus || menus.length === 0) {
      const { data: restaurant, error: rError } = await this.supabase.client
        .from('restaurants')
        .select('id')
        .eq('id', restaurantId)
        .maybeSingle();
      if (rError) {
        throw new Error('MENU_RESTAURANT_LOOKUP_FAILED');
      }
      if (!restaurant) {
        throw new NotFoundException('식당을 찾을 수 없습니다.');
      }
      return { conflicts: [] };
    }

    // ── 3) 정확 매칭 (정규화 후 교집합) ─────────────────────
    const userSet = new Set(userAllergens);
    const conflicts: MenuAllergenConflict[] = [];

    for (const row of menus) {
      const menuAllergensRaw = (row.allergens as string[] | null) ?? [];
      if (menuAllergensRaw.length === 0) continue;

      const menuAllergens = this.normalizeAllergens(menuAllergensRaw);
      const matched: string[] = [];
      for (const a of menuAllergens) {
        if (userSet.has(a)) matched.push(a);
      }

      // 중복 제거 후 길이가 0보다 크면 충돌로 등록.
      const matchedUnique = Array.from(new Set(matched));
      if (matchedUnique.length > 0) {
        conflicts.push({
          menuId: row.id as string,
          name: row.name as string,
          matchedAllergens: matchedUnique,
        });
      }
    }

    return { conflicts };
  }

  // ── 정규화 헬퍼 ────────────────────────────────────────────
  // - 소문자화: 사용자/메뉴가 다른 케이스로 등록해도 매칭 가능 ('Nuts' vs 'nuts').
  // - trim: 공백으로 인한 미매칭 방어.
  // - 빈 문자열 / null 제거.
  // 한국어 키워드는 소문자 변환 영향 없음 (한글은 case 가 없음).
  private normalizeAllergens(list: (string | null | undefined)[]): string[] {
    const out: string[] = [];
    for (const raw of list) {
      if (raw == null) continue;
      const norm = String(raw).trim().toLowerCase();
      if (norm.length === 0) continue;
      out.push(norm);
    }
    return out;
  }
}
