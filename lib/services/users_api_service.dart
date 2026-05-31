import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/api_retry.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 유저 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   PATCH /api/users/me              — 온보딩 완료 시 이름/소속/조건 저장
//   PATCH /api/users/me/preferences  — CU-04 취향/알레르기/비선호 카테고리 일괄 저장
//   GET   /api/users/me              — 내 프로필 조회
// ══════════════════════════════════════════════════════════

// GET /api/users/me 응답 데이터 모델
// 백엔드 users.service.ts의 getMe() 반환값과 필드 구조 동일
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    this.org,
    this.profileImage,
    this.radius,
    this.budget,
    this.speed,
    this.role,
    this.status,
    this.authProvider,
    this.email,
    this.phoneNumber,
    this.businessName,
    this.businessNumber,
    this.restaurantId,
    this.allergies = const [],
    this.dislikes = const [],
    // 2026-05-31 CU-04 — 추천 엔진이 읽는 구조화 취향 데이터
    this.tasteTags = const [],
    this.allergens = const [],
    this.dislikedCategories = const [],
  });

  final String id;
  final String name;
  final String? org;           // 소속 (온보딩 CU-03에서 입력)
  final String? profileImage;
  final String? radius;        // 반경 조건 (온보딩 CU-05에서 입력)
  final int? budget;           // 예산 조건
  final String? speed;         // 속도 조건
  final String? role;          // CUSTOMER | OWNER
  // 회원가입/인증 결정(2026-05-07) 추가 필드
  final String? status;          // PENDING | APPROVED | REJECTED
  final String? authProvider;    // KAKAO | EMAIL | PHONE
  final String? email;
  final String? phoneNumber;
  final String? businessName;    // OWNER 가게 상호
  final String? businessNumber;  // OWNER 사업자등록번호
  final String? restaurantId;    // OWNER가 운영하는 restaurants.id (운영자가 콘솔에서 매핑)
  final List<String> allergies; // 알레르기 자유 입력 키워드 (구버전)
  final List<String> dislikes;  // 비선호 음식 자유 입력 키워드 (구버전)

  // 2026-05-31 CU-04 — 추천 엔진 직접 참조 구조화 데이터.
  // 위 allergies/dislikes 와 의도적으로 분리: 표준 라벨만 들어옴.
  final List<String> tasteTags;          // 좋아하는 맛 (매콤/담백/짠/단/신/쓴)
  final List<String> allergens;          // 알레르기 식재료 (견과/유제품/계란 등)
  final List<String> dislikedCategories; // 비선호 카테고리 (한식/중식 등)

  // JSON 파싱: GET /api/users/me 응답의 data 필드에서 생성
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      org: json['org'] as String?,
      profileImage: json['profileImage'] as String?,
      radius: json['radius'] as String?,
      budget: json['budget'] as int?,
      speed: json['speed'] as String?,
      role: json['role'] as String?,
      status: json['status'] as String?,
      authProvider: json['authProvider'] as String?,
      email: json['email'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      businessName: json['businessName'] as String?,
      businessNumber: json['businessNumber'] as String?,
      restaurantId: json['restaurantId'] as String?,
      allergies: (json['allergies'] as List<dynamic>?)?.cast<String>() ?? [],
      dislikes: (json['dislikes'] as List<dynamic>?)?.cast<String>() ?? [],
      // 2026-05-31 CU-04 — 새 컬럼은 누락 시 빈 배열 fallback
      tasteTags:
          (json['tasteTags'] as List<dynamic>?)?.cast<String>() ?? const [],
      allergens:
          (json['allergens'] as List<dynamic>?)?.cast<String>() ?? const [],
      dislikedCategories:
          (json['dislikedCategories'] as List<dynamic>?)?.cast<String>() ??
              const [],
    );
  }
}


class UsersApiService {
  const UsersApiService();

