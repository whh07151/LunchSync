import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:capstone/features/auth/email_otp_screen.dart';
import 'package:capstone/providers/user_provider.dart';
import 'package:capstone/services/auth_api_service.dart';
import 'package:capstone/services/email_otp_api_service.dart';

class _FakeEmailOtpApiService extends EmailOtpApiService {
  int sendCalls = 0;
  int verifyCalls = 0;

  @override
  Future<OtpResult> sendOtp(String email, String verificationToken) async {
    expect(verificationToken, 'verification-token');
    sendCalls++;
    return OtpResult.ok('인증 메일을 보냈어요.');
  }

  @override
  Future<OtpResult> verifyOtp(
    String email,
    String code,
    String verificationToken,
  ) async {
    expect(verificationToken, 'verification-token');
    verifyCalls++;
    return OtpResult.ok(
      '이메일 인증이 완료됐어요.',
      const AuthResponse(
        accessToken: 'full-access-token',
        isNewUser: true,
        nextStep: 'PROFILE_SETUP',
        userId: '11111111-1111-4111-8111-111111111111',
        name: '테스트 사용자',
        role: 'CUSTOMER',
        status: 'APPROVED',
      ),
    );
  }
}

void main() {
  testWidgets('OTP 성공 뒤에만 일반 JWT를 저장하고 다음 단계로 이동한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final otpService = _FakeEmailOtpApiService();
    String? completedStep;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: EmailOtpScreen(
            email: 'owner@example.com',
            verificationToken: 'verification-token',
            otpService: otpService,
            onComplete: ({required nextStep}) {
              completedStep = nextStep;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(otpService.sendCalls, 1);
    expect(find.text('나중에 인증하기'), findsNothing);
    expect(container.read(userProvider).accessToken, isNull);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('인증하기'));
    await tester.pumpAndSettle();

    expect(otpService.verifyCalls, 1);
    expect(container.read(userProvider).accessToken, 'full-access-token');
    expect(completedStep, 'PROFILE_SETUP');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('ls_jwt'), 'full-access-token');
  });
}
