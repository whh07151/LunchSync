import 'dart:async';
import '../owner/owner_home_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/components/components.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/utils/normalizer.dart';
import '../../core/utils/distance_calculator.dart';
import '../session/member_select_screen.dart';
import '../session/session_create_screen.dart';
import '../session/join_session_screen.dart';
import '../session/session_lobby_screen.dart';
import '../restaurant/restaurant_detail_screen.dart';
import '../orders/order_list_screen.dart';
import '../notifications/notification_screen.dart';
import '../my_info/my_info_screen.dart';
import '../auth/login_screen.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/users_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../../services/restaurants_api_service.dart';
import '../../services/geolocation_service.dart';
import '../../services/crawl_api_service.dart';
import '../../services/notifications_api_service.dart';
import '../../services/favorites_api_service.dart';
// WOW#9 — 이번 주 토너먼트 인기 식당(최근 N일 우승 빈도 상위) 트렌딩 섹션.
//   섹션은 데이터 0개일 때 자체 숨김 → 도메인 누락 시 UI 영향 없음.
import '../../services/tournaments_api_service.dart';
import '../../models/session.dart';
import '../my_info/favorites_list_screen.dart';
import '../tournament/tournament_screen.dart';
import 'widgets/home_primary_layout.dart';

/// 홈 앱바의 알림 진입점.
///
/// 화면에 보이는 배지는 10개부터 `9+`로 줄여 쓰되, 보조 기술에는 실제
/// 미읽음 개수를 전달한다.
class HomeNotificationButton extends StatelessWidget {
  const HomeNotificationButton({
    super.key,
    required this.unreadCount,
    required this.onPressed,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final normalizedCount = unreadCount < 0 ? 0 : unreadCount;
    final semanticLabel = '알림, 읽지 않음 $normalizedCount개';

    return Semantics(
      label: semanticLabel,
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        tooltip: semanticLabel,
        onPressed: onPressed,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(
              Icons.notifications_outlined,
              color: AppColors.textPrimary,
            ),
            if (normalizedCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 14,
                    minHeight: 14,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    normalizedCount > 9 ? '9+' : '$normalizedCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 오늘의 세션 조회가 실패했을 때 빈 상태 대신 표시하는 재시도 카드.
class HomeTodaySessionsErrorCard extends StatelessWidget {
  const HomeTodaySessionsErrorCard({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '오늘의 세션 조회 오류. $message',
      child: AppHighlightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  color: AppColors.error,
                  semanticLabel: '조회 오류',
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '오늘의 세션을 불러오지 못했어요',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            AppOutlinedButton(label: '다시 시도', height: 44, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-06 홈 대시보드 화면
//
// 구성 (와이어프레임 기준):
//   - 상단 앱바: 앱 로고 + 알림 아이콘
//   - 인사말 헤더: 사용자 이름 + 소속
//   - 빠른 실행 CTA 4개: 점심 만들기 / 코드로 참가 / 최근 이력 / 토너먼트(WOW#6)
//     (※ 알림은 AppBar 우측 아이콘 + 탭바에서 이미 도달 가능 — 중복 제거)
//   - 오늘의 세션 섹션: 오늘 참여 중인 세션 카드
//   - 주문 가능한 등록 식당과 읽기 전용 카카오 주변 장소 섹션
//   - 하단 탭바 5개: 홈 / 점심세션 / 주문현황 / 내역 / 내정보
//
// 📌 지도는 홈에 없음. CU-15(지도/리스트 토글) 화면에서만 표시 (와이어프레임 기준).
//
// 연동:
//   - GET /api/users/me               → userProvider
//   - GET /api/sessions/today         → _todaySessions
//   - GET /api/restaurants?limit=10   → _recommendedRestaurants
// ══════════════════════════════════════════════════════════

// ConsumerStatefulWidget: Riverpod의 userProvider를 읽기 위해 사용
// StatefulWidget 대신 이걸 쓰면 ref.watch/read로 전역 상태에 접근 가능
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

// WidgetsBindingObserver: 앱 라이프사이클(포그라운드/백그라운드) 변화 수신.
// 위치 권한을 시스템 설정에서 켜고 돌아왔을 때
// 주변 장소를 다시 조회한다. 권한 변경 자체는 OS 이벤트가 없어
// "포그라운드 복귀 시점" 을 트리거로 사용한다.
class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  // ── 하단 탭바 상태 ─────────────────────────────────────
  // 현재 선택된 탭의 인덱스 (0: 홈, 1: 점심세션, 2: 주문현황, 3: 내역, 4: 내정보)
  // 기본값: 0 (홈 탭)
  int _currentTabIndex = 0;

  // ── 홈 데이터 상태 (백엔드 API 응답 저장소) ───────────────
  // 로딩 중에는 null, 조회 완료 후 실제 값으로 채움
  // Session 리스트 첫 번째 항목을 "오늘의 세션"으로 사용
  List<Session>? _todaySessions;
  String? _sessionsLoadError;
  List<RestaurantDto>? _recommendedRestaurants;

  // 각 섹션 로딩 상태 — UI에서 스켈레톤/스피너 표시용
  bool _isSessionsLoading = true;
  bool _isRestaurantsLoading = true;

  // 조회 성공이 확인되기 전에는 기존 세션 유무를 알 수 없으므로 새 세션 생성
  // CTA를 노출하지 않는다. 실패를 "세션 없음"으로 오인해 중복 생성하는 것을 방지.
  bool get _canCreateSession =>
      !_isSessionsLoading &&
      _sessionsLoadError == null &&
      _todaySessions != null;

  // ── 내 즐겨찾기 위젯 상태 (배민 패턴) ─────────────────
  // 홈에서 가로 스크롤 칩으로 즐겨찾기한 식당 미리보기.
  // 0개면 안내 박스 노출, 1개 이상이면 카드 가로 스크롤.
  // 화면 진입 + 식당 상세 pop 복귀 시 갱신.
  List<FavoriteDto> _myFavorites = const [];
  bool _isFavoritesLoading = true;

  // ── 이번 주 토너먼트 트렌딩 (WOW#9) ───────────────────
  // 최근 7일 동안 사용자들이 토너먼트로 우승시킨 식당의 빈도 상위 5개.
  // 데이터 0개면 섹션 자체를 숨김 → 초기 운영 시에도 빈 영역이 안 보이게.
  // 진입 + 토너먼트 화면 pop 복귀 시 자동 갱신.
  List<TrendingRestaurantDto> _trendingRestaurants = const [];
  bool _isTrendingLoading = true;

  // ── 알림 미읽음 카운트 (배지 표시용) ────────────────────
  // 0 일 때는 배지 숨김, 1 이상이면 빨간 점.
  int _unreadNotifications = 0;

  /// 미읽음 알림 폴링 타이머 — 홈 머무는 동안 30초마다 카운트 동기화.
  /// FCM 푸시는 백그라운드/포그라운드 알림만, 카운트는 별도 조회.
  Timer? _unreadPollingTimer;
  static const _kUnreadPollInterval = Duration(seconds: 30);

  // ── 읽기 전용 주변 장소 탐색 상태 ───────────────────────
  // 카카오 장소는 주문 가능한 DB 식당과 독립적으로 보여 준다.
  StreamSubscription<Position>? _positionSub;
  DateTime? _lastDiscoveryAt;
  double? _lastDiscoveryLat;
  double? _lastDiscoveryLng;
  bool _isDiscoveryLoading = false;
  String? _discoveryError;
  List<NearbyPlaceDto> _nearbyPlaces = const [];
  int _discoveryRequestSerial = 0;
  static const _kDiscoveryCooldown = Duration(minutes: 5);
  static const _kNearbyRadiusM = 1000;
  static const _kDiscoveryMoveFilter = 500;

  // ── 사용자 현재 위치(거리 표시용) ──────────────────────
  // 주변 탐색 스트림에서 받은 좌표를 그대로 재사용 — Geolocator 권한이 없거나
  // 위치 서비스가 꺼져 있으면 영구히 null. 식당 카드의 "거리" 라인은
  // null 인 동안 자체적으로 숨겨진다(distanceLabel 이 null 반환).
  double? _userLat;
  double? _userLng;

  // ── 위치 권한 상태 ────────────────────────────────────
  // 빈 상태 카피를 세 갈래로 분기하기 위한 플래그.
  //   true  : 권한 OK → "주변 식당 찾는 중..." + LoadingIndicator
  //   false : 거부/제한 → "위치 권한을 켜주세요" + 설정 안내
  //   null  : 아직 미확인(첫 진입 직후) → 단순 안내
  // 위치 탐색 진입 시 평가하고, 권한 오류 후 포그라운드 복귀 시 재평가.
  bool? _hasLocationPermission;

  // ── 생명주기: 화면이 처음 만들어질 때 ──────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-06');

    // 앱 라이프사이클 옵저버 등록 — 포그라운드 복귀 감지용.
    // dispose 에서 짝맞춰 removeObserver 호출 필수.
    WidgetsBinding.instance.addObserver(this);

    // 화면 진입 시 DB에서 최신 프로필 조회 후 userProvider 갱신.
    // addPostFrameCallback: initState 안에서 ref.read가 안전하게 실행되도록
    // 첫 프레임 렌더링 완료 후 실행.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserProfile();
      _loadTodaySessions();
      _loadRecommendedRestaurants();
      _loadUnreadNotifications();
      _loadMyFavorites();
      // WOW#9 — 이번 주 토너먼트 트렌딩 식당 미리 로드(0개면 섹션 숨김).
      _loadTrendingRestaurants();
      // 위치 기반 읽기 전용 장소 탐색 + 이동 스트림 구독
      _startNearbyDiscovery();

      // 알림 미읽음 카운트 30초 폴링 — 홈 머무는 동안 배지 자동 갱신
      _unreadPollingTimer = Timer.periodic(_kUnreadPollInterval, (_) {
        if (mounted) _loadUnreadNotifications();
      });
    });
  }

  @override
  void dispose() {
    // 홈 화면 이탈 시 스트림/타이머/옵저버 해제 — 배터리/권한 UI 정리
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _unreadPollingTimer?.cancel();
    super.dispose();
  }

  // ── 앱 라이프사이클 콜백 ──────────────────────────────
  // 사용자가 시스템 설정에서 위치 권한을 켜고 앱으로 돌아오면
  // 자동으로 한 번 더 장소 탐색을 시도한다.
  // resumed 외 상태(paused/inactive 등)는 모두 무시.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    if (_hasLocationPermission == false || _discoveryError != null) {
      _lastDiscoveryAt = null;
      _startNearbyDiscovery();
    }
  }

  // ── 멤버 선택 화면(CU-08)으로 이동 ──────────────────────
  // "점심 만들기"와 "친구 초대" CTA 둘 다 이 메서드를 통해 진입.
  // CU-09(세션 생성, 우현호) 완성 후 onNext 콜백에서 CU-09로 이동하도록 교체.
  void _goToMemberSelect() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberSelectScreen(
          onNext: (selectedMembers) {
            // CU-08 완료 → CU-09 세션 조건 설정 화면으로 이동
            // selectedMembers는 이미 sessionProvider에 저장된 상태이므로
            // SessionCreateScreen에서 ref.watch(sessionProvider).selectedMembers 로 읽음
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SessionCreateScreen()),
            );
          },
        ),
      ),
    );
  }

  // ── DB에서 프로필 조회 후 userProvider 갱신 ──────────────
  // GET /api/users/me 호출 → 이름/소속 최신값을 userProvider에 반영
  Future<void> _loadUserProfile() async {
    // accessToken이 없으면 조회 불가 (로그아웃 상태)
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final profile = await const UsersApiService().getMe(token);
    if (profile != null && mounted) {
      // mounted: 비동기 완료 전에 화면이 사라졌을 경우 setState 방지
      ref.read(userProvider.notifier).setFromProfile(profile);

      // 2026-05-31 회귀 fix: 자동 로그인은 _autoLoginNextStep 을 initState
      // 한 번만 계산하므로, DB 에서 role 이 OWNER 로 바뀐 뒤 앱을 백그라운드
      // 에서 다시 켜도 CustomerHome 에 계속 머무는 버그. /api/users/me 응답
      // 으로 role 가 OWNER + status APPROVED 면 OwnerHomeScreen 으로 강제
      // 라우팅한다 (pushAndRemoveUntil 로 손님 스택 정리).
      if (profile.role == 'OWNER' &&
          (profile.status ?? 'APPROVED') == 'APPROVED') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OwnerHomeScreen()),
          (route) => false,
        );
      }
    }
  }

  // ── 오늘의 세션 조회 ────────────────────────────────────
  // GET /api/sessions/today — 오늘 날짜에 내가 참여하거나 만든 세션 목록
  // 첫 번째 항목을 홈 화면 "오늘의 세션" 카드로 노출.
  // 세션이 없으면 null로 두고 "시작하기" 유도 상태를 표시.
  Future<void> _loadTodaySessions() async {
    if (mounted && !_isSessionsLoading) {
      setState(() => _isSessionsLoading = true);
    }

    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) {
        setState(() {
          _todaySessions = null;
          _sessionsLoadError = '로그인 정보가 없어 오늘의 세션을 불러올 수 없어요.';
          _isSessionsLoading = false;
        });
      }
      return;
    }

    final result = await const SessionsApiService().getTodaySessionsResult(
      accessToken: token,
    );

    if (!mounted) return;
    setState(() {
      _todaySessions = result.sessions;
      _sessionsLoadError = result.message;
      _isSessionsLoading = false;
    });
  }

  // ── 카카오 장소 탐색 ────────────────────────────────────
  // 위치 정보는 주변 탐색에만 전송한다. 주문 가능한 식당 DB는 수정하지 않는다.
  void _startNearbyDiscovery() {
    _positionSub?.cancel();
    _discoveryRequestSerial++;
    var streamPositionSeen = false;
    setState(() {
      _nearbyPlaces = const [];
      _isDiscoveryLoading = true;
      _discoveryError = null;
    });
    () async {
      final pos = await const GeolocationService().getCurrentPosition();
      if (!mounted) return;
      // 스트림의 더 최신 위치가 먼저 도착했다면 늦은 스냅샷으로 덮지 않는다.
      if (streamPositionSeen) return;
      setState(() {
        _hasLocationPermission = pos != null;
        if (pos == null) {
          _discoveryRequestSerial++;
          _nearbyPlaces = const [];
          _isDiscoveryLoading = false;
          _discoveryError = null;
          _userLat = null;
          _userLng = null;
        }
      });
      if (pos != null) {
        _updateUserCoord(pos);
        await _discoverIfDue(pos);
      } else {
        _loadRecommendedRestaurants();
      }
    }();

    _positionSub = const GeolocationService()
        .positionStream(distanceFilterMeters: _kDiscoveryMoveFilter)
        .listen(
          (pos) {
            streamPositionSeen = true;
            _updateUserCoord(pos);
            _discoverIfDue(pos);
          },
          onError: (_) {
            if (!mounted) return;
            setState(() => _discoveryError = '위치를 갱신하지 못했어요. 다시 시도해 주세요.');
          },
        );
  }

  // ── 거리 표기용 사용자 좌표 갱신 ───────────────────────
  // 장소 탐색 흐름과 별도로 카드 거리 라인에 사용. setState 로 식당 카드
  // 리빌드하여 "거리 320m" 같은 한 줄이 자동 업데이트되도록 한다.
  void _updateUserCoord(Position pos) {
    if (!mounted) return;
    // 위/경도가 동일하면 굳이 setState 안 함 — 불필요한 리빌드 방지.
    if (_userLat == pos.latitude && _userLng == pos.longitude) {
      if (_isRestaurantsLoading) _loadRecommendedRestaurants();
      return;
    }
    setState(() {
      _userLat = pos.latitude;
      _userLng = pos.longitude;
    });
    // 현재 위치를 기준으로 주문 가능한 식당도 다시 조회한다.
    _loadRecommendedRestaurants();
  }

  // 같은 지역은 5분 동안 재조회하지 않지만, 500m 이상 이동하면 즉시 갱신한다.
  Future<void> _discoverIfDue(Position pos) async {
    final now = DateTime.now();
    final moved =
        _lastDiscoveryLat == null ||
        _lastDiscoveryLng == null ||
        Geolocator.distanceBetween(
              _lastDiscoveryLat!,
              _lastDiscoveryLng!,
              pos.latitude,
              pos.longitude,
            ) >=
            _kDiscoveryMoveFilter;
    if (!moved &&
        _lastDiscoveryAt != null &&
        now.difference(_lastDiscoveryAt!) < _kDiscoveryCooldown) {
      return;
    }

    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) {
        setState(() => _discoveryError = '로그인한 뒤 주변 장소를 확인해 주세요.');
      }
      return;
    }
    _lastDiscoveryAt = now; // 진행 중 같은 좌표로 중복 요청 방지
    _lastDiscoveryLat = pos.latitude;
    _lastDiscoveryLng = pos.longitude;
    final requestSerial = ++_discoveryRequestSerial;
    setState(() {
      _nearbyPlaces = const [];
      _isDiscoveryLoading = true;
      _discoveryError = null;
    });
    try {
      final places = await const CrawlApiService().getNearbyPlaces(
        accessToken: token,
        lat: pos.latitude,
        lng: pos.longitude,
        radius: _kNearbyRadiusM,
      );
      if (!mounted || requestSerial != _discoveryRequestSerial) return;
      setState(() {
        _nearbyPlaces = places;
        _isDiscoveryLoading = false;
      });
    } catch (_) {
      if (!mounted || requestSerial != _discoveryRequestSerial) return;
      _lastDiscoveryAt = null;
      setState(() {
        _isDiscoveryLoading = false;
        _discoveryError = '카카오 장소 정보를 불러오지 못했어요.';
      });
    }
  }

  // ── 알림 미읽음 수 조회 ──────────────────────────────────
  // GET /api/notifications 결과에서 isRead=false 개수를 센다.
  // 알림함 화면에서 돌아왔을 때도 자동 갱신을 위해 _openNotifications() 에서 재호출.
  Future<void> _loadUnreadNotifications() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    final list = await const NotificationsApiService().getMyNotifications(
      accessToken: token,
    );
    if (!mounted) return;
    setState(() {
      _unreadNotifications = list.where((n) => !n.isRead).length;
    });
  }

  // 알림함 진입 → 닫고 돌아오면 미읽음 수 재조회 (서버에서 read 처리됐을 수 있음)
  Future<void> _openNotifications() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationScreen()));
    if (!mounted) return;
    _loadUnreadNotifications();
  }

  // ── AI 추천 식당 조회 ────────────────────────────────────
  // 위치를 얻은 뒤 반경 1km 내 식당을 거리순으로 조회한다.
  Future<void> _loadRecommendedRestaurants() async {
    final token = ref.read(userProvider).accessToken;
    final lat = _userLat;
    final lng = _userLng;
    if (token == null) {
      if (mounted) setState(() => _isRestaurantsLoading = false);
      return;
    }

    final list = await const RestaurantsApiService().getRestaurants(
      accessToken: token,
      limit: 10,
      lat: lat,
      lng: lng,
      radius: lat != null && lng != null ? _kNearbyRadiusM : null,
    );

    if (!mounted || lat != _userLat || lng != _userLng) return;
    setState(() {
      _recommendedRestaurants = list;
      _isRestaurantsLoading = false;
    });
  }

  // ── 내 즐겨찾기 목록 조회 (배민 "찜한 가게" 패턴) ───────
  // GET /api/users/me/favorites — 식당 정보 join된 결과.
  // 로그인 토큰 없으면 빈 리스트로 폴백(가드).
  // 식당 상세에서 하트 토글 후 pop으로 돌아오는 경우에도 자동 갱신되도록
  // 즐겨찾기 위젯 우측 "전체 보기" 진입 후 복귀 시점에 한 번 더 호출.
  Future<void> _loadMyFavorites() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) setState(() => _isFavoritesLoading = false);
      return;
    }
    final list = await const FavoritesApiService().list(accessToken: token);
    if (!mounted) return;
    setState(() {
      _myFavorites = list;
      _isFavoritesLoading = false;
    });
  }

  // ── 트렌딩 식당(이번 주 토너먼트) 조회 (WOW#9) ──────────
  // GET /api/tournaments/trending?limit=5&days=7
  //   - 우승 빈도 0건 → 빈 리스트(섹션 숨김).
  //   - 토큰 없으면 호출 자체 스킵 — 비로그인 가드.
  //   - 실패해도 UX 차단 X — 서비스 자체가 빈 리스트로 폴백.
  // 토너먼트 화면 pop 복귀 시 자동 갱신을 위해 _openTournament 헬퍼에서 재호출.
  Future<void> _loadTrendingRestaurants() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) setState(() => _isTrendingLoading = false);
      return;
    }
    final list = await const TournamentsApiService().getTrending(
      accessToken: token,
      // 5개 카드 가로 스크롤 권장 + 7일 윈도우("이번 주" 의미).
      limit: 5,
      days: 7,
    );
    if (!mounted) return;
    setState(() {
      _trendingRestaurants = list;
      _isTrendingLoading = false;
    });
  }

  // ── 토너먼트 화면 진입 + 복귀 시 트렌딩 갱신 ──────────
  // 사용자가 직접 우승을 만든 직후에는 가장 신선한 트렌딩을 보고 싶어할 가능성이
  // 높아 복귀 시점에 한 번 더 호출. 백엔드는 우승 INSERT 1건이 즉시 반영됨.
  Future<void> _openTournament() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TournamentScreen()));
    if (!mounted) return;
    _loadTrendingRestaurants();
  }

  // ── 즐겨찾기 목록 화면으로 이동 + 복귀 시 자동 갱신 ────
  // 사용자가 목록에서 항목을 탭해 식당 상세로 들어가 하트 해제 후
  // 두 번 pop 으로 홈에 돌아오면, 홈 위젯도 즉시 반영되어야 함.
  Future<void> _openFavoritesList() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FavoritesListScreen()));
    if (!mounted) return;
    _loadMyFavorites();
  }

  // ── UI 구성 ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,

      // ── 상단 앱바 ──────────────────────────────────────
      appBar: _buildAppBar(),

      // ── 본문: 현재 선택된 탭에 따라 다른 화면 표시 ────
      body: _buildBody(),

      // ── 하단 탭바 ──────────────────────────────────────
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── 상단 앱바 위젯 ──────────────────────────────────────
  // 왼쪽: 앱 이름/로고, 오른쪽: 알림 아이콘 버튼
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      // automaticallyImplyLeading: 뒤로가기 버튼 자동 추가 방지
      // (홈 화면은 뒤로가기가 없으므로 false)
      automaticallyImplyLeading: false,

      // ── 왼쪽: 앱 이름 ────────────────────────────────
      title: Text(
        'LunchSync',
        style: AppTextStyles.heading3.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),

      // ── 오른쪽: 알림 아이콘 버튼 ─────────────────────
      actions: [
        HomeNotificationButton(
          unreadCount: _unreadNotifications,
          onPressed: _openNotifications,
        ),
        // 오른쪽 끝 여백
        const SizedBox(width: 4),
      ],
    );
  }

  // ── 본문 위젯: 탭 인덱스에 따라 화면 전환 ────────────────
  Widget _buildBody() {
    // IndexedStack: 모든 탭 화면을 메모리에 유지하면서 선택된 것만 표시
    // (탭 전환 시 화면이 재생성되지 않아 스크롤 위치 등이 유지됨)
    return IndexedStack(
      index: _currentTabIndex,
      children: [
        // 0번 탭: 홈
        _buildHomeTab(),

        // 1번 탭: 점심세션 — 오늘 참여 중인 세션 카드 모음 + 만들기/참가하기 진입점
        _buildSessionsTab(),

        // 2번 탭: 주문현황 — OrderListScreen (오늘 내 주문 목록)
        const OrderListScreen(),

        // 3번 탭: 내역 — OrderListScreen 의 history 모드 (오늘 외 과거 주문도 포함)
        const OrderListScreen(historyMode: true),

        // 4번 탭: 내정보 — CU-23 내정보/설정
        MyInfoScreen(
          // 로그아웃 처리:
          //   1. userProvider 초기화 (JWT + 유저 정보 삭제)
          //   2. 내비게이션 스택 전체 제거 후 LoginScreen으로 이동
          //      (온보딩은 완료 상태이므로 SplashScreen 건너뜀)
          onLogout: () {
            ref.read(userProvider.notifier).clear();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (ctx) => LoginScreen(
                  onLoginSuccess: ({required String nextStep}) {
                    // 로그아웃 후 재로그인: nextStep에 따라 화면 분기
                    // 온보딩 완료 기기이므로 대부분 HOME이지만,
                    // 다른 카카오 계정으로 로그인 시 PROFILE_SETUP이 올 수 있음
                    if (nextStep == 'HOME') {
                      Navigator.of(ctx).pushReplacement(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                      );
                    } else {
                      // 온보딩 필요한 계정 → main.dart의 라우팅 로직과 동일하게 처리
                      Navigator.of(ctx).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ),
              (route) => false, // 이전 스택 전체 제거
            );
          },
        ),
      ],
    );
  }

  // ── 홈 탭 콘텐츠 위젯 ──────────────────────────────────
  // 스크롤 가능한 홈 화면의 실제 내용
  Widget _buildHomeTab() {
    return SingleChildScrollView(
      // physics: 스크롤 동작 방식. BouncingScrollPhysics = iOS처럼 끝에서 튕기는 효과
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 인사말 헤더 섹션 ────────────────────────────
          _buildGreetingHeader(),

          const SizedBox(height: AppSpacing.lg),

          // 오늘 해야 할 일을 먼저, 보조 동작은 그다음에 보여 준다.
          // 같은 콘텐츠를 모바일에서는 세로로, 넓은 웹에서는 나란히 배치한다.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: HomePrimaryLayout(
              todaySession: _buildTodaySession(),
              quickActions: _buildQuickActions(),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── 내 즐겨찾기 섹션 (배민 "찜한 가게" 패턴, 2026-05-15 추가) ─
          // AI 추천 위에 두는 이유:
          //   사용자가 이미 검증한 식당이 추천보다 신뢰도가 높음.
          //   특히 단골 점심 패턴이 있는 직장인은 이 영역에서 바로 점심 결정 가능.
          // 0개면 안내 박스(즐겨찾기 사용 유도) → 잠재 사용자 학습.
          _buildFavoritesSectionHeader(),
          const SizedBox(height: AppSpacing.sm),
          _buildFavoritesList(),

          // ── 이번 주 토너먼트 트렌딩 섹션 (WOW#9) ───────
          // 데이터 0개면 _buildTrendingSection 이 SizedBox.shrink() 를
          // 반환하므로 위/아래 간격까지 한 번에 사라진다(어색한 빈 공간 방지).
          _buildTrendingSection(),

          const SizedBox(height: AppSpacing.lg),

          // 등록 식당은 주문에, 카카오 장소는 탐색에만 사용한다.
          // 타이틀 옆에 "기준" 칩을 함께 노출 → 사장님 피드백
          // ("AI 추천 기준이 불명") 반영. 별도 정보 다이얼로그 없이
          // 한 줄로 "왜 이 식당이 보이는가" 를 즉시 이해할 수 있게 함.
          _buildRecommendationSectionHeader(),
          const SizedBox(height: AppSpacing.sm),

          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: RestaurantDataNotice(),
          ),
          const SizedBox(height: AppSpacing.sm),

          // 가로 스크롤 식당 카드 목록
          // (와이어프레임: 홈에는 지도 X. 지도는 CU-15 "지도/리스트 토글"에서만)
          _buildRestaurantList(),

          const SizedBox(height: AppSpacing.lg),
          _buildNearbyPlacesSection(),

          // 하단 여백 (하단 탭바와 겹치지 않도록)
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  // ── 인사말 헤더 위젯 ────────────────────────────────────
  // 주황 단색 배경 + 사용자 이름 + 현재 해야 할 일
  // DB에서 조회한 실제 이름/소속을 userProvider를 통해 표시
  Widget _buildGreetingHeader() {
    final primary = Theme.of(context).colorScheme.primary;

    // userProvider에서 실제 이름/소속 읽기
    // _loadUserProfile()이 완료되면 자동으로 리빌드됨
    final user = ref.watch(userProvider);
    final userName = user.name ?? '...'; // 로딩 중이면 '...' 표시
    final userOrg = user.org ?? ''; // 소속 미설정 시 빈 문자열

    return Semantics(
      header: true,
      label: userOrg.isNotEmpty
          ? '$userName님, $userOrg의 오늘 점심'
          : '$userName님의 오늘 점심',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          color: primary,
          // 헤더 하단 모서리만 둥글게 처리 (카드처럼 보이도록)
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(AppRadius.bottomSheet),
            bottomRight: Radius.circular(AppRadius.bottomSheet),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$userName님, 오늘도 반가워요',
                    style: AppTextStyles.heading2.copyWith(color: Colors.white),
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(34),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withAlpha(72)),
                  ),
                  child: const Icon(
                    Icons.lunch_dining_rounded,
                    color: Colors.white,
                    semanticLabel: '점심',
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xs),

            // 소속 + 문구
            // userOrg가 비어 있으면 소속 부분 없이 문구만 표시
            Text(
              userOrg.isNotEmpty
                  ? '$userOrg · 지금 참여할 세션부터 확인해 보세요'
                  : '지금 참여할 세션부터 확인해 보세요',
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white.withAlpha(224),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 빠른 실행 CTA 4개 위젯 ────────────────────────────────
  // 2x2 그리드 형태로 주요 기능에 빠르게 접근할 수 있는 버튼들
  Widget _buildQuickActions() {
    // CTA 버튼 데이터를 리스트로 관리
    // 새로운 버튼 추가 시 이 리스트에만 추가하면 됨
    final actions = [
      if (_canCreateSession)
        _QuickAction(
          icon: Icons.add_circle_rounded,
          label: '점심 만들기',
          emphasized: true,
          // CU-08 멤버 선택 화면 진입 (세션 생성의 첫 단계)
          // CU-09(세션 생성, 우현호) 완성 후 onNext에서 CU-09로 이동하도록 교체
          onTap: () => _goToMemberSelect(),
        ),
      _QuickAction(
        icon: Icons.person_add_rounded,
        label: '코드로 참가',
        emphasized: true,
        // 초대 코드를 입력해 다른 사람의 세션에 참가하는 화면으로 이동
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const JoinSessionScreen()));
        },
      ),
      _QuickAction(
        icon: Icons.history_rounded,
        label: '최근 이력',
        // 하단 탭 3번 (내역)으로 전환
        onTap: () => setState(() => _currentTabIndex = 3),
      ),
      _QuickAction(
        // WOW#6 — 식당/메뉴 이상형월드컵 진입점 (2026-05-31).
        // 알림은 AppBar 우측 아이콘에 이미 있으므로 결정 도우미를 4번째 슬롯으로.
        // WOW#9 — _openTournament 로 교체: pop 복귀 시 트렌딩 자동 갱신.
        icon: Icons.emoji_events_outlined,
        label: '토너먼트',
        onTap: _openTournament,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 92,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
          ),
          itemCount: actions.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) =>
              _buildQuickActionItem(actions[index]),
        );
      },
    );
  }

  // 빠른 실행 버튼 항목 하나 (아이콘 원 + 텍스트 레이블)
  Widget _buildQuickActionItem(_QuickAction action) {
    final primary = Theme.of(context).colorScheme.primary;

    final background = action.emphasized
        ? CustomerColors.primarySurface
        : AppColors.surface;

    return Semantics(
      button: true,
      label: action.label,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: action.emphasized
                ? primary.withAlpha(62)
                : AppColors.divider,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: primary, size: 28),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  action.label,
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: action.emphasized
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── "내 즐겨찾기" 섹션 헤더 (2026-05-15 신규) ────────────
  // 타이틀 + 카운트 칩 + 우측 "전체 보기" 액션.
  // 카운트는 즐겨찾기 1개 이상일 때만 노출(0개면 안내 박스로 충분).
  Widget _buildFavoritesSectionHeader() {
    final count = _myFavorites.length;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: Row(
        children: [
          Text('내 즐겨찾기', style: AppTextStyles.heading3),
          if (count > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.backgroundGrey,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const Spacer(),
          // 1개 이상일 때만 "전체 보기" 노출 — 0개일 때 의미 없음.
          if (count > 0)
            TextButton(
              onPressed: _openFavoritesList,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '전체 보기',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.iconInactive,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 즐겨찾기 가로 스크롤 위젯 ─────────────────────────────
  // 상태:
  //   - 로딩 : 80픽셀 회색 박스 1줄로 placeholder
  //   - 빈   : 안내 박스 ("자주 가는 식당의 하트를 눌러보세요")
  //   - 정상 : 가로 스크롤 카드 (이미지 + 이름 + 카테고리)
  // 카드 폭은 추천 식당 카드보다 작게(140) — 위/아래 시각 위계 정리.
  Widget _buildFavoritesList() {
    // 로딩: 가로 가는 회색 박스로 placeholder (스피너보다 페이지 점프 적음)
    if (_isFavoritesLoading) {
      return SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, _) => Container(
            width: 140,
            decoration: BoxDecoration(
              color: AppColors.backgroundGrey,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
          ),
        ),
      );
    }

    // 빈 상태: 즐겨찾기 학습 유도 박스 + "둘러보기" CTA
    if (_myFavorites.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md + 2,
          ),
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.favorite_outline_rounded,
                size: 28,
                color: AppColors.iconInactive,
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '자주 가는 식당을 즐겨찾기 해보세요',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '식당 상세에서 하트를 누르면 여기에 모여요',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 정상: 가로 스크롤 카드 리스트
    // 최대 10개만 — 그 이상은 "전체 보기" 진입으로 유도.
    final preview = _myFavorites.length > 10
        ? _myFavorites.sublist(0, 10)
        : _myFavorites;
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        itemCount: preview.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, index) => _buildFavoriteCard(preview[index]),
      ),
    );
  }

  // ── 즐겨찾기 카드 한 장 (홈 미리보기) ─────────────────────
  // 작은 가로 카드 — 이미지(48) + 이름 + 카테고리.
  // 탭 시 식당 상세로 이동, 복귀 시 즐겨찾기 다시 조회(하트 해제 반영).
  Widget _buildFavoriteCard(FavoriteDto fav) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RestaurantDetailScreen(
              restaurantId: fav.id,
              initialName: fav.name,
            ),
          ),
        );
        if (!mounted) return;
        // 하트 해제 후 복귀했을 수 있어 갱신.
        _loadMyFavorites();
      },
      child: SizedBox(
        width: 160,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: FoodImage(
                // 2026-05-15 자율 E2E 회귀 fix: categoryLabel required 누락 → analyze error.
                // FavoriteDto.category 를 그대로 전달. 이미지 없으면 이 라벨 기반 fallback.
                imageUrl: fav.imageUrl,
                categoryLabel: fav.category,
                width: 48,
                height: 48,
                emojiSize: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    fav.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fav.category,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 이번 주 토너먼트 트렌딩 섹션 (WOW#9) ────────────────
  //
  // 동작:
  //   - 로딩 중 / 데이터 0개 → SizedBox.shrink() 로 섹션 자체 숨김.
  //     (홈에 새 빈 영역이 영구히 보이는 것을 방지 — 도메인 데이터가
  //      쌓이기 전까지는 사용자에게 없는 섹션처럼 보이는 게 자연스러움)
  //   - 1개 이상 → 섹션 헤더 + 가로 스크롤 카드 5개.
  //
  // 카드 정책:
  //   - _buildFavoriteCard 와 동일한 가로 카드 형태(이미지 64 + 본문).
  //   - 우측 상단에 "🏆 N회" 칩으로 우승 횟수를 표시 → 트렌딩의 핵심 시그널.
  //   - 탭 시 식당 상세로 이동.
  Widget _buildTrendingSection() {
    // 로딩 중에는 노출 자체를 보류 — 빈 placeholder 가 깜빡이며 사라지면
    // 페이지 점프가 생겨 즐겨찾기/AI 추천 위치가 흔들리는 UX 가 발생.
    // 첫 로드는 대부분 빠르므로 잠깐의 미노출이 시각적으로 더 깔끔.
    if (_isTrendingLoading) return const SizedBox.shrink();
    if (_trendingRestaurants.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),

        // ── 섹션 헤더 ─────────────────────────────────
        // "이번 주 토너먼트 인기 식당" + 개수 칩.
        // 즐겨찾기 헤더와 패턴 통일 → 시각 일관성.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 4),
              Text('이번 주 토너먼트 인기 식당', style: AppTextStyles.heading3),
              const SizedBox(width: AppSpacing.sm),
              // 개수 칩 — 즐겨찾기 헤더와 같은 톤(backgroundGrey + caption).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.backgroundGrey,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_trendingRestaurants.length}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),

        // ── 부제(기준 설명) ───────────────────────────
        // "AI 추천 기준이 불명" 회귀 방지 — 트렌딩의 기준도 명확히 표기.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Text(
            '최근 7일 동안 토너먼트에서 가장 많이 우승한 식당',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── 가로 스크롤 카드 리스트 ───────────────────
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            itemCount: _trendingRestaurants.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, index) =>
                _buildTrendingCard(_trendingRestaurants[index]),
          ),
        ),
      ],
    );
  }

  // ── 트렌딩 카드 한 장 (홈 가로 스크롤용) ────────────────
  // - 좌측 이미지 64 + 우측 본문(이름, 카테고리, 우승 횟수 칩).
  // - 탭 시 식당 상세로 이동.
  // - 카드 폭은 즐겨찾기 카드와 동일(160) — 시각 통일.
  Widget _buildTrendingCard(TrendingRestaurantDto item) {
    final primary = Theme.of(context).colorScheme.primary;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RestaurantDetailScreen(
              restaurantId: item.restaurantId,
              initialName: item.name,
            ),
          ),
        );
        if (!mounted) return;
        // 식당 상세에서 별점/즐겨찾기 변경이 있을 수 있으니 전반 갱신.
        // 트렌딩 빈도 자체는 거의 안 바뀌지만 새로고침 비용은 무시 가능.
        _loadTrendingRestaurants();
      },
      child: SizedBox(
        width: 180,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: FoodImage(
                // category 가 null 이어도 FoodImage 가 안전하게 폴백 처리.
                imageUrl: item.imageUrl,
                categoryLabel: item.category ?? '식당',
                width: 48,
                height: 48,
                emojiSize: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  // 우승 횟수 칩 — 트렌딩의 핵심 시그널.
                  // 카테고리도 같이 보여주되, 횟수가 더 눈에 띄도록 칩으로.
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: primary.withAlpha(30),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '🏆 ${item.winCount}회',
                          style: AppTextStyles.caption.copyWith(
                            color: primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (item.category != null &&
                          item.category!.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            item.category!,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
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

  // ── 저장된 식당 섹션 전용 헤더 ──────────────────────────
  // 타이틀(heading3) + 그 아래 작은 기준 안내 칩.
  // 사장님 피드백(2026-05-13) 반영: "AI 추천 기준이 뭔지 모르겠다" 해소.
  // 칩은 backgroundGrey + 작은 caption 으로, 디자인 토큰 추가 없음.
  Widget _buildRecommendationSectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                _userLat == null ? '식당 둘러보기' : '주변 식당',
                style: AppTextStyles.heading3,
              ),
              // 기준 안내 칩 — 작고 부드러운 회색 톤.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.backgroundGrey,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 11,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _userLat == null ? '위치 미사용 · 저장된 식당' : '1km 내 저장된 식당',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 내가 이 세션의 호스트인지 판정 ───────────────────────
  // 호스트면 더보기 메뉴를 노출(삭제 불가 상태여도 안내용으로 표시).
  // 사장님 피드백(2026-05-14) 반영: 메뉴 자체가 안 보여 "왜 어떤 건 삭제 가능
  // 어떤 건 안 되나" 혼란이 컸음. 메뉴는 항상 보이고, 비활성/안내로 분기.
  bool _isSessionHost(Session session) {
    final myUserId = ref.read(userProvider).userId;
    if (myUserId == null) return false;
    final hostId = session.createdBy?.id;
    return hostId != null && hostId == myUserId;
  }

  // ── 세션 삭제 가능 여부 판정 ────────────────────────────
  // 백엔드 정책과 일치:
  //   - 본인이 호스트 (createdBy.id == 내 userId)
  //   - 상태가 WAITING 또는 DONE (VOTING/ORDERED 는 다른 멤버 영향)
  //
  // UI 단에서는 메뉴를 숨기지 않고, 비활성 + 안내 다이얼로그로 노출.
  bool _canDeleteSession(Session session) {
    if (!_isSessionHost(session)) return false;
    return session.status == 'WAITING' || session.status == 'DONE';
  }

  // ── 삭제 불가 안내 다이얼로그 ───────────────────────────
  // VOTING/ORDERED 처럼 진행 중인 세션을 호스트가 삭제 시도할 때 노출.
  // 사장님 피드백: "왜 어떤 건 안 되는지" 가 핵심. 사유와 다음 액션을 함께 안내.
  Future<void> _showDeleteBlockedDialog(Session session) async {
    // 한국어 상태 라벨 — 사용자에게 더 친근.
    final statusKor = switch (session.status) {
      'VOTING' => '투표 중',
      'ORDERED' => '주문이 진행 중',
      _ => '진행 중',
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('지금은 삭제할 수 없어요', style: AppTextStyles.heading3),
        content: Text(
          '"${session.name}"은(는) $statusKor 인 세션이라\n'
          '안전을 위해 삭제가 막혀 있어요.\n\n'
          '세션 종료 후 다시 시도해봐요.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('알겠어요'),
          ),
        ],
      ),
    );
  }

  // ── 세션 삭제 흐름 ──────────────────────────────────────
  // 1) 확인 다이얼로그 (친근 톤) — 멤버 영향을 명시
  // 2) 사용자가 "삭제하기" 선택 시 백엔드 호출
  // 3) 성공: 목록 새로고침 + 스낵바 안내
  //    실패: SessionDeleteResult.message 그대로 스낵바 노출 (재로그인/방장만/진행 중 등)
  Future<void> _confirmAndDeleteSession(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('세션을 삭제할까요?', style: AppTextStyles.heading3),
        content: Text(
          // 본문 — 친근하지만 "되돌릴 수 없다" 명시
          '"${session.name}"을(를) 삭제하면\n'
          '멤버들이 더 이상 참여할 수 없어요.\n'
          '이 작업은 되돌릴 수 없어요.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('로그인이 풀렸어요. 다시 로그인해봐요')));
      }
      return;
    }

    final result = await const SessionsApiService().deleteSession(
      accessToken: token,
      sessionId: session.id,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      // 성공 — 친근한 완료 안내 + 목록 새로고침
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${session.name}" 세션을 삭제했어요')));
      // 화면 상의 세션 카드가 사라지도록 즉시 목록 재조회
      await _loadTodaySessions();
    } else {
      // 실패 — 백엔드/네트워크에서 받은 한국어 메시지 그대로 노출
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '세션을 삭제하지 못했어요')),
      );
    }
  }

  // ── 오늘의 세션 카드 위젯 ──────────────────────────────────
  // 상태별 표시:
  //   ① 로딩 중        → 스피너 카드
  //   ② 세션 없음      → "점심 만들기" CTA 유도 카드
  //   ③ 세션 존재      → 첫 번째 세션 정보 카드 + 입장 버튼
  Widget _buildTodaySession() {
    // ① 로딩 상태
    if (_isSessionsLoading) {
      return const AppHighlightCard(
        child: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final loadError = _sessionsLoadError;
    if (loadError != null) {
      return HomeTodaySessionsErrorCard(
        message: loadError,
        onRetry: _loadTodaySessions,
      );
    }

    final sessions = _todaySessions ?? const <Session>[];

    // ② 오늘 세션 없음 → 만들기 유도 카드
    if (sessions.isEmpty) {
      return AppHighlightCard(
        onTap: _goToMemberSelect,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // 빈 상태 카피 — 친근한 인사로 다음 행동 자연 유도 (Toss/카카오뱅크 톤)
              '오늘 점심 뭐 드실래요?',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              // 다음 액션 안내 — "함께"라는 단어로 협업 느낌 강조
              '동료를 초대해 점심을 함께 정해봐요',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            AppPrimaryButton(
              label: '점심 만들기',
              height: 44,
              onPressed: _goToMemberSelect,
            ),
          ],
        ),
      );
    }

    // ③ 실제 세션 렌더링 — 첫 번째 세션을 메인으로 노출
    final session = sessions.first;
    // statusLabel이 있으면 한글 레이블 우선, 없으면 내부 enum 문자열
    final statusText = session.statusLabel ?? session.status;
    // scheduledAt은 ISO 8601 문자열 → 시:분만 추출. null이면 '시간 미정'
    final scheduledText = _formatScheduledTime(session.scheduledAt);
    // memberCount는 목록 응답에서만 제공. 없으면 "- 명"
    final memberText = session.memberCount != null
        ? '${session.memberCount}명 참여'
        : '참여 인원 확인 중';

    return AppHighlightCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionLobbyScreen(
              sessionId: session.id,
              initialSession: session, // 재조회 실패 회피 — sessions/today 응답 그대로 사용
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 세션 상태 배지 + 세션 이름 + (호스트 한정) 삭제 메뉴 ──
          Row(
            children: [
              // 공통 AppBadge 컴포넌트 — 상태별 tone 자동 적용
              AppBadge(
                label: statusText,
                tone: _toneForSessionStatus(session.status),
                filled: true,
              ),

              const SizedBox(width: AppSpacing.sm),

              // 세션 이름
              Expanded(
                child: Text(
                  session.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 호스트면 항상 더보기 메뉴 노출 — 진행 중이면 비활성+안내로 표시.
              // 사장님 피드백(2026-05-14): "어떤 건 메뉴가 보이고 어떤 건
              // 안 보여 헷갈렸다" 해소. 메뉴 자체는 일관적으로 노출.
              if (_isSessionHost(session)) _buildSessionMoreMenu(session),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── 세션 상세 정보 ───────────────────────────
          Row(
            children: [
              _buildSessionInfoItem(Icons.people_rounded, memberText),
              const SizedBox(width: AppSpacing.md),
              _buildSessionInfoItem(Icons.access_time_rounded, scheduledText),
            ],
          ),

          const SizedBox(height: AppSpacing.sm + 4),

          // ── "세션 입장하기" 버튼 ─────────────────────
          AppPrimaryButton(
            label: '세션 입장하기',
            height: 44,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionLobbyScreen(
                    sessionId: session.id,
                    initialSession:
                        session, // 재조회 실패 회피 — sessions/today 응답 그대로 사용
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── scheduledAt ISO 문자열 → "오후 12:00" 형태 포맷 ───────
  // 백엔드가 null을 줄 수도 있어서 안전하게 처리.
  String _formatScheduledTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '시간 미정';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return '시간 미정';
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    // 12시간제 + 오전/오후 표기 (한국식)
    final isAfternoon = hour >= 12;
    final display12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '${isAfternoon ? "오후" : "오전"} $display12:$minute';
  }

  // 세션 상태 → AppBadge 톤 매핑 (디자인 일관성)
  AppBadgeTone _toneForSessionStatus(String status) {
    switch (status) {
      case 'WAITING':
        return AppBadgeTone.warning;
      case 'VOTING':
        return AppBadgeTone.primary;
      case 'ORDERED':
        return AppBadgeTone.success;
      case 'DONE':
        return AppBadgeTone.neutral;
      default:
        return AppBadgeTone.primary;
    }
  }

  // ── 세션 카드용 "더보기" 메뉴 위젯 ──────────────────────
  // 호스트면 항상 노출. 삭제 가능 여부는 PopupMenuItem 단에서 enabled 분기로
  // 시각적으로 비활성(회색) 처리 + 탭 시 사유 안내 다이얼로그.
  // 향후 액션 추가(예: "복사하기", "공유") 시에도 이 위젯에 PopupMenuItem 만 늘리면 됨.
  Widget _buildSessionMoreMenu(Session session) {
    final canDelete = _canDeleteSession(session);
    // 비활성 시 글자색 — 카드 톤과 통일된 회색.
    final itemColor = canDelete ? AppColors.error : AppColors.iconInactive;
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: AppColors.iconInactive,
      ),
      // 메뉴 그림자/모서리 — 앱 카드 라운드 토큰과 통일
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      // 카드 자체 onTap(세션 입장) 과 충돌 방지 — 메뉴 활성화 시 카드 탭 발생 X.
      // PopupMenuButton 은 자체 GestureDetector 가 부모 InkWell 까지 이벤트 전파 막아줌.
      tooltip: '세션 메뉴',
      onSelected: (value) async {
        if (value == 'delete') {
          if (canDelete) {
            await _confirmAndDeleteSession(session);
          } else {
            // 삭제 불가 상태에서 탭한 경우 — 사유 안내 다이얼로그.
            await _showDeleteBlockedDialog(session);
          }
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          value: 'delete',
          // enabled 를 false 로 두면 onSelected 가 호출되지 않아 안내 다이얼로그를
          // 띄울 수 없음 → 의도적으로 true 유지하고 색상만 비활성처럼 표현.
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: itemColor),
              const SizedBox(width: 8),
              // 삭제 가능 여부와 무관하게 동일 카피 — 단, 비활성 색상으로 구분.
              // 탭 시점에 onSelected 에서 사유 안내 다이얼로그가 뜨므로,
              // "왜 안 되는지" 가 한 번의 액션으로 즉시 노출됨.
              Text(
                '세션 삭제',
                style: AppTextStyles.bodyMedium.copyWith(color: itemColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 세션 정보 항목 하나 (아이콘 + 텍스트 조합)
  Widget _buildSessionInfoItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min, // Row가 내용물 크기만큼만 차지
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: AppTextStyles.bodySmall),
      ],
    );
  }

  // 카카오의 위치 기반 장소 결과는 매장 등록이나 메뉴 정보로 취급하지 않는다.
  Widget _buildNearbyPlacesSection() {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.explore_outlined, color: primary, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('주변 장소 둘러보기', style: AppTextStyles.heading3),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '카카오 장소 정보 · 메뉴·가격은 매장 확인',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_hasLocationPermission == null || _isDiscoveryLoading)
          _buildDiscoveryMessage(
            icon: Icons.location_searching_rounded,
            title: '주변 장소를 찾고 있어요',
            detail: '현재 위치에서 1km 안의 카카오 장소를 확인합니다.',
            loading: true,
          )
        else if (_hasLocationPermission == false)
          _buildDiscoveryMessage(
            icon: Icons.location_off_outlined,
            title: '위치 권한이 필요해요',
            detail: '위치 권한이나 기기 위치 서비스를 켠 뒤 다시 시도해 주세요.',
            retry: true,
          )
        else if (_discoveryError != null)
          _buildDiscoveryMessage(
            icon: Icons.wifi_off_rounded,
            title: _discoveryError!,
            detail: '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
            retry: true,
          )
        else if (_nearbyPlaces.isEmpty)
          _buildDiscoveryMessage(
            icon: Icons.map_outlined,
            title: '1km 안에 표시할 장소가 없어요',
            detail: '다른 위치에서 다시 찾아보거나 잠시 후 시도해 주세요.',
            retry: true,
          )
        else
          SizedBox(
            height: 175,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
              ),
              itemCount: _nearbyPlaces.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppSpacing.sm + 4),
              itemBuilder: (_, index) =>
                  _buildNearbyPlaceCard(_nearbyPlaces[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildDiscoveryMessage({
    required IconData icon,
    required String title,
    required String detail,
    bool loading = false,
    bool retry = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 24),
            const SizedBox(width: AppSpacing.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detail,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (retry) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: () {
                        _lastDiscoveryAt = null;
                        _startNearbyDiscovery();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('다시 찾기'),
                    ),
                  ],
                ],
              ),
            ),
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyPlaceCard(NearbyPlaceDto place) {
    final kakaoUri = Uri.tryParse(place.kakaoUrl);
    // Kakao Local can return an http detail URL; open the same host over HTTPS.
    final uri = kakaoUri?.scheme == 'http'
        ? kakaoUri!.replace(scheme: 'https')
        : kakaoUri;
    final isKakaoUrl =
        uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'place.map.kakao.com' || uri.host == 'map.kakao.com');
    final distance = place.distanceMeters < 1000
        ? '${place.distanceMeters}m'
        : '${(place.distanceMeters / 1000).toStringAsFixed(1)}km';
    return Container(
      width: 274,
      padding: const EdgeInsets.all(AppSpacing.md),
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
              Expanded(
                child: Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                distance,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            place.address.isEmpty ? '주소 정보 없음' : place.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '카카오 장소 정보',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: isKakaoUrl ? () => _openKakaoPlace(uri) : null,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('카카오 상세 보기'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              side: const BorderSide(color: AppColors.border),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openKakaoPlace(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // The same non-sensitive, actionable message is shown for plugin failures.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('카카오 상세 화면을 열지 못했어요. 다시 시도해 주세요.')),
    );
  }

  // ── 등록 식당 가로 스크롤 목록 위젯 ──────────────────────
  // 식당 카드를 가로로 스크롤하며 볼 수 있는 리스트
  // 상태별 표시: 로딩(스켈레톤 카드) / 빈 상태(친절한 안내) / 리스트
  Widget _buildRestaurantList() {
    // 로딩 중 — 스켈레톤 카드 3개로 실제 카드 모양 미리 보여줌
    // 단순 스피너보다 페이지 점프가 적어 UX 부드러움.
    if (_isRestaurantsLoading) {
      return SizedBox(
        // 2026-05-30 회귀 fix: 카드 콘텐츠가 5px overflow 되어 노란 줄무늬
        // 경고가 노출됨. 안전 마진 포함 184로 통일.
        height: 184,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm + 4),
          // 회색 박스 스켈레톤 카드 — 데이터 로드 완료 시 실제 카드로 자동 교체.
          // 위젯 정의는 lib/core/widgets/skeleton_card.dart (재사용 위해 분리).
          itemBuilder: (_, _) => const RestaurantSkeletonCard(),
        ),
      );
    }

    final restaurants = _recommendedRestaurants ?? const <RestaurantDto>[];

    // 등록 식당이 없는 상태는 장소 탐색 결과와 구분한다.
    //   (b) 권한 거부 : "위치 권한을 켜주세요" + 설정/재시도 버튼
    //   (c) 미확인    : 권한 평가 전 → "잠시만요" 정도의 중립 카피
    // 카드 구조/색상 토큰은 동일. 카피와 보조 위젯(스피너/설정버튼)만 분기.
    if (restaurants.isEmpty) {
      final hasPerm = _hasLocationPermission;
      // 분기별 화면 데이터 — 한 카드 안에서 자연스럽게 바뀜.
      final IconData icon;
      final String title;
      final String subtitle;
      final bool showSpinner; // 권한 OK 일 때만 스피너 노출
      final bool showRetry; // 권한 거부 시 강조 버튼 1개로 단순화
      if (hasPerm == true) {
        icon = Icons.storefront_outlined;
        title = '저장된 주변 식당이 없어요';
        subtitle = '아래 카카오 장소 정보에서 주변 매장을 둘러볼 수 있어요.';
        showSpinner = false;
        showRetry = true;
      } else if (hasPerm == false) {
        icon = Icons.location_off_rounded;
        title = '위치 권한이 필요해요';
        subtitle = '근처 등록 식당을 보려면 위치 권한을 켜주세요.';
        showSpinner = false;
        showRetry = true;
      } else {
        icon = Icons.location_searching_rounded;
        title = '잠시만요, 준비 중이에요';
        subtitle = '위치 정보를 확인하고 있어요';
        showSpinner = true;
        showRetry = true;
      }
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 40, color: AppColors.iconInactive),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              // 권한 OK 일 때만 진행 중 스피너 표시 — 시각적으로 "지금 일하는 중" 신호.
              if (showSpinner) ...[
                const SizedBox(height: AppSpacing.sm + 4),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              if (showRetry) ...[
                const SizedBox(height: AppSpacing.sm + 4),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _isRestaurantsLoading = true);
                    _lastDiscoveryAt = null;
                    _startNearbyDiscovery();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('다시 시도'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      // 2026-05-30 회귀 fix: AI 추천 카드 콘텐츠 5px overflow.
      // 스켈레톤과 동일하게 184 로 통일 (rating 칩 추가로 1줄 늘어난 영향).
      height: 184,
      child: ListView.separated(
        // scrollDirection.horizontal: 가로 방향으로 스크롤
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
        ),
        itemCount: restaurants.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.sm + 4),
        itemBuilder: (context, index) {
          return _buildRestaurantCard(restaurants[index]);
        },
      ),
    );
  }

  // 식당 카드 스켈레톤은 lib/core/widgets/skeleton_card.dart 의
  // RestaurantSkeletonCard 로 분리 — 추천 리스트 등 다른 화면에서도 재사용 예정.

  // 식당 카드 위젯 하나 (이름 / 카테고리 / 가격 / 거리)
  // RestaurantDto는 priceRange(int) / address / lat / lng를 제공.
  // 거리(distance)는 사용자 위치(_userLat/_userLng) 가 있을 때만 한 줄 추가.
  // rating, 리뷰 수는 백엔드에 아직 없어서 카드 레이아웃 간소화.
  Widget _buildRestaurantCard(RestaurantDto restaurant) {
    // 가격 레이블은 공통 헬퍼로 통일.
    // price_range 값이 시드/크롤/Gemini 출처별로 의미가 달라
    // ("5500원" vs "13" vs "2") 단순 출력 시 "13원~", "2원~" 같은
    // 부자연스러운 문구가 보여 정규화 헬퍼로 통일했음.
    final priceLabel = formatRestaurantPriceRange(restaurant.priceRange);

    // 거리 라벨 — 사용자 위치/식당 좌표 둘 중 하나라도 없으면 null.
    // null이면 거리 줄을 그리지 않음(디자인 유지: 새 줄을 "추가" 만 함).
    final distance = distanceLabel(
      userLat: _userLat,
      userLng: _userLng,
      targetLat: restaurant.lat,
      targetLng: restaurant.lng,
    );

    // 2026-05-31 WOW#1: 사장님 "오늘의 한 줄" 노란 띠.
    //   todaysNote 가 있을 때만 카드 상단(이미지 위)에 표시.
    //   배경 #FFF3CD + 👨‍🍳 이모지 + 메시지 한 줄(ellipsis).
    //   카드 폭이 150px 이라 길이가 길면 자동으로 잘림 — 손님은 상세 진입 후 전체 확인.
    final todaysNote = restaurant.todaysNote;

    return AppCard(
      // 식당 카드 탭 → CU-13 식당 상세 화면으로 이동
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RestaurantDetailScreen(
              restaurantId: restaurant.id,
              initialName: restaurant.name,
            ),
          ),
        );
      },
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 사장님 한 줄 (있을 때만) ────────────────────
            if (todaysNote != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  // 디자인 명세: #FFF3CD 배경 + 살짝 어두운 노란 테두리.
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 👨‍🍳 이모지 — 의미를 시각적으로 즉시 전달.
                    const Text(
                      '👨‍🍳',
                      style: TextStyle(fontSize: 11, height: 1.1),
                    ),
                    const SizedBox(width: 3),
                    // 인용구 — 가로 카드 폭 좁아 1줄로만 노출, 넘치면 ellipsis.
                    Expanded(
                      child: Text(
                        todaysNote,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],

            // 등록 사진이 있으면 표시하고, 없거나 로드에 실패하면 음식 아이콘으로 대체.
            FoodImage(
              imageUrl: restaurant.imageUrl,
              categoryLabel: restaurant.category,
              width: 150,
              height: 72,
              emojiSize: 30,
              borderRadius: BorderRadius.circular(AppRadius.small),
              semanticLabel: '${restaurant.name} 사진',
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── 식당 이름 ────────────────────────────────
            Text(
              restaurant.name,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 2),

            // ── 카테고리 ─────────────────────────────────
            Text(
              restaurant.category ?? '카테고리 미정',
              style: AppTextStyles.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),

            const Spacer(),

            // ── 가격대 ───────────────────────────────────
            Text(
              priceLabel,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),

            // ── 거리(distance) ───────────────────────────
            // 사용자 위치/식당 좌표 둘 다 있을 때만 한 줄 추가.
            // 디자인 토큰 변경 없이 caption + textSecondary 색만 사용.
            if (distance != null) ...[
              const SizedBox(height: 2),
              Text(
                distance,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 가격대 표기는 normalizer.dart 의 formatRestaurantPriceRange 로 통일.
  // 홈 카드에서 천단위 콤마 포맷은 더 이상 사용하지 않아 제거했음.

  // ── 하단 탭바 위젯 ──────────────────────────────────────────
  // 손님앱 주요 5개 섹션 탭 (홈 / 점심세션 / 주문현황 / 내역 / 내정보)
  Widget _buildBottomNav() {
    // 탭 항목 데이터 목록
    // 순서 = 탭 인덱스 (0~4). _currentTabIndex와 순서가 반드시 일치해야 함
    final tabs = [
      _NavTab(icon: Icons.home_rounded, label: '홈'),
      _NavTab(icon: Icons.restaurant_menu_rounded, label: '점심세션'),
      _NavTab(icon: Icons.receipt_long_rounded, label: '주문현황'),
      _NavTab(icon: Icons.history_rounded, label: '내역'),
      _NavTab(icon: Icons.person_rounded, label: '내정보'),
    ];

    return BottomNavigationBar(
      currentIndex: _currentTabIndex,
      // onTap: 탭을 누르면 해당 인덱스로 상태 업데이트 → IndexedStack이 화면 전환
      onTap: (index) => setState(() => _currentTabIndex = index),

      // type.fixed: 탭이 5개이므로 fixed 타입 사용 (shifting 타입은 선택 시 레이블 표시)
      type: BottomNavigationBarType.fixed,

      // 선택/비선택 색상: 테마의 primary 색과 비활성 색으로 자동 구분
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: AppColors.iconInactive,

      // 선택된 탭의 레이블 크기: 강조하지 않고 동일하게 유지
      selectedFontSize: 11,
      unselectedFontSize: 11,

      // 배경색 + 상단 구분선
      backgroundColor: AppColors.surface,

      items: tabs.map((tab) {
        return BottomNavigationBarItem(icon: Icon(tab.icon), label: tab.label);
      }).toList(),
    );
  }

  // ── 1번 탭: 점심세션 ───────────────────────────────────
  // 오늘 참여 중인 세션 목록 + 만들기/참가 액션을 한 화면에 노출.
  // 폴링은 하지 않음 — 사용자가 탭 진입할 때마다 _loadTodaySessions() 결과 활용.
  Widget _buildSessionsTab() {
    final primary = Theme.of(context).colorScheme.primary;
    final sessions = _todaySessions ?? const <Session>[];
    final loadError = _sessionsLoadError;

    return RefreshIndicator(
      onRefresh: _loadTodaySessions,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        children: [
          // 헤더
          Text('점심 세션', style: AppTextStyles.heading2),
          const SizedBox(height: 4),
          Text(
            loadError != null
                ? '세션 목록을 확인하지 못했어요. 다시 시도해 주세요'
                : sessions.isEmpty
                // 빈 상태 — 두 가지 다음 액션(만들기/참가)을 자연스럽게 안내
                ? '아직 비어있어요. 새로 만들거나 초대 코드로 참가해봐요'
                : '오늘 ${sessions.length}개 세션에 참여 중',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // 액션 버튼 2종 (만들기 / 코드로 참가)
          Row(
            children: [
              if (_canCreateSession) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _goToMemberSelect,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('점심 만들기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const JoinSessionScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: const Text('코드로 참가'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),
          Text('오늘의 세션', style: AppTextStyles.heading3),
          const SizedBox(height: AppSpacing.sm),

          // 세션 카드 리스트 (없으면 빈 상태 안내)
          if (_isSessionsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (loadError != null)
            HomeTodaySessionsErrorCard(
              message: loadError,
              onRetry: _loadTodaySessions,
            )
          else if (sessions.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.restaurant_menu_rounded,
                    size: 36,
                    color: AppColors.iconInactive,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    // 빈 상태 — 위의 액션 버튼(만들기/코드로 참가)을 자연 연결
                    '오늘 점심, 위 버튼으로 시작해봐요',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            ...sessions.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SessionLobbyScreen(
                          sessionId: s.id,
                          initialSession: s, // 재조회 실패 회피
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Icon(
                        Icons.lunch_dining_rounded,
                        color: primary,
                        size: 28,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${s.statusLabel ?? s.status} · '
                              '${_formatScheduledTime(s.scheduledAt)}',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 호스트면 항상 더보기 메뉴(삭제 불가 상태는 비활성+안내),
                      // 호스트가 아니면 기존 chevron 표시. 색상 토큰 동일.
                      if (_isSessionHost(s))
                        _buildSessionMoreMenu(s)
                      else
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.iconInactive,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 내부 데이터 모델 클래스들 (이 파일 안에서만 사용하는 Mock 구조체)
//
// 왜 별도 파일이 아닌 여기에 정의하나?
//   이 클래스들은 오직 이 화면의 Mock 데이터 표현 용도로만 쓰임.
//   API 연동 후에는 서버 응답 DTO(Data Transfer Object)로 교체되므로
//   별도 파일을 만들어 관리할 필요가 없음.
// ══════════════════════════════════════════════════════════

// 빠른 실행 CTA 버튼 하나의 데이터
class _QuickAction {
  const _QuickAction({
    required this.icon, // 버튼 아이콘
    required this.label, // 버튼 레이블 텍스트
    required this.onTap, // 탭 시 실행할 함수
    this.emphasized = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;
}

// 하단 탭바 항목 하나의 데이터
class _NavTab {
  const _NavTab({
    required this.icon, // 탭 아이콘
    required this.label, // 탭 레이블
  });
  final IconData icon;
  final String label;
}
