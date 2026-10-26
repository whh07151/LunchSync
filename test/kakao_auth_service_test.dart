import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:capstone/services/kakao_auth_service.dart';

void main() {
  test('카카오 플랫폼 설정 오류를 네트워크 장애와 구분한다', () {
    final error = KakaoAuthException(AuthErrorCause.misconfigured, null);

    expect(kakaoLoginErrorMessage(error), contains('등록되지 않았어요'));
  });

  test('사용자가 취소한 카카오 로그인을 실패로 오인하지 않게 안내한다', () {
    final error = KakaoAuthException(AuthErrorCause.accessDenied, null);

    expect(kakaoLoginErrorMessage(error), '카카오 로그인이 취소됐어요.');
    expect(
      kakaoLoginErrorMessage(
        KakaoClientException(ClientErrorCause.cancelled, 'User Cancelled'),
      ),
      '카카오 로그인이 취소됐어요.',
    );
    expect(
      isKakaoLoginCancelled(
        PlatformException(code: 'CANCELED', message: 'User canceled.'),
      ),
      isTrue,
    );
    expect(
      isKakaoLoginCancelled(PlatformException(code: 'NETWORK_ERROR')),
      isFalse,
    );
  });
}
