// ══════════════════════════════════════════════════════════
// 파일 역할: 점심 Wrapped (월간 리포트) — WOW 포인트 4순위
//
// 컨셉:
//   - 인스타 스토리 톤의 풀스크린 슬라이드 (PageView 5장)
//   - 자동 슬라이드(5초) + 좌우 탭으로 수동 이동
//   - 그라디언트 배경 + 큰 숫자로 임팩트 강조
//
// 슬라이드 구성:
//   ① 표지       : "2026년 4월의 점심 리포트"
//   ② N끼        : "총 N끼 드셨어요!"
//   ③ 평균 금액  : "1끼 평균 9,200원"
//   ④ Top 식당   : 단골 1위 식당 이름 + 카테고리 이모지 + 방문 횟수
//   ⑤ 카테고리   : 도넛 차트(자체 CustomPainter) + 한식 45% / 일식 22% ...
//
// 데이터 소스:
//   OrdersApiService.getWrappedStats(year, month)
//     → 백엔드 전용 엔드포인트 / 월 단위 주문 / 오늘 주문 / 시드데이터 순 폴백
//
// 공유:
//   마지막 슬라이드 하단 "친구에게 자랑하기" 버튼
//   → 외부 공유 SDK 없이 클립보드 복사 + 안내 스낵바로 대체 가능 (현재 구현)
//   → share_plus 패키지 설치 후 Share.share(...)로 교체 가능 (TODO 주석 참고)
//
// 진입 경로:
//   CU-23 내정보 화면 상단 "이번 달 점심 Wrapped 보기" 카드 → 이 화면(풀스크린 dialog)
// ══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/orders_api_service.dart';

class WrappedScreen extends ConsumerStatefulWidget {
  const WrappedScreen({super.key, this.year, this.month});

  /// 조회할 연도 (null이면 현재 시각 기준)
  final int? year;

  /// 조회할 월 (null이면 현재 시각 기준)
  final int? month;

