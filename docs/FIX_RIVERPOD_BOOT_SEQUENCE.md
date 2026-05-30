Flutter Riverpod 앱 시작 오류 수정 요청
문제 요약

Flutter Web 실행 시 앱 시작 단계에서 Riverpod provider 수정 오류가 발생합니다.

현재 결제 기능 테스트 중인데, 백엔드 포트 충돌 문제는 해결했지만 프론트에서 아래 오류가 계속 발생합니다.

Tried to modify a provider while the widget tree was building.

현재 에러 로그 핵심

Uncaught (in promise) DartError: Tried to modify a provider while the widget tree was building.

UserNotifier.restoreFromSession (user_provider.dart:210)
_restoreUserFromSession (main.dart:196)
_bootSequence (main.dart:142)
_RootNavigatorState.initState (main.dart:137)

추정 원인

main.dart의 _RootNavigatorState.initState()에서 _bootSequence()를 바로 실행하고 있습니다.

그 안에서 _restoreUserFromSession()이 호출되고, 다시 userProvider.notifier.restoreFromSession()이 실행되면서 userProvider의 state를 변경합니다.

하지만 이 시점은 아직 Flutter 위젯 트리가 build 중인 상태라서 Riverpod이 provider state 변경을 막고 있습니다.

즉, 문제 흐름은 다음과 같습니다.

앱 시작
→ RootNavigator initState 실행
→ _bootSequence 실행
→ _restoreUserFromSession 실행
→ userProvider.notifier.restoreFromSession 실행
→ userProvider state 변경
→ 아직 widget tree build 중
→ Riverpod 오류 발생

수정 요청

아래 요구사항에 맞게 수정해주세요.

build, initState, dispose, didUpdateWidget, didChangeDependencies 중에 provider state가 직접 변경되지 않도록 수정
앱 시작 시 세션 복원 로직은 유지
restoreFromSession() 호출 또는 _bootSequence() 실행을 첫 frame 이후로 지연
결제 흐름에 필요한 로그인/유저 복원 상태가 정상적으로 유지되도록 수정
Flutter Web에서 아래 오류가 더 이상 발생하지 않도록 수정

Tried to modify a provider while the widget tree was building.

우선 확인할 파일

아래 파일들을 중심으로 확인해주세요.

lib/main.dart
lib/providers/user_provider.dart

특히 아래 부분을 확인해주세요.

_RootNavigatorState.initState
_bootSequence
_restoreUserFromSession
UserNotifier.restoreFromSession

예상 수정 방향

현재 코드가 이런 형태라면:

@override
void initState() {
super.initState();
_bootSequence();
}

아래처럼 첫 frame 이후 실행되게 변경해주세요.

@override
void initState() {
super.initState();

WidgetsBinding.instance.addPostFrameCallback((_) {
_bootSequence();
});
}

또는 _restoreUserFromSession() 내부에서 provider state를 변경하는 부분만 지연해도 됩니다.

예시:

WidgetsBinding.instance.addPostFrameCallback((_) {
ref.read(userProvider.notifier).restoreFromSession(user);
});

단, 단순히 에러만 숨기는 것이 아니라 앱 시작 시 세션 복원, 로그인 상태 유지, 라우팅 흐름이 정상적으로 동작해야 합니다.

주의사항

백엔드 쪽에서는 기존에 PM2에 lunchsync-backend와 main이 동시에 떠 있어서 3000번 포트 충돌이 있었습니다.

현재는 main을 삭제하고 lunchsync-backend만 남긴 상태입니다.

따라서 지금 남은 주요 문제는 백엔드 포트 충돌이 아니라 Flutter 프론트의 Riverpod 생명주기 오류입니다.

최종 목표

수정 후 아래 조건을 만족해야 합니다.

Flutter Web 실행 시 Riverpod provider 수정 오류가 발생하지 않음
앱 시작 시 세션 복원이 정상 작동함
로그인 상태가 정상 반영됨
결제 화면/결제 승인 흐름이 정상적으로 진행됨
main.dart의 boot sequence가 widget tree build 중 provider를 수정하지 않음

Claude에게 보낼 말:

이 md 파일 내용 기준으로 Flutter Riverpod 앱 시작 오류 수정해줘. 특히 main.dart의 _bootSequence와 user_provider.dart의 restoreFromSession 호출 타이밍을 봐줘.