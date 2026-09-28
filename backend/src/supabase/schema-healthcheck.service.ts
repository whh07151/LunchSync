// ══════════════════════════════════════════════════════════
// 파일 역할: 부트 시 DB 스키마 무결성 헬스체크
//
// 왜 만들었는가? (2026-05-14 image_url silent failure 사고)
//   PostgREST 는 select 에 누락된 컬럼이 있어도 에러를 내지 않고
//   조용히 무시 → 코드는 정상, DB 응답은 빈 칸. 빌드/analyze 만으로는
//   누락된 마이그레이션을 절대 잡을 수 없음.
//
//   따라서 NestJS 부트 시 information_schema 를 조회해
//   기대 자원이 모두 존재하는지 1회 검증하고, 누락된 자원은
//   console.warn 으로 명시적으로 노출.
//
// 동작:
//   1. onModuleInit 훅에서 RPC `check_schema_resources` 호출
//      (현재 응답 계약은 2026-07-29-schema-introspection-function-signatures.sql 에 정의)
//   2. 응답 JSON 의 columns/tables/functions 배열을 순회
//   3. present=false 인 자원이 있으면 누락 항목을 console.warn 로 출력
//      + 적용해야 할 마이그레이션 파일명 안내
//   4. 모두 정상이면 console.log 1줄로 종료 (시연 환경 noise 최소화)
//   5. RPC 자체가 실패하면 (예: RPC 미배포 상황) console.warn 으로 안내
//
// 원칙:
//   - 부트 자체는 절대 막지 않음 — warn 로그만
//   - ERROR 가 아닌 WARN 으로 — silent failure 디버깅 시
//     즉시 보이게 하기 위함이지 부팅 실패를 유발하기 위함이 아님
//   - 시연 환경에서 정상이면 단 1줄 로그
// ══════════════════════════════════════════════════════════

import { Injectable, OnModuleInit } from '@nestjs/common';
import { SupabaseService } from './supabase.service';

// RPC `check_schema_resources` 응답 타입
// (introspection RPC 가 반환하는 JSON 스키마와 1:1 매칭)
interface SchemaCheckResult {
  columns: Array<{ table: string; column: string; present: boolean }>;
  tables: Array<{ table: string; present: boolean }>;
  functions: Array<{
    name: string;
    signature?: string | null;
    parameters?: SchemaFunctionParameter[] | null;
    returnType?: string | null;
    contract?: SchemaFunctionContract | null;
    present: boolean;
  }>;
}

interface SchemaFunctionParameter {
  name: string;
  type: string;
}

interface SchemaFunctionContract {
  parameters: SchemaFunctionParameter[];
  returnType: string;
}

export interface SchemaReadinessStatus {
  ready: boolean;
  checked: boolean;
  missingCount: number;
  reason?:
    | 'not_checked'
    | 'missing_resources'
    | 'rpc_failed'
    | 'empty_response'
    | 'exception';
}

const CREATE_ORDER_WITH_ITEMS_PARAMETERS: SchemaFunctionParameter[] = [
  { name: 'p_session_id', type: 'uuid' },
  { name: 'p_user_id', type: 'uuid' },
  { name: 'p_restaurant_id', type: 'uuid' },
  { name: 'p_total_price', type: 'integer' },
  { name: 'p_payment_method', type: 'text' },
  { name: 'p_items', type: 'json' },
];

const CREATE_ORDER_WITH_ITEMS_SIGNATURE =
  'public.create_order_with_items(uuid,uuid,uuid,integer,text,json)';
const CREATE_ORDER_WITH_ITEMS_RETURN_TYPE = 'json';
const CREATE_ORDER_CONTRACT_METADATA =
  'check_schema_resources.create_order_with_items.contract';

function hasExpectedOrderParameters(
  parameters: SchemaFunctionParameter[] | null | undefined,
): boolean {
  return (
    Array.isArray(parameters) &&
    parameters.length === CREATE_ORDER_WITH_ITEMS_PARAMETERS.length &&
    parameters.every((parameter, index) => {
      const expected = CREATE_ORDER_WITH_ITEMS_PARAMETERS[index];
      return (
        parameter.name === expected.name && parameter.type === expected.type
      );
    })
  );
}

function hasExpectedOrderContract(
  contract: SchemaFunctionContract | null | undefined,
): boolean {
  return (
    contract?.returnType === CREATE_ORDER_WITH_ITEMS_RETURN_TYPE &&
    hasExpectedOrderParameters(contract.parameters)
  );
}

