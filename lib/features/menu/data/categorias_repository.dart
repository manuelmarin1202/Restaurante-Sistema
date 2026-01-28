import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/categoria_model.dart';

class CategoriasRepository {
  final _supabase = Supabase.instance.client;

  // LEER
  Future<List<Categoria>> getCategorias() async {
    final data = await _supabase
        .from('categorias')
        .select()
        .order('orden', ascending: true); // Importante: Respetar el orden visual
    return (data as List).map((e) => Categoria.fromJson(e)).toList();
  }

  // CREAR O ACTUALIZAR (Upsert)
  Future<void> upsertCategoria({
    int? id, 
    required String nombre, 
    required int orden, 
    required bool activo
  }) async {
    final data = {
      'nombre': nombre,
      'orden': orden,
      'activo': activo,
    };

    if (id != null) {
      // Actualizar
      await _supabase.from('categorias').update(data).eq('id', id);
    } else {
      // Crear
      await _supabase.from('categorias').insert(data);
    }
  }

  // ELIMINAR
  // Nota: Si la categoría tiene productos, esto podría fallar por la llave foránea.
  // En ese caso, lo mejor es desactivarla (activo = false) en lugar de borrarla.
  Future<void> deleteCategoria(int id) async {
    try {
      await _supabase.from('categorias').delete().eq('id', id);
    } catch (e) {
      throw Exception('No se puede borrar: Probablemente tiene productos asociados. Intenta desactivarla.');
    }
  }
}