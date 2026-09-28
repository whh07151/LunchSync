// ══════════════════════════════════════════════════════════
// 파일 역할: WOW#6 식당/메뉴 토너먼트(이상형월드컵 스타일) 화면
//
// 진입 방법(부모가 호출):
//   Navigator.of(context).push(
//     MaterialPageRoute(builder: (_) => const TournamentScreen()),
//   );
//
// 동작 흐름:
//   1) 진입 시 모드 선택 다이얼로그 노출
//       - [식당 토너먼트] : /api/restaurants 에서 후보 셔플 → 8강 시작
//       - [메뉴 토너먼트] : 식당 선택 화면 → 그 식당 메뉴 셔플 → 8강 시작
//   2) 8강 → 4강 → 결승 → 우승 (PageView 대신 setState 단순 진행)
//       - 각 라운드 = 카드 페어(좌/우) 비교 → 탭하면 다음 라운드 진출
//       - 후보 부족(< 8) 시 가지고 있는 만큼만으로 4강·결승 직행
//   3) 결과 화면
//       - 우승 카드 큰 이미지 + 이름 + "이걸로 결정!" CTA
//       - 식당 모드: [식당 상세로] + [다시 토너먼트] + [공유]
//       - 메뉴 모드: [장바구니에 담기] + [다시 토너먼트] + [공유]
//
// 데이터 소스 (백엔드 추가 API 불필요):
//   - 식당: RestaurantsApiService.getRestaurants(limit: 30) → shuffle().take(8)
//   - 메뉴: RestaurantsApiService.getMenus(restaurantId) → shuffle().take(8)
//
// 디자인 정책:
//   - 디자인 토큰(CustomerColors / AppColors / AppSpacing) 만 사용
//   - 카드는 FoodImage(160x200) + 이름 + 카테고리(식당) 또는 가격(메뉴)
//   - 패배 카드 fade out + 승리 카드 scale 1.0→1.06 미세 애니메이션
//
// 주의:
//   - 메뉴 모드의 "장바구니에 담기" 는 cartProvider 의 MenuItem 모델을 요구
//     → 백엔드 MenuItemDto → MenuItem 변환을 본 화면에서 수행(menu_screen
//       _mapCategory 로직과 1:1 동일하게 단순화)
//   - 식당 모드의 "식당 상세로" 는 RestaurantDetailScreen(restaurantId, initialName).
// ══════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_retry.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/food_image.dart';
import '../../models/menu_item.dart';
import '../../providers/cart_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/restaurants_api_service.dart';
// WOW#9 — 우승 직후 백그라운드로 결과 적재(트렌딩 집계 소스).
//   실패해도 UX 차단 X — 서비스 자체가 false 만 돌려준다.
import '../../services/tournaments_api_service.dart';
import '../menu/menu_screen.dart';
import '../restaurant/restaurant_detail_screen.dart';

/// 토너먼트 모드 — 사용자가 진입 시 선택.
enum TournamentMode {
  /// 식당 토너먼트(8개 식당 중 1곳 결정)
  restaurant('식당 토너먼트', '🍽️'),

  /// 메뉴 토너먼트(특정 식당의 메뉴 8개 중 1개 결정)
  menu('메뉴 토너먼트', '🥢');

  const TournamentMode(this.label, this.emoji);

  /// 화면 카피용 한글 라벨
  final String label;

  /// 모드 선택 카드에 표시할 이모지
  final String emoji;
}

/// 토너먼트 후보 1개를 추상화한 공용 모델.
///
/// 식당과 메뉴 양쪽을 한 화면에서 처리하기 위해 공통 필드만 추려서 정의.
/// [id] 로 라우팅(식당 상세) 또는 장바구니 추가에 사용.
class _TournamentCandidate {
  const _TournamentCandidate({
    required this.id,
    required this.name,
    required this.categoryLabel,
    required this.imageUrl,
    this.subtitleLabel,
    this.menuItem,
  });

  /// 식당이면 restaurantId, 메뉴이면 menuId.
  final String id;

  /// 카드 상단 큰 글자 — 식당명 또는 메뉴명.
  final String name;

  /// FoodImage fallback 용 카테고리 라벨(이모지 매핑).
  final String categoryLabel;

  /// 카드 이미지 URL(없을 수도 있음 — FoodImage 가 안전 처리).
  final String? imageUrl;

  /// 카드 하단 부가 라벨.
  /// - 식당 모드: 카테고리 라벨(한식/중식 등)
  /// - 메뉴 모드: 가격 표시("8,500원")
  final String? subtitleLabel;

  /// 메뉴 모드일 때 장바구니 추가에 사용할 MenuItem(식당 모드면 null).
  ///
  /// 우승 후 "장바구니에 담기" 버튼에서만 사용한다.
  final MenuItem? menuItem;
}

