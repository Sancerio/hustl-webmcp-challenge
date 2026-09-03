import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hustl_app/features/auth/presentation/bloc/auth_bloc.dart';

/// Adaptive app-bar leading control.
///
/// This widget sits in the app-bar leading (or, on a couple of custom headers,
/// the leading slot of a header row) on every screen. Its behaviour depends on
/// whether the current route can be popped:
///
/// * On a **pushed** route it renders a back button, so screens like Settings,
///   Templates, Strategy, Health, and Account always have a way back instead of
///   stranding the user with only an account avatar (the previous dead-ends).
/// * On a **tab root** (nothing to pop) it renders the account avatar, which
///   opens the Account screen. Tapping uses `push` so Account overlays the
///   shell with its own back button.
///
/// Navigation goes through `context.pop()` / `context.push()` (never
/// `Navigator.*`) to stay consistent with the app's GoRouter rules.
///
/// Tab roots are decided by the *page's* matched location, not the global
/// `canPop()`. In go_router 14.x `GoRouter.canPop()` is a global stack
/// predicate that also walks into the active shell branch navigator, so a
/// modal/route lingering on the branch (or root) could flip a tab root's
/// leading control to a back chevron. Reading the enclosing page's
/// `matchedLocation` and forcing the avatar on the five tab roots makes the
/// control immune to that leak regardless of what sits on either navigator.
const Set<String> _tabRoots = {
  '/',
  '/nutrition',
  '/history',
  '/progress',
  '/exercise_library',
};

class HustlMenuButton extends StatelessWidget {
  final double radius;

  /// Retained for source compatibility with callers that previously passed a
  /// scaffold key to open the drawer. No longer used.
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const HustlMenuButton({super.key, this.radius = 16, this.scaffoldKey});

  String _initials(AuthAuthenticated state) {
    final name = (state.user.displayName ?? '').trim();
    if (name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
      final letters = parts
          .take(2)
          .map((p) => p.isNotEmpty ? p.substring(0, 1) : '')
          .join();
      if (letters.isNotEmpty) return letters.toUpperCase();
    }
    final email = (state.user.email ?? '').trim();
    if (email.isNotEmpty) return email.substring(0, 1).toUpperCase();
    return 'H';
  }

  Widget _avatar(BuildContext context) {
    final theme = Theme.of(context);
    AuthBloc? authBloc;
    try {
      authBloc = context.read<AuthBloc>();
    } catch (_) {
      authBloc = null;
    }

    Widget circle(ImageProvider? image, String initials) => CircleAvatar(
      radius: radius,
      backgroundImage: image,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      child: image == null
          ? Text(
              initials,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            )
          : null,
    );

    if (authBloc == null) {
      return circle(null, 'H');
    }

    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (prev, curr) =>
          curr is AuthAuthenticated || curr is AuthUnauthenticated,
      builder: (context, state) {
        final imageProvider =
            state is AuthAuthenticated && state.user.photoUrl != null
            ? NetworkImage(state.user.photoUrl!)
            : null;
        final initials = state is AuthAuthenticated ? _initials(state) : 'H';
        return circle(imageProvider, initials);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Decide back-vs-avatar from the *page* this button lives in, not the
    // global router stack. `GoRouterState.of(context).matchedLocation` resolves
    // the matched path of the nearest enclosing Page; on a tab root it is one
    // of `_tabRoots`, on a pushed detail route it is that route's path. It
    // throws (GoError) when there is no enclosing Page — e.g. widget tests that
    // pump a bare screen — so we guard it and treat that as "not a tab root",
    // mirroring the existing null-safe avatar fallback.
    String? matchedLocation;
    try {
      matchedLocation = GoRouterState.of(context).matchedLocation;
    } catch (_) {
      matchedLocation = null;
    }
    final bool isTabRoot =
        matchedLocation != null && _tabRoots.contains(matchedLocation);

    // A tab root never shows a back button — it always opens Account via the
    // avatar — even if `canPop()` were true because of a route lingering on the
    // active branch or root navigator. Only genuinely pushed detail routes get
    // the back button.
    //
    // Use the null-safe `canPop` lookup so this is inert (shows the avatar)
    // when there is no GoRouter ancestor, e.g. in widget tests that pump a bare
    // screen — `context.canPop()` would throw there.
    final bool canPop =
        !isTabRoot && (GoRouter.maybeOf(context)?.canPop() ?? false);
    if (canPop) {
      return IconButton(
        icon: const BackButtonIcon(),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => context.pop(),
      );
    }
    return IconButton(
      tooltip: 'Account',
      // Push (not go) so the shell stays mounted beneath and the Account
      // screen gets a real back button instead of becoming a dead-end.
      onPressed: () => context.push('/account'),
      icon: _avatar(context),
    );
  }
}
