import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';

import 'analytics_providers_test.dart' show FakeAuth;

void main() {
  test(
    'Store destinations and legacy routes resolve without duplicate patterns',
    () async {
      final container = ProviderContainer(
        overrides: [authControllerProvider.overrideWith(FakeAuth.new)],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final router = container.read(routerProvider);
      addTearDown(router.dispose);
      for (final path in [
        '/app/menu/catering',
        '/app/menu/store',
        '/app/menu/store/categories/new',
        '/app/menu/catering/categories/new',
        '/app/store/locations',
        '/app/promotions',
        '/app/store/pickup-settings',
        '/app/store/delivery-settings',
        '/app/printing',
        '/app/menu',
        '/app/store-operations',
      ]) {
        expect(
          router.configuration.findMatch(Uri.parse(path)).isError,
          isFalse,
          reason: path,
        );
        expect(
          authRedirect(status: AuthRouteStatus.unauthenticated, location: path),
          '/login',
        );
      }
      final paths = <String>[];
      void collect(List<RouteBase> routes, String parent) {
        for (final route in routes) {
          final path = route is GoRoute ? '$parent/${route.path}' : parent;
          if (route is GoRoute) paths.add(path);
          collect(route.routes, path);
        }
      }

      collect(router.configuration.routes, '');
      expect(paths.toSet().length, paths.length);
    },
  );
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
