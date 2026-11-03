import 'dart:convert';

import 'package:capstone/services/auth_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('카카오 API의 인증 오류를 연결 장애로 바꾸지 않는다', () async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/auth/kakao'));
      expect(jsonDecode(request.body)['kakaoAccessToken'], 'synthetic-token');
      return http.Response(
        jsonEncode({'message': '유효하지 않은 카카오 토큰입니다.'}),
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);

    final result = await AuthApiService(
      client: client,
    ).loginWithKakao('synthetic-token');

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, '유효하지 않은 카카오 토큰입니다.');
  });

  test('카카오 API의 성공 응답을 로그인 상태로 변환한다', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'data': {
            'accessToken': 'synthetic-jwt',
            'isNewUser': true,
            'nextStep': 'PROFILE_SETUP',
            'user': {
              'id': 'synthetic-user',
              'name': '테스트 사용자',
              'role': 'CUSTOMER',
              'status': 'APPROVED',
            },
          },
        }),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    addTearDown(client.close);

    final result = await AuthApiService(
      client: client,
    ).loginWithKakao('synthetic-token');

    expect(result.isSuccess, isTrue);
    expect(result.response?.nextStep, 'PROFILE_SETUP');
  });
}
