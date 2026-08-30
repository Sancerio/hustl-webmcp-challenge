import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/features/auth/domain/services/auth_redirect_service.dart';
import 'package:hustl_app/app/navigation/app_routes.dart';

void main() {
  test('returns default when no route set', () {
    final service = AuthRedirectService();
    expect(service.consumeAfterLoginRoute(), AppRoutes.defaultAfterLoginRoute);
  });

  test('returns and clears valid route', () {
    final service = AuthRedirectService();
    service.setAfterLoginRoute('/history');
    expect(service.consumeAfterLoginRoute(), '/history');
    expect(service.consumeAfterLoginRoute(), AppRoutes.defaultAfterLoginRoute);
  });

  test('invalid routes fall back to default', () {
    final service = AuthRedirectService();
    service.setAfterLoginRoute('/bogus');
    expect(service.consumeAfterLoginRoute(), AppRoutes.defaultAfterLoginRoute);
  });

  // Regression: post-login must never strand the user. With no stored route the
  // default landing has to be a navigable shell tab (home) — never the
  // standalone `/account` overlay, which on web has no bottom nav and no back.
  test('default after-login route is home, not the account dead-end', () {
    expect(AppRoutes.defaultAfterLoginRoute, '/');
    final service = AuthRedirectService();
    expect(service.consumeAfterLoginRoute(), '/');
  });

  // Regression: a stale/standalone `/account` (or `/settings`) redirect must NOT
  // be honored as a post-login landing — `context.go` would replace the stack
  // and leave the user on a screen with no nav/back. It falls back to home.
  test('standalone overlay routes are not honored as after-login landings', () {
    expect(AppRoutes.validAfterLoginRoutes.contains('/account'), isFalse);
    expect(AppRoutes.validAfterLoginRoutes.contains('/settings'), isFalse);

    final service = AuthRedirectService();
    service.setAfterLoginRoute('/account');
    expect(service.consumeAfterLoginRoute(), '/');

    service.setAfterLoginRoute('/settings');
    expect(service.consumeAfterLoginRoute(), '/');
  });

  // A genuine deep-linkable shell tab the user intended is still honored.
  test('a valid shell-tab route is honored as the after-login landing', () {
    final service = AuthRedirectService();
    service.setAfterLoginRoute('/history');
    expect(service.consumeAfterLoginRoute(), '/history');
  });
}
