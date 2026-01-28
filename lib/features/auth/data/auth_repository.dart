import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Iniciar sesión
  Future<void> signIn(String email, String password) async {
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      throw Exception('Error al iniciar sesión: ${e.toString()}');
    }
  }

  // Cerrar sesión
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // Escuchar cambios de estado (Login/Logout)
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
  
  // Obtener usuario actual
  User? get currentUser => _supabase.auth.currentUser;
}