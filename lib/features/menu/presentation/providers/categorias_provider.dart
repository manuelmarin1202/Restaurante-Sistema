import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/categoria_model.dart';
// Asegúrate de importar tu provider de modo (el que creamos antes)
import '../../../../shared/providers/modo_negocio_provider.dart'; 

final categoriasProvider = FutureProvider<List<Categoria>>((ref) async {
  final supabase = Supabase.instance.client;

  // 1. ESCUCHAR EL MODO ACTUAL (Esto hace que se recargue si cambias el switch)
  final modoActual = ref.watch(modoNegocioProvider); // 'MENU' o 'RESTOBAR'

  // 2. Traer todas las categorías activas
  final data = await supabase
      .from('categorias')
      .select()
      .eq('activo', true)
      .order('orden');
  
  final todasLasCategorias = (data as List).map((e) => Categoria.fromJson(e)).toList();

  // 3. FILTRAR SEGÚN EL MODO
  // Regla: Mostramos la categoría si es 'AMBOS' (ej. Bebidas) 
  // O si coincide con el modo actual (ej. MENU == MENU)
  final categoriasFiltradas = todasLasCategorias.where((cat) {
    return cat.tipoCarta == 'AMBOS' || cat.tipoCarta == modoActual;
  }).toList();

  return categoriasFiltradas;
});