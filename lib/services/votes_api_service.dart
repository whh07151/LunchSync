import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../core/api/api_auth_hooks.dart';
import '../core/api/error_message_extractor.dart';
import '../core/api/http_headers_helper.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 투표(CU-14/15) 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   POST /api/sessions/:id/votes   — 한 표 던지기 (1인 1표, UNIQUE 위반 시 409)
//   GET  /api/sessions/:id/votes   — 세션 투표 현황 raw 리스트
//   POST /api/sessions/:id/decide  — 호스트가 결과 확정 (→ status ORDERED)
//
// 백엔드 응답 형태(2026-05-14 votes.controller/service.ts 기준):
//   POST /votes  → { success, data: { id, userId, sessionId, restaurantId, createdAt } }
//   GET  /votes  → { success, data: [{ id, userId, restaurantId, restaurantName, createdAt }] }
//                  ※ "raw 투표 row 배열" 만 내려옴. 진행도/퍼센티지는 프론트 집계.
//   POST /decide → { success, data: { winnerId, winnerName, voteCount, totalVotes,
//                                     tally:[{ restaurantId, restaurantName, count }] } }
//
// 프론트 변환 정책:
//   - 백엔드는 isFinished/totalMembers/votedCount 를 직접 내려주지 않으므로
//     본 서비스에서 GET /votes raw 데이터 + (선택) totalMembers 인자를 받아
//     VotesProgressDto 로 합산·정렬·퍼센티지화한다.
//   - totalMembers 는 호출부가 SessionsApiService.getSessionMembers().joinedCount
//     로 별도 조회해 넘긴다. 미지정 시 votedCount==results 합산 결과만 의미 있음.
//
// 친근 톤·디자인 토큰 변경 없음. 색상/배경은 화면 레이어 책임.
// ══════════════════════════════════════════════════════════

/// 한 식당의 집계 결과 (가로 바 차트 한 줄)
///
/// percentage 는 0~100 정수. 분모는 "전체 투표 수"(votedCount) — 동률 가시화용.
/// 미투표자 비율을 노출하고 싶으면 totalMembers 분모를 별도로 계산해 표시.
class VoteResultItem {
  const VoteResultItem({
    required this.restaurantId,
    required this.restaurantName,
    required this.voteCount,
    required this.percentage,
  });

  final String restaurantId;
  final String restaurantName;
  final int voteCount;
  final int percentage; // 0~100, votedCount 분모 기준
}

/// 우승 식당 정보 (isFinished=true 시 채워짐)
///
/// 백엔드 sessions.winner_restaurant_id 가 채워진 ORDERED 상태에서만 의미 있음.
/// 본 SDK 는 GET /votes 만으로는 winner 를 알 수 없어 별도 SessionsApiService
/// 의 session.winnerRestaurantId 와 함께 사용한다. (decide() 결과를 캐싱해도 됨)
class WinnerInfo {
  const WinnerInfo({
    required this.restaurantId,
    required this.restaurantName,
    required this.voteCount,
  });

  final String restaurantId;
  final String restaurantName;
  final int voteCount;
}

/// 투표 진행 상황 통합 DTO
///
/// 화면(vote_progress_screen)이 폴링으로 받아 즉시 그릴 수 있는 형태로 가공.
/// - results 는 voteCount 내림차순.
/// - isFinished 는 호출부가 session.status=='ORDERED' 여부로 판단한 결과를 넣음.
class VotesProgressDto {
  const VotesProgressDto({
    required this.isFinished,
    required this.totalMembers,
    required this.votedCount,
    required this.results,
    required this.votedUserIds,
    this.winner,
  });

  final bool isFinished;     // true 면 우승 식당으로 라우팅
  final int totalMembers;    // 분모 — 미지정 시 0
  final int votedCount;      // 지금까지 던진 표 총합 (1인 1표라 곧 투표 완료자 수)
  final List<VoteResultItem> results;
  final WinnerInfo? winner;  // 우승 — 결정 후에만
  // Phase D: 멤버별 투표 ✓/대기 가시화용 — raw votes 의 userId 집합.
  // vote_progress_screen 에서 멤버 목록(SessionsApi.getSessionMembers)과
  // 교차 매칭해 "누가 투표했고 누가 대기 중인지" 표시.
  final Set<String> votedUserIds;
}

/// POST /decide 응답 (CU-15 결과 확정 직후 호스트 화면에서 사용)
class DecideResultDto {
  const DecideResultDto({
    required this.winnerRestaurantId,
    required this.winnerName,
    required this.voteCount,
    required this.totalVotes,
  });

  final String winnerRestaurantId;
  final String winnerName;
  final int voteCount;   // 우승 식당이 받은 표 수
  final int totalVotes;  // 전체 던진 표 수
}

