// ══════════════════════════════════════════════════════════
// 파일 역할: WOW#7 — 메뉴 스와이프 (Tinder 스타일) 화면
//
// 진입 경로:
//   CU-13 식당 상세 → CU-16 메뉴 화면
//     → 앱바 우측 "스와이프 모드" 토글 (Icons.swipe)
//       → 이 화면 (MenuSwipeScreen) 전체 화면 모달 진입
//
// 사용자 흐름:
//   1) 화면 진입 시 메뉴 리스트(_menus) 를 카드 스택으로 그림
//   2) 카드 좌/우/위 스와이프 또는 하단 액션 버튼 3개로 분류
//       - ❌ 좌 스와이프 / "패스" 버튼  → 다음 카드
//       - ❤️ 우 스와이프 / "찜" 버튼   → SharedPreferences 누적 + SnackBar
//       - 🛒 위 스와이프 / "담기" 버튼 → cartProvider 에 1개 추가 + SnackBar
//   3) 모든 카드 소진 시 결과 화면 노출
//       (찜 N개 / 장바구니에 M개 담음 + [리스트 모드로])
//
// 데이터 / 디자인 원칙:
//   - 의존성 추가 0건. Dismissible / GestureDetector / Transform.translate 로 자체 구현
//   - 디자인 토큰만 사용 — AppColors / AppRadius / AppSpacing / AppTextStyles
//     (디자이너 약속과 정합성 유지 — 임의 색상·폰트 신규 금지)
//   - 찜 데이터는 일단 SharedPreferences 만 사용. 키: `ls_favorite_menus_<userId>`
//     백엔드 menu_favorites 테이블은 별도 티켓에서 만든다.
//   - 카드 회전: 스와이프 진행도(±200px 기준) 에 따라 ±15° 살짝 기울기
//   - PASS / LIKE 오버레이 라벨이 진행도에 비례해 페이드 인
// ══════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../providers/user_provider.dart';

/// 찜 메뉴 ID 누적용 SharedPreferences 키 prefix.
/// 추천 가중치 미래 사용을 위해 user 별로 분리.
/// 비로그인 케이스는 `_guest` suffix 로 떨어뜨려 충돌 방지.
const String _kFavoriteMenusKeyPrefix = 'ls_favorite_menus_';

/// 카드 스와이프 판정 임계값 (논리 픽셀).
/// 카드 중앙 기준으로 좌/우 100px, 위 80px 이상 끌어다 놓으면 확정.
/// 너무 작으면 오탐, 너무 크면 손가락이 아플 정도로 멀리 끌어야 해서
/// 100/80 으로 균형. (배민/티몬 스와이프 류 앱 평균값과 유사)
const double _kHorizontalThreshold = 100.0;
const double _kVerticalThreshold = 80.0;

/// 진행도 표시(라벨 페이드, 회전) 산정 기준 거리.
/// 끌어다 놓은 거리 / 이 값 = 0.0 ~ 1.0 진행도.
const double _kProgressDenominator = 200.0;

/// 카드 최대 기울기(라디안 환산용). 사용자가 ±200px 끌면 ±15°.
const double _kMaxRotationDeg = 15.0;

/// 스와이프 결과 분류.
enum _SwipeAction { pass, like, addToCart }

class MenuSwipeScreen extends ConsumerStatefulWidget {
  const MenuSwipeScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    required this.menus,
  });

  /// 어느 식당의 메뉴인지 (찜 분석/통계용 메타)
  final String restaurantId;

  /// 상단 앱바 제목 — 식당 이름
  final String restaurantName;

  /// 스와이프 대상 메뉴 리스트. 5개 미만이면 호출부에서 미리 막아주지만
  /// 방어적으로 빈 상태도 안전 처리.
  final List<MenuItem> menus;

  @override
  ConsumerState<MenuSwipeScreen> createState() => _MenuSwipeScreenState();
}

