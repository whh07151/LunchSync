import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../core/debug/debug_toast.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-22 알림함 화면
//
// 와이어프레임 기준 구성 요소:
//   - 상단 앱바: "알림" 타이틀 + "전체 읽음" 버튼
//   - 알림 카드 목록: 타입별 아이콘 + 제목 + 메시지 + 시간
//   - 읽지 않은 알림: 왼쪽 파란 점 + 배경 강조
//   - 읽은 알림: 기본 배경
//   - 빈 상태: "새 알림이 없어요" 안내
//
// 알림 4종 (명세서 기준):
//   ORDER_RECEIVED  — 점주에게 주문이 들어왔을 때
//   ORDER_ACCEPTED  — 점주가 주문을 수락했을 때
//   ORDER_DONE      — 조리 완료, 수령 요청
//   VOTE_RESULT     — 투표 결과 확정
//
// 동작 흐름:
//   홈 상단 알림 아이콘 탭 → 이 화면(push)
//   알림 카드 탭 → 읽음 처리 (상태 변경)
//   "전체 읽음" 탭 → 모든 알림 읽음 처리
//
// TODO: API 연동 시 교체 지점:
//   _mockNotifications → GET /notifications 응답으로 교체
//   _markAsRead()      → PATCH /notifications/:id/read 호출
//   _markAllAsRead()   → PATCH /notifications/read-all 호출 (또는 개별 반복)
// ══════════════════════════════════════════════════════════

// ── 알림 타입 enum ────────────────────────────────────────
// DB의 type VARCHAR(50) 값과 1:1 대응
enum NotificationType {
  orderReceived,  // ORDER_RECEIVED
  orderAccepted,  // ORDER_ACCEPTED
  orderDone,      // ORDER_DONE
  voteResult,     // VOTE_RESULT
}

// ── 알림 데이터 모델 ──────────────────────────────────────
// GET /notifications 응답의 notifications 배열 한 항목에 대응
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAtLabel,
    this.isRead = false,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final String createdAtLabel; // "방금 전", "20분 전" 등 서버에서 계산해서 내려줌
  final bool isRead;

  // 읽음 상태 변경 시 새 객체 반환 (불변 패턴)
  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      type: type,
      title: title,
      message: message,
      createdAtLabel: createdAtLabel,
      isRead: isRead ?? this.isRead,
    );
  }
}


class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {

  // ── Mock 알림 데이터 ──────────────────────────────────────
  // TODO: API 연동 시 — initState에서 GET /notifications 호출로 교체
  // 알림 4종을 모두 포함해서 데모 시 보여줄 수 있도록 구성
  late List<NotificationItem> _notifications = [
    const NotificationItem(
      id: 'notif_001',
      type: NotificationType.orderAccepted,
      title: '주문이 수락되었습니다',
      message: '한솥도시락에서 주문을 수락했습니다. 약 15분 후 완료 예정이에요.',
      createdAtLabel: '방금 전',
      isRead: false,
    ),
    const NotificationItem(
      id: 'notif_002',
      type: NotificationType.voteResult,
      title: '투표 결과가 나왔습니다',
      message: '개발팀 점심 세션에서 한솥도시락이 선택되었습니다.',
      createdAtLabel: '20분 전',
      isRead: false,
    ),
    const NotificationItem(
      id: 'notif_003',
      type: NotificationType.orderDone,
      title: '조리가 완료되었습니다',
      message: '주문하신 음식이 준비됐어요. 지금 수령하러 가세요!',
      createdAtLabel: '어제',
      isRead: true,
    ),
    const NotificationItem(
      id: 'notif_004',
      type: NotificationType.orderReceived,
      title: '새 주문이 들어왔습니다',
      message: '개발팀 4명이 도시락을 주문했습니다.',
      createdAtLabel: '어제',
      isRead: true,
    ),
  ];

