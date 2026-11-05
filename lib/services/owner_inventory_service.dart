import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/api/api_auth_hooks.dart';
import '../core/config/app_config.dart';
import '../core/api/http_headers_helper.dart';
import 'pos_menus_api_service.dart';

enum InventoryStockStatus { sufficient, lowStock, outOfStock }

enum InventoryExpiryStatus {
  fresh, // D-3 이상 여유
  expiringSoon, // D-Day ~ D-2 임박
  expired, // 유통기한 경과 (D+1~)
}

enum StoreBusinessStatus { open, breakTime, closed }

extension StoreBusinessStatusExt on StoreBusinessStatus {
  String get label {
    switch (this) {
      case StoreBusinessStatus.open:
        return '영업 중';
      case StoreBusinessStatus.breakTime:
        return '브레이크타임';
      case StoreBusinessStatus.closed:
        return '영업 마감';
    }
  }

  String get description {
    switch (this) {
      case StoreBusinessStatus.open:
        return '손님 주문과 예약을 정상 접수하고 있어요';
      case StoreBusinessStatus.breakTime:
        return '재료 준비 및 브레이크타임 상태예요';
      case StoreBusinessStatus.closed:
        return '오늘 영업이 마감되었어요';
    }
  }
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.currentQty,
    required this.minThreshold,
    required this.unit,
    this.linkedMenuNames = const [],
    this.expiryDate,
    this.recipeUnitPerServing = 1,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String category;
  final int currentQty;
  final int minThreshold;
  final String unit;
  final List<String> linkedMenuNames;

  /// YYYY-MM-DD 형식의 유통기한 (null 이면 미지정)
  final String? expiryDate;

  /// 메뉴 1인분 조리 시 기본 소요 수량 (기본 1단위)
  final int recipeUnitPerServing;
  final String? updatedAt;

  InventoryStockStatus get status {
    if (currentQty <= 0) return InventoryStockStatus.outOfStock;
    if (currentQty <= minThreshold) return InventoryStockStatus.lowStock;
    return InventoryStockStatus.sufficient;
  }

  bool get needsAttention => status != InventoryStockStatus.sufficient;

