-- 상용화 업그레이드: 매장 식자재·레시피(BOM)·유통기한 DB 영속화 및 세션 실시간 공동 장바구니 테이블
ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS business_status TEXT NOT NULL DEFAULT 'OPEN';
ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS operating_hours_note TEXT NOT NULL DEFAULT '영업 11:00~21:00 · 브레이크타임 15:00~17:00';

CREATE TABLE IF NOT EXISTS public.pos_inventory_items (
  id TEXT NOT NULL,
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT '기타',
  current_qty INTEGER NOT NULL DEFAULT 0,
  min_threshold INTEGER NOT NULL DEFAULT 5,
  unit TEXT NOT NULL DEFAULT '인분',
  linked_menu_names TEXT[] NOT NULL DEFAULT '{}',
  expiry_date TEXT,
  recipe_unit_per_serving INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (restaurant_id, id)
);

CREATE TABLE IF NOT EXISTS public.session_cart_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user_name TEXT NOT NULL DEFAULT '동료',
  menu_item_id UUID NOT NULL REFERENCES public.menu_items(id) ON DELETE CASCADE,
  menu_name TEXT NOT NULL,
  price INTEGER NOT NULL DEFAULT 0,
  quantity INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (session_id, user_id, menu_item_id)
);

ALTER TABLE public.pos_inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_cart_items ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.pos_inventory_items,
  public.session_cart_items
FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.pos_inventory_items,
  public.session_cart_items
TO service_role;