  @override
  ConsumerState<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends ConsumerState<WrappedScreen> {
  // ── API & 페이지 컨트롤러 ──────────────────────────────
  static const _ordersApi = OrdersApiService();
  final PageController _pageController = PageController();

  // ── 자동 슬라이드 타이머 (5초 간격) ────────────────────
  // 마지막 페이지에 도달하면 정지 (사용자가 공유 버튼 누를 시간 확보)
  Timer? _autoTimer;
  static const Duration _autoInterval = Duration(seconds: 5);

  // ── 상태 ───────────────────────────────────────────────
  bool _isLoading = true;
  WrappedStats? _stats;

  // 표시할 슬라이드는 총 5장 (0~4)
  int _currentPage = 0;
  static const int _pageCount = 5;

  @override
  void initState() {
    super.initState();

    // 첫 프레임 이후에 API 호출 (context가 안정된 후 ref 사용)
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ── 통계 로드 ──────────────────────────────────────────
  Future<void> _loadStats() async {
    final now = DateTime.now();
    final year = widget.year ?? now.year;
    final month = widget.month ?? now.month;

    final token = ref.read(userProvider).accessToken;

    WrappedStats stats;
    if (token == null) {
      // 비로그인 시연용 — 데모 데이터로 동작
      stats = WrappedStats.demo(year, month);
    } else {
      stats = await _ordersApi.getWrappedStats(
        accessToken: token,
        year: year,
        month: month,
      );
    }

    if (!mounted) return;
    setState(() {
      _stats = stats;
      _isLoading = false;
    });

    _startAutoSlide();
  }

  // ── 자동 슬라이드 시작 ─────────────────────────────────
  void _startAutoSlide() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(_autoInterval, (_) {
      if (!mounted) return;
      // 마지막 페이지면 정지 — 사용자가 공유 버튼을 누를 수 있게
      if (_currentPage >= _pageCount - 1) {
        _autoTimer?.cancel();
        return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // ── 좌우 탭으로 페이지 이동 ────────────────────────────
  // 화면을 좌/우 절반으로 나눠서: 왼쪽 = 이전, 오른쪽 = 다음
  void _onTapNavigate(Offset position, Size size) {
    final isLeft = position.dx < size.width / 2;
    if (isLeft) {
      if (_currentPage > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } else {
      if (_currentPage < _pageCount - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  // ── "친구에게 자랑하기" 버튼 ──────────────────────────
  // share_plus의 Share.share()로 OS 공유 시트 호출 (카카오톡/메시지/문자 등)
  // 공유 시트가 실패하거나 미지원 플랫폼이면 클립보드 복사로 폴백.
  Future<void> _shareWrapped() async {
    final s = _stats;
    if (s == null) return;

    final summary = '''
🍱 ${s.year}년 ${s.month}월의 점심 Wrapped 🍱
• 총 ${s.totalCount}끼
• 1끼 평균 ${_formatPrice(s.averagePrice)}원
• 단골 식당: ${s.topRestaurantName} (${s.topVisitCount}회)
- LunchSync로 보내요!
''';

    try {
      // share_plus 10.1.x: 정적 Share.share() — OS 공유 시트 호출
      await Share.share(summary, subject: '점심 Wrapped');
    } catch (_) {
      // 공유 시트 실패 시 클립보드 폴백 — UX 끊김 방지
      await Clipboard.setData(ClipboardData(text: summary));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wrapped 요약을 복사했어요! 카톡에 붙여넣으세요 💛'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── 가격 포맷팅: 9200 → "9,200" ────────────────────────
  String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ─────────────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // 풀스크린 스토리 톤 → 시스템 UI 위에 그림
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // 닫기 버튼 — 다이얼로그/풀스크린 닫기
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final stats = _stats!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 좌/우 탭으로 페이지 이동 (인스타 스토리 UX)
          onTapDown: (d) => _onTapNavigate(d.localPosition, size),
          child: Stack(
            children: [
              // ── PageView 본체 ───────────────────────
              PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _coverSlide(stats),
                  _countSlide(stats),
                  _averageSlide(stats),
                  _topRestaurantSlide(stats),
                  _categorySlide(stats),
                ],
              ),

              // ── 상단 페이지 인디케이터 (스토리 톤) ─
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                child: _StoryIndicator(
                  count: _pageCount,
                  current: _currentPage,
                ),
              ),

              // ── 마지막 페이지에서만 공유 버튼 노출 ─
              if (_currentPage == _pageCount - 1)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 24,
                  child: _ShareButton(onPressed: _shareWrapped),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────
  // 슬라이드 ① 표지
  // ─────────────────────────────────────────────────────
  Widget _coverSlide(WrappedStats s) {
    return _GradientPage(
      colors: const [Color(0xFFFF6B35), Color(0xFFFF8C42), Color(0xFFFFAD72)],
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🍱',
              style: TextStyle(fontSize: 64),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '${s.year}년 ${s.month}월의\n점심 리포트',
              style: AppTextStyles.heading1.copyWith(
                color: Colors.white,
                fontSize: 36,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '한 달간의 점심을 돌아볼 시간이에요',
              style: AppTextStyles.bodyLarge.copyWith(
                color: Colors.white.withAlpha(220),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(60),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                '오른쪽을 탭하면 다음으로 →',
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 슬라이드 ② N끼
  // ─────────────────────────────────────────────────────
  Widget _countSlide(WrappedStats s) {
    return _GradientPage(
      colors: const [Color(0xFF6A5ACD), Color(0xFF9370DB), Color(0xFFB19CD9)],
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '이번 달에는',
              style: AppTextStyles.bodyLarge.copyWith(
                color: Colors.white.withAlpha(230),
                fontSize: 22,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // 큰 숫자 — 임팩트의 핵심
            Text(
              '${s.totalCount}',
              style: TextStyle(
                color: Colors.white,
                fontSize: 160,
                fontWeight: FontWeight.w900,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: Colors.black.withAlpha(60),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '끼를 드셨어요!',
              style: AppTextStyles.heading1.copyWith(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.totalCount >= 15
                  ? '점심을 정말 알차게 보내셨네요 👏'
                  : '다음 달엔 더 자주 만나요!',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white.withAlpha(220),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 슬라이드 ③ 평균 금액
  // ─────────────────────────────────────────────────────
  Widget _averageSlide(WrappedStats s) {
    return _GradientPage(
      colors: const [Color(0xFF1DBFA3), Color(0xFF4ECFBB), Color(0xFF7FE0CD)],
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '1끼 평균',
              style: AppTextStyles.bodyLarge.copyWith(
                color: Colors.white.withAlpha(230),
                fontSize: 22,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatPrice(s.averagePrice),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 88,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    shadows: [
                      Shadow(
                        color: Colors.black.withAlpha(60),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0, left: 6.0),
                  child: Text(
                    '원',
                    style: AppTextStyles.heading1.copyWith(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.averagePrice >= 12000
                  ? '점심 좀 잘 드신 한 달이네요 🍣'
                  : '가성비 점심의 달인 🥗',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white.withAlpha(220),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 슬라이드 ④ Top 식당
  // ─────────────────────────────────────────────────────
  Widget _topRestaurantSlide(WrappedStats s) {
    // 카테고리 → 이모지 매핑 (간단 룩업)
    String emojiFor(String category) {
      switch (category) {
        case '한식': return '🍚';
        case '일식': return '🍣';
        case '양식': return '🍝';
        case '중식': return '🥟';
        case '카페': return '☕';
        case '분식': return '🍢';
        case '아시안': return '🍜';
        default: return '🍱';
      }
    }

    return _GradientPage(
      colors: const [Color(0xFFE91E63), Color(0xFFFF4081), Color(0xFFFF80AB)],
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '이 달의 단골',
              style: AppTextStyles.bodyLarge.copyWith(
                color: Colors.white.withAlpha(230),
                fontSize: 22,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              emojiFor(s.topRestaurantCategory),
              style: const TextStyle(fontSize: 96),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              s.topRestaurantName,
              style: AppTextStyles.heading1.copyWith(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (s.topRestaurantCategory.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(60),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  s.topRestaurantCategory,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '총 ${s.topVisitCount}번 다녀오셨어요',
              style: AppTextStyles.bodyLarge.copyWith(
                color: Colors.white.withAlpha(230),
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 슬라이드 ⑤ 카테고리 도넛
  // ─────────────────────────────────────────────────────
  Widget _categorySlide(WrappedStats s) {
    // 비율 큰 순서로 정렬해서 보여줘야 보기 좋음
    final sorted = s.categoryRatio.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _GradientPage(
      colors: const [Color(0xFF2C3E50), Color(0xFF34495E), Color(0xFF5D6D7E)],
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '카테고리 분포',
              style: AppTextStyles.bodyLarge.copyWith(
                color: Colors.white.withAlpha(230),
                fontSize: 22,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: 220,
              height: 220,
              child: CustomPaint(
                painter: _DonutChartPainter(sorted),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${s.totalCount}',
                        style: AppTextStyles.heading1.copyWith(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '끼',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withAlpha(220),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // 범례 — 카테고리 X% 텍스트
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: List.generate(sorted.length, (i) {
                final entry = sorted[i];
                final pct = (entry.value * 100).round();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _kDonutColors[i % _kDonutColors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${entry.key} $pct%',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              }),
            ),
            const SizedBox(height: AppSpacing.xl + AppSpacing.lg),
            // 공유 버튼 자리를 비워두기 위한 여백 (Stack 위에 버튼이 올라옴)
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 그라디언트 풀스크린 페이지 래퍼
// ─────────────────────────────────────────────────────────
class _GradientPage extends StatelessWidget {
  const _GradientPage({required this.colors, required this.child});
  final List<Color> colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 상단 인스타 스토리 인디케이터 (얇은 바 N개)
// ─────────────────────────────────────────────────────────
class _StoryIndicator extends StatelessWidget {
  const _StoryIndicator({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        final active = i <= current;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == count - 1 ? 0 : 4),
            height: 3,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white
                  : Colors.white.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 공유 버튼 — 마지막 슬라이드 하단에 위치
// ─────────────────────────────────────────────────────────
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.ios_share_rounded),
        label: const Text('친구에게 자랑하기'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 도넛 차트용 색상 팔레트 (외부 패키지 없이 직접 그림)
// ─────────────────────────────────────────────────────────
const List<Color> _kDonutColors = [
  Color(0xFFFF8C42), // 주황
  Color(0xFF4ECFBB), // 청록
  Color(0xFF9370DB), // 보라
  Color(0xFFFFD166), // 노랑
  Color(0xFFEF476F), // 핑크
  Color(0xFF06D6A0), // 민트
  Color(0xFF118AB2), // 파랑
];

// ─────────────────────────────────────────────────────────
// 도넛 차트 페인터 — fl_chart/pie_chart 미설치 환경에서도 동작
//
// 알고리즘:
//   1. 각 entry.value(비율, 0~1)를 360도에 매핑해 sweepAngle 계산
//   2. 12시 방향(-π/2)부터 시계방향으로 순차 sweep
//   3. 두께(strokeWidth) 만큼 외각만 칠해서 도넛 모양 완성
// ─────────────────────────────────────────────────────────
class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter(this.entries);

  final List<MapEntry<String, double>> entries;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (entries.isEmpty) {
      // 빈 상태 — 옅은 회색 원
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..color = Colors.white.withAlpha(40);
      canvas.drawCircle(center, radius, paint);
      return;
    }

    // 비율 합이 1이 아닐 수도 있으니 정규화
    final total = entries.fold<double>(0, (a, b) => a + b.value);
    final normalized = total == 0 ? 1.0 : total;

    double startAngle = -math.pi / 2; // 12시 방향
    for (int i = 0; i < entries.length; i++) {
      final sweep = (entries[i].value / normalized) * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..strokeCap = StrokeCap.butt
        ..color = _kDonutColors[i % _kDonutColors.length];
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter old) =>
      old.entries != entries;
}
