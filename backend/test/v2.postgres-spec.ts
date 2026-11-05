import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { DisposablePostgres } from './support/disposable-postgres';

const R = '33333333-3333-4333-8333-333333333333';
const U = '11111111-1111-4111-8111-111111111111';
const B = '99999999-9999-4999-8999-999999999999';
const S = '22222222-2222-4222-8222-222222222222';
const M = '44444444-4444-4444-8444-444444444444';
const root = resolve(__dirname, '../..');

describe('v2 actual PostgreSQL transaction and permission contracts', () => {
  let db: DisposablePostgres;
  beforeAll(async () => {
    db = await DisposablePostgres.start(
      resolve(
        root,
        'backend/scripts/migrations/2026-07-27-create-order-with-items-v2.sql',
      ),
    );
  }, 90000);
  afterAll(async () => {
    if (db) await db.stop();
  }, 15000);
  beforeEach(async () => {
    await db.pool.query(
      'TRUNCATE public.restaurants,public.users,public.sessions,public.menu_items CASCADE',
    );
    await db.pool.query('INSERT INTO public.restaurants(id) VALUES($1)', [R]);
    await db.pool.query(
      "INSERT INTO public.users(id,role) VALUES($1,'CUSTOMER'),($2,'CUSTOMER')",
      [U, B],
    );
    await db.pool.query(
      "INSERT INTO public.sessions(id,status,winner_restaurant_id) VALUES($1,'ORDERED',$2)",
      [S, R],
    );
    await db.pool.query(
      'INSERT INTO public.session_members(session_id,user_id) VALUES($1,$2),($1,$3)',
      [S, U, B],
    );
    await db.pool.query(
      "INSERT INTO public.menu_items(id,name,price,restaurant_id) VALUES($1,'Rice Bowl',100,$2)",
      [M, R],
    );
  });
  const item = (qty = 10, extra: Record<string, unknown> = {}) => ({
    id: 'rice',
    name: 'Rice',
    currentQty: qty,
    minThreshold: 1,
    recipeUnitPerServing: 1,
    linkedMenuNames: ['Rice Bowl'],
    ...extra,
  });
  async function replace(items: unknown[]) {
    const current = (await db.pool.query('SELECT id,updated_at::text AS \"updatedAt\" FROM public.pos_inventory_items WHERE restaurant_id=$1', [R])).rows;
    return db.pool.query('SELECT public.replace_pos_inventory_items($1,$2::jsonb,$3::jsonb)', [R,JSON.stringify(items),JSON.stringify(current)]);
  }
  async function order(qty = 2) {
    const { rows } = await db.pool.query(
      "SELECT public.create_order_with_options($1,$2,$3,$4,'TOSS',$5::json,'TAKEOUT','Less spicy') data",
      [
        S,
        U,
        R,
        qty * 100,
        JSON.stringify([{ menuItemId: M, quantity: qty, price: 100 }]),
      ],
    );
    const id = rows[0].data.id as string;
    await db.pool.query("UPDATE public.orders SET status='PAID' WHERE id=$1", [
      id,
    ]);
    return id;
  }
  async function stock() {
    return (
      await db.pool.query('SELECT current_qty FROM public.pos_inventory_items')
    ).rows[0].current_qty;
  }
  async function cart(user = U, qty = 2) {
    await db.pool.query(
      `INSERT INTO public.session_cart_items(session_id,user_id,menu_item_id,menu_name,price,quantity)
      VALUES($1,$2,$3,'Rice Bowl',100,$4) ON CONFLICT(session_id,user_id,menu_item_id) DO UPDATE SET quantity=excluded.quantity`,
      [S, user, M, qty],
    );
  }
  test('new tables use RLS and reject direct browser-role access and RPC execution', async () => {
    for (const role of ['anon', 'authenticated']) {
      const c = await db.pool.connect();
      try {
        await c.query(`SET ROLE ${role}`);
        await expect(
          c.query('SELECT * FROM public.pos_inventory_items'),
        ).rejects.toThrow(/permission denied/);
        await expect(
          c.query("SELECT public.replace_pos_inventory_items($1,'[]'::jsonb,'[]'::jsonb)", [
            R,
          ]),
        ).rejects.toThrow(/permission denied/);
      } finally {
        await c.query('RESET ROLE');
        c.release();
      }
    }
    const rows = (
      await db.pool.query(
        "SELECT relrowsecurity FROM pg_class WHERE relname IN ('pos_inventory_items','pos_inventory_deductions','session_cart_items')",
      )
    ).rows;
    expect(rows).toHaveLength(3);
    expect(rows.every((r) => r.relrowsecurity)).toBe(true);
    const c = await db.pool.connect();
    try {
      await c.query('SET ROLE service_role');
      await c.query('SELECT public.replace_pos_inventory_items($1,$2::jsonb,$3::jsonb)', [
        R,
        JSON.stringify([item()]),
        JSON.stringify([]),
      ]);
    } finally {
      await c.query('RESET ROLE');
      c.release();
    }
    expect(await stock()).toBe(10);
  });
  test('invalid replacement preserves old rows, stale stock snapshot cannot overwrite deduction', async () => {
    await replace([item()]);
    const stamp = (
      await db.pool.query(
        "SELECT updated_at::text stamp FROM public.pos_inventory_items WHERE id='rice'",
      )
    ).rows[0].stamp;
    await expect(
      replace([
        item(3, { expectedUpdatedAt: stamp }),
        item(4, { expectedUpdatedAt: stamp }),
      ]),
    ).rejects.toThrow(/DUPLICATE/);
    await expect(replace([null])).rejects.toThrow(/INVALID/);
    expect(await stock()).toBe(10);
    const id = await order();
    await db.pool.query(
      'SELECT public.transition_order_to_preparing_with_bom($1,$2)',
      [id, R],
    );
    await expect(
      replace([item(10, { expectedUpdatedAt: stamp })]),
    ).rejects.toThrow(/CHANGED/);
    await expect(db.pool.query(
      'SELECT public.replace_pos_inventory_items($1,$2::jsonb,$3::jsonb)',
      [R, '[]', JSON.stringify([{ id: 'rice', updatedAt: stamp }])],
    )).rejects.toThrow(/CHANGED/);
    expect(await stock()).toBe(8);
  });
  test('concurrent distinct orders accumulate deductions and duplicate prepare is idempotent', async () => {
    await replace([item()]);
    const a = await order();
    const b = await order();
    await Promise.all(
      [a, b, a].map((id) =>
        db.pool.query(
          'SELECT public.transition_order_to_preparing_with_bom($1,$2)',
          [id, R],
        ),
      ),
    );
    expect(await stock()).toBe(6);
    expect(
      (
        await db.pool.query(
          'SELECT count(*)::int n FROM public.pos_inventory_deductions',
        )
      ).rows[0].n,
    ).toBe(2);
  });
  test('insufficient inventory rolls back earlier rows and order state', async () => {
    await replace([item(10, { id: 'a' }), item(1, { id: 'z' })]);
    const id = await order();
    await expect(
      db.pool.query(
        'SELECT public.transition_order_to_preparing_with_bom($1,$2)',
        [id, R],
      ),
    ).rejects.toThrow(/INSUFFICIENT/);
    expect(
      (
        await db.pool.query(
          'SELECT current_qty FROM public.pos_inventory_items ORDER BY id',
        )
      ).rows.map((x) => x.current_qty),
    ).toEqual([10, 1]);
    expect(
      (
        await db.pool.query('SELECT status FROM public.orders WHERE id=$1', [
          id,
        ])
      ).rows[0].status,
    ).toBe('PAID');
    expect(
      (
        await db.pool.query(
          'SELECT count(*)::int n FROM public.pos_inventory_deductions',
        )
      ).rows[0].n,
    ).toBe(0);
  });
  test('order options and cart snapshot commit atomically, repeated consume preserves new and peer items', async () => {
    await cart();
    await cart(B, 3);
    const id = await order();
    const meta = (
      await db.pool.query(
        'SELECT dining_type,customer_note,jsonb_array_length(cart_snapshot) n FROM public.orders WHERE id=$1',
        [id],
      )
    ).rows[0];
    expect(meta).toEqual({
      dining_type: 'TAKEOUT',
      customer_note: 'Less spicy',
      n: 1,
    });
    await db.pool.query(
      'SELECT public.consume_ordered_session_cart_items($1)',
      [id],
    );
    await cart(U, 4);
    await db.pool.query(
      'SELECT public.consume_ordered_session_cart_items($1)',
      [id],
    );
    expect(
      (
        await db.pool.query(
          'SELECT user_id,quantity FROM public.session_cart_items ORDER BY user_id',
        )
      ).rows,
    ).toEqual([
      { user_id: U, quantity: 4 },
      { user_id: B, quantity: 3 },
    ]);
  });
  test('cart edits after capture are conservatively preserved; unpaid orders cannot consume', async () => {
    await cart();
    const id = await order();
    await cart(U, 5);
    await db.pool.query(
      'SELECT public.consume_ordered_session_cart_items($1)',
      [id],
    );
    expect(
      (await db.pool.query('SELECT quantity FROM public.session_cart_items'))
        .rows[0].quantity,
    ).toBe(5);
    const pending = await order();
    await db.pool.query(
      "UPDATE public.orders SET status='PENDING' WHERE id=$1",
      [pending],
    );
    await expect(
      db.pool.query('SELECT public.consume_ordered_session_cart_items($1)', [
        pending,
      ]),
    ).rejects.toThrow(/NOT_PAID/);
  });
  test('all checked-in migrations and declarative schema parse and execute in separate empty schemas', async () => {
    // Separate databases inside this disposable container; never a user database.
    const admin = await db.pool.connect();
    try {
      for (const kind of ['source', 'migrations']) {
        const schemaName = 'v2_' + kind;
        await admin.query(`CREATE SCHEMA ${schemaName}`);
        let sql: string;
        if (kind === 'source')
          sql = await readFile(
            resolve(root, 'supabase/schemas/lunchsync.sql'),
            'utf8',
          );
        else {
          const files = (await readdir(resolve(root, 'supabase/migrations')))
            .filter((f) => f.endsWith('.sql'))
            .sort();
          sql = (
            await Promise.all(
              files.map((f) =>
                readFile(resolve(root, 'supabase/migrations', f), 'utf8'),
              ),
            )
          ).join('\n');
        }
        // Isolate every explicit public reference; roles are fixture-owned.
        sql = sql
          .replace(/\bpublic\./g, `${schemaName}.`)
          .replace(/SCHEMA public/gi, `SCHEMA ${schemaName}`)
          .replace(/schema public/gi, `schema ${schemaName}`);
        if (kind === 'migrations')
          await admin.query(`
          CREATE SCHEMA IF NOT EXISTS storage;
          CREATE TABLE IF NOT EXISTS storage.objects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),bucket_id text);
          CREATE TABLE IF NOT EXISTS storage.buckets(id text PRIMARY KEY,name text,public boolean,file_size_limit bigint,allowed_mime_types text[],updated_at timestamptz DEFAULT now());
        `);
        await admin.query(sql);
        await admin.query('SET check_function_bodies = true');
        expect(
          (
            await admin.query(
              `SELECT count(*)::int n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=$1 AND proname='create_order_with_options'`,
              [schemaName],
            )
          ).rows[0].n,
        ).toBe(1);
      }
    } finally {
      admin.release();
    }
  }, 30000);
});
