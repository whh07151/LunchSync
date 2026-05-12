import 'package:flutter/material.dart';
import '../theme/theme.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 멤버 프로필 원형 위젯 (호스트 표시 + 상태 점)
//
// 사용처:
//   - 세션 로비 멤버 목록
//   - 투표 화면 참여자 표시
//   - 더치페이 명세서
//
// 디자인 원칙:
//   - 이미지 없으면 이름 첫 글자 + 배경색은 이름 해시 기반
//   - 호스트는 우측 상단에 작은 별 배지
//   - 온라인/투표 완료 등 상태는 우측 하단 점
// ══════════════════════════════════════════════════════════

class AppMemberAvatar extends StatelessWidget {
  const AppMemberAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.isHost = false,
    this.statusColor,
    this.size = 40,
  });

  final String name;
  final String? imageUrl;
  final bool isHost;

  /// 우측 하단 상태 점 색상 (null 이면 표시 안 함)
  final Color? statusColor;

  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first : '?';
    final color = _colorFromName(name);

    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? Image.network(
                    imageUrl!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _fallbackAvatar(initial, color),
                  )
                : _fallbackAvatar(initial, color),
          ),
          if (isHost)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          if (statusColor != null)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallbackAvatar(String initial, Color color) {
    return Container(
      width: size,
      height: size,
      color: color,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.bodyMedium.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }

  /// 이름 해시 → 따뜻한 톤의 색상 (이름이 같으면 같은 색)
  Color _colorFromName(String name) {
    // 디자인 토큰과 잘 어울리는 따뜻한 8색 팔레트
    const palette = [
      Color(0xFFFF8C42), // 주황
      Color(0xFFEB6F92), // 핑크
      Color(0xFF6BB6FF), // 하늘
      Color(0xFF9C88FF), // 라벤더
      Color(0xFF4ECDC4), // 민트
      Color(0xFFFFC857), // 머스타드
      Color(0xFF95D5B2), // 세이지
      Color(0xFFB8869F), // 더스티 로즈
    ];
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[hash % palette.length];
  }
}
