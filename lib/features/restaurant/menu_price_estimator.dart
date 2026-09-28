import '../../services/restaurants_api_service.dart';

/// 확인되지 않은 메뉴에만 보여 주는 참고 가격. 주문 금액으로 사용하지 않는다.
class MenuPriceEstimate {
  const MenuPriceEstimate(this.won, this.basis);

  final int won;
  final String basis;
}

MenuPriceEstimate? estimateMenuPrice({
  required MenuItemDto target,
  required List<MenuItemDto> restaurantMenus,
  required int? restaurantPriceRange,
}) {
  if (target.source == 'MANUAL') return null;

  final registered = restaurantMenus
      .where(
        (item) =>
            item.source == 'MANUAL' && item.price > 0 && item.price <= 200000,
      )
      .toList();
  final category = target.category?.trim().toLowerCase();
  if (category != null && category.isNotEmpty) {
    final sameCategory = registered
        .where((item) => item.category?.trim().toLowerCase() == category)
        .map((item) => item.price)
        .toList();
    if (sameCategory.isNotEmpty) {
      return MenuPriceEstimate(
        _roundedAverage(sameCategory),
        '이 식당 같은 종류 메뉴 ${sameCategory.length}개 평균',
      );
    }
  }

  if (registered.isNotEmpty) {
    return MenuPriceEstimate(
      _roundedAverage(registered.map((item) => item.price).toList()),
      '이 식당 등록 메뉴 ${registered.length}개 평균',
    );
  }

  final normalized = _restaurantPriceRangeWon(restaurantPriceRange);
  if (normalized != null) {
    return MenuPriceEstimate(normalized, '이 식당 가격대 기준');
  }
  return null;
}

int _roundedAverage(List<int> values) =>
    ((values.reduce((a, b) => a + b) / values.length) / 500).round() * 500;

// 기존 restaurants.price_range에는 원·천원 단위·1~5 척도가 섞여 있다.
// 이 값은 공개 평균이 아니라 해당 식당의 대략적인 예산에만 사용한다.
int? _restaurantPriceRangeWon(int? raw) {
  if (raw == null || raw <= 0) return null;
  if (raw <= 5) {
    return const {1: 5000, 2: 10000, 3: 15000, 4: 25000, 5: 35000}[raw];
  }
  if (raw < 1000) return raw * 1000;
  return raw;
}
