import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/mesa_model.dart';
//import 'package:flutter/foundation.dart';

class MesasRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Obtener todas las mesas ordenadas por ID
  Future<List<Mesa>> getMesas() async {
    try {
      
      final response = await _supabase
          .from('mesas')
          .select()
          .order('id', ascending: true);
      
      // Convertir la lista de JSONs a lista de objetos Mesa
      final data = response as List<dynamic>;
      return data.map((json) => Mesa.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Error cargando mesas: $e');
    }
  }

  // Escuchar cambios en tiempo real (Para ver cuando una mesa cambia de estado sola)
  Stream<List<Mesa>> mesasStream() {
    return _supabase
        .from('mesas')
        .stream(primaryKey: ['id'])
        .order('id', ascending: true)
        .map((data) => data.map((json) => Mesa.fromJson(json)).toList());
  }
}