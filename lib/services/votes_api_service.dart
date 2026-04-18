import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 투표 + 후보 관련 API 호출 서비스
//
// 담당 엔드포인트:
//   POST /api/sessions/:id/votes           — 투표하기
//   GET  /api/sessions/:id/votes           — 투표 현황 조회
//   POST /api/sessions/:id/decide          — 투표 결과 확정
//   GET  /api/sessions/:id/candidates      — 후보 목록 조회
//   POST /api/sessions/:id/candidates      — 후보 1개 추가
//   POST /api/sessions/:id/candidates/batch — 후보 일괄 추가
//   DELETE /api/sessions/:id/candidates/:restaurantId — 후보 삭제
// ══════════════════════════════════════════════════════════

class VotesApiService {
  const VotesApiService();

  Map<String, String> _headers(String accessToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

  // ── 투표하기 ──────────────────────────────────────────
  Future<VoteResult?> castVote({
    required String accessToken,
    required String sessionId,
    required String restaurantId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/votes'),
        headers: _headers(accessToken),
        body: jsonEncode({'restaurantId': restaurantId}),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return VoteResult.fromJson(json['data'] as Map<String, dynamic>);
      }
      if (response.statusCode == 409) {
        return null; // 이미 투표함
      }
      print('[VotesApiService] castVote 실패: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      print('[VotesApiService] castVote 에러: $e');
      return null;
    }
  }

  // ── 투표 현황 조회 ────────────────────────────────────
  Future<List<VoteStatus>> getVotes({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/votes'),
        headers: _headers(accessToken),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;
        return list
            .map((e) => VoteStatus.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('[VotesApiService] getVotes 에러: $e');
      return [];
    }
  }

  // ── 투표 결과 확정 ────────────────────────────────────
  Future<VoteDecideResult?> decide({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/decide'),
        headers: _headers(accessToken),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return VoteDecideResult.fromJson(json['data'] as Map<String, dynamic>);
      }
      print('[VotesApiService] decide 실패: ${response.statusCode}');
      return null;
    } catch (e) {
      print('[VotesApiService] decide 에러: $e');
      return null;
    }
  }

  // ── 후보 목록 조회 ────────────────────────────────────
  Future<List<CandidateDto>> getCandidates({
    required String accessToken,
    required String sessionId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/candidates'),
        headers: _headers(accessToken),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final list = json['data'] as List<dynamic>;
        return list
            .map((e) => CandidateDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('[VotesApiService] getCandidates 에러: $e');
      return [];
    }
  }

  // ── 후보 1개 추가 ─────────────────────────────────────
  Future<bool> addCandidate({
    required String accessToken,
    required String sessionId,
    required String restaurantId,
    String source = 'MANUAL',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/candidates'),
        headers: _headers(accessToken),
        body: jsonEncode({'restaurantId': restaurantId, 'source': source}),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      print('[VotesApiService] addCandidate 에러: $e');
      return false;
    }
  }

  // ── 후보 일괄 추가 (AI 추천 결과 등록) ────────────────
  Future<bool> addCandidatesBatch({
    required String accessToken,
    required String sessionId,
    required List<Map<String, String>> candidates,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/candidates/batch'),
        headers: _headers(accessToken),
        body: jsonEncode({'candidates': candidates}),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      print('[VotesApiService] addCandidatesBatch 에러: $e');
      return false;
    }
  }

  // ── 후보 삭제 ─────────────────────────────────────────
  Future<bool> removeCandidate({
    required String accessToken,
    required String sessionId,
    required String restaurantId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.backendBaseUrl}/sessions/$sessionId/candidates/$restaurantId'),
        headers: _headers(accessToken),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('[VotesApiService] removeCandidate 에러: $e');
      return false;
    }
  }
}

// ── DTO 클래스들 ──────────────────────────────────────────

class VoteResult {
  const VoteResult({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.restaurantId,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String sessionId;
  final String restaurantId;
  final String createdAt;

  factory VoteResult.fromJson(Map<String, dynamic> json) {
    return VoteResult(
      id: json['id'] as String,
      userId: json['userId'] as String,
      sessionId: json['sessionId'] as String,
      restaurantId: json['restaurantId'] as String,
      createdAt: json['createdAt'] as String,
    );
  }
}

class VoteStatus {
  const VoteStatus({
    required this.id,
    required this.userId,
    required this.restaurantId,
    this.restaurantName,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String restaurantId;
  final String? restaurantName;
  final String createdAt;

  factory VoteStatus.fromJson(Map<String, dynamic> json) {
    return VoteStatus(
      id: json['id'] as String,
      userId: json['userId'] as String,
      restaurantId: json['restaurantId'] as String,
      restaurantName: json['restaurantName'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }
}

class VoteDecideResult {
  const VoteDecideResult({
    required this.winnerId,
    required this.winnerName,
    required this.voteCount,
    required this.totalVotes,
    required this.tally,
  });

  final String winnerId;
  final String winnerName;
  final int voteCount;
  final int totalVotes;
  final List<TallyItem> tally;

  factory VoteDecideResult.fromJson(Map<String, dynamic> json) {
    final tallyRaw = json['tally'] as List<dynamic>? ?? [];
    return VoteDecideResult(
      winnerId: json['winnerId'] as String,
      winnerName: json['winnerName'] as String,
      voteCount: json['voteCount'] as int,
      totalVotes: json['totalVotes'] as int,
      tally: tallyRaw
          .map((e) => TallyItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TallyItem {
  const TallyItem({
    required this.restaurantId,
    required this.restaurantName,
    required this.count,
  });

  final String restaurantId;
  final String restaurantName;
  final int count;

  factory TallyItem.fromJson(Map<String, dynamic> json) {
    return TallyItem(
      restaurantId: json['restaurantId'] as String,
      restaurantName: json['restaurantName'] as String? ?? '',
      count: json['count'] as int,
    );
  }
}

class CandidateDto {
  const CandidateDto({
    required this.id,
    required this.sessionId,
    required this.restaurantId,
    required this.addedBy,
    required this.source,
    this.name,
    this.category,
    this.priceRange,
    this.address,
    this.createdAt,
  });

  final String id;
  final String sessionId;
  final String restaurantId;
  final String addedBy;
  final String source;
  final String? name;
  final String? category;
  final int? priceRange;
  final String? address;
  final String? createdAt;

  factory CandidateDto.fromJson(Map<String, dynamic> json) {
    return CandidateDto(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      restaurantId: json['restaurantId'] as String,
      addedBy: json['addedBy'] as String,
      source: json['source'] as String? ?? 'MANUAL',
      name: json['name'] as String?,
      category: json['category'] as String?,
      priceRange: json['priceRange'] as int?,
      address: json['address'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}
