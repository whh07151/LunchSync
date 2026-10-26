import 'package:capstone/features/restaurant/menu_price_estimator.dart';
import 'package:capstone/services/restaurants_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const soup = MenuItemDto(
    id: 's',
    name: '국',
    price: 0,
    category: '밥류',
    source: 'AI_GEMINI',
  );
  const rice = MenuItemDto(
    id: 'r',
    name: '덮밥',
    price: 9000,
    category: '밥류',
    source: 'MANUAL',
  );
  const rice2 = MenuItemDto(
    id: 'r2',
    name: '비빔밥',
    price: 11000,
    category: '밥류',
    source: 'MANUAL',
  );
  const drink = MenuItemDto(
    id: 'd',
    name: '커피',
    price: 4000,
    category: '음료',
    source: 'MANUAL',
  );

  test('같은 식당의 같은 종류 등록 메뉴 평균을 예상가로 사용한다', () {
    final result = estimateMenuPrice(
      target: soup,
      restaurantMenus: [soup, rice, rice2, drink],
      restaurantPriceRange: 20,
    );
    expect(result?.won, 10000);
    expect(result?.basis, contains('같은 종류'));
  });

  test('등록 메뉴가 없으면 식당 가격대를 참고하고, 근거가 없으면 숫자를 만들지 않는다', () {
    expect(
      estimateMenuPrice(
        target: soup,
        restaurantMenus: [soup],
        restaurantPriceRange: 12,
      )?.won,
      12000,
    );
    expect(
      estimateMenuPrice(
        target: soup,
        restaurantMenus: [soup],
        restaurantPriceRange: null,
      ),
      isNull,
    );
  });

  test('등록 메뉴의 실제 입력 가격은 예상가로 교체하지 않는다', () {
    expect(
      estimateMenuPrice(
        target: rice,
        restaurantMenus: [rice, rice2],
        restaurantPriceRange: 20,
      ),
      isNull,
    );
  });
}
