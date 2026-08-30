import 'package:flutter/material.dart';
import 'package:hustl_app/core/widgets/hustl_inline_skeleton.dart';
import 'package:hustl_app/core/widgets/screen_empty_state.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// no entity needed here
import '../../domain/repositories/auth_repository.dart';
import '../../data/repositories/api_auth_repository.dart';
import '../../errors/auth_exception.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';
import '../../domain/services/auth_redirect_service.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/web/platform_redirect.dart';

class OAuthCallbackScreen extends StatefulWidget {
  const OAuthCallbackScreen({super.key, this.callbackUri});

  /// The URL that triggered this callback route.
  ///
  /// On web, `Uri.base` reflects the document's `<base href>` and may not
  /// include the current path/query. GoRouter's `state.uri` is the canonical
  /// source of truth, so we pass it in from the route builder.
  final Uri? callbackUri;

  @override
  State<OAuthCallbackScreen> createState() => _OAuthCallbackScreenState();
}

class _OAuthCallbackScreenState extends State<OAuthCallbackScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _handleCallback();
  }

  Future<void> _handleCallback() async {
    try {
      final uri = widget.callbackUri ?? Uri.base;
      final code = uri.queryParameters['code'];
      final state = uri.queryParameters['state'];
      final stateToken = uri.queryParameters['state_token'];
      final webSession = uri.queryParameters['web_session'];
      final providerError = uri.queryParameters['error'];
      final providerErrorDesc = uri.queryParameters['error_description'];

      // Web: if we already completed the server-side exchange and came back via redirect,
      // mark the session hint and rehydrate via refresh cookie.
      if (kIsWeb && (webSession == '1' || webSession == 'true')) {
        await GetIt.instance<PreferencesService>().setHasWebSession(true);
        if (!mounted) return;
        context.read<AuthBloc>().add(AuthCheckRequested());
        final redirect = GetIt.instance<AuthRedirectService>()
            .consumeAfterLoginRoute();
        context.go(redirect);
        return;
      }

      if (providerError != null) {
        setState(() {
          _error = _friendlyProviderError(providerError, providerErrorDesc);
        });
        return;
      }

      if (code == null || state == null) {
        setState(
          () => _error =
              'We couldn\'t read the sign-in response. Please try again.',
        );
        return;
      }

      if (code.isEmpty || state.isEmpty) {
        setState(
          () => _error =
              'That sign-in link looks incomplete. Please try signing in again.',
        );
        return;
      }

      if (kIsWeb) {
        final repo = GetIt.instance<AuthRepository>();
        if (repo is ApiAuthRepository) {
          try {
            // Prefer an in-app exchange so we can immediately store the access
            // token and update UI state (avoids relying on a cookie-only
            // rehydrate step).
            await repo.completeOAuthOnWeb(
              provider: 'google',
              code: code,
              state: state,
              stateToken: stateToken,
            );
            if (!mounted) return;
            context.read<AuthBloc>().add(AuthCheckRequested());
            final redirect = GetIt.instance<AuthRedirectService>()
                .consumeAfterLoginRoute();
            context.go(redirect);
            return;
          } catch (_) {
            // Fallback: do the code exchange via a top-level navigation so
            // cookies are set reliably in environments where XHR cookie writes
            // are blocked/misconfigured.
            final origin = Uri.parse(Uri.base.origin);
            final landing = origin.replace(
              path: '/auth/google/callback',
              queryParameters: const {'web_session': '1'},
            );
            final exchange = Uri.parse(ApiConfig.authBaseUrl).replace(
              path: '/api/auth/google/callback',
              queryParameters: {
                'code': code,
                'state': state,
                if (stateToken != null && stateToken.isNotEmpty)
                  'state_token': stateToken,
                'redirect': landing.toString(),
              },
            );
            webRedirectTo(exchange.toString());
            return;
          }
        }
        setState(() => _error = 'Unsupported auth flow on this platform.');
        return;
      }

      final repo = GetIt.instance<AuthRepository>();
      if (repo is ApiAuthRepository) {
        try {
          await repo.completeOAuthOnWeb(
            provider: 'google',
            code: code,
            state: state,
            stateToken: stateToken,
          );
          if (!mounted) return;
          context.read<AuthBloc>().add(AuthCheckRequested());
          final redirect = GetIt.instance<AuthRedirectService>()
              .consumeAfterLoginRoute();
          context.go(redirect);
          return;
        } catch (e) {
          setState(() {
            _error = e is AuthException
                ? e.message
                : 'We couldn\'t finish signing you in. Please try again.';
          });
          return;
        }
      } else {
        setState(() => _error = 'Unsupported auth flow on this platform.');
      }
    } catch (e) {
      setState(() {
        _error = 'We couldn\'t finish signing you in. Please try again.';
      });
    }
  }

  String _friendlyProviderError(String code, String? desc) {
    switch (code) {
      case 'access_denied':
        return 'Sign-in was cancelled. No changes were made.';
      case 'redirect_uri_mismatch':
        return 'Sign-in failed due to a configuration issue. Please try again later.';
      case 'invalid_request':
        return 'Invalid sign-in request. Please try again.';
      default:
        return 'Sign-in failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error == null) {
      // Announce progress to screen readers instead of dropping them onto a
      // silent "Loading content" surface mid-sign-in.
      return const Scaffold(
        body: HustlInlineSkeleton(
          semanticsLabel: 'Signing you in',
          liveRegion: true,
        ),
      );
    }

    // Reframed through the shared empty-state language: a soft holder, a kind
    // headline, the friendly reason demoted to the supportive line, and a
    // single blue "Try again" that re-triggers Google sign-in. The friendly
    // reason already avoids leaking technical details.
    return Scaffold(
      appBar: AppBar(title: const Text('Sign-in')),
      body: ScreenEmptyState(
        icon: Icons.error_outline,
        title: "Sign-in didn't finish",
        message: _error,
        actionLabel: 'Try again',
        onAction: () {
          // Re-trigger Google sign-in and land on a navigable screen. Home is
          // the shell's first tab (bottom nav present); `/account` here would
          // strand the user on a standalone overlay with no back/nav on web.
          context.read<AuthBloc>().add(AuthSignInWithGoogleRequested());
          // On web this immediately starts a full-page redirect to Google, so
          // navigating home first would just flash the shell. Native still
          // needs a navigable screen to land on.
          if (!kIsWeb) context.go('/');
        },
      ),
    );
  }
}
