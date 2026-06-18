import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/otp_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/dashboard/dashboard_shell.dart';
import '../../features/landing/landing_page.dart';

// Bridges Riverpod auth state into a Listenable so GoRouter can refresh
// redirects WITHOUT recreating the entire router on each auth change.
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(this._ref) {
    _ref.listen<AsyncValue<dynamic>>(authStateProvider, (_, __) {
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

      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/otp');
      final isRegisterRoute = state.matchedLocation.startsWith('/register');
      final isDashboard = state.matchedLocation.startsWith('/dashboard');

      if (isLoggedIn && isAuthRoute) return '/dashboard';
      if (!isLoggedIn && (isDashboard || isRegisterRoute)) return '/';
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
