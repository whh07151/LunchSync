import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/pos_menus_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장 메뉴 관리 화면
//
// 기능:
//   - 식당 메뉴 목록 표시 (카테고리별 그룹)
//   - 메뉴 추가 (이름/가격/카테고리/설명)
//   - 메뉴 수정 (인라인 편집 다이얼로그)
//   - 메뉴 품절 토글 (스위치)
//   - 메뉴 삭제 (FK 있으면 백엔드가 거절 — 그땐 품절 사용 안내)
//
// 진입:
//   owner_home_screen 빠른 실행 "메뉴 관리" 또는 하단 탭 "메뉴" 에서.
//
// 데이터:
//   PosMenusApiService — GET/POST/PATCH/DELETE /api/pos/menus/...
//   restaurantId 는 userProvider.restaurantId (5/11 사장 홈 작업으로 prefs 영속).
// ══════════════════════════════════════════════════════════

class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  ConsumerState<MenuManagementScreen> createState() =>
      _MenuManagementScreenState();
}

class _MenuManagementScreenState
    extends ConsumerState<MenuManagementScreen> {
  static const _api = PosMenusApiService();

  List<PosMenuItem> _menus = const [];
  bool _isLoading = false;
  String? _busyMenuId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = ref.read(userProvider);
    final token = user.accessToken;
    final restaurantId = user.restaurantId;
    if (token == null || restaurantId == null) return;

    setState(() => _isLoading = true);
    final menus = await _api.list(
      accessToken: token,
      restaurantId: restaurantId,
    );
    if (!mounted) return;
    setState(() {
      _menus = menus;
      _isLoading = false;
    });
  }

  Future<void> _toggleAvailability(PosMenuItem menu) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _busyMenuId = menu.id);
    final updated = await _api.update(
      accessToken: token,
      menuId: menu.id,
      isAvailable: !menu.isAvailable,
    );
    if (!mounted) return;
    setState(() {
      _busyMenuId = null;
      if (updated != null) {
        _menus = _menus
            .map((m) => m.id == menu.id ? updated : m)
            .toList(growable: false);
      }
    });
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상태 변경에 실패했어요.')),
      );
    }
  }

  Future<void> _openAddDialog() async {
    final result = await _showMenuFormDialog(context);
    if (result == null) return;

    final user = ref.read(userProvider);
    final token = user.accessToken;
    final restaurantId = user.restaurantId;
    if (token == null || restaurantId == null) return;

    final created = await _api.create(
      accessToken: token,
      restaurantId: restaurantId,
      name: result.name,
      price: result.price,
      category: result.category,
      description: result.description,
    );
    if (!mounted) return;

    if (created != null) {
      setState(() => _menus = [..._menus, created]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메뉴를 추가했어요.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메뉴 추가에 실패했어요.')),
      );
    }
  }

  Future<void> _openEditDialog(PosMenuItem menu) async {
    final result = await _showMenuFormDialog(context, initial: menu);
    if (result == null) return;

    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _busyMenuId = menu.id);
    final updated = await _api.update(
      accessToken: token,
      menuId: menu.id,
      name: result.name,
      price: result.price,
      category: result.category,
      description: result.description,
    );
    if (!mounted) return;
    setState(() {
      _busyMenuId = null;
      if (updated != null) {
        _menus = _menus
            .map((m) => m.id == menu.id ? updated : m)
            .toList(growable: false);
      }
    });
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메뉴 수정에 실패했어요.')),
      );
    }
  }

  Future<void> _confirmDelete(PosMenuItem menu) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메뉴 삭제'),
        content: Text(
          '${menu.name} 을(를) 삭제할까요?\n'
          '주문에 사용된 메뉴는 삭제 대신 "품절"로 변경하는 것을 권장합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() => _busyMenuId = menu.id);
    final success = await _api.delete(accessToken: token, menuId: menu.id);
    if (!mounted) return;
    setState(() {
      _busyMenuId = null;
      if (success) {
        _menus = _menus.where((m) => m.id != menu.id).toList(growable: false);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? '메뉴를 삭제했어요.'
            : '삭제에 실패했어요. 이미 주문에 사용된 메뉴는 "품절"로 변경해 주세요.'),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final hasRestaurant =
        user.restaurantId != null && user.restaurantId!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        title: const Text('메뉴 관리'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: hasRestaurant
          ? FloatingActionButton.extended(
              onPressed: _openAddDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('메뉴 추가'),
            )
          : null,
      body: !hasRestaurant
          ? _buildPending()
          : (_isLoading && _menus.isEmpty)
              ? const Center(child: CircularProgressIndicator())
              : _menus.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    );
  }

  Widget _buildPending() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          '매장 매핑이 완료되면 메뉴를 관리할 수 있어요.\n잠시만 기다려 주세요.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Center(
            child: Column(
              children: [
                Icon(Icons.menu_book_rounded,
                    size: 56, color: AppColors.iconInactive),
                const SizedBox(height: AppSpacing.sm),
                Text('등록된 메뉴가 없어요',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text('우측 하단 "메뉴 추가" 버튼을 눌러주세요',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    // 카테고리별 그룹화
    final byCategory = <String, List<PosMenuItem>>{};
    for (final m in _menus) {
      final cat = (m.category?.isNotEmpty ?? false) ? m.category! : '기타';
      byCategory.putIfAbsent(cat, () => []).add(m);
    }

    final categories = byCategory.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
        itemCount: categories.length,
        itemBuilder: (_, i) {
          final cat = categories[i];
          final items = byCategory[cat]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 8),
                child: Text(cat,
                    style: AppTextStyles.heading3
                        .copyWith(color: AppColors.textPrimary)),
              ),
              ...items.map(_buildMenuCard),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMenuCard(PosMenuItem menu) {
    final isBusy = _busyMenuId == menu.id;
    final dimmed = !menu.isAvailable;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        menu.name,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: dimmed
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          decoration:
                              dimmed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (dimmed) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withAlpha(28),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '품절',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatWon(menu.price)}원',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (menu.description != null && menu.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      menu.description!,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          // 품절 토글
          Switch(
            value: menu.isAvailable,
            onChanged: isBusy ? null : (_) => _toggleAvailability(menu),
          ),
          IconButton(
            tooltip: '수정',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: isBusy ? null : () => _openEditDialog(menu),
          ),
          IconButton(
            tooltip: '삭제',
            icon: Icon(Icons.delete_outline,
                size: 20, color: AppColors.error.withAlpha(180)),
            onPressed: isBusy ? null : () => _confirmDelete(menu),
          ),
        ],
      ),
    );
  }

  String _formatWon(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ══════════════════════════════════════════════════════════
// 메뉴 추가/수정 폼 다이얼로그
// 반환: _MenuFormResult (이름/가격/카테고리/설명) 또는 null(취소)
// ══════════════════════════════════════════════════════════

class _MenuFormResult {
  const _MenuFormResult({
    required this.name,
    required this.price,
    this.category,
    this.description,
  });
  final String name;
  final int price;
  final String? category;
  final String? description;
}

Future<_MenuFormResult?> _showMenuFormDialog(
  BuildContext context, {
  PosMenuItem? initial,
}) async {
  final nameCtrl = TextEditingController(text: initial?.name ?? '');
  final priceCtrl =
      TextEditingController(text: initial?.price.toString() ?? '');
  final categoryCtrl = TextEditingController(text: initial?.category ?? '');
  final descCtrl =
      TextEditingController(text: initial?.description ?? '');
  String? errorText;

  return showDialog<_MenuFormResult>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(initial == null ? '메뉴 추가' : '메뉴 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '메뉴 이름',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: '가격(원)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(
                    labelText: '카테고리 (선택)',
                    hintText: '예: 메인, 사이드, 음료',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '설명 (선택)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 6),
                  Text(errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
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
              onPressed: () {
                final name = nameCtrl.text.trim();
                final priceStr = priceCtrl.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = '메뉴 이름을 입력해주세요.');
                  return;
                }
                final price = int.tryParse(priceStr);
                if (price == null || price < 0) {
                  setState(() => errorText = '가격을 0 이상의 숫자로 입력해주세요.');
                  return;
                }
                final cat = categoryCtrl.text.trim();
                final desc = descCtrl.text.trim();
                Navigator.of(ctx).pop(_MenuFormResult(
                  name: name,
                  price: price,
                  category: cat.isEmpty ? null : cat,
                  description: desc.isEmpty ? null : desc,
                ));
              },
              child: Text(initial == null ? '추가' : '수정'),
            ),
          ],
        ),
      );
    },
  );
}
