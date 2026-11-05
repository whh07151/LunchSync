import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/owner_inventory_service.dart';
import '../../services/pos_menus_api_service.dart';
import '../../services/pos_operations_api_service.dart';

class StoreOperationsScreen extends ConsumerStatefulWidget {
  const StoreOperationsScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  ConsumerState<StoreOperationsScreen> createState() =>
      _StoreOperationsScreenState();
}

class _StoreOperationsScreenState extends ConsumerState<StoreOperationsScreen>
    with SingleTickerProviderStateMixin {
  static const _opsApi = PosOperationsApiService();
  static const _menusApi = PosMenusApiService();
  static const _inventoryService = OwnerInventoryService();

  late final TabController _tabController;

  List<PosSeat> _seats = const [];
  List<PosReservation> _reservations = const [];
  List<PosMenuItem> _menus = const [];
  StoreBusinessStatus _businessStatus = StoreBusinessStatus.open;
  final TextEditingController _todaysNoteCtrl = TextEditingController();
  final TextEditingController _hoursNoteCtrl = TextEditingController();

  bool _isLoading = false;
  String? _loadError;
  bool _isSavingOps = false;
  String? _busySeatId;
  String? _busyReservationId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _todaysNoteCtrl.dispose();
    _hoursNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final user = ref.read(userProvider);
    final token = user.accessToken;
    final restaurantId = user.restaurantId;
    if (token == null || restaurantId == null || restaurantId.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _opsApi.listSeats(accessToken: token, restaurantId: restaurantId),
        _opsApi.listReservations(
          accessToken: token,
          restaurantId: restaurantId,
        ),
        _menusApi.list(accessToken: token, restaurantId: restaurantId),
        _inventoryService.loadBusinessStatus(restaurantId, accessToken: token),
        _inventoryService.loadOperatingHoursNote(
          restaurantId,
          accessToken: token,
        ),
      ]);

      if (!mounted) return;
      final loadedHours = results[4] as String;
      setState(() {
        _seats = results[0] as List<PosSeat>;
        _reservations = results[1] as List<PosReservation>;
        _menus = results[2] as List<PosMenuItem>;
        _businessStatus = results[3] as StoreBusinessStatus;
        _hoursNoteCtrl.text = loadedHours;
        _loadError = null;
      });
    } on OwnerInventoryException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _emptySeatCount => _seats.where((s) => !s.isOccupied).length;
  int get _occupiedSeatCount => _seats.where((s) => s.isOccupied).length;

  Future<void> _handleAddSeat() async {
    final user = ref.read(userProvider);
    final token = user.accessToken;
    final restaurantId = user.restaurantId;
    if (token == null || restaurantId == null) return;

    setState(() => _isSavingOps = true);
    final created = await _opsApi.addSeat(
      accessToken: token,
      restaurantId: restaurantId,
      label: '${_seats.length + 1}번 테이블',
    );
    if (!mounted) return;
    setState(() {
      _isSavingOps = false;
      if (created != null) {
        _seats = [..._seats, created];
      }
    });
  }

  Future<void> _handleToggleSeat(PosSeat seat) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _busySeatId = seat.id);
    final updated = await _opsApi.updateSeatStatus(
      accessToken: token,
      seatId: seat.id,
      occupied: !seat.isOccupied,
    );
    if (!mounted) return;
    setState(() {
      _busySeatId = null;
      if (updated != null) {
        _seats = _seats
            .map((s) => s.id == seat.id ? updated : s)
            .toList(growable: false);
      }
    });
  }

  Future<void> _handleDeleteEmptySeat(PosSeat seat) async {
    if (seat.isOccupied) return;
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _busySeatId = seat.id);
    final ok = await _opsApi.deleteSeat(accessToken: token, seatId: seat.id);
    if (!mounted) return;
    setState(() {
      _busySeatId = null;
      if (ok) {
        _seats = _seats.where((s) => s.id != seat.id).toList(growable: false);
      }
    });
  }

  Future<void> _handleClearAllSeats() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;
    final occupied = _seats.where((s) => s.isOccupied).toList();
    if (occupied.isEmpty) return;

    setState(() => _isSavingOps = true);
    final updatedById = <String, PosSeat>{};
    for (final seat in occupied) {
      final res = await _opsApi.updateSeatStatus(
        accessToken: token,
        seatId: seat.id,
        occupied: false,
      );
      if (res != null) updatedById[seat.id] = res;
    }
    if (!mounted) return;
    setState(() {
      _isSavingOps = false;
      _seats = _seats
          .map((s) => updatedById[s.id] ?? s)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('식사 중이던 좌석 ${updatedById.length}석을 빈 좌석으로 정리했어요.'),
      ),
    );
  }

  Future<void> _handleReservationDecision(
    PosReservation reservation, {
    required String nextStatus,
    bool assignEmptySeat = false,
  }) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _busyReservationId = reservation.id);
    final updated = await _opsApi.updateReservationStatus(
      accessToken: token,
      reservationId: reservation.id,
      status: nextStatus,
    );

    if (updated != null && assignEmptySeat && nextStatus == 'SEATED') {
      final emptySeats = _seats.where((s) => !s.isOccupied).toList();
      final needed = reservation.requiredTables.clamp(1, emptySeats.length);
      final updatedSeatsById = <String, PosSeat>{};
      for (int i = 0; i < needed && i < emptySeats.length; i++) {
        final seatRes = await _opsApi.updateSeatStatus(
          accessToken: token,
          seatId: emptySeats[i].id,
          occupied: true,
        );
        if (seatRes != null) updatedSeatsById[emptySeats[i].id] = seatRes;
      }
      if (mounted && updatedSeatsById.isNotEmpty) {
        setState(() {
          _seats = _seats
              .map((s) => updatedSeatsById[s.id] ?? s)
              .toList(growable: false);
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _busyReservationId = null;
      if (updated != null) {
        _reservations = _reservations
            .map((r) => r.id == reservation.id ? updated : r)
            .toList(growable: false);
      }
    });

    if (updated != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextStatus == 'SEATED'
                ? '${reservation.customerName}님(${reservation.partySize}명) 예약/웨이팅을 수락·착석 처리했어요.'
                : '${reservation.customerName}님 예약/웨이팅을 거절·취소 처리했어요.',
          ),
        ),
      );
    }
  }

  Future<void> _openCreateReservationDialog() async {
    final result = await _showCreateReservationDialog(context);
    if (result == null) return;

    final user = ref.read(userProvider);
    final token = user.accessToken;
    final restaurantId = user.restaurantId;
    if (token == null || restaurantId == null) return;

    final created = await _opsApi.createReservation(
      accessToken: token,
      restaurantId: restaurantId,
      kind: result.kind,
      customerName: result.customerName,
      partySize: result.partySize,
      scheduledAt: result.kind == 'RESERVATION'
          ? DateTime.now()
                .add(const Duration(minutes: 30))
                .toUtc()
                .toIso8601String()
          : null,
      note: result.note,
    );
    if (!mounted) return;
    if (created != null) {
      setState(() => _reservations = [created, ..._reservations]);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('신규 예약/웨이팅을 등록했어요.')));
    }
  }

  Future<void> _handleBusinessStatusChange(StoreBusinessStatus next) async {
    final user = ref.read(userProvider);
    final restaurantId = user.restaurantId;
    final token = user.accessToken;
    if (_isSavingOps || restaurantId == null || token == null) return;
    setState(() => _isSavingOps = true);
    try {
      await _inventoryService.saveBusinessStatus(
        restaurantId,
        next,
        accessToken: token,
      );
      if (!mounted) return;
      setState(() => _businessStatus = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('매장 상태를 "${next.label}"(으)로 변경했어요.')),
      );
    } on OwnerInventoryException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isSavingOps = false);
    }
  }

  Future<void> _handleSaveOperatingHours() async {
    final user = ref.read(userProvider);
    final restaurantId = user.restaurantId;
    final token = user.accessToken;
    if (_isSavingOps || restaurantId == null || token == null) return;
    setState(() => _isSavingOps = true);
    try {
      await _inventoryService.saveOperatingHoursNote(
        restaurantId,
        _hoursNoteCtrl.text.trim(),
        accessToken: token,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('영업/브레이크타임 안내를 저장했어요.')));
      }
    } on OwnerInventoryException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isSavingOps = false);
    }
  }

  Future<void> _handleSaveTodaysNote({bool clear = false}) async {
    final user = ref.read(userProvider);
    final token = user.accessToken;
    final restaurantId = user.restaurantId;
    if (token == null || restaurantId == null) return;

    final note = clear ? null : _todaysNoteCtrl.text.trim();
    setState(() => _isSavingOps = true);
    final ok = await _opsApi.updateTodaysNote(
      accessToken: token,
      restaurantId: restaurantId,
      note: (note == null || note.isEmpty) ? null : note,
    );
    if (!mounted) return;
    setState(() {
      _isSavingOps = false;
      if (clear && ok) _todaysNoteCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (clear ? '오늘의 한 줄 공지를 내렸어요.' : '오늘의 한 줄 공지를 손님 앱에 반영했어요!')
              : '오늘의 한 줄 저장에 실패했어요.',
        ),
      ),
    );
  }

  Future<void> _handleBulkPrepTimeAdjust({
    int? deltaMinutes,
    int? resetTo,
  }) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null || _menus.isEmpty) return;

    setState(() => _isSavingOps = true);
    final updatedById = <String, PosMenuItem>{};
    for (final menu in _menus) {
      final target =
          resetTo ?? (menu.prepTimeMinutes + (deltaMinutes ?? 0)).clamp(5, 120);
      final res = await _menusApi.update(
        accessToken: token,
        menuId: menu.id,
        prepTimeMinutes: target,
      );
      if (res != null) updatedById[menu.id] = res;
    }
    if (!mounted) return;
    setState(() {
      _isSavingOps = false;
      _menus = _menus
          .map((m) => updatedById[m.id] ?? m)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resetTo != null
              ? '전체 메뉴 조리 시간을 기본 $resetTo분으로 초기화했어요.'
              : '피크타임 대응: 전체 메뉴 조리 시간을 +$deltaMinutes분 조정했어요.',
        ),
      ),
    );
  }

  Future<void> _handleRestoreAllSoldOutMenus() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;
    final soldOut = _menus.where((m) => !m.isAvailable).toList();
    if (soldOut.isEmpty) return;

    setState(() => _isSavingOps = true);
    final updatedById = <String, PosMenuItem>{};
    for (final menu in soldOut) {
      final res = await _menusApi.update(
        accessToken: token,
        menuId: menu.id,
        isAvailable: true,
      );
      if (res != null) updatedById[menu.id] = res;
    }
    if (!mounted) return;
    setState(() {
      _isSavingOps = false;
      _menus = _menus
          .map((m) => updatedById[m.id] ?? m)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('오픈 준비 완료: 품절 메뉴 ${updatedById.length}건을 판매 재개했어요.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final hasRestaurant =
        user.restaurantId != null && user.restaurantId!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        title: const Text('가게 운영 · 좌석/예약'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '좌석 현황 (${_seats.length})'),
            Tab(
              text: '예약·웨이팅 (${_reservations.where((r) => r.isOpen).length})',
            ),
            const Tab(text: '운영 설정'),
          ],
        ),
      ),
      body: _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!, textAlign: TextAlign.center),
                  TextButton(onPressed: _loadAll, child: const Text('다시 불러오기')),
                ],
              ),
            )
          : !hasRestaurant
          ? const Center(child: Text('매장 매핑 후 이용할 수 있어요.'))
          : (_isLoading && _seats.isEmpty && _reservations.isEmpty)
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSeatsTab(),
                _buildReservationsTab(),
                _buildOperationsSettingsTab(),
              ],
            ),
    );
  }

  Widget _buildSeatsTab() {
    final emptyCount = _emptySeatCount;
    final occupiedCount = _occupiedSeatCount;
    final estimatedCapacity = emptyCount * 4;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.chair_alt_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '현재 빈 좌석 $emptyCount석 · 식사 중 $occupiedCount석 (총 ${_seats.length}석)',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '4인 테이블 기준 즉시 수용 가능 인원: 약 $estimatedCapacity명',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSavingOps ? null : _handleAddSeat,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 42),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('테이블 추가'),
                      ),
                    ),
                    if (occupiedCount > 0) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSavingOps ? null : _handleClearAllSeats,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 42),
                          ),
                          icon: const Icon(
                            Icons.cleaning_services_outlined,
                            size: 16,
                          ),
                          label: const Text('식사 중 일괄 비우기'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_seats.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Text('등록된 테이블이 없어요. 위 "테이블 추가" 버튼을 눌러주세요.'),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _seats.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (_, idx) => _buildSeatTile(_seats[idx]),
            ),
        ],
      ),
    );
  }

  Widget _buildSeatTile(PosSeat seat) {
    final isBusy = _busySeatId == seat.id;
    final occupied = seat.isOccupied;
    final accent = occupied ? AppColors.warning : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: occupied ? AppColors.warning.withAlpha(110) : AppColors.border,
          width: occupied ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  seat.label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withAlpha(24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  occupied ? '식사 중' : '빈 좌석',
                  style: AppTextStyles.caption.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy ? null : () => _handleToggleSeat(seat),
                  child: Text(occupied ? '퇴석(비우기)' : '착석 처리'),
                ),
              ),
              if (!occupied) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '빈 테이블 삭제',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.error.withAlpha(180),
                  ),
                  onPressed: isBusy ? null : () => _handleDeleteEmptySeat(seat),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReservationsTab() {
    final openList = _reservations
        .where((r) => r.isOpen)
        .toList(growable: false);
    final closedList = _reservations
        .where((r) => !r.isOpen)
        .toList(growable: false);
    final emptyCount = _emptySeatCount;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '현재 빈 좌석 $emptyCount석 기준 예약 가능 판정',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '손님 인원수와 현재 빈 테이블 수를 대조해 수용 가능 여부를 안내해요.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _openCreateReservationDialog,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: const Text('예약·웨이팅 등록'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (openList.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(child: Text('현재 대기 중인 예약·웨이팅이 없어요.')),
            )
          else
            ...openList.map((r) => _buildReservationCard(r, emptyCount)),
          if (closedList.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '처리 완료 내역 (${closedList.length})',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...closedList
                .take(10)
                .map((r) => _buildReservationCard(r, emptyCount)),
          ],
        ],
      ),
    );
  }

  Widget _buildReservationCard(PosReservation r, int emptySeatCount) {
    final isBusy = _busyReservationId == r.id;
    final canSeat = r.canAccommodateWith(emptySeatCount);
    final isWaiting = !r.isReservation;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      (isWaiting
                              ? AppColors.info
                              : Theme.of(context).colorScheme.primary)
                          .withAlpha(22),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isWaiting ? '현장 웨이팅' : '사전 예약',
                  style: AppTextStyles.caption.copyWith(
                    color: isWaiting
                        ? AppColors.info
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${r.customerName} · ${r.partySize}명 (필요 ${r.requiredTables}석)',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!r.isOpen)
                Text(
                  r.status == 'SEATED' ? '착석 완료' : '취소됨',
                  style: AppTextStyles.caption.copyWith(
                    color: r.status == 'SEATED'
                        ? AppColors.success
                        : AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (r.isOpen) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (canSeat ? AppColors.success : AppColors.warning)
                    .withAlpha(18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    canSeat
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    size: 16,
                    color: canSeat ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      canSeat
                          ? 'POS 좌석 판정: 예약 가능 (현재 빈 좌석 $emptySeatCount석)'
                          : 'POS 좌석 판정: 빈 좌석 부족 주의 (빈 좌석 $emptySeatCount석 / 필요 ${r.requiredTables}석)',
                      style: AppTextStyles.caption.copyWith(
                        color: canSeat ? AppColors.success : AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (r.note != null && r.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '요청 메모: ${r.note}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (r.isOpen) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => _handleReservationDecision(
                            r,
                            nextStatus: 'SEATED',
                            assignEmptySeat: canSeat,
                          ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    icon: const Icon(Icons.event_seat_rounded, size: 16),
                    label: Text(canSeat ? '수락 + 좌석 배정' : '수락 (착석)'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: isBusy
                      ? null
                      : () => _handleReservationDecision(
                          r,
                          nextStatus: 'CANCELLED',
                        ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withAlpha(110)),
                  ),
                  child: const Text('거절·취소'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOperationsSettingsTab() {
    final soldOutCount = _menus.where((m) => !m.isAvailable).length;
    final avgPrep = _menus.isEmpty
        ? 15
        : (_menus.fold<int>(0, (s, m) => s + m.prepTimeMinutes) / _menus.length)
              .round();

    const presetNotes = [
      '오늘 재료 신선! 점심 특선 바로 나옵니다 🍲',
      '현재 빈 좌석 여유 있어요, 대기 없이 식사 가능!',
      '비 오는 날 따끈한 국물 메뉴 강추합니다 🌧',
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // 1. 영업 상태 & 시간 설정
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '영업 상태 제어',
                style: AppTextStyles.heading3.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _businessStatus.description,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: StoreBusinessStatus.values.map((s) {
                  final selected = _businessStatus == s;
                  return ChoiceChip(
                    label: Text(
                      s.label,
                      style: TextStyle(
                        color: selected ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => _handleBusinessStatusChange(s),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hoursNoteCtrl,
                      decoration: const InputDecoration(
                        labelText: '영업시간 · 브레이크타임 메모',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _handleSaveOperatingHours,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('저장'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. 사장님 오늘의 한 줄 공지 (백엔드 연동)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '사장님 오늘의 한 줄 공지',
                style: AppTextStyles.heading3.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '손님 추천 카드 상단에 강조 배너로 노출되고 추천 점수가 올라가요.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: presetNotes
                    .map(
                      (p) => ActionChip(
                        label: Text(p, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          _todaysNoteCtrl.text = p;
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _todaysNoteCtrl,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '오늘의 한 줄 (최대 200자)',
                  hintText: '예: 오늘 갓 담근 겉절이와 제육볶음 준비됐어요!',
                  border: OutlineInputBorder(),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSavingOps
                        ? null
                        : () => _handleSaveTodaysNote(clear: true),
                    child: const Text('공지 내리기'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSavingOps
                        ? null
                        : () => _handleSaveTodaysNote(clear: false),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.campaign_rounded, size: 18),
                    label: const Text('공지 반영'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. 피크타임 조리시간 일괄 조정
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '피크타임 조리시간 일괄 조정 (현재 평균 약 $avgPrep분)',
                style: AppTextStyles.heading3.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '점심 주문이 몰릴 때 전체 메뉴 예상 조리시간을 한 번에 조정해 손님 픽업 안내 시각을 맞춥니다.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isSavingOps || _menus.isEmpty
                        ? null
                        : () => _handleBulkPrepTimeAdjust(deltaMinutes: 5),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.timer_outlined, size: 16),
                    label: const Text('전체 +5분 지연'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSavingOps || _menus.isEmpty
                        ? null
                        : () => _handleBulkPrepTimeAdjust(deltaMinutes: 10),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.timer_outlined, size: 16),
                    label: const Text('전체 +10분 지연'),
                  ),
                  TextButton.icon(
                    onPressed: _isSavingOps || _menus.isEmpty
                        ? null
                        : () => _handleBulkPrepTimeAdjust(resetTo: 15),
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('기본(15분) 초기화'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4. 오픈 / 마감 원클릭 운영 도구
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '오픈 · 마감 원클릭 도구',
                style: AppTextStyles.heading3.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _isSavingOps || soldOutCount == 0
                        ? null
                        : _handleRestoreAllSoldOutMenus,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                    ),
                    icon: const Icon(Icons.storefront_rounded, size: 16),
                    label: Text('오픈 준비: 품절 메뉴($soldOutCount건) 일괄 해제'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isSavingOps || _occupiedSeatCount == 0
                        ? null
                        : _handleClearAllSeats,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                    ),
                    icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                    label: Text('마감 정리: 식사 중 좌석($_occupiedSeatCount석) 일괄 비우기'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReservationFormResult {
  const _ReservationFormResult({
    required this.kind,
    required this.customerName,
    required this.partySize,
    this.note,
  });

  final String kind;
  final String customerName;
  final int partySize;
  final String? note;
}

Future<_ReservationFormResult?> _showCreateReservationDialog(
  BuildContext context,
) async {
  String kind = 'RESERVATION';
  final nameCtrl = TextEditingController();
  final sizeCtrl = TextEditingController(text: '4');
  final noteCtrl = TextEditingController();

  return showDialog<_ReservationFormResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('예약 · 웨이팅 수기 등록'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'RESERVATION', label: Text('사전 예약')),
                  ButtonSegment(value: 'WAITING', label: Text('현장 웨이팅')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setState(() => kind = s.first),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '손님 성함 / 팀명',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: sizeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '인원 수 (명)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: '메모 (선택)',
                  hintText: '예: 12:10 도착 예정, 유아 동반 등',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final size = (int.tryParse(sizeCtrl.text.trim()) ?? 2).clamp(
                1,
                50,
              );
              final note = noteCtrl.text.trim();
              Navigator.of(ctx).pop(
                _ReservationFormResult(
                  kind: kind,
                  customerName: name,
                  partySize: size,
                  note: note.isEmpty ? null : note,
                ),
              );
            },
            child: const Text('등록'),
          ),
        ],
      ),
    ),
  );
}
