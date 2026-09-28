import { SchemaHealthcheckService } from './schema-healthcheck.service';
import { SupabaseService } from './supabase.service';

const expectedParameters = [
  { name: 'p_session_id', type: 'uuid' },
  { name: 'p_user_id', type: 'uuid' },
  { name: 'p_restaurant_id', type: 'uuid' },
  { name: 'p_total_price', type: 'integer' },
  { name: 'p_payment_method', type: 'text' },
  { name: 'p_items', type: 'json' },
];

const expectedContract = {
  parameters: expectedParameters,
  returnType: 'json',
};

describe('SchemaHealthcheckService', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  async function runHealthcheck(
    functions: Array<Record<string, unknown>>,
  ): Promise<void> {
    const rpc = jest.fn().mockResolvedValue({
      data: {
        columns: [],
        tables: [],
        functions,
      },
      error: null,
    });
    const service = new SchemaHealthcheckService({
      client: { rpc },
    } as unknown as SupabaseService);

    await service.onModuleInit();
  }

  it('reports the introspection migration for a legacy name-only payload', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation();

    await runHealthcheck([
      {
        name: 'create_order_with_items',
        present: true,
      },
    ]);

    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining(
        '2026-07-29-schema-introspection-function-signatures.sql',
      ),
    );
    expect(warn.mock.calls[0][0]).not.toContain(
      '2026-07-27-create-order-with-items-v2.sql',
    );
  });

  it('reports the v2 migration when the current payload says the order RPC is missing', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation();

    await runHealthcheck([
      {
        name: 'create_order_with_items',
        signature: null,
        parameters: null,
        returnType: null,
        contract: expectedContract,
        present: false,
      },
    ]);

    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining('2026-07-27-create-order-with-items-v2.sql'),
    );
    expect(warn.mock.calls[0][0]).not.toContain(
      '2026-07-29-schema-introspection-function-signatures.sql',
    );
  });

  it('rejects the obsolete five-argument order RPC signature', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation();

    await runHealthcheck([
      {
        name: 'create_order_with_items',
        signature:
          'public.create_order_with_items(uuid,uuid,integer,text,json)',
        parameters: [
          { name: 'p_session_id', type: 'uuid' },
          { name: 'p_user_id', type: 'uuid' },
          { name: 'p_total_price', type: 'integer' },
          { name: 'p_payment_method', type: 'text' },
          { name: 'p_items', type: 'json' },
        ],
        returnType: 'json',
        contract: expectedContract,
        present: false,
      },
    ]);

    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining(
        'public.create_order_with_items(uuid,uuid,uuid,integer,text,json)',
      ),
    );
    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining('2026-07-27-create-order-with-items-v2.sql'),
    );
  });

  it('rejects a six-argument RPC with the wrong parameter name', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation();

    await runHealthcheck([
      {
        name: 'create_order_with_items',
        signature:
          'public.create_order_with_items(uuid,uuid,uuid,integer,text,json)',
        parameters: [
          { name: 'session_id', type: 'uuid' },
          ...expectedParameters.slice(1),
        ],
        returnType: 'json',
        contract: expectedContract,
        present: true,
      },
    ]);

    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining('2026-07-27-create-order-with-items-v2.sql'),
    );
  });

  it('rejects an order RPC with a non-JSON return type', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation();

    await runHealthcheck([
      {
        name: 'create_order_with_items',
        signature:
          'public.create_order_with_items(uuid,uuid,uuid,integer,text,json)',
        parameters: expectedParameters,
        returnType: 'jsonb',
        contract: expectedContract,
        present: true,
      },
    ]);

    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining('2026-07-27-create-order-with-items-v2.sql'),
    );
  });

  it('accepts the exact six-argument order RPC contract', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation();
    jest.spyOn(console, 'log').mockImplementation();

    await runHealthcheck([
      {
        name: 'create_order_with_items',
        signature:
          'public.create_order_with_items(uuid,uuid,uuid,integer,text,json)',
        parameters: expectedParameters,
        returnType: 'json',
        contract: expectedContract,
        present: true,
      },
    ]);

    expect(warn).not.toHaveBeenCalled();
  });
});
