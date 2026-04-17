import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/notifications_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-22 알림함 화면
//
// 와이어프레임 기준 구성:
//   - 상단 앱바: "알림" 타이틀 + "전체 읽음" 버튼 (미읽음 있을 때만)
//   - 알림 카드 목록: 타입별 아이콘 + 제목 + 메시지 + 시간
//   - 미읽음: 배경 강조 + 오른쪽 파란 점
//   - 빈 상태: "새 알림이 없어요"
//
// 연동 API:
//   GET   /api/notifications              — 목록 (최신 50개)
//   PATCH /api/notifications/:id/read     — 단건 읽음
//   PATCH /api/notifications/read-all     — 전체 읽음
//
// 알림 타입 4종 (서버 type 값과 매핑):
//   ORDER_RECEIVED / ORDER_ACCEPTED / ORDER_DONE / VOTE_RESULT
// ══════════════════════════════════════════════════════════

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() =>
      _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  static const _api = NotificationsApiService();

  List<NotificationDto>? _notifications;
  bool _isLoading = true;

  // 미읽음 개수 — "전체 읽음" 버튼 표시 여부에 사용
  int get _unreadCount =>
      _notifications?.where((n) => !n.isRead).length ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-22');
      _load();
    });
  }

  // ── 알림 목록 조회 ─────────────────────────────────────
  Future<void> _load() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final list = await _api.getMyNotifications(accessToken: token);
    if (!mounted) return;
    setState(() {
      _notifications = list;
      _isLoading = false;
    });
  }

  // ── 단건 읽음 처리 ─────────────────────────────────────
  // 낙관적 업데이트: UI를 먼저 바꾸고 서버 호출 → 실패 시 롤백
  Future<void> _markAsRead(NotificationDto item) async {
    if (item.isRead) return; // 이미 읽음
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    // UI 선반영
    setState(() {
      _notifications = _notifications
          ?.map((n) => n.id == item.id ? n.copyWith(isRead: true) : n)
          .toList();
    });

    final ok = await _api.markAsRead(
      accessToken: token,
      notificationId: item.id,
    );

    // 실패 시 롤백 (서버 상태가 불일치하지 않도록)
    if (!ok && mounted) {
      setState(() {
        _notifications = _notifications
            ?.map((n) => n.id == item.id ? n.copyWith(isRead: false) : n)
            .toList();
      });
    }
  }

  // ── 전체 읽음 처리 ─────────────────────────────────────
  Future<void> _markAllAsRead() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    // UI 선반영
    setState(() {
      _notifications =
          _notifications?.map((n) => n.copyWith(isRead: true)).toList();
    });

    final ok = await _api.markAllAsRead(accessToken: token);
    if (!ok && mounted) {
      // 실패 시 재조회해서 서버 상태와 동기화
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      // ── 앱바 ────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
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
          // 미읽음 있을 때만 "전체 읽음" 노출
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
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),

      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _notifications ?? const <NotificationDto>[];
    if (items.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (_, i) => _buildNotificationCard(items[i]),
      ),
    );
  }

  // ── 알림 카드 위젯 ────────────────────────────────────
  Widget _buildNotificationCard(NotificationDto item) {
    final isUnread = !item.isRead;

    return InkWell(
      onTap: () => _markAsRead(item),
      child: Container(
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
            // 타입 아이콘
            _buildTypeIcon(item.type),

            const SizedBox(width: AppSpacing.md),

            // 본문
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: isUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _formatRelativeTime(item.createdAt),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
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

            // 미읽음 점
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

  // ── 타입별 아이콘 + 색 배지 ──────────────────────────
  Widget _buildTypeIcon(String type) {
    final (icon, color) = _typeIconAndColor(type);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  (IconData, Color) _typeIconAndColor(String type) {
    switch (type) {
      case 'ORDER_RECEIVED':
        return (Icons.receipt_long_rounded, const Color(0xFF4CAF50));
      case 'ORDER_ACCEPTED':
        return (Icons.check_circle_outline_rounded, const Color(0xFF2196F3));
      case 'ORDER_DONE':
        return (
          Icons.restaurant_rounded,
          Theme.of(context).colorScheme.primary
        );
      case 'VOTE_RESULT':
        return (Icons.emoji_events_rounded, const Color(0xFFFFC107));
      default:
        return (Icons.notifications_rounded, AppColors.textSecondary);
    }
  }

  // ── createdAt(ISO 8601) → "방금 전", "20분 전" 등 ────
  // 서버가 raw timestamp만 주므로 클라이언트에서 상대 시간 계산.
  String _formatRelativeTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';

    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';

    // 일주일 이상: YYYY-MM-DD
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // ── 빈 상태 위젯 ──────────────────────────────────────
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