  /// 기준 시각(now) 대비 남은 유통기한 일수 (0 = 오늘 만료, 음수 = 만료 경과)
  int? daysUntilExpiry({DateTime? now}) {
    if (expiryDate == null || expiryDate!.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(expiryDate!.trim());
    if (parsed == null) return null;
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final target = DateTime(parsed.year, parsed.month, parsed.day);
    return target.difference(today).inDays;
  }

  InventoryExpiryStatus expiryStatus({DateTime? now}) {
    final days = daysUntilExpiry(now: now);
    if (days == null) return InventoryExpiryStatus.fresh;
    if (days < 0) return InventoryExpiryStatus.expired;
    if (days <= 2) return InventoryExpiryStatus.expiringSoon;
    return InventoryExpiryStatus.fresh;
  }

  bool isExpiryAlert({DateTime? now}) =>
      expiryStatus(now: now) != InventoryExpiryStatus.fresh;

  String expiryBadgeLabel({DateTime? now}) {
    final days = daysUntilExpiry(now: now);
    if (days == null) return '유통기한 미지정';
    if (days < 0) return '유통기한 만료 (D+${days.abs()})';
    if (days == 0) return '오늘 만료 (D-Day)';
    if (days <= 2) return '유통기한 임박 (D-$days)';
    return '유통기한 D-$days ($expiryDate)';
  }

  /// 현재 재고로 만들 수 있는 최대 인분 수
  int get maxServingsFromStock {
    final perServing = recipeUnitPerServing <= 0 ? 1 : recipeUnitPerServing;
    if (currentQty <= 0) return 0;
    return currentQty ~/ perServing;
  }

  InventoryItem copyWith({
    String? id,
    String? name,
    String? category,
    int? currentQty,
    int? minThreshold,
    String? unit,
    List<String>? linkedMenuNames,
    String? expiryDate,
    int? recipeUnitPerServing,
    String? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      currentQty: currentQty ?? this.currentQty,
      minThreshold: minThreshold ?? this.minThreshold,
      unit: unit ?? this.unit,
      linkedMenuNames: linkedMenuNames ?? this.linkedMenuNames,
      expiryDate: expiryDate ?? this.expiryDate,
      recipeUnitPerServing: recipeUnitPerServing ?? this.recipeUnitPerServing,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'currentQty': currentQty,
    'minThreshold': minThreshold,
    'unit': unit,
    'linkedMenuNames': linkedMenuNames,
    'expiryDate': expiryDate,
    'recipeUnitPerServing': recipeUnitPerServing,
    'updatedAt': updatedAt,
  };

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    final rawMenus = json['linkedMenuNames'];
    return InventoryItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '기타',
      currentQty: (json['currentQty'] as num?)?.toInt() ?? 0,
      minThreshold: (json['minThreshold'] as num?)?.toInt() ?? 5,
      unit: json['unit']?.toString() ?? '인분',
      linkedMenuNames: rawMenus is List
          ? rawMenus.map((e) => e.toString()).toList(growable: false)
          : const [],
      expiryDate: json['expiryDate'] as String?,
      recipeUnitPerServing:
          (json['recipeUnitPerServing'] as num?)?.toInt() ?? 1,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  List<PosMenuItem> matchMenus(List<PosMenuItem> allMenus) {
    final normalizedName = name.trim().toLowerCase();
    if (normalizedName.isEmpty) return const [];
    final linkedSet = linkedMenuNames
        .map((n) => n.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();

    return allMenus
        .where((menu) {
          final menuNameLower = menu.name.trim().toLowerCase();
          if (linkedSet.contains(menuNameLower)) return true;
          for (final ing in menu.ingredients) {
            final ingLower = ing.trim().toLowerCase();
            if (ingLower == normalizedName ||
                ingLower.contains(normalizedName) ||
                normalizedName.contains(ingLower)) {
              return true;
            }
          }
          return menuNameLower.contains(normalizedName);
        })
        .toList(growable: false);
  }
}

class InventorySummary {
  const InventorySummary({
    required this.totalCount,
    required this.sufficientCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    this.expiringSoonCount = 0,
    this.expiredCount = 0,
  });

  final int totalCount;
  final int sufficientCount;
  final int lowStockCount;
  final int outOfStockCount;
  final int expiringSoonCount;
  final int expiredCount;

  int get alertCount => lowStockCount + outOfStockCount;
  int get expiryAlertCount => expiringSoonCount + expiredCount;

  factory InventorySummary.fromItems(
    List<InventoryItem> items, {
    DateTime? now,
  }) {
    int sufficient = 0;
    int low = 0;
    int out = 0;
    int expSoon = 0;
    int exp = 0;
    for (final item in items) {
      switch (item.status) {
        case InventoryStockStatus.sufficient:
          sufficient++;
          break;
        case InventoryStockStatus.lowStock:
          low++;
          break;
        case InventoryStockStatus.outOfStock:
          out++;
          break;
      }
      switch (item.expiryStatus(now: now)) {
        case InventoryExpiryStatus.fresh:
          break;
        case InventoryExpiryStatus.expiringSoon:
          expSoon++;
          break;
        case InventoryExpiryStatus.expired:
          exp++;
          break;
      }
    }
    return InventorySummary(
      totalCount: items.length,
      sufficientCount: sufficient,
      lowStockCount: low,
      outOfStockCount: out,
      expiringSoonCount: expSoon,
      expiredCount: exp,
    );
  }
}

/// 메뉴 1종에 대해 연결된 레시피 식자재 재고로 현재 몇 인분까지 조리 가능한지 계산한 결과
class MenuRecipeCapacity {
  const MenuRecipeCapacity({
    required this.menuId,
    required this.menuName,
    required this.maxServings,
    required this.matchedIngredientCount,
    this.bottleneckIngredientName,
    this.bottleneckRemainingText,
  });

  final String menuId;
  final String menuName;
  final int maxServings;
  final int matchedIngredientCount;
  final String? bottleneckIngredientName;
  final String? bottleneckRemainingText;
}

/// 목표 판매 인분(예: 메뉴당 15인분)을 달성하기 위해 부족한 식자재와 채워야 할 수량
class RecipeShortageItem {
  const RecipeShortageItem({
    required this.item,
    required this.requiredQty,
    required this.shortageQty,
    required this.usedByMenuCount,
  });

  final InventoryItem item;
  final int requiredQty;
  final int shortageQty;
  final int usedByMenuCount;
}

class OwnerInventoryService {
  const OwnerInventoryService();

  static const List<String> defaultCategories = [
    '육류/해산물',
    '채소/농산물',
    '양념/육수',
    '밥/면/기타',
    '음료/주류',
  ];

  static const List<String> defaultUnits = ['인분', 'kg', '개', '팩', 'L', '모'];

  Future<dynamic> _request(
    String restaurantId,
    String resource,
    String token, {
    Map<String, dynamic>? payload,
  }) async {
    if (token.trim().isEmpty) {
      throw const OwnerInventoryException('로그인 정보가 없습니다. 다시 로그인해주세요.');
    }
    final uri = Uri.parse(
      '${AppConfig.backendBaseUrl}/pos/restaurants/$restaurantId/$resource',
    );
    try {
      final response =
          await (payload == null
                  ? http.get(uri, headers: apiHeaders(token))
                  : http.patch(
                      uri,
                      headers: apiHeaders(token),
                      body: jsonEncode(payload),
                    ))
              .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);
      if (response.statusCode == 409) {
        throw const OwnerInventoryException(
          '다른 작업으로 재고가 변경됐어요. 최신 재고를 다시 불러온 뒤 수정해주세요.',
          isConflict: true,
        );
      }
      if (response.statusCode != 200) {
        throw const OwnerInventoryException('서버에 반영하지 못했어요. 다시 시도해주세요.');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['success'] == false || !decoded.containsKey('data')) {
        throw const OwnerInventoryException('서버 응답을 확인하지 못했어요. 다시 불러와주세요.');
      }
      return decoded['data'];
    } on OwnerInventoryException {
      rethrow;
    } catch (_) {
      throw const OwnerInventoryException('서버와 연결하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  Future<List<InventoryItem>> loadInventory(
    String restaurantId, {
    List<PosMenuItem> menus = const [],
    required String accessToken,
  }) async {
    final data = await _request(restaurantId, 'inventory', accessToken);
    if (data is! List || data.any((row) => row is! Map<String, dynamic>)) {
      throw const OwnerInventoryException('재고 응답 형식이 올바르지 않습니다.');
    }
    return data
        .map((row) => InventoryItem.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  static String formatDateAfterDays(int daysFromToday, {DateTime? now}) {
    final base = now ?? DateTime.now();
    final target = DateTime(
      base.year,
      base.month,
      base.day,
    ).add(Duration(days: daysFromToday));
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${target.year}-${two(target.month)}-${two(target.day)}';
  }

  Future<List<InventoryItem>> saveInventory(
    String restaurantId,
    List<InventoryItem> items, {
    required String accessToken,
    List<InventoryItem>? expectedItems,
  }) async {
    final data = await _request(
      restaurantId,
      'inventory',
      accessToken,
      payload: {
        'items': items.map((e) => e.toJson()).toList(),
        'expectedItems': (expectedItems ?? items)
            .where((e) => e.updatedAt != null)
            .map((e) => {'id': e.id, 'updatedAt': e.updatedAt})
            .toList(),
      },
    );
    if (data is! List || data.any((row) => row is! Map<String, dynamic>)) {
      throw const OwnerInventoryException('재고 저장 응답을 확인하지 못했어요. 다시 불러와주세요.');
    }
    return data
        .map((row) => InventoryItem.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  List<InventoryItem> mergeIngredientsFromMenus(
    List<InventoryItem> current,
    List<PosMenuItem> menus,
  ) {
    final byName = <String, InventoryItem>{
      for (final item in current) item.name.trim().toLowerCase(): item,
    };
    final updatedList = [...current];

    for (final menu in menus) {
      for (final rawIng in menu.ingredients) {
        final ing = rawIng.trim();
        if (ing.isEmpty) continue;
        final key = ing.toLowerCase();
        final existing = byName[key];
        if (existing != null) {
          if (!existing.linkedMenuNames.contains(menu.name)) {
            final nextMenus = [...existing.linkedMenuNames, menu.name];
            final replaced = existing.copyWith(linkedMenuNames: nextMenus);
            byName[key] = replaced;
            final idx = updatedList.indexWhere((e) => e.id == existing.id);
            if (idx >= 0) updatedList[idx] = replaced;
          }
        } else {
          final created = InventoryItem(
            id: 'inv_${DateTime.now().microsecondsSinceEpoch}_${updatedList.length}',
            name: ing,
            category: inferCategory(ing),
            currentQty: 0,
            minThreshold: 5,
            unit: '인분',
            linkedMenuNames: [menu.name],
          );
          byName[key] = created;
          updatedList.add(created);
        }
      }
    }

    return updatedList;
  }

  static String inferCategory(String ingredientName) {
    final lower = ingredientName.toLowerCase();
    if (lower.contains('고기') ||
        lower.contains('한돈') ||
        lower.contains('삼겹') ||
        lower.contains('차돌') ||
        lower.contains('소고기') ||
        lower.contains('닭') ||
        lower.contains('새우') ||
        lower.contains('오징어') ||
        lower.contains('해물')) {
      return '육류/해산물';
    }
    if (lower.contains('김치') ||
        lower.contains('두부') ||
        lower.contains('양파') ||
        lower.contains('대파') ||
        lower.contains('애호박') ||
        lower.contains('버섯') ||
        lower.contains('상추') ||
        lower.contains('마늘')) {
      return '채소/농산물';
    }
    if (lower.contains('육수') ||
        lower.contains('양념') ||
        lower.contains('장') ||
        lower.contains('소스') ||
        lower.contains('기름')) {
      return '양념/육수';
    }
    if (lower.contains('콜라') ||
        lower.contains('사이다') ||
        lower.contains('음료') ||
        lower.contains('주스')) {
      return '음료/주류';
    }
    return '밥/면/기타';
  }

  static List<InventoryItem> buildInitialSeed({
    List<PosMenuItem> menus = const [],
  }) {
    final defaults = <InventoryItem>[
      InventoryItem(
        id: 'seed_pork',
        name: '한돈 앞다리살',
        category: '육류/해산물',
        currentQty: 18,
        minThreshold: 5,
        unit: '인분',
        linkedMenuNames: const ['한돈 숙성 김치찌개', '직화 한돈 제육볶음 정식'],
        expiryDate: formatDateAfterDays(5),
        recipeUnitPerServing: 1,
      ),
      InventoryItem(
        id: 'seed_kimchi',
        name: '숙성 배추김치',
        category: '채소/농산물',
        currentQty: 25,
        minThreshold: 8,
        unit: '인분',
        linkedMenuNames: const ['한돈 숙성 김치찌개'],
        expiryDate: formatDateAfterDays(14),
        recipeUnitPerServing: 1,
      ),
      InventoryItem(
        id: 'seed_tofu',
        name: '국산 손두부',
        category: '채소/농산물',
        currentQty: 4,
        minThreshold: 6,
        unit: '모',
        linkedMenuNames: const ['한돈 숙성 김치찌개', '해물 손두부 된장찌개'],
        expiryDate: formatDateAfterDays(1), // D-1 유통기한 임박 + 수량 부족
        recipeUnitPerServing: 1,
      ),
      InventoryItem(
        id: 'seed_broth',
        name: '사골 진육수',
        category: '양념/육수',
        currentQty: 15,
        minThreshold: 5,
        unit: 'L',
        linkedMenuNames: const ['한돈 숙성 김치찌개'],
        expiryDate: formatDateAfterDays(7),
        recipeUnitPerServing: 1,
      ),
      InventoryItem(
        id: 'seed_rice',
        name: '국내산 햅쌀(공기밥)',
        category: '밥/면/기타',
        currentQty: 40,
        minThreshold: 10,
        unit: '인분',
        linkedMenuNames: const ['직화 한돈 제육볶음 정식'],
        expiryDate: formatDateAfterDays(30),
        recipeUnitPerServing: 1,
      ),
      InventoryItem(
        id: 'seed_egg',
        name: '특란(계란)',
        category: '밥/면/기타',
        currentQty: 30,
        minThreshold: 10,
        unit: '개',
        linkedMenuNames: const ['왕계란말이', '직화 한돈 제육볶음 정식'],
        expiryDate: formatDateAfterDays(2), // D-2 유통기한 임박
        recipeUnitPerServing: 2,
      ),
    ];

    if (menus.isEmpty) return defaults;
    return const OwnerInventoryService().mergeIngredientsFromMenus(
      defaults,
      menus,
    );
  }

  /// 각 메뉴의 레시피 식자재 보유량을 바탕으로 현재 최대 조리 가능 인분과 병목 재료를 계산한다.
  List<MenuRecipeCapacity> calculateMenuCapacities(
    List<InventoryItem> inventory,
    List<PosMenuItem> menus,
  ) {
    final result = <MenuRecipeCapacity>[];
    for (final menu in menus) {
      final matchedItems = inventory
          .where((inv) => inv.matchMenus([menu]).isNotEmpty)
          .toList(growable: false);
      if (matchedItems.isEmpty) continue;

      InventoryItem? bottleneck;
      int minServings = 999999;
      for (final inv in matchedItems) {
        final servings = inv.maxServingsFromStock;
        if (servings < minServings) {
          minServings = servings;
          bottleneck = inv;
        }
      }

      result.add(
        MenuRecipeCapacity(
          menuId: menu.id,
          menuName: menu.name,
          maxServings: minServings == 999999 ? 0 : minServings,
          matchedIngredientCount: matchedItems.length,
          bottleneckIngredientName: bottleneck?.name,
          bottleneckRemainingText: bottleneck == null
              ? null
              : '${bottleneck.currentQty}${bottleneck.unit}',
        ),
      );
    }
    return result;
  }

  /// 메뉴당 목표 판매 인분(targetServingsPerMenu)을 준비하기 위해 부족한 식자재 목록과 필요 수량을 계산한다.
  List<RecipeShortageItem> calculateShortagesForTarget(
    List<InventoryItem> inventory,
    List<PosMenuItem> menus, {
    int targetServingsPerMenu = 15,
  }) {
    final shortages = <RecipeShortageItem>[];
    for (final item in inventory) {
      final matchedMenus = menus.isEmpty
          ? item.linkedMenuNames.length
          : item.matchMenus(menus).length;
      final menuMultiplier = matchedMenus > 0 ? matchedMenus : 1;
      final perServing = item.recipeUnitPerServing <= 0
          ? 1
          : item.recipeUnitPerServing;
      final requiredQty = (targetServingsPerMenu * perServing * menuMultiplier)
          .clamp(item.minThreshold * 2, 9999);
      final shortage = requiredQty - item.currentQty;
      if (shortage > 0 || item.needsAttention) {
        shortages.add(
          RecipeShortageItem(
            item: item,
            requiredQty: requiredQty,
            shortageQty: shortage > 0 ? shortage : item.minThreshold,
            usedByMenuCount: menuMultiplier,
          ),
        );
      }
    }
    return shortages;
  }

  /// 명시적인 입고 작업의 목표 수량을 계산한다. 유통기한은 실물 확인 없이 바꾸지 않는다.
  List<InventoryItem> replenishShortages(
    List<InventoryItem> inventory,
    List<PosMenuItem> menus, {
    int targetServingsPerMenu = 15,
  }) {
    final shortageMap = <String, RecipeShortageItem>{
      for (final s in calculateShortagesForTarget(
        inventory,
        menus,
        targetServingsPerMenu: targetServingsPerMenu,
      ))
        s.item.id: s,
    };

    return inventory
        .map((item) {
          final plan = shortageMap[item.id];
          if (plan == null && !item.isExpiryAlert()) return item;
          final nextQty = plan != null
              ? (item.currentQty + plan.shortageQty)
              : item.currentQty;
          return item.copyWith(currentQty: nextQty);
        })
        .toList(growable: false);
  }

  Future<StoreBusinessStatus> loadBusinessStatus(
    String restaurantId, {
    required String accessToken,
  }) async {
    final data = await _request(restaurantId, 'store-status', accessToken);
    if (data is! Map<String, dynamic>) {
      throw const OwnerInventoryException('매장 영업 상태를 확인하지 못했어요.');
    }
    return switch (data['businessStatus']) {
      'OPEN' => StoreBusinessStatus.open,
      'BREAK_TIME' => StoreBusinessStatus.breakTime,
      'CLOSED' => StoreBusinessStatus.closed,
      _ => throw const OwnerInventoryException('매장 영업 상태를 확인하지 못했어요.'),
    };
  }

  Future<void> saveBusinessStatus(
    String restaurantId,
    StoreBusinessStatus status, {
    required String accessToken,
  }) async {
    final value = switch (status) {
      StoreBusinessStatus.open => 'OPEN',
      StoreBusinessStatus.breakTime => 'BREAK_TIME',
      StoreBusinessStatus.closed => 'CLOSED',
    };
    await _request(
      restaurantId,
      'store-status',
      accessToken,
      payload: {'businessStatus': value},
    );
  }

  Future<String> loadOperatingHoursNote(
    String restaurantId, {
    required String accessToken,
  }) async {
    final data = await _request(restaurantId, 'store-status', accessToken);
    if (data is! Map<String, dynamic> ||
        (data['operatingHoursNote'] != null &&
            data['operatingHoursNote'] is! String)) {
      throw const OwnerInventoryException('영업시간 안내를 확인하지 못했어요.');
    }
    return data['operatingHoursNote'] as String? ?? '';
  }

  Future<void> saveOperatingHoursNote(
    String restaurantId,
    String note, {
    required String accessToken,
  }) async {
    await _request(
      restaurantId,
      'store-status',
      accessToken,
      payload: {'operatingHoursNote': note.trim()},
    );
  }
}

class OwnerInventoryException implements Exception {
  const OwnerInventoryException(this.message, {this.isConflict = false});
  final String message;
  final bool isConflict;
}
