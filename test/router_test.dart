import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/router.dart';

void main() {
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
