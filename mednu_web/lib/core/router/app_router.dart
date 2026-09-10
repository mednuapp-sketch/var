import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/articles/article_detail_page.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/otp_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/dashboard/dashboard_shell.dart';
import '../../features/landing/landing_page.dart';

// Bridges Riverpod auth + live profile state into a Listenable so GoRouter
// can refresh redirects WITHOUT recreating the entire router on each change.
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(this._ref) {
    _ref.listen<AsyncValue<dynamic>>(authStateProvider, (_, __) {
      notifyListeners();
    });
    _ref.listen<AsyncValue<dynamic>>(authProfileProvider, (_, __) {
      notifyListeners();
    });
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);

      // Don't redirect while Firebase is still initialising
      if (authState.isLoading) return null;

      final user = authState.valueOrNull;
      final isLoggedIn = user != null;
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/otp');
      final isRegisterRoute = state.matchedLocation.startsWith('/register');
      final isDashboard = state.matchedLocation.startsWith('/dashboard');

      if (!isLoggedIn) {
        if (isDashboard || isRegisterRoute) return '/';
        return null;
      }

      // Signed in to Firebase Auth doesn't mean the Firestore profile exists
      // yet — signInWithPhoneNumber's confirm() fires authStateChanges the
      // instant it succeeds, well before we know whether this is a brand
      // new number. Wait for the live profile doc before picking a
      // destination, instead of guessing and sending new users straight to
      // /dashboard with no profile.
      final profileState = ref.read(authProfileProvider);
      if (profileState.isLoading) return null;
      final hasProfile = hasCompletedProfile(profileState.valueOrNull);

      if (!hasProfile) {
        if (isRegisterRoute) return null;
        final rawPhone = user.phoneNumber ?? '';
        final localPhone = rawPhone.startsWith('+91') ? rawPhone.substring(3) : rawPhone;
        return '/register?phone=${Uri.encodeComponent(localPhone)}';
      }

      if (isAuthRoute || isRegisterRoute) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => LandingPage(
          onLoginTap: () => context.go('/login'),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(
          onBack: () => context.go('/'),
        ),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          return OtpPage(phone: phone);
        },
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          return RegisterPage(phone: phone);
        },
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => DashboardShell(
          onLogout: () => ref.read(authNotifierProvider.notifier).signOut(),
        ),
      ),
      GoRoute(
        path: '/article/:id',
        builder: (context, state) => ArticleDetailPage(
          articleId: state.pathParameters['id']!,
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('404', style: TextStyle(fontSize: 72, fontWeight: FontWeight.w800)),
            const Text('Page not found'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});
