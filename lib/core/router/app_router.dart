import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/providers/auth_provider.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/password_reset_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/map/map_screen.dart';
import '../../presentation/screens/profile/edit_profile_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/search/search_screen.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import 'deep_link_coordinator.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  final deepLinks = DeepLinkCoordinator();
  ref.listen(authStateProvider, (_, _) => refreshNotifier.refresh());
  ref.onDispose(refreshNotifier.dispose);

  bool isPublicPath(String path) =>
      path == '/login' || path == '/register' || path == '/password-reset';

  return GoRouter(
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoading = authState.maybeWhen(
        loading: () => true,
        orElse: () => false,
      );
      final isAuthenticated = authState.maybeWhen(
        authenticated: (_) => true,
        orElse: () => false,
      );
      final isUnauthenticated = authState.maybeWhen(
        unauthenticated: () => true,
        orElse: () => false,
      );
      final path = state.uri.path;
      final isSplash = path == '/';
      final isPublic = isPublicPath(path);

      if (isLoading) {
        if (!isSplash && !isPublic) deepLinks.remember(state.uri);
        return isSplash ? null : '/';
      }

      if (isUnauthenticated) {
        if (isSplash) return '/login';
        if (!isPublic) {
          deepLinks.remember(state.uri);
          return Uri(
            path: '/login',
            queryParameters: {'from': state.uri.toString()},
          ).toString();
        }
      }

      if (isAuthenticated && (isSplash || isPublic)) {
        return deepLinks.takePendingOr(state.uri.queryParameters['from']);
      }

      if (isAuthenticated) {
        final safeLocation = deepLinks.safeLocation(state.uri);
        if (safeLocation != state.uri.toString()) return safeLocation;
      }

      return null;
    },
    errorBuilder: (_, _) => const MapScreen(),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/password-reset',
        builder: (_, _) => const PasswordResetScreen(),
      ),
      GoRoute(
        path: '/map',
        builder: (_, state) => MapScreen(
          zoneId: int.tryParse(state.uri.queryParameters['zoneId'] ?? ''),
          destinationLatitude: double.tryParse(
            state.uri.queryParameters['lat'] ?? '',
          ),
          destinationLongitude: double.tryParse(
            state.uri.queryParameters['lon'] ?? '',
          ),
          destinationName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/parking/:zoneId',
        builder: (_, state) => MapScreen(
          zoneId: int.tryParse(state.pathParameters['zoneId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/destination',
        builder: (_, state) => MapScreen(
          destinationLatitude: double.tryParse(
            state.uri.queryParameters['lat'] ?? '',
          ),
          destinationLongitude: double.tryParse(
            state.uri.queryParameters['lon'] ?? '',
          ),
          destinationName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const ProfileScreen(),
        routes: [
          GoRoute(path: 'edit', builder: (_, _) => const EditProfileScreen()),
        ],
      ),
      GoRoute(
        path: '/search',
        builder: (_, state) =>
            SearchScreen(initialQuery: state.uri.queryParameters['q']),
      ),
    ],
  );
});
