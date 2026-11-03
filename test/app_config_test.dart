import 'package:flutter_test/flutter_test.dart';
import 'package:capstone/core/config/app_config.dart';

void main() {
  test('local defaults and explicit backend overrides', () {
    expect(AppConfig.resolveBackendUrl(), 'http://localhost:3000/api');
    expect(
      AppConfig.resolveBackendUrl(android: true),
      'http://10.0.2.2:3000/api',
    );
    expect(
      AppConfig.resolveBackendUrl(
        urlOverride: 'http://127.0.0.1:3000/api',
        hostOverride: 'unused',
      ),
      'http://127.0.0.1:3000/api',
    );
  });
  test('release refuses missing or unsafe endpoint', () {
    for (final value in [
      '',
      'http://localhost:3000/api',
      'https://user:pw@example.com/api',
      'https://example.com/api?x=1',
    ]) {
      expect(
        () => AppConfig.resolveBackendUrl(release: true, urlOverride: value),
        throwsStateError,
      );
    }
    expect(
      AppConfig.resolveBackendUrl(
        release: true,
        urlOverride: 'https://example.com/api',
      ),
      'https://example.com/api',
    );
  });
}