/// 토너먼트 화면(이상형월드컵 스타일).
class TournamentScreen extends ConsumerStatefulWidget {
  const TournamentScreen({super.key});

  @override
  ConsumerState<TournamentScreen> createState() => _TournamentScreenState();
}

/// 토너먼트 화면 상태 머신.
///
/// 흐름:
///   intro(모드 선택) → loading(API 호출) → playing(라운드 진행) → result(우승)
///   loading/playing 단계에서 에러나 후보 부족이 발생하면 error 단계로 분기.
enum _Stage { intro, pickRestaurant, loading, playing, result, error }

class _TournamentScreenState extends ConsumerState<TournamentScreen>
    with TickerProviderStateMixin {
  // ── API 클라이언트 ───────────────────────────────────────
  static const _restaurantsApi = RestaurantsApiService();
  // WOW#9 트렌딩 적재용 — 우승 화면 진입 시 1회 백그라운드 POST.
  static const _tournamentsApi = TournamentsApiService();

  // ── WOW#9 트렌딩 분석용 보조 상태 ────────────────────────
  // 시작 시각(_Stage.playing 진입 ms) 과 시작 후보 수를 기록 → 우승 시
  // duration_ms / candidate_count 로 백엔드에 전달.
  DateTime? _tournamentStartAt;
  int _tournamentStartCandidateCount = 0;
  // POST 중복 호출 방지 플래그(우승 진입은 단 1회여야 함 — _restart 시 false 복귀).
  bool _resultReported = false;

  // ── 화면 단계 (state machine) ──────────────────────────
  _Stage _stage = _Stage.intro;

  // ── 토너먼트 모드(식당 / 메뉴) ────────────────────────
  TournamentMode? _mode;

  // ── 후보 목록(초기 N개, 보통 8개) ─────────────────────
  // 라운드가 진행되며 _currentRoundCandidates 로 점점 줄어든다.
  List<_TournamentCandidate> _allCandidates = const [];

  // ── 이번 라운드에서 비교할 후보들(짝수 개수) ─────────
  // 8 → 4 → 2 → (우승) 으로 줄어든다.
  List<_TournamentCandidate> _currentRoundCandidates = const [];

  // ── 다음 라운드로 진출한 승자 누적 ─────────────────────
  // 한 라운드의 모든 페어를 다 본 뒤 _currentRoundCandidates 로 승격.
  final List<_TournamentCandidate> _winnersOfRound = [];

  // ── 현재 페어 인덱스(0,1 / 2,3 / 4,5 ...) ─────────────
  // _currentRoundCandidates[_pairIndex], _pairIndex+1 두 장을 동시에 표시.
  int _pairIndex = 0;

  // ── 메뉴 모드 — 사용자가 선택한 식당 정보 ─────────────
  // 메뉴 토너먼트 결과 화면 헤더와 장바구니 추가에 사용.
  RestaurantDto? _selectedRestaurantForMenu;

  // ── 식당 모드 — 선택 가능한 식당 목록(메뉴 모드 진입 화면용) ─
  List<RestaurantDto> _restaurantPickList = const [];

  // ── 에러 메시지(후보 부족 / API 실패 등) ──────────────
  String _errorMessage = '';

  // ── 패배 카드 fade out 애니메이션 컨트롤러 ────────────
  // 좌/우 어느 쪽이 졌는지 _losingSide 로 표시 (null = 애니메이션 중 아님).
  // -1 = 왼쪽이 짐, 1 = 오른쪽이 짐.
  AnimationController? _pairAnimController;
  int? _losingSide;

  // ── 패배 카드 fade 진행도 (0.0 = 보임 → 1.0 = 완전 사라짐) ──
  double _fadeProgress = 0.0;

  @override
  void initState() {
    super.initState();
    // 화면이 그려진 직후 모드 선택 다이얼로그를 한 번만 띄운다.
    // _showModeDialog 가 async — initState 에서 직접 await 불가능하므로 microtask 활용.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showModeDialog();
    });
  }

  @override
  void dispose() {
    _pairAnimController?.dispose();
    super.dispose();
  }

  // ── 모드 선택 다이얼로그 ─────────────────────────────
  //
  // "어떤 토너먼트?" — [식당 토너먼트] / [메뉴 토너먼트]
  // 다이얼로그 외부 탭/뒤로가기로 닫으면 즉시 화면을 pop 한다.
  Future<void> _showModeDialog() async {
    final picked = await showDialog<TournamentMode>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModePickerDialog(),
    );
    if (!mounted) return;

    if (picked == null) {
      // 다이얼로그 취소 → 진입 자체를 취소한 것으로 보고 pop.
      Navigator.of(context).maybePop();
      return;
    }

    setState(() => _mode = picked);

    if (picked == TournamentMode.restaurant) {
      // 식당 모드 — 곧바로 후보 로드.
      await _loadRestaurantsAndStart();
    } else {
      // 메뉴 모드 — 식당 선택 화면을 먼저 띄움.
      await _loadRestaurantPickList();
    }
  }

  // ── 식당 모드: 식당 후보 8개 로드 + 토너먼트 시작 ─────
  Future<void> _loadRestaurantsAndStart() async {
    setState(() => _stage = _Stage.loading);

    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      _setError('로그인이 풀렸어요. 다시 로그인해봐요');
      return;
    }

    // limit=30 — 충분히 넉넉히 받아서 클라이언트 측에서 셔플.
    // 백엔드가 위치 기반 쿼리를 지원하지 않으므로 전체에서 랜덤 픽으로 폴백.
    //
    // throwOnError:true — 통신 끊김(공용 와이파이 깜빡임)을 "후보 0개"로
    // 오인하지 않도록, 네트워크 오류는 ApiNetworkException 으로 받아 별도 안내.
    final List<RestaurantDto> list;
    try {
      list = await _restaurantsApi.getRestaurants(
        accessToken: token,
        limit: 30,
        throwOnError: true,
      );
    } on ApiNetworkException {
      if (!mounted) return;
      _setError('📡 연결이 불안정해요. 잠시 후 다시 시도해주세요');
      return;
    }

    if (!mounted) return;

    if (list.isEmpty) {
      _setError('이 동네는 토너먼트할 후보가 부족해요 (현재 0개)');
      return;
    }

    // 셔플 + 상위 8개 — 후보 수 < 8 이면 가지고 있는 만큼만 진행.
    final shuffled = [...list]..shuffle(math.Random());
    final picked = shuffled.take(8).toList(growable: false);

    final candidates = picked
        .map((r) => _TournamentCandidate(
              id: r.id,
              name: r.name,
              categoryLabel: r.category ?? '식당',
              imageUrl: r.imageUrl,
              subtitleLabel: r.category,
            ))
        .toList(growable: false);

    if (candidates.length < 2) {
      _setError('이 동네는 토너먼트할 후보가 부족해요 (현재 ${candidates.length}개)');
      return;
    }

    _startTournament(candidates);
  }

  // ── 메뉴 모드: 식당 후보 리스트 로드 (식당 선택 화면용) ─
  Future<void> _loadRestaurantPickList() async {
    setState(() => _stage = _Stage.loading);

    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      _setError('로그인이 풀렸어요. 다시 로그인해봐요');
      return;
    }

    final List<RestaurantDto> list;
    try {
      list = await _restaurantsApi.getRestaurants(
        accessToken: token,
        limit: 20,
        throwOnError: true,
      );
    } on ApiNetworkException {
      if (!mounted) return;
      _setError('📡 연결이 불안정해요. 잠시 후 다시 시도해주세요');
      return;
    }

    if (!mounted) return;

    if (list.isEmpty) {
      _setError('이 동네에 등록된 식당이 없어요. 잠시 후 다시 시도해봐요');
      return;
    }

    setState(() {
      _restaurantPickList = list;
      _stage = _Stage.pickRestaurant;
    });
  }

  // ── 메뉴 모드: 식당 선택 → 그 식당 메뉴 8개 로드 + 시작 ─
  Future<void> _onMenuRestaurantSelected(RestaurantDto restaurant) async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      _setError('로그인이 풀렸어요. 다시 로그인해봐요');
      return;
    }

    setState(() {
      _selectedRestaurantForMenu = restaurant;
      _stage = _Stage.loading;
    });

    final List<MenuItemDto> menus;
    try {
      menus = await _restaurantsApi.getMenus(
        accessToken: token,
        restaurantId: restaurant.id,
        throwOnError: true,
      );
    } on ApiNetworkException {
      if (!mounted) return;
      _setError('📡 연결이 불안정해요. 잠시 후 다시 시도해주세요');
      return;
    }

    if (!mounted) return;

    if (menus.isEmpty) {
      _setError('"${restaurant.name}" 의 메뉴가 아직 등록되지 않았어요');
      return;
    }

    // 셔플 + 상위 8개 — 메뉴가 부족하면 가지고 있는 만큼만(4강·결승 직행).
    final shuffled = [...menus]..shuffle(math.Random());
    final picked = shuffled.take(8).toList(growable: false);

    final candidates = picked
        .map((m) => _TournamentCandidate(
              id: m.id,
              name: m.name,
              categoryLabel: m.category ?? '메뉴',
              imageUrl: m.imageUrl,
              subtitleLabel: _formatPrice(m.price),
              menuItem: _dtoToMenuItem(m, restaurant.id),
            ))
        .toList(growable: false);

    if (candidates.length < 2) {
      _setError('메뉴 후보가 부족해요 (현재 ${candidates.length}개)');
      return;
    }

    _startTournament(candidates);
  }

  // ── 토너먼트 본 진행 시작 ────────────────────────────
  //
  // 후보 수가 홀수면 마지막 한 명에게 부전승을 주기보다,
  // 가장 가까운 짝수(2 이하로 떨어지지 않게)에 맞춘다.
  // 8 → 4 → 2 → 우승 (8 → 6 → 4 처럼도 가능). 단순화를 위해 그대로 진행.
  void _startTournament(List<_TournamentCandidate> candidates) {
    // 홀수면 마지막 1명을 떨어뜨려 짝수로 보정(이상형월드컵 통상 룰).
    final adjusted = candidates.length.isOdd
        ? candidates.sublist(0, candidates.length - 1)
        : candidates;

    setState(() {
      _allCandidates = candidates;
      _currentRoundCandidates = adjusted;
      _winnersOfRound.clear();
      _pairIndex = 0;
      _stage = _Stage.playing;
      _losingSide = null;
      _fadeProgress = 0.0;
    });

    // WOW#9 — 분석용 시작 시각/후보 수 기록(우승 시 백엔드 전송).
    //   _restart 시에는 본 함수가 다시 호출되어 자동으로 초기화됨.
    _tournamentStartAt = DateTime.now();
    _tournamentStartCandidateCount = candidates.length;
    _resultReported = false;
  }

  // ── 페어에서 한 쪽을 선택했을 때 호출 ────────────────
  //
  // [side] = 0 (왼쪽 승) | 1 (오른쪽 승)
  // 패배 카드 fade out 애니메이션 (180ms) 종료 후 다음 페어로 이동.
  Future<void> _selectInPair(int side) async {
    if (_pairIndex >= _currentRoundCandidates.length) return;
    if (_losingSide != null) return; // 애니메이션 진행 중 — 중복 탭 차단.

    // 마지막 페어가 짝이 부족할 수도 있음(부전승) — 안전 가드.
    final hasRight = _pairIndex + 1 < _currentRoundCandidates.length;
    if (!hasRight) {
      // 부전승 — 그대로 진출.
      _winnersOfRound.add(_currentRoundCandidates[_pairIndex]);
      _advanceToNextPairOrRound();
      return;
    }

    // 패배 측 인덱스 표시 — 카드 페어 위젯이 opacity 를 줄이며 사라짐.
    setState(() {
      _losingSide = side == 0 ? 1 : -1;
      _fadeProgress = 0.0;
    });

    // 짧은 fade out 애니메이션 (180ms).
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _pairAnimController?.dispose();
    _pairAnimController = controller;

    controller.addListener(() {
      if (!mounted) return;
      setState(() => _fadeProgress = controller.value);
    });

    try {
      await controller.forward();
    } catch (_) {
      // controller 가 dispose 된 경우 — 무시.
    }
    if (!mounted) return;

    // 승자 누적 + 다음 페어로 이동.
    final winner = _currentRoundCandidates[side == 0 ? _pairIndex : _pairIndex + 1];
    _winnersOfRound.add(winner);
    _advanceToNextPairOrRound();
  }

  // ── 페어 종료 후 다음 페어 / 다음 라운드 / 결과로 분기 ─
  void _advanceToNextPairOrRound() {
    final nextPairIndex = _pairIndex + 2;
    if (nextPairIndex < _currentRoundCandidates.length) {
      // 같은 라운드 안의 다음 페어로.
      setState(() {
        _pairIndex = nextPairIndex;
        _losingSide = null;
        _fadeProgress = 0.0;
      });
      return;
    }

    // 라운드 종료 — 다음 라운드 시작 또는 우승.
    if (_winnersOfRound.length == 1) {
      // 우승자 결정.
      setState(() {
        _stage = _Stage.result;
        _losingSide = null;
        _fadeProgress = 0.0;
      });
      // WOW#9 — 우승 결과 백그라운드 적재(트렌딩 집계용).
      //   await 하지 않음 → 우승 화면 표시가 네트워크 응답에 의존하지 않게.
      _reportResultInBackground(_winnersOfRound.first);
      return;
    }

    // 다음 라운드 시작 — 승자들을 새 라운드 후보로.
    final nextRound = List<_TournamentCandidate>.from(_winnersOfRound);
    setState(() {
      _currentRoundCandidates = nextRound;
      _winnersOfRound.clear();
      _pairIndex = 0;
      _losingSide = null;
      _fadeProgress = 0.0;
    });
  }

  // ── "다시 토너먼트" — 모드 선택부터 다시 ───────────
  void _restart() {
    setState(() {
      _mode = null;
      _allCandidates = const [];
      _currentRoundCandidates = const [];
      _winnersOfRound.clear();
      _pairIndex = 0;
      _selectedRestaurantForMenu = null;
      _restaurantPickList = const [];
      _stage = _Stage.intro;
      _errorMessage = '';
      _losingSide = null;
      _fadeProgress = 0.0;
    });
    // WOW#9 — 분석 보조 상태도 리셋.
    //   다음 토너먼트에서 다시 _startTournament 가 시작 시각을 새로 기록함.
    _tournamentStartAt = null;
    _tournamentStartCandidateCount = 0;
    _resultReported = false;
    _showModeDialog();
  }

  // ── 에러 헬퍼 ────────────────────────────────────────
  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.error;
      _errorMessage = message;
    });
  }

  // ── MenuItemDto → MenuItem 변환 (cartProvider 호환용) ─
  //
  // menu_screen 의 _mapCategory 풍부 매핑까지는 불필요 — 토너먼트 결과
  // 화면에서는 카테고리 표시를 하지 않으므로 MenuCategory.other 로 충분.
  // 장바구니에 담기만 하면 결제·주문 흐름은 그대로 동작.
  MenuItem _dtoToMenuItem(MenuItemDto dto, String restaurantId) {
    return MenuItem(
      id: dto.id,
      restaurantId: restaurantId,
      name: dto.name,
      description: dto.description ?? '',
      price: dto.price,
      // 토너먼트 결과 → 장바구니 단순 추가용. 정확한 카테고리는 메뉴 화면에서.
      category: MenuCategory.other,
      imageUrl: dto.imageUrl,
    );
  }

  // ── 가격 포맷 ("8,500원") ────────────────────────────
  String _formatPrice(int price) {
    final parts = <String>[];
    var n = price;
    while (n >= 1000) {
      parts.insert(0, (n % 1000).toString().padLeft(3, '0'));
      n ~/= 1000;
    }
    parts.insert(0, n.toString());
    return '${parts.join(',')}원';
  }

  // ── 현재 라운드 라벨 ("8강 1/4", "4강 2/2", "결승") ──
  String _roundLabel() {
    final total = _currentRoundCandidates.length;
    final pairsTotal = (total / 2).ceil();
    final pairIdx = (_pairIndex / 2).floor() + 1;
    if (total == 2) return '결승';
    if (total == 4) return '4강 $pairIdx/$pairsTotal';
    if (total == 6) return '6강 $pairIdx/$pairsTotal';
    if (total == 8) return '8강 $pairIdx/$pairsTotal';
    return '$total강 $pairIdx/$pairsTotal';
  }

  // ── 진행률(LinearProgressIndicator 용) ──────────────
  //
  // 토너먼트 전체에서 "본 페어 수" 비율.
  // 초기 후보 N개 → 최종 우승까지 (N-1) 번의 페어가 필요.
  double _overallProgress() {
    final initial = _allCandidates.length;
    if (initial < 2) return 0.0;
    final totalPairs = initial - 1; // N개 → N-1번의 비교로 우승 결정.
    // 지금까지 처리한 페어 수 = 이미 라운드를 마친 승자들 수 + 현재 라운드 winners
    //   - 현재 라운드 후보 수만큼 시작했고, _pairIndex/2 가 처리된 페어 수.
    //   - 이전 라운드까지 처리한 페어 수 = (initial - currentRoundSize)
    final processedPairsInPrev = initial - _currentRoundCandidates.length;
    final processedPairsInCurrent = (_pairIndex / 2).floor();
    final processed = processedPairsInPrev + processedPairsInCurrent;
    return (processed / totalPairs).clamp(0.0, 1.0);
  }

  // ── 우승 → 식당 상세 ────────────────────────────────
  void _gotoRestaurantDetail(_TournamentCandidate winner) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RestaurantDetailScreen(
          restaurantId: winner.id,
          initialName: winner.name,
        ),
      ),
    );
  }

  // ── 우승 → 장바구니에 담기 + 메뉴 화면으로 ───────────
  void _addToCartAndGotoMenu(_TournamentCandidate winner) {
    final menuItem = winner.menuItem;
    final restaurant = _selectedRestaurantForMenu;
    if (menuItem == null || restaurant == null) {
      // 안전 가드 — 메뉴 모드가 아니면 호출되지 말아야 함.
      return;
    }
    ref.read(cartProvider.notifier).addItem(menuItem);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${menuItem.name}" 을(를) 장바구니에 담았어요'),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
    // 메뉴 화면으로 이동 — 사용자가 다른 메뉴도 추가하거나 주문 진행 가능.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          restaurantId: restaurant.id,
          restaurantName: restaurant.name,
        ),
      ),
    );
  }

  // ── WOW#9 — 우승 결과를 백엔드에 백그라운드 적재 ──────
  //
  // 호출 시점: _Stage.result 진입 직후 1회.
  // 정책:
  //   - await 하지 않음 → 우승 UI 표시가 네트워크 응답을 기다리지 않게.
  //   - JWT 없거나 호출 실패해도 UX 영향 없음(서비스가 false 만 돌려줌).
  //   - _resultReported 플래그로 중복 호출 차단 — _restart 시 false 복귀.
  //
  // 보내는 값:
  //   - mode               : 식당 모드 / 메뉴 모드
  //   - winnerRestaurantId : 식당 모드는 winner.id, 메뉴 모드는
  //                          _selectedRestaurantForMenu.id (트렌딩 집계 핵심).
  //   - winnerMenuId       : 메뉴 모드일 때 winner.id, 식당 모드는 null.
  //   - candidateCount     : _tournamentStartCandidateCount.
  //   - durationMs         : 시작 시각 ~ 지금 까지의 ms (0 이상으로 clamp).
  void _reportResultInBackground(_TournamentCandidate winner) {
    if (_resultReported) return;
    _resultReported = true;

    final token = ref.read(userProvider).accessToken;
    if (token == null || token.isEmpty) {
      debugPrint('[TournamentScreen] 토너먼트 결과 적재 스킵 — accessToken 없음');
      return;
    }

    final modeNow = _mode;
    if (modeNow == null) {
      // 정상 흐름에서는 도달 불가 — 안전 가드.
      debugPrint('[TournamentScreen] 토너먼트 결과 적재 스킵 — mode 미설정');
      return;
    }

    // 식당 ID 결정: 모드별로 다르게 채움.
    //   식당 모드 → winner.id
    //   메뉴 모드 → 사용자가 선택한 식당의 id (트렌딩 집계 기준)
    final String? winnerRestaurantId;
    final String? winnerMenuId;
    final TournamentApiMode apiMode;
    if (modeNow == TournamentMode.restaurant) {
      apiMode = TournamentApiMode.restaurant;
      winnerRestaurantId = winner.id;
      winnerMenuId = null;
    } else {
      apiMode = TournamentApiMode.menu;
      winnerRestaurantId = _selectedRestaurantForMenu?.id;
      winnerMenuId = winner.id;
    }

    // 소요 시간 — 음수/누락 방지.
    int? durationMs;
    final startAt = _tournamentStartAt;
    if (startAt != null) {
      final diff = DateTime.now().difference(startAt).inMilliseconds;
      durationMs = diff < 0 ? 0 : diff;
    }

    // fire-and-forget — await 하지 않고 unawaited 가시화를 위해 then 으로 로그만.
    _tournamentsApi
        .postResult(
          accessToken: token,
          mode: apiMode,
          winnerRestaurantId: winnerRestaurantId,
          winnerMenuId: winnerMenuId,
          candidateCount: _tournamentStartCandidateCount > 0
              ? _tournamentStartCandidateCount
              : null,
          durationMs: durationMs,
        )
        .then((ok) {
          if (!ok) {
            debugPrint(
              '[TournamentScreen] 우승 결과 적재 실패 — UX 영향 없음',
            );
          }
        })
        .catchError((Object e) {
          debugPrint('[TournamentScreen] RESULT_PERSIST_FAILED');
        });
  }

  // ── 공유하기 (share_plus) ────────────────────────────
  //
  // 식당 모드: "오로라 식당 토너먼트 우승! 🏆 #LunchSync"
  // 메뉴 모드: "오늘 점심은 김치찌개로 결정! 🏆 #LunchSync"
  Future<void> _shareWinner(_TournamentCandidate winner) async {
    final isRestaurantMode = _mode == TournamentMode.restaurant;
    final text = isRestaurantMode
        ? '${winner.name} 식당 토너먼트 우승! 🏆\n#LunchSync 로 점심 결정'
        : '오늘 점심은 ${winner.name} 로 결정! 🏆\n#LunchSync 로 메뉴 결정';
    try {
      // share_plus 10.1.x — 정적 Share.share() 호출(wrapped_screen 동일 패턴).
      await Share.share(text, subject: '점심 토너먼트 우승');
    } catch (e) {
      debugPrint('[TournamentScreen] SHARE_FAILED');
    }
  }

  // ─────────────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('점심 토너먼트'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _Stage.intro:
        // 다이얼로그가 떠 있는 동안 배경 — 단순 안내 텍스트.
        // AppTextStyles 게터(TextStyle 생성)는 런타임 평가라 const 사용 불가.
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              '토너먼트를 시작할게요...',
              style: AppTextStyles.bodyMedium,
            ),
          ),
        );
      case _Stage.pickRestaurant:
        return _buildRestaurantPicker();
      case _Stage.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: CustomerColors.primary),
              const SizedBox(height: AppSpacing.md),
              Text('후보를 모으는 중이에요...', style: AppTextStyles.bodyMedium),
            ],
          ),
        );
      case _Stage.playing:
        return _buildPlaying();
      case _Stage.result:
        return _buildResult();
      case _Stage.error:
        return _buildError();
    }
  }

  // ── 메뉴 모드: 식당 선택 화면 ──────────────────────
  Widget _buildRestaurantPicker() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      itemCount: _restaurantPickList.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '어느 식당의 메뉴로 토너먼트할까요?',
              style: AppTextStyles.heading3,
            ),
          );
        }
        final r = _restaurantPickList[index - 1];
        return _RestaurantPickerCard(
          restaurant: r,
          onTap: () => _onMenuRestaurantSelected(r),
        );
      },
    );
  }

  // ── 게임 진행 화면 ─────────────────────────────────
  Widget _buildPlaying() {
    final hasRight = _pairIndex + 1 < _currentRoundCandidates.length;
    final left = _currentRoundCandidates[_pairIndex];
    final right = hasRight ? _currentRoundCandidates[_pairIndex + 1] : null;

    return Column(
      children: [
        // ── 상단 라운드 라벨 + 진행률 ─────────────
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: CustomerColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _roundLabel(),
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.background,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _mode == TournamentMode.restaurant
                    ? '🍽️ 식당 토너먼트'
                    : '🥢 메뉴 토너먼트',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${(_overallProgress() * 100).round()}%',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _overallProgress(),
              minHeight: 6,
              backgroundColor: AppColors.disabledBackground,
              valueColor: const AlwaysStoppedAnimation<Color>(
                CustomerColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── 안내 카피 ────────────────────────────
        Text(
          '둘 중 하나를 골라봐요',
          style: AppTextStyles.heading3,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '탭한 쪽이 다음 라운드로 진출해요',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── 카드 페어 ────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _CandidateCard(
                    candidate: left,
                    onTap: () => _selectInPair(0),
                    // _losingSide == -1 → 왼쪽이 짐 → opacity 감소.
                    opacity: _losingSide == -1 ? 1.0 - _fadeProgress : 1.0,
                    scale: _losingSide == 1 ? 1.0 + _fadeProgress * 0.06 : 1.0,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (right != null)
                  Expanded(
                    child: _CandidateCard(
                      candidate: right,
                      onTap: () => _selectInPair(1),
                      opacity: _losingSide == 1 ? 1.0 - _fadeProgress : 1.0,
                      scale:
                          _losingSide == -1 ? 1.0 + _fadeProgress * 0.06 : 1.0,
                    ),
                  )
                else
                  // 부전승 — 한 쪽만 그려진 경우(드물게 후보 홀수 보정 실패 시).
                  const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),

        // ── 하단 'VS' 칩 ─────────────────────────
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'VS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 결과 화면(우승) ─────────────────────────────────
  Widget _buildResult() {
    if (_winnersOfRound.isEmpty && _currentRoundCandidates.isEmpty) {
      // 이론상 도달 불가 — 안전 폴백.
      return const Center(child: Text('우승자를 찾지 못했어요'));
    }
    // 마지막 페어를 진행하고 _winnersOfRound 에 1명 남은 시점에 도착.
    // 만약 _winnersOfRound 가 비었다면(특이 케이스) _currentRoundCandidates[0] 로 폴백.
    final winner = _winnersOfRound.isNotEmpty
        ? _winnersOfRound.first
        : _currentRoundCandidates.first;

    final isRestaurantMode = _mode == TournamentMode.restaurant;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 우승 헤더 ─────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text('🏆', style: TextStyle(fontSize: 36)),
              SizedBox(width: AppSpacing.sm),
              Text(
                '우승!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: CustomerColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── 우승 카드 큰 이미지 ──────────────────
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CustomerColors.primary.withAlpha(40),
                  CustomerColors.primarySurface,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: CustomerColors.primary.withAlpha(50),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: CustomerColors.primary,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                FoodImage(
                  imageUrl: winner.imageUrl,
                  categoryLabel: winner.categoryLabel,
                  width: double.infinity,
                  height: 220,
                  emojiSize: 80,
                  semanticLabel: '${winner.name} 이미지',
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  winner.name,
                  style: AppTextStyles.heading2.copyWith(
                    color: CustomerColors.primaryDark,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (winner.subtitleLabel != null &&
                    winner.subtitleLabel!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    winner.subtitleLabel!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '이걸로 결정!',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── 액션 버튼 ────────────────────────
          // 메인 CTA(식당 상세 / 장바구니) + 보조(다시 / 공유)
          ElevatedButton.icon(
            onPressed: () {
              if (isRestaurantMode) {
                _gotoRestaurantDetail(winner);
              } else {
                _addToCartAndGotoMenu(winner);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: CustomerColors.primary,
              foregroundColor: AppColors.background,
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.sm + 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            icon: Icon(
              isRestaurantMode
                  ? Icons.storefront_rounded
                  : Icons.shopping_cart_rounded,
              size: 20,
            ),
            label: Text(
              isRestaurantMode ? '식당 상세 보러 가기' : '장바구니에 담기',
              style: AppTextStyles.buttonMedium.copyWith(
                color: AppColors.background,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _restart,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CustomerColors.primary,
                    side: const BorderSide(
                      color: CustomerColors.primary,
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm + 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    '다시 토너먼트',
                    style: AppTextStyles.buttonMedium.copyWith(
                      color: CustomerColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareWinner(winner),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(
                      color: AppColors.disabledBackground,
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm + 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(
                    '공유',
                    style: AppTextStyles.buttonMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  // ── 에러 / 후보 부족 화면 ───────────────────────────
  Widget _buildError() {
    final isRestaurantMode = _mode == TournamentMode.restaurant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🥲', style: TextStyle(fontSize: 56)),
            const SizedBox(height: AppSpacing.md),
            Text(
              _errorMessage,
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            // 식당 모드의 후보 부족이면 "다시 시도"가 의미 있음(서버 캐시/재시도).
            if (isRestaurantMode)
              OutlinedButton.icon(
                onPressed: _loadRestaurantsAndStart,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('다시 시도'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CustomerColors.primary,
                  side: const BorderSide(
                    color: CustomerColors.primary,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _restart,
              child: Text(
                '모드 다시 선택',
                style: AppTextStyles.buttonMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// 모드 선택 다이얼로그
// ─────────────────────────────────────────────────────
class _ModePickerDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.bottomSheet),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏆', style: TextStyle(fontSize: 40)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '어떤 토너먼트를 할까요?',
              style: AppTextStyles.heading3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '둘 중에 하나를 골라봐요',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: TournamentMode.values
                  .map(
                    (m) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: m == TournamentMode.restaurant ? 0 : 0,
                        ),
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(m),
                          child: Container(
                            margin: EdgeInsets.only(
                              right: m == TournamentMode.restaurant
                                  ? AppSpacing.xs
                                  : 0,
                              left: m == TournamentMode.menu
                                  ? AppSpacing.xs
                                  : 0,
                            ),
                            padding:
                                const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: CustomerColors.primarySurface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card),
                              border: Border.all(
                                color: CustomerColors.primaryLight,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  m.emoji,
                                  style: const TextStyle(fontSize: 36),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  m.label,
                                  style: AppTextStyles.buttonMedium.copyWith(
                                    color: CustomerColors.primaryDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '취소',
                style: AppTextStyles.buttonMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// 후보 카드(좌/우 한 장)
//
// - GestureDetector 로 탭 → onTap 콜백.
// - opacity / scale 은 부모가 fade out 애니메이션 진행도에 따라 주입.
//   (패배: opacity 1→0, 승리: scale 1.0→1.06)
// ─────────────────────────────────────────────────────
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.onTap,
    required this.opacity,
    required this.scale,
  });

  final _TournamentCandidate candidate;
  final VoidCallback onTap;
  final double opacity;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CustomerColors.primarySurface,
                  CustomerColors.primary.withAlpha(20),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: CustomerColors.primaryLight,
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 카드 이미지 — FoodImage 가 null/실패를 카테고리 이모지로 폴백.
                FoodImage(
                  imageUrl: candidate.imageUrl,
                  categoryLabel: candidate.categoryLabel,
                  width: double.infinity,
                  height: 160,
                  emojiSize: 56,
                  semanticLabel: '${candidate.name} 이미지',
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  candidate.name,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (candidate.subtitleLabel != null &&
                    candidate.subtitleLabel!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    candidate.subtitleLabel!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// 메뉴 모드 — 식당 선택 리스트 카드
// ─────────────────────────────────────────────────────
class _RestaurantPickerCard extends StatelessWidget {
  const _RestaurantPickerCard({
    required this.restaurant,
    required this.onTap,
  });

  final RestaurantDto restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.disabledBackground, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            FoodImage(
              imageUrl: restaurant.imageUrl,
              categoryLabel: restaurant.category ?? '식당',
              width: 64,
              height: 64,
              emojiSize: 28,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    restaurant.category ?? '식당',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.iconInactive,
            ),
          ],
        ),
      ),
    );
  }
}
