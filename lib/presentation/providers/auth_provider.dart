import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/models/user.dart';
import '../../core/storage/session_expired_notifier.dart';
import 'app_providers.dart';

part 'auth_provider.freezed.dart';

@freezed
class AuthState with _$AuthState {
  const factory AuthState.loading() = _Loading;
  const factory AuthState.authenticated(User user) = _Authenticated;
  const factory AuthState.unauthenticated() = _Unauthenticated;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState.loading()) {
    sessionExpiredNotifier.addListener(_onSessionExpired);
  }

  final Ref _ref;

  @override
  void dispose() {
    sessionExpiredNotifier.removeListener(_onSessionExpired);
    super.dispose();
  }

  void _onSessionExpired() {
    if (sessionExpiredNotifier.value) {
      sessionExpiredNotifier.value = false;
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> checkSession() async {
    try {
      final user = await _ref.read(authRepositoryProvider).getMe();
      state = user != null
          ? AuthState.authenticated(user)
          : const AuthState.unauthenticated();
    } catch (_) {
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> login(String login, String password) async {
    final user = await _ref.read(authRepositoryProvider).login(login, password);
    state = AuthState.authenticated(user);
  }

  Future<void> register(String email, String password, {String? fullName}) async {
    final user = await _ref.read(authRepositoryProvider).register(
          email,
          password,
          fullName: fullName,
        );
    state = AuthState.authenticated(user);
  }

  Future<void> signOut() async {
    await _ref.read(authRepositoryProvider).logout();
    state = const AuthState.unauthenticated();
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);
