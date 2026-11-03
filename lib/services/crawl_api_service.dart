import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api/api_auth_hooks.dart';
import '../core/config/app_config.dart';

/// A Kakao place discovered for this location. It is not an orderable restaurant.
class NearbyPlaceDto {
  const NearbyPlaceDto({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    required this.kakaoUrl,
    required this.distanceMeters,
    required this.source,
  });

  final String id;
  final String name;
  final String category;
  final String address;
  final double lat;
  final double lng;
  final String kakaoUrl;
  final int distanceMeters;
  final String source;

  factory NearbyPlaceDto.fromJson(Map<String, dynamic> json) {
    double coordinate(Object? value) =>
        value is num ? value.toDouble() : double.parse(value.toString());
    int distance(Object? value) =>
        value is num ? value.round() : int.parse(value.toString());

    return NearbyPlaceDto(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      lat: coordinate(json['lat']),
      lng: coordinate(json['lng']),
      kakaoUrl: json['kakaoUrl']?.toString() ?? '',
      distanceMeters: distance(json['distanceMeters']),
      source: json['source']?.toString() ?? 'KAKAO',
    );
  }
}

/// Read-only nearby place discovery. This request never writes to the app DB.
class CrawlApiService {
  const CrawlApiService();

  Future<List<NearbyPlaceDto>> getNearbyPlaces({
    required String accessToken,
    required double lat,
    required double lng,
    int radius = 1000,
  }) async {
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/crawl/nearby');
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'lat': lat, 'lng': lng, 'radius': radius}),
        )
        .timeout(const Duration(seconds: 12));
    ApiAuthHooks.check(response.statusCode);
    if (response.statusCode != 200) {
      throw Exception('Nearby places request failed: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> ||
        payload['success'] != true ||
        payload['data'] is! List) {
      throw const FormatException('Invalid nearby places response');
    }
    return (payload['data'] as List)
        .map((place) => NearbyPlaceDto.fromJson(place as Map<String, dynamic>))
        .where(
          (place) =>
              place.source == 'KAKAO' &&
              place.id.isNotEmpty &&
              place.name.isNotEmpty,
        )
        .toList(growable: false);
  }
}
