# Kakao·Firebase 앱 식별자 마이그레이션 검토

날짜: 2026-08-05
브랜치: `agent/reliability-observability`

## 해결하려는 문제

LunchSync 모바일 앱은 생성기 기본값인 `com.example.capstone`과 이전 Kakao 앱 설정을
사용하고 있었다. 새 Kakao Developers 앱 1534395와 기존 Firebase 프로젝트
`lunchsync-cf32f`를 장기 사용 식별자 `com.whh07151.lunchsync`에 맞춰 정렬했다.

## 적용한 변경

- Android `namespace`와 `applicationId`를 `com.whh07151.lunchsync`로 변경했다.
- `MainActivity`의 Java 패키지 선언과 디렉터리를 새 namespace에 맞췄다.
- iOS Runner와 RunnerTests의 bundle identifier를 같은 식별자 계열로 변경했다.
- Kakao Native/JavaScript 공개 앱 식별자와 Android/iOS OAuth callback scheme을
  새 Kakao 앱 기준으로 원자적으로 교체했다.
- Kakao Login을 켜고 닉네임은 필수, 프로필 이미지는 선택 동의로 설정했다.
- Kakao Android 플랫폼에 새 패키지와 현재 debug 키 해시를, iOS 플랫폼에 새 bundle
  identifier를 등록했다. 개발 JavaScript 도메인은 `http://localhost:8080`만 등록했다.
- Firebase 프로젝트에 `com.whh07151.lunchsync` Android 앱을 추가하고 현재 debug
  인증서의 SHA-1과 SHA-256을 등록했다.
- 새 Firebase 구성으로 `google-services.json`과 Android `FirebaseOptions` 전체를
  함께 교체했다. 프로젝트 ID, App ID, API 키, 발신자 ID와 Storage bucket의 상호
  일치를 로컬에서 확인했다.
- 서버용 Kakao REST 키는 추적 파일이 아닌 `backend/.env`에만 두고, 해당 파일이
  `backend/.gitignore`에 의해 제외됨을 확인했다.

## 보안 경계

- Kakao Native/JavaScript 키와 Firebase 클라이언트 API 키는 앱 바이너리에 포함되는
  클라이언트 식별자다. 보안은 Kakao 패키지·키 해시·도메인 제한과 Firebase API/IAM
  정책으로 보완한다.
- Kakao REST 키, 서비스 계정 JSON, keystore와 비밀번호는 저장소에 추가하지 않았다.
- 실제 release/Play App Signing 인증서를 도입하면 Kakao 키 해시와 Firebase SHA
  지문을 별도로 추가해야 한다. 현재 release 빌드는 기존 설정대로 debug 키를 쓴다.
- 기존 Manifest는 cleartext HTTP를 전역 허용한다. 이번 식별자 변경과 별도 문제지만,
  release에서는 HTTPS만 허용하고 필요한 로컬 HTTP 예외를 debug 전용 설정으로
  제한하기 전까지 배포하면 안 된다.

## 검증

- `cmd /c C:\flutter\bin\flutter.bat analyze --fatal-infos`: 문제 없음.
- `cmd /c C:\flutter\bin\flutter.bat test --reporter expanded`: 12개 통과.
- `cmd /c npm test -- --runInBand`: Jest 23개 스위트, 122개 테스트 통과.
- `cmd /c npm run build`: NestJS 빌드 통과.
- `cmd /c C:\flutter\bin\flutter.bat build apk --debug`: APK 빌드 통과.
- `aapt dump badging`: 생성 APK의 package가 `com.whh07151.lunchsync`임을 확인했다.
- `apksigner verify --print-certs`: APK 인증서 SHA-1·SHA-256이 Firebase에 등록한
  debug 지문과 일치함을 확인했다.
- `git diff --check`: 공백 오류 없음. Windows 줄바꿈 안내만 발생했다.

## 남은 위험과 사람의 검증

- 새 application ID는 OS에서 별도 앱으로 취급되므로 기존 설치의 JWT, 온보딩 상태와
  로컬 찜 데이터가 자동 승계되지 않는다.
- Kakao 사용자 ID는 앱 단위다. 기존 Kakao 앱 사용자는 별도 계정 연결 전략 없이
  로그인하면 백엔드에서 신규 사용자로 생성될 수 있다. 기존 계정이 폐기 가능한
  테스트 데이터가 아니라면 계정 연결 또는 이전 앱 유지 결정을 출시 전 차단 조건으로 둔다.
- 실제 Android 기기에서 Kakao 앱/계정 로그인 복귀, Phone Auth, FCM 토큰 등록과
  알림 수신을 사람 손으로 검증해야 한다.
- iOS Firebase 앱과 `GoogleService-Info.plist`, APNs/entitlements는 이번 범위에
  포함하지 않았다. 현재 코드도 iOS Firebase 초기화를 명시적으로 지원하지 않는다.
- 기존 Firebase Android 앱은 롤백을 위해 보존했고 새 구성 파일에도 두 client가
  들어 있다. 호환성 필요가 끝난 뒤에만 콘솔에서 이전 앱을 폐기하고 파일을 다시 받는다.
- Kakao Map은 활성화하지 않았다. 계정의 최초 활성화 앱에 무료 쿼터가 귀속되고 다른
  앱으로 이전할 수 없다는 콘솔 경고 때문에, 장기 운영 앱 확정 후 별도 승인해야 한다.
  따라서 새 JavaScript 키를 사용하는 지도 화면은 현재 동작 보장 대상이 아니며,
  지도 기능을 포함해 출시하려면 활성화와 실제 렌더링 스모크 테스트가 선행돼야 한다.

## 롤백

코드에서는 위 식별자·구성 파일 변경을 되돌릴 수 있다. 다만 Firebase에 생성한 앱
항목과 Kakao 콘솔 설정은 외부 상태이므로 코드 롤백과 별도로 관리해야 한다. 기존
Firebase Android 앱은 삭제하지 않아 이전 패키지 빌드의 복구 경로를 보존했다.
