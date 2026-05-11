import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 알림(Notifications) API 호출 서비스
//
// 담당 엔드포인트:
//   GET   /api/notifications              — 내 알림 목록 (최신 50개)
//   PATCH /api/notifications/:id/read     — 단건 읽음 처리
//   PATCH /api/notifications/read-all     — 전체 읽음 처리
// ══════════════════════════════════════════════════════════

/// 알림 DTO — 서버 응답과 1:1 매핑
///
/// createdAt은 ISO 8601 문자열 그대로 받고, UI에서 "방금 전" 등으로 포맷.
class NotificationDto {
  const NotificationDto({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String type; // ORDER_RECEIVED | ORDER_ACCEPTED | ORDER_DONE | VOTE_RESULT
  final String title;
  final String message;
  final bool isRead;
  final String createdAt; // ISO 8601 문자열

  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    return NotificationDto(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      isRead: json['isRead'] as bool? ?? false,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  // 읽음 상태 변경 시 새 객체 반환 (불변 패턴)
  NotificationDto copyWith({bool? isRead}) {
    return NotificationDto(
      id: id,
      type: type,
      title: title,
      message: message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}

class NotificationsApiService {
  const NotificationsApiService();

  Map<String, String> _headers(String accessToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

  // ── GET /api/notifications ────────────────────────────
  Future<List<NotificationDto>> getMyNotifications({
    required String accessToken,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/notifications'),
        headers: _headers(accessToken),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;
        return list
            .map((e) => NotificationDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[NotificationsApiService] getMyNotifications 에러: $e');
      return [];
    }
  }

  // ── PATCH /api/notifications/:id/read ─────────────────
  Future<bool> markAsRead({
    required String accessToken,
    required String notificationId,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse(
            '${AppConfig.backendBaseUrl}/notifications/$notificationId/read'),
        headers: _headers(accessToken),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── PATCH /api/notifications/read-all ─────────────────
  Future<bool> markAllAsRead({required String accessToken}) async {
    try {
      final response = await http.patch(
        Uri.parse('${AppConfig.backendBaseUrl}/notifications/read-all'),
        headers: _headers(accessToken),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