/// POST /votes 결과 래퍼
///
/// - isSuccess=true: 정상 등록(200/201)
/// - alreadyVoted=true: 백엔드가 409 ConflictException 반환 (1인 1표)
/// - 그 외: 네트워크/서버 에러 → 두 플래그 모두 false
class CastVoteResult {
  const CastVoteResult({
    required this.isSuccess,
    required this.alreadyVoted,
    this.message,
  });

  const CastVoteResult.success()
      : isSuccess = true,
        alreadyVoted = false,
        message = null;

  const CastVoteResult.duplicate()
      : isSuccess = false,
        alreadyVoted = true,
        message = '이미 투표했어요. 결과 화면에서 진행 상황을 확인해봐요';

  const CastVoteResult.failure(this.message)
      : isSuccess = false,
        alreadyVoted = false;

  final bool isSuccess;
  final bool alreadyVoted;
  final String? message;
}

class VotesApiService {
  const VotesApiService();

  // 2026-05-30 헤더 빌더 통합: 공통 헬퍼 apiHeaders() 로 이관
  //   (lib/core/api/http_headers_helper.dart). 9개 서비스 중복 제거.

  // ── POST /api/sessions/:id/votes ───────────────────────
  // body: { restaurantId } — 백엔드 CastVoteDto 와 일치.
  // sessionId 는 URL path 로만 전달 (백엔드는 body 의 sessionId 를 받지 않음).
  //
  // 응답 분기:
  //   200/201 → CastVoteResult.success()
  //   409     → CastVoteResult.duplicate() — 1인 1표 UNIQUE 위반
  //   401     → ApiAuthHooks 가 글로벌 로그아웃 콜백 호출
  //   기타    → CastVoteResult.failure(친근 메시지)
  Future<CastVoteResult> castVote({
    required String accessToken,
    required String sessionId,
    required String restaurantId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
                '${AppConfig.backendBaseUrl}/sessions/$sessionId/votes'),
            headers: apiHeaders(accessToken),
            body: jsonEncode({'restaurantId': restaurantId}),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return const CastVoteResult.success();
      }
      // 409 Conflict — 백엔드 ConflictException('이미 투표했어요.')
      if (response.statusCode == 409) {
        return const CastVoteResult.duplicate();
      }

      // 그 외 백엔드 message 우선 추출, 실패 시 케이스별 친근 메시지
      String message = '투표가 안 됐어요. 잠시 후 다시 시도해봐요';
      switch (response.statusCode) {
        case 401:
          message = '로그인이 풀렸어요. 다시 로그인해봐요';
          break;
        case 400:
          // VOTING 이 아닌 상태에서 시도 — 호스트가 아직 시작 안 했거나 이미 끝남
          message = '지금은 투표할 수 없어요. 세션 상태를 확인해봐요';
          break;
        case 404:
          message = '세션 또는 식당을 찾지 못했어요';
          break;
      }
      // 백엔드가 더 구체적인 message 를 내려주면 그걸로 덮어씀
      // (공용 헬퍼가 String / List<String> / 빈 문자열을 일괄 처리)
      final backendMsg = extractApiErrorMessage(response.body);
      if (backendMsg != null) {
        message = backendMsg;
      }

