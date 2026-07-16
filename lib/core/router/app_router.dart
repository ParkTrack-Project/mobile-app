import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/map/map_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/profile/edit_profile_screen.dart';
import '../../presentation/screens/search/search_screen.dart';
import '../../presentation/screens/auth/password_reset_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoading = authState.maybeWhen(loading: () => true, orElse: () => false);
      final isAuth = authState.maybeWhen(authenticated: (_) => true, orElse: () => false);
      final isUnauth = authState.maybeWhen(unauthenticated: () => true, orElse: () => false);

      if (isLoading) {
        return state.matchedLocation == '/' ? null : '/';
      }

      final isLoginRoute = state.matchedLocation == '/login';
      final isRegisterRoute = state.matchedLocation == '/register';
      final isPasswordResetRoute = state.matchedLocation == '/password-reset';
      final isSplashRoute = state.matchedLocation == '/';

      if (isUnauth) {
        if (isSplashRoute) return '/login';
        if (!isLoginRoute && !isRegisterRoute && !isPasswordResetRoute) return '/login';
      }

      if (isAuth && (isSplashRoute || isLoginRoute || isRegisterRoute)) return '/map';

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/map', builder: (_, _) => const MapScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen(), routes: [
        GoRoute(path: 'edit', builder: (_, _) => const EditProfileScreen()),
      ]),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(path: '/password-reset', builder: (_, _) => const PasswordResetScreen()),
    ],
  );
});