  // ── 읽지 않은 알림 수 계산 ────────────────────────────────
  // 상단 "전체 읽음" 버튼 표시 여부와 배지 카운트에 사용
  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  // ── 생명주기: 화면 초기화 ─────────────────────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-22');
  }

  // ── 알림 단건 읽음 처리 ──────────────────────────────────
  // 카드 탭 시 호출
  // TODO: API 연동 시 — PATCH /notifications/:id/read 호출 추가
  void _markAsRead(String id) {
    setState(() {
      _notifications = _notifications.map((n) {
        return n.id == id ? n.copyWith(isRead: true) : n;
      }).toList();
    });
  }

  // ── 전체 읽음 처리 ──────────────────────────────────────
  // 상단 "전체 읽음" 버튼 탭 시 호출
  // TODO: API 연동 시 — 각 미읽음 알림에 PATCH /notifications/:id/read 반복 호출
  void _markAllAsRead() {
    setState(() {
      _notifications = _notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
    });
  }

  // ── UI 구성 ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      // ── 앱바: 타이틀 + 전체 읽음 버튼 ───────────────────
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          // 뒤로가기: 홈 화면으로 복귀
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '알림',
          style: AppTextStyles.heading3.copyWith(color: AppColors.textPrimary),
        ),
        centerTitle: false,
        actions: [
          // "전체 읽음" 버튼: 읽지 않은 알림이 있을 때만 활성화
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                '전체 읽음',
                style: AppTextStyles.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          // 앱바 아래 얇은 구분선
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),

      body: _notifications.isEmpty
          ? _buildEmptyState()   // 알림 없을 때
          : _buildNotificationList(), // 알림 있을 때
    );
  }

  // ── 알림 목록 위젯 ────────────────────────────────────────
  // 각 알림을 카드 형태로 나열
  Widget _buildNotificationList() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _notifications.length,
      // 알림 카드 사이 구분선
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, index) {
        return _buildNotificationCard(_notifications[index]);
      },
    );
  }

  // ── 알림 카드 위젯 ────────────────────────────────────────
  // 탭하면 읽음 처리됨
  Widget _buildNotificationCard(NotificationItem item) {
    final isUnread = !item.isRead;

    return InkWell(
      onTap: () => _markAsRead(item.id),
      child: Container(
        // 읽지 않은 알림은 연한 주황 배경으로 강조
        color: isUnread
            ? Theme.of(context).colorScheme.primary.withAlpha(12)
            : AppColors.background,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 알림 타입 아이콘 ────────────────────────
            _buildTypeIcon(item.type, isUnread),

            const SizedBox(width: AppSpacing.md),

            // ── 알림 내용 텍스트 ────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 제목 + 시간 한 줄
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: isUnread
                                ? FontWeight.w600  // 미읽음: 굵게
                                : FontWeight.w400, // 읽음: 보통
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // 시간 레이블 (서버에서 내려온 "방금 전", "20분 전" 등)
                      Text(
                        item.createdAtLabel,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // 알림 메시지
                  Text(
                    item.message,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // ── 읽지 않음 파란 점 배지 ──────────────────
            if (isUnread) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 알림 타입 아이콘 위젯 ─────────────────────────────────
  // 타입에 따라 아이콘과 배경색이 달라짐
  Widget _buildTypeIcon(NotificationType type, bool isUnread) {
    // 타입별 아이콘 및 색상 정의
    final IconData icon;
    final Color color;

    switch (type) {
      case NotificationType.orderReceived:
        // 주문 접수: 영수증 아이콘, 초록색
        icon = Icons.receipt_long_rounded;
        color = const Color(0xFF4CAF50);
      case NotificationType.orderAccepted:
        // 주문 수락: 체크 아이콘, 파란색
        icon = Icons.check_circle_outline_rounded;
        color = const Color(0xFF2196F3);
      case NotificationType.orderDone:
        // 조리 완료: 식기 아이콘, 주황색 (앱 primary)
        icon = Icons.restaurant_rounded;
        color = Theme.of(context).colorScheme.primary;
      case NotificationType.voteResult:
        // 투표 결과: 트로피 아이콘, 황금색
        icon = Icons.emoji_events_rounded;
        color = const Color(0xFFFFC107);
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        // 아이콘 배경: 해당 색의 연한 버전
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  // ── 빈 상태 위젯 ─────────────────────────────────────────
  // 알림이 하나도 없을 때 표시
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 64,
            color: AppColors.textSecondary.withAlpha(80),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '새 알림이 없어요',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '점심 세션 진행 중 알림이 여기에 표시됩니다',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
