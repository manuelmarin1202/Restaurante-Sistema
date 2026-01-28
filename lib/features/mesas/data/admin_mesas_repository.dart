import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/mesa_model.dart';
import '../../../shared/models/zona_model.dart';

class AdminMesasRepository {
  final _supabase = Supabase.instance.client;

  // --- ZONAS ---
  Future<List<Zona>> getZonas() async {
    final data = await _supabase.from('zonas').select().order('orden');
    return (data as List).map((e) => Zona.fromJson(e)).toList();
  }

  Future<void> upsertZona(int? id, String nombre, String tipo) async {
    final data = {
      'nombre': nombre,
      'tipo': tipo,
    };
    if (id != null) {
      await _supabase.from('zonas').update(data).eq('id', id);
    } else {
      await _supabase.from('zonas').insert(data);
    }
  }

  Future<void> deleteZona(int id) async {
    await _supabase.from('zonas').delete().eq('id', id);
  }

  // --- MESAS ---
  // Nota: Sobrescribimos el getMesas original para que traiga el JOIN de zonas
  Future<List<Mesa>> getMesasConZona() async {
    final data = await _supabase
        .from('mesas')
        .select('*, zonas(nombre)') // <--- JOIN CLAVE
        .order('id');
    return (data as List).map((e) => Mesa.fromJson(e)).toList();
  }

  Future<void> upsertMesa(int? id, String numero, int zonaId) async {
    final data = {
      'numero': numero,
      'zona_id': zonaId,
    };
    if (id != null) {
      await _supabase.from('mesas').update(data).eq('id', id);
    } else {
      // Al crear, estado default es libre
      await _supabase.from('mesas').insert({...data, 'estado': 'libre'});
    }
  }

  Future<void> deleteMesa(int id) async {
    await _supabase.from('mesas').delete().eq('id', id);
  }
}