      debugPrint(
        '[VotesApiService] castVote 실패: '
        '${response.statusCode} body=${response.body}',
      );
      return CastVoteResult.failure(message);
    } catch (e) {
      debugPrint('[VotesApiService] castVote 예외: $e');
      return const CastVoteResult.failure(
          '서버에 닿지 못했어요. 인터넷 연결을 확인해봐요');
    }
  }

  // ── GET /api/sessions/:id/votes ───────────────────────
  // 백엔드는 raw 투표 row 배열을 내려준다.
  //   data: [{ id, userId, restaurantId, restaurantName, createdAt }, ...]
  //
  // 본 서비스가 식당별로 그룹핑·집계 → VotesProgressDto 로 변환한다.
  //
  // [totalMembers] 는 별도 SessionsApiService.getSessionMembers().joinedCount
  // 로 조회해 넘긴다. 미지정 시 0 — UI 가 "n/?명" 같이 fallback 처리.
  //
  // [isFinished] 는 호출부가 sessions/:id 의 status==ORDERED 여부로 판단해
  // 같이 넘긴다. raw votes 만으로는 끝났는지 판단할 수 없기 때문.
  //
  // [winnerRestaurantId] 가 주어지면 winner 정보(이름+표수) 를 채워준다.
  Future<VotesProgressDto?> getVotes({
    required String accessToken,
    required String sessionId,
    int totalMembers = 0,
    bool isFinished = false,
    String? winnerRestaurantId,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
                '${AppConfig.backendBaseUrl}/sessions/$sessionId/votes'),
            headers: apiHeaders(accessToken),
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode != 200) {
        debugPrint(
          '[VotesApiService] getVotes 실패: '
          '${response.statusCode} body=${response.body}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (json['data'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();

      // 식당별 그룹핑 (Map: restaurantId → { name, count })
      // 식당명은 백엔드 join 으로 함께 내려오나 null 가능 → 안전 처리.
      // Phase D 추가: 투표한 사용자 ID 집합도 함께 수집 → 멤버별 ✓/대기 가시화.
      final grouped = <String, _Bucket>{};
      final votedUserIds = <String>{};
      for (final v in list) {
        final rid = (v['restaurantId'] as String?) ?? '';
        if (rid.isEmpty) continue;
        final rname = (v['restaurantName'] as String?) ?? '';
        final bucket = grouped.putIfAbsent(rid, () => _Bucket(rname));
        bucket.count += 1;
        // 후행 row 가 이름을 더 정확히 가질 수도 있어 빈 값일 때만 업데이트
        if (bucket.name.isEmpty && rname.isNotEmpty) bucket.name = rname;
        // 투표한 사용자 ID 모으기 (Phase D)
        final uid = (v['userId'] as String?) ?? '';
        if (uid.isNotEmpty) votedUserIds.add(uid);
      }

      final votedCount = list.length;
      // 동률 시 안정 정렬 보장 — count 내림차순, 동률이면 name 오름차순
      final entries = grouped.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.count.compareTo(a.value.count);
          if (byCount != 0) return byCount;
          return a.value.name.compareTo(b.value.name);
        });

      final results = entries.map((e) {
        // 퍼센티지는 voted 분모 기준 — 미투표자 비율은 별도 UI 표기.
        final pct = votedCount == 0
            ? 0
            : ((e.value.count * 100) / votedCount).round();
        return VoteResultItem(
          restaurantId: e.key,
          restaurantName: e.value.name,
          voteCount: e.value.count,
          percentage: pct,
        );
      }).toList(growable: false);

      // winner 정보 채우기 — winnerRestaurantId 가 주어진 경우 매칭되는
      // result row 의 이름/표수 를 그대로 사용. 매칭 실패 시 null 유지.
      WinnerInfo? winner;
      if (winnerRestaurantId != null && winnerRestaurantId.isNotEmpty) {
        for (final r in results) {
          if (r.restaurantId == winnerRestaurantId) {
            winner = WinnerInfo(
              restaurantId: r.restaurantId,
              restaurantName: r.restaurantName,
              voteCount: r.voteCount,
            );
            break;
          }
        }
      }

      return VotesProgressDto(
        isFinished: isFinished,
        totalMembers: totalMembers,
        votedCount: votedCount,
        results: results,
        winner: winner,
        votedUserIds: votedUserIds,
      );
    } catch (e) {
      debugPrint('[VotesApiService] getVotes 예외: $e');
      return null;
    }
  }

  // ── POST /api/sessions/:id/decide ─────────────────────
  // 호스트만 호출 가능 (백엔드가 403 으로 차단).
  // 성공 시 sessions.status → ORDERED, winner_restaurant_id 채워짐.
  // 응답: { winnerId, winnerName, voteCount, totalVotes, tally:[...] }
  // [restaurantId] 지정 시 = 룰렛/사다리 즉석 결정 (WAITING 에서도 호스트가 바로 확정).
  // 미지정 시 = 기존 투표 집계 (VOTING + 최소 1표). 2026-05-15 회귀 fix.
  Future<DecideResultDto?> decide({
    required String accessToken,
    required String sessionId,
    String? restaurantId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
                '${AppConfig.backendBaseUrl}/sessions/$sessionId/decide'),
            headers: apiHeaders(accessToken),
            body: restaurantId != null
                ? jsonEncode({'restaurantId': restaurantId})
                : null,
          )
          .timeout(AppConfig.apiTimeout);
      ApiAuthHooks.check(response.statusCode);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        return DecideResultDto(
          winnerRestaurantId: (data['winnerId'] as String?) ?? '',
          winnerName: (data['winnerName'] as String?) ?? '',
          voteCount: (data['voteCount'] as num?)?.toInt() ?? 0,
          totalVotes: (data['totalVotes'] as num?)?.toInt() ?? 0,
        );
      }
      debugPrint(
        '[VotesApiService] decide 실패: '
        '${response.statusCode} body=${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[VotesApiService] decide 예외: $e');
      return null;
    }
  }
}

/// 내부 집계용 mutable 버킷.
///
/// `Map<String, VoteResultItem>` 으로 직접 모으면 count 증가가 어색해
/// 짧은 라이프사이클의 mutable 헬퍼로 분리.
class _Bucket {
  _Bucket(this.name);
  String name;
  int count = 0;
}
