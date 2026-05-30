import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../core/api/api_auth_hooks.dart';
import '../core/api/http_headers_helper.dart';
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 친구 관계 관련 API 호출 서비스 (CU-08 보강)
//
// 담당 엔드포인트:
//   POST   /api/friends                — 이메일로 친구 추가
//   GET    /api/friends                — 내 친구 목록 조회
//   DELETE /api/friends/:friendUserId  — 친구 삭제 (양방향)
//
// 흐름:
//   - 로그인한 사용자의 JWT(accessToken) 를 Authorization 헤더로 전달
//   - 백엔드 friends 모듈이 양방향 INSERT/DELETE 트랜잭션 처리
//   - 응답은 { success: true, data: ... } 형식이라 data 만 뽑아서 반환
//
// 에러 처리 정책:
//   - 네트워크/타임아웃 등 예외는 catch 후 null/false 반환
//   - HTTP 400/404/409 같은 비즈니스 에러는 호출자가 분기할 수 있도록
//     AddFriendResult sealed 클래스로 결과를 명확히 구분
//   - 401 응답은 ApiAuthHooks.check 가 글로벌 로그아웃 처리
// ══════════════════════════════════════════════════════════

/// 친구 1명 데이터 모델 (백엔드 FriendDto 와 1:1 매칭)
///
/// 필드 의미:
///   id           — 친구 사용자 UUID (users.id 와 동일)
///   name         — 친구 이름 (표시용)
///   email        — 친구 이메일 (가입 시 입력값) — null 가능
///   profileImage — 카카오 프로필 이미지 URL — null 가능
///   since        — 친구가 된 시각 ISO8601 문자열 (정렬용)
class FriendDto {
  const FriendDto({
    required this.id,
    required this.name,
    required this.email,
    required this.profileImage,
    required this.since,
  });

  final String id;
  final String name;
  final String? email;
  final String? profileImage;
  final String since;

  /// 백엔드 응답 JSON → FriendDto 변환
  factory FriendDto.fromJson(Map<String, dynamic> json) {
    return FriendDto(
      id: json['id'] as String,
      // 이름이 없는 데이터 보호 (백엔드는 항상 채워주지만 방어적)
      name: (json['name'] as String?) ?? '이름 없음',
      email: json['email'] as String?,
      profileImage: json['profileImage'] as String?,
      since: (json['since'] as String?) ?? '',
    );
  }
}

// ── 친구 추가 결과 타입 ─────────────────────────────────────
// 호출 화면에서 SnackBar 메시지를 분기하기 쉽도록 sealed 클래스로 묶음
sealed class AddFriendResult {
  const AddFriendResult();

  /// 정상 추가 (data 에 새로 추가된 FriendDto 포함)
  const factory AddFriendResult.success(FriendDto friend) = AddFriendSuccess;

  /// 이메일에 해당하는 가입 사용자가 없을 때 (HTTP 404)
  const factory AddFriendResult.notFound() = AddFriendNotFound;

  /// 이미 친구로 등록되어 있을 때 (HTTP 409)
  const factory AddFriendResult.duplicate() = AddFriendDuplicate;

  /// 본인 자신을 추가하려 한 경우 등 잘못된 요청 (HTTP 400)
  const factory AddFriendResult.invalid(String message) = AddFriendInvalid;

  /// 네트워크/서버 오류 — 사용자에게는 친근하게 "다시 시도해봐요" 안내
  const factory AddFriendResult.error() = AddFriendError;
}

class AddFriendSuccess extends AddFriendResult {
  const AddFriendSuccess(this.friend);
  final FriendDto friend;
}

class AddFriendNotFound extends AddFriendResult {
  const AddFriendNotFound();
}

class AddFriendDuplicate extends AddFriendResult {
  const AddFriendDuplicate();
}

class AddFriendInvalid extends AddFriendResult {
  const AddFriendInvalid(this.message);
  final String message;
}

class AddFriendError extends AddFriendResult {
  const AddFriendError();
}

class FriendsApiService {
  const FriendsApiService();

