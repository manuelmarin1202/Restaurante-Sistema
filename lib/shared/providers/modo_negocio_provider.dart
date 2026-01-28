import 'package:flutter/foundation.dart'; // Para debugPrint
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final modoNegocioProvider = StateNotifierProvider<ModoNegocioNotifier, String>((ref) {
  return ModoNegocioNotifier();
});

class ModoNegocioNotifier extends StateNotifier<String> {
  ModoNegocioNotifier() : super('MENU') {
    _cargarEstadoInicial();
    _escucharCambiosGlobales();
  }

  final _supabase = Supabase.instance.client;

  // 1. Cargar el turno inicial desde la DB
  Future<void> _cargarEstadoInicial() async {
    try {
      final res = await _supabase
          .from('ajustes_sistema')
          .select('turno_actual')
          .eq('id', 1)
          .maybeSingle();
      
      if (res != null && res['turno_actual'] != null) {
        state = res['turno_actual'];
      }
    } catch (e) {
      debugPrint("⚠️ Error cargando turno inicial: $e");
    }
  }

  // 2. Escuchar cambios en tiempo real
  void _escucharCambiosGlobales() {
    _supabase
      .channel('public:ajustes_sistema')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'ajustes_sistema',
        // Quitamos el 'filter' problemático y filtramos dentro del callback
        callback: (payload) {
          final newRecord = payload.newRecord;
          // Verificamos que sea la fila de configuración (ID 1)
          if (newRecord['id'] == 1 && newRecord['turno_actual'] != null) {
            state = newRecord['turno_actual'];
            debugPrint("🔄 Turno actualizado globalmente a: ${state}");
          }
        },
      )
      .subscribe();
  }

  // 3. Cambiar el turno para TODO EL RESTAURANTE (Base de Datos)
  Future<void> cambiarTurno(String nuevoTurno) async {
    try {
      await _supabase
          .from('ajustes_sistema')
          .update({'turno_actual': nuevoTurno})
          .eq('id', 1);
      
      // Nota: No actualizamos 'state' aquí. 
      // Esperamos a que Supabase nos confirme el cambio vía Realtime (punto 2).
    } catch (e) {
      debugPrint("❌ Error al cambiar turno en base de datos: $e");
    }
  }
}