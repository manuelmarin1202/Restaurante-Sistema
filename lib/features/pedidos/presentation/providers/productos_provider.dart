import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/producto_model.dart';
import '../../../../shared/providers/modo_negocio_provider.dart';
//import '../../../menu/presentation/providers/admin_productos_provider.dart';


// 1. PROVIDER "EN VIVO" (Stream)
// Este provider mantiene una conexión abierta con Supabase.
// Si alguien cambia algo en la tabla 'productos' (desde PC, otro cel o base de datos),
// este provider se actualiza solo y avisa a toda la app.
final productosListProvider = StreamProvider<List<Producto>>((ref) {
  return Supabase.instance.client
      .from('productos')
      .stream(primaryKey: ['id']) // Escucha cambios basados en el ID
      .order('nombre')            // Ordena alfabéticamente
      .map((data) {
        // Convierte la lista de mapas (JSON) a lista de objetos Producto
        return data.map((e) => Producto.fromJson(e)).toList();
      });
});

// 2. PROVIDER FILTRADO (Ya lo tenías, solo confirma que use el de arriba)
// Este escucha al de arriba. Si la lista "En Vivo" cambia, este se recalcula solo.
// Provider FILTRADO INTELIGENTE
final productosPorCategoriaProvider = Provider.family<List<Producto>, int>((ref, categoriaId) {
  // 1. Traemos todos los productos (En vivo)
  final todos = ref.watch(productosListProvider).asData?.value ?? [];
  
  // 2. Traemos el MODO ACTUAL (Menu o Restobar)
  final modoActual = ref.watch(modoNegocioProvider);

  return todos.where((p) {
    // CONDICIÓN 1: Que sea de la categoría correcta
    final esCategoria = p.categoriaId == categoriaId;
    
    // CONDICIÓN 2: Que esté activo
    final esActivo = p.activo == true;

    // CONDICIÓN 3 (NUEVA): Que coincida con el turno
    // Se muestra si es del modo actual O si es 'AMBOS' (ej. Gaseosa)
    final esTurnoCorrecto = (p.tipoCarta == 'AMBOS' || p.tipoCarta == modoActual);

    return esCategoria && esActivo && esTurnoCorrecto;
  }).toList();
});