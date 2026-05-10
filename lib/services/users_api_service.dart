import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 유저 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   PATCH /api/users/me — 온보딩 완료 시 이름/소속/조건 저장
//   GET   /api/users/me — 내 프로필 조회
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
  final List<String> allergies; // 알레르기 목록 (CU-04)
  final List<String> dislikes;  // 비선호 음식 목록 (CU-04)

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
    );
  }
}


class UsersApiService {
  const UsersApiService();

  // ── GET /api/users/me ────────────────────────────────
  // DB에서 내 프로필 최신 정보 조회
  // accessToken: userProvider에서 가져온 JWT
  // 반환: UserProfile (성공) / null (실패)
  Future<UserProfile?> getMe(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/users/me'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        return UserProfile.fromJson(data);
      }

      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[UsersApiService] getMe 에러: $e');
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

      final response = await http.patch(
        Uri.parse('${AppConfig.backendBaseUrl}/users/me'),
        headers: {
          'Content-Type': 'application/json',
          // JWT 인증: NestJS JwtAuthGuard가 이 헤더로 user_id 추출
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(body),
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
