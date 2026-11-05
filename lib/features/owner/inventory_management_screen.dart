import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/owner_inventory_service.dart';
import '../../services/pos_menus_api_service.dart';

class InventoryManagementScreen extends ConsumerStatefulWidget {
  const InventoryManagementScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<InventoryManagementScreen> createState() =>
      _InventoryManagementScreenState();
}

class _InventoryManagementScreenState
    extends ConsumerState<InventoryManagementScreen> {
  static const _inventoryService = OwnerInventoryService();
  static const _menusApi = PosMenusApiService();

  List<InventoryItem> _items = const [];
  List<PosMenuItem> _menus = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadError;
  String? _busyItemId;
  String _statusFilter = 'ALL'; // ALL | ALERT | EXPIRY | OUT
  String _selectedCategory = '전체';
  int _targetServingsPerMenu = 15;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  void _showFailure(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _loadAll() async {
    if (_isSaving) return;
    final user = ref.read(userProvider);
    final restaurantId = user.restaurantId;
    final token = user.accessToken;
    if (restaurantId == null || restaurantId.isEmpty || token == null) return;
    setState(() => _isLoading = true);
    try {
      final menus = await _menusApi.list(
        accessToken: token,
        restaurantId: restaurantId,
      );
      final items = await _inventoryService.loadInventory(
        restaurantId,
        accessToken: token,
      );
      if (!mounted) return;
      setState(() {
        _menus = menus;
        _items = items;
        _loadError = null;
      });
    } on OwnerInventoryException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _persistItems(List<InventoryItem> next) async {
    final user = ref.read(userProvider);
    final restaurantId = user.restaurantId;
    final token = user.accessToken;
    if (_isSaving ||
        _isLoading ||
        _loadError != null ||
        restaurantId == null ||
        token == null) {
      return false;
    }
    setState(() => _isSaving = true);
    try {
      final saved = await _inventoryService.saveInventory(
        restaurantId,
        next,
        accessToken: token,
        expectedItems: _items,
      );
      if (!mounted) return true;
      setState(() => _items = saved);
      return true;
    } on OwnerInventoryException catch (error) {
      _showFailure(error.message);
      if (error.isConflict && mounted) {
        setState(() => _isSaving = false);
        await _loadAll();
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _adjustQuantity(InventoryItem item, int delta) async {
    final nextQty = (item.currentQty + delta).clamp(0, 9999);
    final updated = item.copyWith(currentQty: nextQty);
    final nextList = _items
        .map((e) => e.id == item.id ? updated : e)
        .toList(growable: false);
    await _persistItems(nextList);
  }

  Future<void> _markDepleted(InventoryItem item) async {
    final updated = item.copyWith(currentQty: 0);
    final nextList = _items
        .map((e) => e.id == item.id ? updated : e)
        .toList(growable: false);
    await _persistItems(nextList);
  }

  Future<void> _syncFromMenus() async {
    final restaurantId = ref.read(userProvider).restaurantId;
    if (restaurantId == null || restaurantId.isEmpty) return;
    final merged = _inventoryService.mergeIngredientsFromMenus(_items, _menus);
    if (!await _persistItems(merged)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('메뉴에 등록된 식자재를 재고 목록과 동기화했어요.')),
    );
  }

  Future<void> _setLinkedMenusAvailability(
    InventoryItem item,
    List<PosMenuItem> targetMenus,
    bool makeAvailable,
  ) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null || targetMenus.isEmpty) return;

    setState(() => _busyItemId = item.id);
    final updatedMenusById = <String, PosMenuItem>{};
    for (final menu in targetMenus) {
      final res = await _menusApi.update(
        accessToken: token,
        menuId: menu.id,
        isAvailable: makeAvailable,
      );
      if (res != null) {
        updatedMenusById[menu.id] = res;
      }
    }
    if (!mounted) return;
    setState(() {
      _busyItemId = null;
      _menus = _menus
          .map((m) => updatedMenusById[m.id] ?? m)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          makeAvailable
              ? '${item.name} 관련 메뉴 ${updatedMenusById.length}건을 판매 재개했어요.'
              : '${item.name} 부족으로 관련 메뉴 ${updatedMenusById.length}건을 품절 처리했어요.',
        ),
      ),
    );
  }

  Future<void> _replenishAllShortages() async {
    final nextList = _inventoryService.replenishShortages(
      _items,
      _menus,
      targetServingsPerMenu: _targetServingsPerMenu,
    );
    if (!await _persistItems(nextList)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '메뉴당 $_targetServingsPerMenu인분 레시피 기준으로 입고 수량을 반영했어요. 유통기한은 실물을 확인해주세요.',
        ),
      ),
    );
  }

  Future<void> _extendFreshExpiry(InventoryItem item, {int days = 7}) async {
    final freshDate = OwnerInventoryService.formatDateAfterDays(days);
    final nextQty = item.currentQty < item.minThreshold * 2
        ? item.minThreshold * 3
        : item.currentQty;
    final updated = item.copyWith(currentQty: nextQty, expiryDate: freshDate);
    final nextList = _items
        .map((e) => e.id == item.id ? updated : e)
        .toList(growable: false);
    if (!await _persistItems(nextList)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${item.name} 신선 입고 완료 (수량 $nextQty${item.unit} · 유통기한 $freshDate)',
        ),
      ),
    );
  }

  Future<void> _openAddOrEditDialog({InventoryItem? initial}) async {
    final result = await _showInventoryFormDialog(
      context,
      initial: initial,
      allMenus: _menus,
    );
    if (result == null) return;

    if (initial == null) {
      final created = InventoryItem(
        id: 'inv_${DateTime.now().microsecondsSinceEpoch}',
        name: result.name,
        category: result.category,
        currentQty: result.currentQty,
        minThreshold: result.minThreshold,
        unit: result.unit,
        linkedMenuNames: result.linkedMenuNames,
        expiryDate: result.expiryDate,
        recipeUnitPerServing: result.recipeUnitPerServing,
      );
      await _persistItems([..._items, created]);
    } else {
      final updated = initial.copyWith(
        name: result.name,
        category: result.category,
        currentQty: result.currentQty,
        minThreshold: result.minThreshold,
        unit: result.unit,
        linkedMenuNames: result.linkedMenuNames,
        expiryDate: result.expiryDate,
        recipeUnitPerServing: result.recipeUnitPerServing,
      );
      await _persistItems(
        _items.map((e) => e.id == initial.id ? updated : e).toList(),
      );
    }
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final next = _items.where((e) => e.id != item.id).toList(growable: false);
    if (!await _persistItems(next)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${item.name} 항목을 삭제했어요.')));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final hasRestaurant =
        user.restaurantId != null && user.restaurantId!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('식자재 · 재고 관리'),
        actions: [
          if (hasRestaurant)
            IconButton(
              tooltip: '메뉴 재료와 동기화',
              icon: const Icon(Icons.sync_rounded),
              onPressed: _syncFromMenus,
            ),
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAll,
          ),
        ],
      ),
      floatingActionButton: hasRestaurant
          ? FloatingActionButton.extended(
              heroTag: 'owner_inventory_fab',
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              onPressed: () => _openAddOrEditDialog(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('식자재 추가'),
            )
          : null,
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
          ? _buildPending()
          : (_isLoading && _items.isEmpty)
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildPending() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          '매장 매핑이 완료되면 식자재 재고를 관리할 수 있어요.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final summary = InventorySummary.fromItems(_items);
    final categories = <String>{
      '전체',
      ...OwnerInventoryService.defaultCategories,
      ..._items.map((e) => e.category),
    }.toList(growable: false);

    final filtered = _items
        .where((item) {
          if (_statusFilter == 'ALERT' && !item.needsAttention) return false;
          if (_statusFilter == 'EXPIRY' && !item.isExpiryAlert()) return false;
          if (_statusFilter == 'OUT' &&
              item.status != InventoryStockStatus.outOfStock) {
            return false;
          }
          if (_selectedCategory != '전체' && item.category != _selectedCategory) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          100,
        ),
        children: [
          _buildSummaryRow(summary),
          const SizedBox(height: 12),
          _buildRecipePlannerCard(),
          const SizedBox(height: 12),
          _buildFilterBar(summary, categories),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Text(
                  '조건에 맞는 식자재가 없어요.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            ...filtered.map(_buildInventoryCard),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(InventorySummary summary) {
    Widget cell({
      required String label,
      required int count,
      required Color color,
      required String filterKey,
    }) {
      final active = _statusFilter == filterKey;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => setState(() => _statusFilter = filterKey),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: active ? color.withAlpha(18) : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: active ? color : AppColors.border,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: AppTextStyles.heading2.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        cell(
          label: '전체 품목',
          count: summary.totalCount,
          color: AppColors.textPrimary,
          filterKey: 'ALL',
        ),
        const SizedBox(width: 6),
        cell(
          label: '수량 부족',
          count: summary.alertCount,
          color: AppColors.warning,
          filterKey: 'ALERT',
        ),
        const SizedBox(width: 6),
        cell(
          label: '유통기한 임박',
          count: summary.expiryAlertCount,
          color: const Color(0xFFE67E22),
          filterKey: 'EXPIRY',
        ),
        const SizedBox(width: 6),
        cell(
          label: '소진됨(0)',
          count: summary.outOfStockCount,
          color: AppColors.error,
          filterKey: 'OUT',
        ),
      ],
    );
  }

  Widget _buildRecipePlannerCard() {
    final primary = Theme.of(context).colorScheme.primary;
    final capacities = _inventoryService.calculateMenuCapacities(
      _items,
      _menus,
    );
    final shortages = _inventoryService.calculateShortagesForTarget(
      _items,
      _menus,
      targetServingsPerMenu: _targetServingsPerMenu,
    );
    final expiringCount = _items.where((e) => e.isExpiryAlert()).length;

    return Container(
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
              Icon(Icons.calculate_outlined, size: 18, color: primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '레시피(BOM) 기준 필요 재료량 & 조리 가능 인분',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '목표 준비량:',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final target in const [10, 15, 20, 30])
                ChoiceChip(
                  label: Text(
                    '메뉴당 $target인분',
                    style: TextStyle(
                      color: _targetServingsPerMenu == target
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selected: _targetServingsPerMenu == target,
                  onSelected: (_) =>
                      setState(() => _targetServingsPerMenu = target),
                ),
            ],
          ),
          if (capacities.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              '현재 재고 기준 메뉴별 최대 조리 가능 수량',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final cap in capacities)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        cap.menuName,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      cap.bottleneckIngredientName != null
                          ? '최대 ${cap.maxServings}인분 (병목: ${cap.bottleneckIngredientName} ${cap.bottleneckRemainingText})'
                          : '최대 ${cap.maxServings}인분 가능',
                      style: AppTextStyles.caption.copyWith(
                        color: cap.maxServings <= 5
                            ? AppColors.warning
                            : AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (shortages.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withAlpha(80)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '목표($_targetServingsPerMenu인분) 대비 보충이 필요한 식자재 (${shortages.length}품목)',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final s in shortages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• ${s.item.name}: +${s.shortageQty}${s.item.unit} 필요 (현재 ${s.item.currentQty}${s.item.unit} / 목표 ${s.requiredQty}${s.item.unit})',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (shortages.isNotEmpty || expiringCount > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _replenishAllShortages,
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                label: Text(
                  '레시피 기준 부족 재고(${shortages.length}건) 채우기 + 유통기한 임박($expiringCount건) 신선 입고',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar(InventorySummary summary, List<String> categories) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: categories.map((cat) {
        final selected = _selectedCategory == cat;
        return ChoiceChip(
          label: Text(
            cat,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          selected: selected,
          onSelected: (_) => setState(() => _selectedCategory = cat),
        );
      }).toList(),
    );
  }

  Widget _buildInventoryCard(InventoryItem item) {
    final isBusy = _busyItemId == item.id;
    final linkedMenus = item.matchMenus(_menus);
    final availableLinked = linkedMenus
        .where((m) => m.isAvailable)
        .toList(growable: false);
    final soldOutLinked = linkedMenus
        .where((m) => !m.isAvailable)
        .toList(growable: false);

    Color statusColor;
    String statusLabel;
    switch (item.status) {
      case InventoryStockStatus.outOfStock:
        statusColor = AppColors.error;
        statusLabel = '소진됨';
        break;
      case InventoryStockStatus.lowStock:
        statusColor = AppColors.warning;
        statusLabel = '부족 경고';
        break;
      case InventoryStockStatus.sufficient:
        statusColor = AppColors.success;
        statusLabel = '충분';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: item.needsAttention
              ? statusColor.withAlpha(110)
              : AppColors.border,
          width: item.needsAttention ? 1.3 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: AppTextStyles.caption.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                item.category,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              IconButton(
                tooltip: '수정',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _openAddOrEditDialog(initial: item),
              ),
              IconButton(
                tooltip: '삭제',
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.error.withAlpha(180),
                ),
                onPressed: () => _deleteItem(item),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: item.expiryStatus() == InventoryExpiryStatus.expired
                      ? AppColors.error.withAlpha(22)
                      : item.expiryStatus() ==
                            InventoryExpiryStatus.expiringSoon
                      ? AppColors.warning.withAlpha(22)
                      : AppColors.backgroundGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_note_rounded,
                      size: 13,
                      color:
                          item.expiryStatus() == InventoryExpiryStatus.expired
                          ? AppColors.error
                          : item.expiryStatus() ==
                                InventoryExpiryStatus.expiringSoon
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.expiryBadgeLabel(),
                      style: AppTextStyles.caption.copyWith(
                        color:
                            item.expiryStatus() == InventoryExpiryStatus.expired
                            ? AppColors.error
                            : item.expiryStatus() ==
                                  InventoryExpiryStatus.expiringSoon
                            ? AppColors.warning
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '1인분 소요: ${item.recipeUnitPerServing}${item.unit} · 최대 ${item.maxServingsFromStock}인분 가능',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (item.isExpiryAlert())
                TextButton.icon(
                  onPressed: () => _extendFreshExpiry(item),
                  icon: const Icon(Icons.autorenew_rounded, size: 15),
                  label: const Text('신선 입고(+7일)'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '현재 ${item.currentQty}${item.unit}',
                style: AppTextStyles.heading3.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(안전재고 ${item.minThreshold}${item.unit})',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              _qtyButton(label: '-5', onTap: () => _adjustQuantity(item, -5)),
              const SizedBox(width: 4),
              _qtyButton(label: '-1', onTap: () => _adjustQuantity(item, -1)),
              const SizedBox(width: 4),
              _qtyButton(
                label: '+1',
                primary: true,
                onTap: () => _adjustQuantity(item, 1),
              ),
              const SizedBox(width: 4),
              _qtyButton(
                label: '+5',
                primary: true,
                onTap: () => _adjustQuantity(item, 5),
              ),
              const SizedBox(width: 4),
              _qtyButton(
                label: '소진',
                danger: true,
                onTap: item.currentQty == 0 ? null : () => _markDepleted(item),
              ),
            ],
          ),
          if (linkedMenus.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: linkedMenus.map((m) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: m.isAvailable
                        ? AppColors.backgroundGrey
                        : AppColors.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    m.isAvailable ? '${m.name} (판매중)' : '${m.name} (품절)',
                    style: AppTextStyles.caption.copyWith(
                      color: m.isAvailable
                          ? AppColors.textPrimary
                          : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (item.needsAttention && availableLinked.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => _setLinkedMenusAvailability(
                          item,
                          availableLinked,
                          false,
                        ),
                  icon: const Icon(Icons.block_rounded, size: 16),
                  label: Text('재료 부족 · 연결 메뉴 ${availableLinked.length}건 품절 전환'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withAlpha(110)),
                  ),
                ),
              ),
            ] else if (!item.needsAttention && soldOutLinked.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => _setLinkedMenusAvailability(
                          item,
                          soldOutLinked,
                          true,
                        ),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                  ),
                  label: Text(
                    '재고 확보 · 연결 품절 메뉴 ${soldOutLinked.length}건 판매 재개',
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _qtyButton({
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
    bool danger = false,
  }) {
    final color = danger
        ? AppColors.error
        : primary
        ? Theme.of(context).colorScheme.primary
        : AppColors.textPrimary;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: primary
              ? color.withAlpha(18)
              : danger
              ? color.withAlpha(14)
              : AppColors.backgroundGrey,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: onTap == null ? AppColors.textSecondary : color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InventoryFormResult {
  const _InventoryFormResult({
    required this.name,
    required this.category,
    required this.currentQty,
    required this.minThreshold,
    required this.unit,
    this.linkedMenuNames = const [],
    this.expiryDate,
    this.recipeUnitPerServing = 1,
  });

  final String name;
  final String category;
  final int currentQty;
  final int minThreshold;
  final String unit;
  final List<String> linkedMenuNames;
  final String? expiryDate;
  final int recipeUnitPerServing;
}

Future<_InventoryFormResult?> _showInventoryFormDialog(
  BuildContext context, {
  InventoryItem? initial,
  List<PosMenuItem> allMenus = const [],
}) async {
  final nameCtrl = TextEditingController(text: initial?.name ?? '');
  final qtyCtrl = TextEditingController(
    text: (initial?.currentQty ?? 20).toString(),
  );
  final minCtrl = TextEditingController(
    text: (initial?.minThreshold ?? 5).toString(),
  );
  final recipeUnitCtrl = TextEditingController(
    text: (initial?.recipeUnitPerServing ?? 1).toString(),
  );
  final expiryCtrl = TextEditingController(text: initial?.expiryDate ?? '');
  String selectedCategory =
      initial?.category ?? OwnerInventoryService.defaultCategories.first;
  String selectedUnit =
      initial?.unit ?? OwnerInventoryService.defaultUnits.first;
  final selectedMenus = <String>{...?initial?.linkedMenuNames};
  String? errorText;

  return showDialog<_InventoryFormResult>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(initial == null ? '식자재 추가' : '식자재 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '식자재 이름',
                    hintText: '예: 한돈 앞다리살, 국산 손두부',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue:
                      OwnerInventoryService.defaultCategories.contains(
                        selectedCategory,
                      )
                      ? selectedCategory
                      : OwnerInventoryService.defaultCategories.first,
                  decoration: const InputDecoration(
                    labelText: '카테고리',
                    border: OutlineInputBorder(),
                  ),
                  items: OwnerInventoryService.defaultCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => selectedCategory = v);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '현재 수량',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '안전재고 기준',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            OwnerInventoryService.defaultUnits.contains(
                              selectedUnit,
                            )
                            ? selectedUnit
                            : OwnerInventoryService.defaultUnits.first,
                        decoration: const InputDecoration(
                          labelText: '단위',
                          border: OutlineInputBorder(),
                        ),
                        items: OwnerInventoryService.defaultUnits
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => selectedUnit = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: recipeUnitCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '1인분 레시피 소요량',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: expiryCtrl,
                  decoration: const InputDecoration(
                    labelText: '유통기한 (YYYY-MM-DD)',
                    hintText: '예: 2026-11-09',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final entry in const [
                      (3, '+3일(신선)'),
                      (7, '+7일(냉장)'),
                      (14, '+14일'),
                      (30, '+30일(양념)'),
                    ])
                      ActionChip(
                        label: Text(
                          entry.$2,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          expiryCtrl.text =
                              OwnerInventoryService.formatDateAfterDays(
                                entry.$1,
                              );
                        },
                      ),
                  ],
                ),
                if (allMenus.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '연결 메뉴 선택 (선택 시 부족/소진 품절 연동)',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: allMenus.map((m) {
                      final active = selectedMenus.contains(m.name);
                      return FilterChip(
                        label: Text(
                          m.name,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: active,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              selectedMenus.add(m.name);
                            } else {
                              selectedMenus.remove(m.name);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
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
                if (name.isEmpty) {
                  setState(() => errorText = '식자재 이름을 입력해주세요.');
                  return;
                }
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                final minQty = int.tryParse(minCtrl.text.trim()) ?? 0;
                final recipeUnit =
                    (int.tryParse(recipeUnitCtrl.text.trim()) ?? 1).clamp(
                      1,
                      100,
                    );
                final expiry = expiryCtrl.text.trim();
                Navigator.of(ctx).pop(
                  _InventoryFormResult(
                    name: name,
                    category: selectedCategory,
                    currentQty: qty.clamp(0, 9999),
                    minThreshold: minQty.clamp(0, 9999),
                    unit: selectedUnit,
                    linkedMenuNames: selectedMenus.toList(growable: false),
                    expiryDate: expiry.isEmpty ? null : expiry,
                    recipeUnitPerServing: recipeUnit,
                  ),
                );
              },
              child: Text(initial == null ? '추가' : '저장'),
            ),
          ],
        ),
      );
    },
  );
}