  // ── GET /api/users/me ────────────────────────────────
  // DB에서 내 프로필 최신 정보 조회
  // accessToken: userProvider에서 가져온 JWT
  // 반환: UserProfile (성공) / null (실패)
  //
  // timeout 적용 (2026-05-12 박검토B 긴급):
  //   main.dart `_bootSequence` 가 이 호출을 await 하므로 네트워크 끊김 시
  //   스플래시 화면 무한 로딩으로 멈춤. AppConfig.apiTimeout 으로 강제 종료.
  Future<UserProfile?> getMe(String accessToken) async {
    try {
      final response = await ApiRetry.get(
        Uri.parse('${AppConfig.backendBaseUrl}/users/me'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        return UserProfile.fromJson(data);
      }

      return null;
    } catch (e) {
      debugPrint('[UsersApiService] getMe 에러: $e');
      return null;
    }
  }

  // ── PATCH /api/users/me ───────────────────────────────
  // 온보딩(CU-03 + CU-05) 완료 시 호출
  // accessToken: userProvider에서 가져온 JWT
  // 성공: true / 실패: false
  Future<bool> updateMe({
    required String accessToken,
    String? name,
    String? org,
    String? radius,
    int? budget,
    String? speed,
    List<String>? allergies,
    List<String>? dislikes,
    // OWNER 전용 — 사장 내정보 탭에서 상호/사업자번호 수정
    String? businessName,
    String? businessNumber,
  }) async {
    try {
      // null이 아닌 필드만 요청 바디에 포함
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (org != null) body['org'] = org;
      if (radius != null) body['radius'] = radius;
      if (budget != null) body['budget'] = budget;
      if (speed != null) body['speed'] = speed;
      if (allergies != null) body['allergies'] = allergies;
      if (dislikes != null) body['dislikes'] = dislikes;
      if (businessName != null) body['businessName'] = businessName;
      if (businessNumber != null) body['businessNumber'] = businessNumber;

      final response = await http
          .patch(
            Uri.parse('${AppConfig.backendBaseUrl}/users/me'),
            headers: {
              'Content-Type': 'application/json',
              // JWT 인증: NestJS JwtAuthGuard가 이 헤더로 user_id 추출
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── PATCH /api/users/me/preferences ──────────────────
  // 2026-05-31 CU-04 — 취향/알레르기/비선호 카테고리 일괄 저장.
  //
  // 추천 엔진이 직접 읽는 구조화 데이터라서 일반 PATCH /users/me 와
  // 분리 엔드포인트로 운용. 빈 배열 []을 보내면 "모두 해제" 의 의미.
  //
  // 반환:
  //   { tasteTags, allergens, dislikedCategories } — 서버가 저장한 최종값.
  //   실패(네트워크/4xx/5xx) 시 null.
  Future<Map<String, List<String>>?> updatePreferences({
    required String accessToken,
    List<String>? tasteTags,
    List<String>? allergens,
    List<String>? dislikedCategories,
  }) async {
    try {
      // null 이 아닌 필드만 바디에 포함 → 부분 업데이트
      final body = <String, dynamic>{};
      if (tasteTags != null) body['tasteTags'] = tasteTags;
      if (allergens != null) body['allergens'] = allergens;
      if (dislikedCategories != null) {
        body['dislikedCategories'] = dislikedCategories;
      }

      final response = await http
          .patch(
            Uri.parse('${AppConfig.backendBaseUrl}/users/me/preferences'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode != 200) {
        debugPrint(
          '[UsersApiService] updatePreferences 실패: ${response.statusCode}',
        );
        return null;
      }

      // 응답 파싱 — 백엔드 응답: { success, data: { tasteTags, allergens, dislikedCategories } }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      return {
        'tasteTags':
            (data['tasteTags'] as List<dynamic>?)?.cast<String>() ?? const [],
        'allergens':
            (data['allergens'] as List<dynamic>?)?.cast<String>() ?? const [],
        'dislikedCategories':
            (data['dislikedCategories'] as List<dynamic>?)?.cast<String>() ??
                const [],
      };
    } catch (e) {
      debugPrint('[UsersApiService] updatePreferences 에러: $e');
      return null;
    }
  }
}