  // ── 공용 헤더 빌더 ────────────────────────────────────────
  // 2026-05-30 헤더 빌더 통합: 공통 헬퍼 apiHeaders() 로 이관
  //   (lib/core/api/http_headers_helper.dart). 9개 서비스 중복 제거.

  // ── POST /api/friends — 이메일로 친구 추가 ────────────────
  //
  // 백엔드 동작:
  //   1) 이메일로 users 테이블에서 상대 조회
  //   2) 자기 자신/이미 친구/없는 사용자 검증
  //   3) 양방향 2건 INSERT (UNIQUE 제약 위반 → 409)
  //
  // 반환 타입은 AddFriendResult — 호출자가 SnackBar 톤을 분기 가능
  Future<AddFriendResult> addFriend({
    required String accessToken,
    required String email,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/friends'),
            headers: apiHeaders(accessToken),
            body: jsonEncode({'email': email.trim()}),
          )
          .timeout(AppConfig.apiTimeout);
      // 401 자동 로그아웃 글로벌 훅
      ApiAuthHooks.check(response.statusCode);

      // 정상 추가 (201 Created or 200 OK)
      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        return AddFriendResult.success(FriendDto.fromJson(data));
      }

      // 잘못된 요청 (자기 자신 추가, 이메일 형식 오류 등)
      if (response.statusCode == 400) {
        final message = _extractMessage(response.body) ??
            '이메일을 다시 확인해주세요.';
        return AddFriendResult.invalid(message);
      }

      // 가입 사용자 없음
      if (response.statusCode == 404) {
        return const AddFriendResult.notFound();
      }

      // 이미 친구로 등록되어 있음
      if (response.statusCode == 409) {
        return const AddFriendResult.duplicate();
      }

      debugPrint(
        '[FriendsApiService] addFriend 실패: '
        '${response.statusCode} ${response.body}',
      );
      return const AddFriendResult.error();
    } catch (e) {
      debugPrint('[FriendsApiService] addFriend 에러: $e');
      return const AddFriendResult.error();
    }
  }

  // ── GET /api/friends — 내 친구 목록 조회 ──────────────────
  //
  // 반환:
  //   - 성공: FriendDto 리스트 (최신 추가 순)
  //   - 실패: 빈 리스트 (호출자가 로딩 종료만 처리하면 됨)
  Future<List<FriendDto>> listFriends({required String accessToken}) async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.backendBaseUrl}/friends'),
            headers: apiHeaders(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (json['data'] as List<dynamic>?) ?? const [];
        // 각 item 을 FriendDto 로 변환 (방어적 캐스트)
        return list
            .map((e) => FriendDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      debugPrint(
        '[FriendsApiService] listFriends 실패: ${response.statusCode}',
      );
      return const [];
    } catch (e) {
      debugPrint('[FriendsApiService] listFriends 에러: $e');
      return const [];
    }
  }

  // ── DELETE /api/friends/:friendUserId — 친구 삭제 ────────
  //
  // 백엔드가 양방향(2건) 삭제를 한 번에 처리.
  // 반환:
  //   - true: 삭제 성공
  //   - false: 네트워크/서버 오류 (호출자가 SnackBar 처리)
  Future<bool> removeFriend({
    required String accessToken,
    required String friendUserId,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${AppConfig.backendBaseUrl}/friends/$friendUserId'),
            headers: apiHeaders(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      }
      debugPrint(
        '[FriendsApiService] removeFriend 실패: ${response.statusCode}',
      );
      return false;
    } catch (e) {
      debugPrint('[FriendsApiService] removeFriend 에러: $e');
      return false;
    }
  }

  // ── 응답 body 에서 NestJS 표준 메시지 필드 추출 헬퍼 ──────
  // NestJS 예외는 { "message": "...", "error": "...", "statusCode": ... } 형태로 옵니다.
  // 메시지가 문자열 배열일 수도 있어서(class-validator) 둘 다 처리.
  String? _extractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message'];
        if (msg is String) return msg;
        if (msg is List && msg.isNotEmpty) return msg.first.toString();
      }
    } catch (_) {
      // 파싱 실패는 무시 (기본 안내 문구로 fallback)
    }
    return null;
  }
}
