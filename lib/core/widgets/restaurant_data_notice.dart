import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// 식당·메뉴 정보가 실시간 가격이나 검증된 사진으로 오해되지 않도록 안내한다.
/// 개별 데이터의 출처 필드가 생기기 전까지는 항목별 출처를 추정하지 않는다.
class RestaurantDataNotice extends StatelessWidget {
  const RestaurantDataNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      decoration: BoxDecoration(
        color: primary.withAlpha(12),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: primary.withAlpha(40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              kDebugMode
                  ? '로컬 시연 데이터가 포함될 수 있어요. 메뉴·가격·사진은 실제 방문 전에 확인해 주세요.'
                  : '메뉴·가격·사진은 등록 정보예요. 실제 방문 전에 최신 정보를 확인해 주세요.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