// Fixed repository filenames only; no database response text is logged.
const MIGRATION_HINTS: Record<string, string> = {
  'restaurants.image_url': '2026-05-14-fill-empty-image-urls.sql',
  'restaurants.rating': '2026-05-14-add-rating-column.sql',
  'users.fcm_token': '2026-05-14-add-fcm-token.sql',
  'sessions.radius': '2026-05-14-ensure-sessions-columns.sql',
  'sessions.budget': '2026-05-14-ensure-sessions-columns.sql',
  'sessions.return_minutes': '2026-05-14-ensure-sessions-columns.sql',
  'sessions.memo': '2026-05-14-ensure-sessions-columns.sql',
  pos_seats: '2026-05-14-add-pos-tables.sql',
  pos_reservations: '2026-05-14-add-pos-reservations.sql',
  delete_session_cascade: '2026-05-13-delete-session-rpc.sql',
  [CREATE_ORDER_CONTRACT_METADATA]:
    '2026-07-29-schema-introspection-function-signatures.sql',
  [CREATE_ORDER_WITH_ITEMS_SIGNATURE]:
    '2026-07-27-create-order-with-items-v2.sql',
  create_session_with_host_member: '2026-05-14-create-session-rpc.sql',
};

@Injectable()
export class SchemaHealthcheckService implements OnModuleInit {
  private status: SchemaReadinessStatus = {
    ready: false,
    checked: false,
    missingCount: 0,
    reason: 'not_checked',
  };

  constructor(private readonly supabase: SupabaseService) {}

  getReadinessStatus(): SchemaReadinessStatus {
    return { ...this.status };
  }

  /**
   * NestJS 부트 사이클: 모든 모듈 의존성 주입이 완료된 직후 1회 호출.
   * 실패해도 부트는 계속 진행 (warn 로그만 남기고 return).
   */
  async onModuleInit(): Promise<void> {
    try {
      // service_role 키로 RPC 호출 → information_schema 접근 권한 보장
      const { data, error } = await this.supabase.client.rpc(
        'check_schema_resources',
      );

      if (error) {
        // RPC 가 아예 배포되지 않은 환경(=초기 셋업) 도 여기에 해당.
        // 부팅을 막지 않고 안내만 출력.
        console.warn(
          '[SchemaHealthcheck] SCHEMA_INTROSPECTION_RPC_FAILED; apply 2026-07-29-schema-introspection-function-signatures.sql',
        );
        this.status = {
          ready: false,
          checked: true,
          missingCount: 0,
          reason: 'rpc_failed',
        };
        return;
      }

      // RPC 가 정상 응답이지만 페이로드가 비어있는 비정상 케이스
      if (!data) {
        this.status = {
          ready: false,
          checked: true,
          missingCount: 0,
          reason: 'empty_response',
        };
        console.warn(
          '[SchemaHealthcheck] introspection RPC 응답이 비어있습니다.',
        );
        return;
      }

      const result = data as SchemaCheckResult;

      // 누락 자원을 한 곳으로 모음 — "테이블.컬럼" / "테이블" / "함수명" 키 형태
      const missing: string[] = [];

      for (const col of result.columns ?? []) {
        if (!col.present) {
          missing.push(`${col.table}.${col.column}`);
        }
      }
      for (const tbl of result.tables ?? []) {
        if (!tbl.present) {
          missing.push(tbl.table);
        }
      }
      for (const fn of result.functions ?? []) {
        if (fn.name === 'create_order_with_items') {
          if (
            !Object.prototype.hasOwnProperty.call(fn, 'contract') ||
            !hasExpectedOrderContract(fn.contract)
          ) {
            missing.push(CREATE_ORDER_CONTRACT_METADATA);
          } else if (
            !fn.present ||
            fn.signature !== CREATE_ORDER_WITH_ITEMS_SIGNATURE ||
            !hasExpectedOrderParameters(fn.parameters) ||
            fn.returnType !== CREATE_ORDER_WITH_ITEMS_RETURN_TYPE
          ) {
            missing.push(CREATE_ORDER_WITH_ITEMS_SIGNATURE);
          }
        } else if (!fn.present) {
          missing.push(fn.name);
        }
      }

      this.status =
        missing.length === 0
          ? {
              ready: true,
              checked: true,
              missingCount: 0,
            }
          : {
              ready: false,
              checked: true,
              missingCount: missing.length,
              reason: 'missing_resources',
            };

      if (missing.length === 0) {
        // 시연 환경 noise 최소화 — 정상은 단 1줄
        console.log('[SchemaHealthcheck] 스키마 무결성 확인 완료');
        return;
      }

      const lines = missing.map((key) => {
        const hint = MIGRATION_HINTS[key] ?? 'migration-not-mapped';
        return `    - ${key} -> ${hint}`;
      });

      console.warn(
        `[SchemaHealthcheck] SCHEMA_RESOURCES_MISSING count=${missing.length}\n` +
          lines.join('\n'),
      );
    } catch {
      // 네트워크 오류 등 예기치 못한 실패에도 부트는 계속.
      console.warn('[SchemaHealthcheck] SCHEMA_HEALTHCHECK_EXCEPTION');
      this.status = {
        ready: false,
        checked: true,
        missingCount: 0,
        reason: 'exception',
      };
    }
  }
}
