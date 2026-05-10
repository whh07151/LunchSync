// 데모용 메뉴 데이터.
// TODO(backend): GET /restaurants/:id/menus 응답으로 교체.
//                LUNCHSYNC_DTO.md §6 형태 — { categories[], menus[] }
//                pos_memo.md §2 (메뉴/가격 수정 — POS도 권한)와 합쳐 메뉴 편집 페이지(/menu) 구현 시 재활용

export interface DemoMenuItem {
  id: string;
  name: string;
  price: number;
  category: string;
}

export const DEMO_CATEGORIES = ["전체", "도시락", "찌개", "면", "분식", "음료"] as const;

export const DEMO_MENU: DemoMenuItem[] = [
  { id: "m-1", name: "제육볶음 도시락", price: 6500, category: "도시락" },
  { id: "m-2", name: "치킨마요 도시락", price: 5500, category: "도시락" },
  { id: "m-3", name: "불고기 도시락", price: 7000, category: "도시락" },
  { id: "m-4", name: "김치찌개", price: 7000, category: "찌개" },
  { id: "m-5", name: "된장찌개", price: 7000, category: "찌개" },
  { id: "m-6", name: "라면", price: 4500, category: "면" },
  { id: "m-7", name: "비빔국수", price: 6500, category: "면" },
  { id: "m-8", name: "떡볶이", price: 5000, category: "분식" },
  { id: "m-9", name: "콜라", price: 2000, category: "음료" },
  { id: "m-10", name: "사이다", price: 2000, category: "음료" },
];
