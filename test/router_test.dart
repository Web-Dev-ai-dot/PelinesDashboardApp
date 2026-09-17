import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';

import 'analytics_providers_test.dart' show FakeAuth;

void main() {
  test(
    'official Analytics route is registered and preview route is absent',
    () async {
      final container = ProviderContainer(
        overrides: [authControllerProvider.overrideWith(FakeAuth.new)],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final router = container.read(routerProvider);
      addTearDown(router.dispose);
      final match = router.configuration.findMatch(Uri.parse('/app/analytics'));
      expect(match.isError, isFalse);
      expect(match.last.route.path, 'analytics');
      expect(
        router.configuration
            .findMatch(Uri.parse('/app/analytics-preview'))
            .isError,
        isTrue,
      );
    },
  );
  test('unauthenticated users are redirected to login', () {
    expect(
      authRedirect(status: AuthRouteStatus.unauthenticated, location: '/app'),
      '/login',
    );
  });

  test('validated admins are redirected to the admin app', () {
    expect(
      authRedirect(status: AuthRouteStatus.authenticated, location: '/login'),
      '/app',
    );
  });

  test('loading never exposes the admin route', () {
    expect(
      authRedirect(status: AuthRouteStatus.loading, location: '/app'),
      '/loading',
    );
  });
}