class _MenuSwipeScreenState extends ConsumerState<MenuSwipeScreen>
    with TickerProviderStateMixin {
  // ── 현재 보고 있는 카드 인덱스 ─────────────────────────────
  // 0 부터 시작해 widget.menus.length - 1 까지 진행.
  // _currentIndex >= length 이면 모든 카드 소진 → 결과 화면.
  int _currentIndex = 0;

  // ── 찜한 메뉴 / 장바구니에 담은 메뉴 카운터 ───────────────
  // 결과 화면 요약에 사용.
  int _likedCount = 0;
  int _addedToCartCount = 0;

  // ── 드래그 상태 ───────────────────────────────────────────
  // 사용자가 카드를 끌고 있는 동안 누적 이동 거리(픽셀).
  // dx > 0 = 우로 이동 (찜), dx < 0 = 좌로 이동 (패스), dy < 0 = 위 (장바구니)
  Offset _dragOffset = Offset.zero;

  // 카드 이탈 애니메이션용 컨트롤러.
  // 스와이프 확정 시 _dragOffset 에서 화면 밖까지 부드럽게 보내고
  // 그 후에 _currentIndex 를 증가시켜 다음 카드 노출.
  late final AnimationController _flyAwayController;
  Offset? _flyAwayStart;
  Offset? _flyAwayEnd;
  _SwipeAction? _flyingAction;

  // 카드 복귀 애니메이션 (임계값 미달 시 원위치).
  late final AnimationController _resetController;
  Offset? _resetStart;

  // 진행 중인 찜 ID 누적 캐시 — flush 호출 시 한꺼번에 prefs 저장.
  // 카드마다 prefs 쓰는 대신 한 번에 모아 저장해 I/O 줄임.
  final Set<String> _pendingFavoriteIds = <String>{};

  // ── 생명주기: 초기화 ────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // 카드 이탈 애니메이션 (220ms 짧게 — 흐름 빠르게 유지)
    _flyAwayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onFlyAwayTick);

    _flyAwayController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 이탈 완료 → 카운터 갱신 + 다음 카드로
        _commitFlyAway();
      }
    });

    // 카드 복귀 애니메이션 (180ms — 자연스러운 스프링 느낌)
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(_onResetTick);
  }

  @override
  void dispose() {
    _flyAwayController.dispose();
    _resetController.dispose();
    // 화면 종료 시 누적된 찜 ID 를 SharedPreferences 에 영속화.
    // await 하지 않고 fire-and-forget — UI 닫힘 지연 방지.
    _flushFavoritesIfAny();
    super.dispose();
  }

  // ── SharedPreferences 에 찜 누적 저장 ───────────────────
  // userId 기준 키로 기존 찜 목록과 합집합 처리.
  // 호출 시점:
  //   - 결과 화면 도달 직전
  //   - 사용자가 화면을 닫을 때 (dispose)
  Future<void> _flushFavoritesIfAny() async {
    if (_pendingFavoriteIds.isEmpty) return;
    final userId = ref.read(userProvider).userId ?? 'guest';
    final key = '$_kFavoriteMenusKeyPrefix$userId';

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(key) ?? const <String>[];
    final merged = <String>{...existing, ..._pendingFavoriteIds}.toList();
    await prefs.setStringList(key, merged);

    debugPrint(
      '[MenuSwipeScreen] FAVORITES_PERSISTED_${_pendingFavoriteIds.length}',
    );
    _pendingFavoriteIds.clear();
  }

  // ── 진행도 계산 헬퍼 ────────────────────────────────────
  // 0.0 ~ 1.0 로 정규화된 좌/우/위 진행도 산출.
  double get _leftProgress {
    if (_dragOffset.dx >= 0) return 0.0;
    return math.min(1.0, -_dragOffset.dx / _kProgressDenominator);
  }

  double get _rightProgress {
    if (_dragOffset.dx <= 0) return 0.0;
    return math.min(1.0, _dragOffset.dx / _kProgressDenominator);
  }

  double get _upProgress {
    if (_dragOffset.dy >= 0) return 0.0;
    return math.min(1.0, -_dragOffset.dy / _kProgressDenominator);
  }

  // ── 카드 회전각 (라디안) ─────────────────────────────────
  // 좌/우 드래그 진행도에 비례해 ±15° 까지.
  double get _rotation {
    final progress = (_rightProgress - _leftProgress); // -1.0 ~ 1.0
    final deg = progress * _kMaxRotationDeg;
    return deg * math.pi / 180.0;
  }

  // ── 드래그 시작 ──────────────────────────────────────────
  void _onPanStart(DragStartDetails details) {
    // 진행 중인 애니메이션이 있으면 무시 — 중복 입력 방지
    if (_flyAwayController.isAnimating || _resetController.isAnimating) return;
  }

  // ── 드래그 진행 ──────────────────────────────────────────
  void _onPanUpdate(DragUpdateDetails details) {
    if (_flyAwayController.isAnimating || _resetController.isAnimating) return;
    setState(() {
      _dragOffset += details.delta;
    });
  }

  // ── 드래그 종료 — 임계값 판정 ────────────────────────────
  // 좌/우/위 임계값을 넘었으면 해당 액션 확정, 아니면 원위치 복귀.
  void _onPanEnd(DragEndDetails details) {
    if (_flyAwayController.isAnimating || _resetController.isAnimating) return;

    final dx = _dragOffset.dx;
    final dy = _dragOffset.dy;

    // 위로 끌어올린 것이 명확하면 (수직 임계 + 수평 < 수직)
    if (dy < -_kVerticalThreshold && dy.abs() > dx.abs()) {
      _startFlyAway(_SwipeAction.addToCart);
      return;
    }
    // 우로 끌어 찜
    if (dx > _kHorizontalThreshold) {
      _startFlyAway(_SwipeAction.like);
      return;
    }
    // 좌로 끌어 패스
    if (dx < -_kHorizontalThreshold) {
      _startFlyAway(_SwipeAction.pass);
      return;
    }

    // 임계값 미달 — 원위치 복귀 애니메이션 시작
    _resetStart = _dragOffset;
    _resetController.forward(from: 0);
  }

  // ── 카드 이탈 애니메이션 시작 ─────────────────────────────
  // 액션별로 종점(화면 밖) 좌표 지정.
  void _startFlyAway(_SwipeAction action) {
    final size = MediaQuery.of(context).size;
    _flyAwayStart = _dragOffset;
    _flyingAction = action;

    switch (action) {
      case _SwipeAction.pass:
        // 좌측 화면 밖으로
        _flyAwayEnd = Offset(-size.width * 1.2, _dragOffset.dy);
        break;
      case _SwipeAction.like:
        // 우측 화면 밖으로
        _flyAwayEnd = Offset(size.width * 1.2, _dragOffset.dy);
        break;
      case _SwipeAction.addToCart:
        // 위쪽 화면 밖으로
        _flyAwayEnd = Offset(_dragOffset.dx, -size.height * 1.2);
        break;
    }

    _flyAwayController.forward(from: 0);
  }

  // ── 카드 이탈 애니메이션 매 프레임 ────────────────────────
  void _onFlyAwayTick() {
    final start = _flyAwayStart;
    final end = _flyAwayEnd;
    if (start == null || end == null) return;
    setState(() {
      _dragOffset = Offset.lerp(start, end, _flyAwayController.value)!;
    });
  }

  // ── 이탈 완료 시 — 카운터 갱신 + 다음 카드 ────────────────
  void _commitFlyAway() {
    final action = _flyingAction;
    if (action == null) return;
    final menu = widget.menus[_currentIndex];

    switch (action) {
      case _SwipeAction.pass:
        debugPrint('[MenuSwipeScreen] MENU_PASSED');
        break;
      case _SwipeAction.like:
        _likedCount++;
        _pendingFavoriteIds.add(menu.id);
        _showQuickToast('찜했어요 ❤️', AppColors.background);
        debugPrint('[MenuSwipeScreen] MENU_LIKED');
        break;
      case _SwipeAction.addToCart:
        _addedToCartCount++;
        ref.read(cartProvider.notifier).addItem(menu);
        _showQuickToast('장바구니에 담았어요 🛒', AppColors.background);
        debugPrint('[MenuSwipeScreen] MENU_ADDED_TO_CART');
        break;
    }

    // 카드 인덱스 진행 + 드래그 상태 초기화
    setState(() {
      _currentIndex++;
      _dragOffset = Offset.zero;
      _flyAwayStart = null;
      _flyAwayEnd = null;
      _flyingAction = null;
    });

    // 결과 화면 도달 직전에 prefs 영속화 (실패해도 흐름 영향 없음)
    if (_currentIndex >= widget.menus.length) {
      _flushFavoritesIfAny();
    }
  }

  // ── 원위치 복귀 애니메이션 매 프레임 ──────────────────────
  void _onResetTick() {
    final start = _resetStart;
    if (start == null) return;
    setState(() {
      _dragOffset = Offset.lerp(start, Offset.zero, _resetController.value)!;
    });
    if (_resetController.status == AnimationStatus.completed) {
      _resetStart = null;
    }
  }

  // ── 하단 액션 버튼 핸들러 ────────────────────────────────
  // 스와이프 안 되는 사용자를 위한 접근성 대안.
  // 내부적으로 _startFlyAway 를 호출해 같은 애니메이션 경로 공유.
  void _onActionTap(_SwipeAction action) {
    if (_flyAwayController.isAnimating || _resetController.isAnimating) return;
    if (_currentIndex >= widget.menus.length) return;

    // 버튼 탭은 화면 중앙에서 시작하므로 _dragOffset 을 시작점으로 살짝 설정
    setState(() {
      switch (action) {
        case _SwipeAction.pass:
          _dragOffset = const Offset(-30, 0);
          break;
        case _SwipeAction.like:
          _dragOffset = const Offset(30, 0);
          break;
        case _SwipeAction.addToCart:
          _dragOffset = const Offset(0, -30);
          break;
      }
    });
    _startFlyAway(action);
  }

  // ── 짧은 SnackBar 토스트 ─────────────────────────────────
  // 색상/폰트 토큰 그대로 사용. 짧게(1.2s) 표시해 흐름 끊지 않음.
  void _showQuickToast(String label, Color background) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: background,
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            120, // 하단 액션 버튼과 겹치지 않게 위로 올림
          ),
        ),
      );
  }

  // ── UI 최상위 구성 ───────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isFinished = _currentIndex >= widget.menus.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(
        showBack: true,
        title: '${widget.restaurantName} · 스와이프',
      ),
      body: isFinished
          ? _buildFinishedView()
          : _buildSwipeView(),
    );
  }

  // ── 스와이프 카드 스택 본문 ──────────────────────────────
  Widget _buildSwipeView() {
    return SafeArea(
      child: Column(
        children: [
          // 진행도 안내 줄 — "3 / 12" 와 가이드 카피
          _buildProgressBar(),

          // 카드 스택 — 화면의 대부분을 차지
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: _buildCardStack(),
            ),
          ),

          // 하단 액션 버튼 (3개)
          _buildActionBar(),
        ],
      ),
    );
  }

  // ── 진행도 표시 (현재 카드 N / 전체 M + 가이드) ──────────
  Widget _buildProgressBar() {
    final total = widget.menus.length;
    final current = math.min(_currentIndex + 1, total);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          Text(
            '$current / $total',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '좌(패스)·우(찜)·위(담기)로 쓸어보세요',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── 카드 스택 — 상위 3장 노출 ────────────────────────────
  // 인덱스가 큰 카드부터(=뒤쪽에 깔리는 카드) 먼저 쌓고, 맨 위에 현재 카드.
  // - 0번 (최상단, 현재) : scale 1.0, opacity 1.0, 드래그/회전 적용
  // - 1번 (뒤쪽 1장)     : scale 0.95, opacity 0.8
  // - 2번 (뒤쪽 2장)     : scale 0.90, opacity 0.6
  Widget _buildCardStack() {
    final visibleCount = math.min(3, widget.menus.length - _currentIndex);
    if (visibleCount <= 0) {
      return const SizedBox.shrink();
    }

    // children 순서: 뒤쪽 카드(idx=2) 먼저, 마지막에 최상단 카드(idx=0).
    final children = <Widget>[];
    for (int stackPos = visibleCount - 1; stackPos >= 0; stackPos--) {
      final menu = widget.menus[_currentIndex + stackPos];
      children.add(_buildCard(menu, stackPos));
    }

    return Stack(
      alignment: Alignment.center,
      children: children,
    );
  }

  // ── 카드 위젯 한 장 ──────────────────────────────────────
  // stackPos 0 이면 최상단(드래그/회전 적용), 그 외엔 배경 카드.
  Widget _buildCard(MenuItem menu, int stackPos) {
    final isTop = stackPos == 0;
    final scale = 1.0 - (stackPos * 0.05);
    final opacity = 1.0 - (stackPos * 0.2);
    // 뒤쪽 카드는 살짝 아래로 밀어 깊이감 강조 (12px 씩).
    final translateY = stackPos * 12.0;

    Widget card = _buildCardContent(menu, isTop: isTop);

    // 최상단 카드만 드래그 변환과 오버레이 라벨을 갖는다.
    if (isTop) {
      card = GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Transform.translate(
          offset: _dragOffset,
          child: Transform.rotate(
            angle: _rotation,
            child: Stack(
              alignment: Alignment.center,
              children: [
                card,
                _buildOverlayLabels(),
              ],
            ),
          ),
        ),
      );
    }

    return Transform.translate(
      offset: Offset(0, translateY),
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: card,
        ),
      ),
    );
  }

  // ── 카드 내부 콘텐츠 (이미지 + 이름 + 가격 + 설명) ────────
  Widget _buildCardContent(MenuItem menu, {required bool isTop}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000), // 검정 8% — 토큰화돼있지 않아 표준값 사용
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 카드 상단: 메뉴 이미지 (가로폭 100% × 280) ──
            // FoodImage 가 imageUrl 없으면 카테고리 이모지 fallback.
            SizedBox(
              width: double.infinity,
              height: 280,
              child: FoodImage(
                imageUrl: menu.imageUrl,
                categoryLabel: menu.category.label,
                width: double.infinity,
                height: 280,
                emojiSize: 96,
                borderRadius: BorderRadius.zero, // 이미 ClipRRect 가 둥글림 처리
                semanticLabel: '${menu.name} 메뉴 사진',
              ),
            ),

            // ── 카드 하단: 메뉴 정보 ──────────────────────
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 메뉴명 + 가격 (한 줄)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          menu.name,
                          style: AppTextStyles.heading3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        menu.formattedPrice,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // 한 줄 설명 — 비어있으면 줄 자체 생략
                  if (menu.description.isNotEmpty)
                    Text(
                      menu.description,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: AppSpacing.sm),

                  // 알레르기/카테고리 칩 (현 모델엔 알레르기 필드 없음 →
                  // 카테고리 라벨만 칩으로 표시. 미래에 spicy/allergyNotes 가
                  // 모델에 추가되면 칩 더 늘리면 됨.)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildChip(menu.category.label),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 카테고리/알레르기 칩 ─────────────────────────────────
  Widget _buildChip(String label) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: primary.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(
          color: primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── PASS / LIKE / CART 오버레이 라벨 ─────────────────────
  // 진행도 비례 페이드 인. 좌/우/위 별 색과 위치 다름.
  Widget _buildOverlayLabels() {
    return IgnorePointer(
      ignoring: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // PASS — 좌상단에 빨강 라벨
          Positioned(
            top: 24,
            left: 24,
            child: Opacity(
              opacity: _leftProgress,
              child: _overlayLabel(
                text: '넘기기',
                color: AppColors.error,
                rotateDeg: -15,
              ),
            ),
          ),

          // LIKE — 우상단에 분홍 라벨
          Positioned(
            top: 24,
            right: 24,
            child: Opacity(
              opacity: _rightProgress,
              child: _overlayLabel(
                text: '좋아요',
                color: const Color(0xFFE91E63), // 표준 핑크 — 토큰 미정의
                rotateDeg: 15,
              ),
            ),
          ),

          // CART — 상단 중앙에 주황 라벨
          Positioned(
            top: 90,
            left: 0,
            right: 0,
            child: Opacity(
              opacity: _upProgress,
              child: Center(
                child: _overlayLabel(
                  text: '담기',
                  color: Theme.of(context).colorScheme.primary,
                  rotateDeg: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overlayLabel({
    required String text,
    required Color color,
    required double rotateDeg,
  }) {
    return Transform.rotate(
      angle: rotateDeg * math.pi / 180.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(AppRadius.small),
          color: Colors.white.withAlpha(220),
        ),
        child: Text(
          text,
          style: AppTextStyles.heading3.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  // ── 하단 액션 버튼 3개 ───────────────────────────────────
  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: Icons.close_rounded,
            color: AppColors.iconInactive,
            label: '패스',
            onTap: () => _onActionTap(_SwipeAction.pass),
          ),
          _buildActionButton(
            icon: Icons.favorite_rounded,
            color: const Color(0xFFE91E63), // 표준 핑크
            label: '찜',
            onTap: () => _onActionTap(_SwipeAction.like),
          ),
          _buildActionButton(
            icon: Icons.shopping_cart_rounded,
            color: Theme.of(context).colorScheme.primary,
            label: '담기',
            onTap: () => _onActionTap(_SwipeAction.addToCart),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withAlpha(20),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, color: color, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── 결과 화면 — 모든 카드 소진 시 ───────────────────────
  // 찜 N개 / 장바구니 M개 요약 + 리스트 모드 복귀 버튼.
  Widget _buildFinishedView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.celebration_rounded,
              size: 80,
              color: Color(0xFFFFA000),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '모든 메뉴를 다 봤어요!',
              style: AppTextStyles.heading2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '찜 $_likedCount개 · 장바구니에 $_addedToCartCount개 담음',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(
                label: '리스트 모드로',
                onPressed: () {
                  // 결과 화면 닫고 메뉴 리스트 화면으로 복귀.
                  // (스택에 MenuScreen 이 깔려 있으므로 pop 만 하면 됨)
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
