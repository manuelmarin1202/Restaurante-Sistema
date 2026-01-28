import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/auth_repository.dart';

// 1. Instancia del Repositorio
final authRepositoryProvider = Provider((ref) => AuthRepository());

// 2. Stream que nos dice si hay usuario o no en tiempo real
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// 3. Controller para manejar el Login en la UI
class AuthController extends StateNotifier<AsyncValue<void>> {
  final AuthRepository _repo;

  AuthController(this._repo) : super(const AsyncValue.data(null));

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      await _repo.signIn(email, password);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
  
  Future<void> logout() async {
    await _repo.signOut();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});