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

      final location = state.uri.path;
      final isLoginRoute = location == '/login';
      final isRegisterRoute = location == '/register';
      final isPasswordResetRoute = location == '/password-reset';
      final isSplashRoute = location == '/';

      if (isUnauth) {
        if (isSplashRoute) return '/login';
        if (!isLoginRoute && !isRegisterRoute && !isPasswordResetRoute) {
          final from = state.uri.toString();
          return '/login?from=${Uri.encodeComponent(from)}';
        }
      }

      if (isAuth && (isSplashRoute || isLoginRoute || isRegisterRoute)) {
        final from = state.uri.queryParameters['from'];
        if (from != null && from.isNotEmpty) return from;
        return '/map';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/map',
        builder: (context, state) {
          final id = int.tryParse(state.uri.queryParameters['id'] ?? '');
          final query = state.uri.queryParameters['q'];
          return MapScreen(initialParkingId: id, searchQuery: query);
        },
        routes: [
          GoRoute(
            path: 'parking/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              return MapScreen(initialParkingId: id);
            },
          ),
        ],
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen(), routes: [
        GoRoute(path: 'edit', builder: (_, _) => const EditProfileScreen()),
      ]),
      GoRoute(
        path: '/search',
        builder: (context, state) {
          final q = state.uri.queryParameters['q'];
          return SearchScreen(initialQuery: q);
        },
      ),
      GoRoute(path: '/password-reset', builder: (_, _) => const PasswordResetScreen()),
    ],
  );
});
