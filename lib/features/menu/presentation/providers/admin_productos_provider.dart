import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Necesario para stream
import '../../../../shared/models/producto_model.dart';
import '../../data/productos_repository.dart';

final productosRepoProvider = Provider((ref) => ProductosRepository());

// CAMBIAMOS FutureProvider POR StreamProvider
final productosListProvider = StreamProvider<List<Producto>>((ref) {
  // Escuchamos la tabla 'productos' en tiempo real
  return Supabase.instance.client
      .from('productos')
      .stream(primaryKey: ['id'])
      .order('nombre')
      .map((data) => data.map((json) => Producto.fromJson(json)).toList());
});