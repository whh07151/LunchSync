import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/api_retry.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 별점/리뷰 API 호출 서비스 (배민 패턴 — 2026-05-15 발전)
//
// 담당 엔드포인트:
//   PATCH /api/orders/:id/review              — 본인 주문에 별점/리뷰 작성
//   GET   /api/restaurants/:id/reviews        — 매장별 리뷰 + 평균 평점
//
// 데이터 모델:
//   - orders.review_score INT (1~5 CHECK)
//   - orders.review_text  TEXT (최대 500자)
//   - orders.review_at    TIMESTAMPTZ (작성 시각)
//   → 같은 PR DDL: backend/scripts/migrations/2026-05-15-add-order-review.sql
//
// 화면 사용:
//   - order_tracking_screen: COMPLETED 도달 시 "별점 남기기" 카드 + 바텀시트
//   - restaurant_detail_screen: AppBar 평점 표시 + 리뷰 화면 진입
//   - owner_home_screen: 매장 평점 카드 + 리뷰 리스트 화면
//   - restaurant_reviews_screen: 평균 + 리뷰 리스트 (신규)
// ══════════════════════════════════════════════════════════

/// 매장별 리뷰 단건 응답 DTO
///
/// 백엔드 OrdersService.getReviewsByRestaurant 에서 매핑된 형태와 동일.
/// 작성자 이름은 단축 표기를 위한 raw 값 — UI 에서 이니셜 또는 마스킹 처리.
class ReviewDto {
  const ReviewDto({
    required this.orderId,
    required this.score,
    required this.reviewAt,
    required this.userName,
    this.text,
  });

  /// 원본 주문 ID — 리뷰는 1주문 1리뷰 정책이라 PK 역할도 겸함.
  final String orderId;

  /// 별점 (1~5).
  final int score;

  /// 리뷰 본문 (선택, 최대 500자). null 가능.
  final String? text;

  /// 작성 시각 (ISO 8601 → DateTime 변환).
  /// 파싱 실패 시 호출부에서 안전하게 fallback 시각으로 처리.
  final DateTime reviewAt;

  /// 작성자 이름 (백엔드 join: users.name). 익명 처리 시 '익명'.
  final String userName;

  factory ReviewDto.fromJson(Map<String, dynamic> json) {
    // 백엔드 응답 키: id (= order id), score, text, at, authorName
    final atRaw = json['at'] as String?;
    return ReviewDto(
      orderId: (json['id'] as String?) ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      text: json['text'] as String?,
      reviewAt: atRaw != null
          ? (DateTime.tryParse(atRaw) ?? DateTime.now())
          : DateTime.now(),
      userName: (json['authorName'] as String?) ?? '익명',
    );
  }
}

/// 매장 리뷰 종합 응답
class RestaurantReviewsResult {
  const RestaurantReviewsResult({
    required this.averageScore,
    required this.count,
    required this.reviews,
  });

  /// 평균 평점 (소수점 1자리). 리뷰 0건이면 0.0.
  final double averageScore;

  /// 리뷰 총 개수.
  final int count;

  /// 최신순 리뷰 목록 (백엔드에서 최대 50건 제한).
  final List<ReviewDto> reviews;

  factory RestaurantReviewsResult.fromJson(Map<String, dynamic> json) {
    final rawReviews = json['reviews'] as List<dynamic>? ?? const [];
    return RestaurantReviewsResult(
      averageScore: (json['averageScore'] as num?)?.toDouble() ?? 0.0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      reviews: rawReviews
          .whereType<Map<String, dynamic>>()
          .map(ReviewDto.fromJson)
          .toList(),
    );
  }

  /// 빈 상태 — 토큰 없음/네트워크 실패 시 호출부 fallback.
  static const RestaurantReviewsResult empty = RestaurantReviewsResult(
    averageScore: 0.0,
    count: 0,
    reviews: <ReviewDto>[],
  );
}

class ReviewsApiService {
  const ReviewsApiService();

  Map<String, String> _headers(String accessToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

  // ── PATCH /api/orders/:id/review ──────────────────────────
  // 본인 주문에 별점/리뷰 작성 (또는 덮어쓰기).
  //
  // 입력 검증은 백엔드 OrdersService.addReview 가 책임지지만,
  // 클라이언트도 score 1~5 / text 500자 범위만 호출하도록 호출부에서 가드.
  //
  // 반환: 성공 시 true, 실패(권한/상태/네트워크) 시 false.
  Future<bool> submitReview({
    required String accessToken,
    required String orderId,
    required int score,
    String? text,
  }) async {
    try {
      final body = jsonEncode({
        'score': score,
        // null 이면 키 자체를 보내지 않아 백엔드 IsOptional 매핑이 안전.
        if (text != null && text.isNotEmpty) 'text': text,
      });

      final response = await http
          .patch(
            Uri.parse('${AppConfig.backendBaseUrl}/orders/$orderId/review'),
            headers: _headers(accessToken),
            body: body,
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
      debugPrint(
        '[ReviewsApi] SUBMIT_REVIEW_HTTP_${response.statusCode}',
      );
      return false;
    } catch (e) {
      debugPrint('[ReviewsApi] SUBMIT_REVIEW_FAILED');
      return false;
    }
  }

  // ── GET /api/restaurants/:id/reviews ──────────────────────
  // 매장별 평균 평점 + 최근 리뷰 50건. 인증 필요(JwtAuthGuard).
  //
  // 사장 어플(매장 평점 카드/리뷰 화면) + 손님 식당 상세(평점 칩) 양쪽에서 호출.
  Future<RestaurantReviewsResult> getReviewsByRestaurant({
    required String accessToken,
    required String restaurantId,
  }) async {
    try {
      final response = await ApiRetry.get(
        Uri.parse(
          '${AppConfig.backendBaseUrl}/restaurants/$restaurantId/reviews',
        ),
        headers: _headers(accessToken),
        timeout: AppConfig.apiTimeout,
      );
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>?;
        if (data == null) return RestaurantReviewsResult.empty;
        return RestaurantReviewsResult.fromJson(data);
      }
      debugPrint(
        '[ReviewsApi] GET_REVIEWS_HTTP_${response.statusCode}',
      );
      return RestaurantReviewsResult.empty;
    } catch (e) {
      debugPrint('[ReviewsApi] GET_REVIEWS_FAILED');
      return RestaurantReviewsResult.empty;
    }
  }
}
