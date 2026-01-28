import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/promocion_model.dart';

class PromocionesRepository {
  final _supabase = Supabase.instance.client;

  /// Obtiene todas las promociones activas
  Future<List<Promocion>> obtenerPromocionesActivas({
    required String tipoCarta, 
  }) async {
    final ahora = DateTime.now();
    debugPrint("🔍 [REPO] Buscando promos para: $tipoCarta | Hora: $ahora");

    final data = await _supabase
        .from('promociones')
        .select('''
          *,
          promocion_productos ( *, productos (id, nombre, precio, subtipo, categoria_id) ),
          promocion_adicionales ( *, productos (id, nombre, precio, categoria_id) )
        ''')
        .eq('activo', true)
        .order('nombre');

    final todas = (data as List).map((json) => Promocion.fromJson(json)).toList();
    
    // Filtros en memoria
    final filtradas = todas.where((p) {
      // CORRECCIÓN 1: Manejo seguro de nulos con ( ?? '' )
      final tipoPromo = (p.tipoCarta ?? '').trim().toUpperCase();
      final tipoSolicitado = tipoCarta.trim().toUpperCase();
      
      // Si la promo no tiene tipo carta definido, asumimos que es válida para todo (o no, según tu regla)
      // Aquí asumiremos que si es nulo, es 'AMBOS' por defecto para no perderla.
      final cartaValida = tipoPromo == 'AMBOS' || tipoPromo == tipoSolicitado || tipoPromo.isEmpty;
      
      final tiempoValido = p.estaActivaAhora();
      return cartaValida && tiempoValido;
    }).toList();

    debugPrint("🔍 [REPO] Promos activas tras filtros: ${filtradas.length}");
    return filtradas;
  }

  /// Verifica si un producto tiene promociones activas (Principales o Adicionales)
  Future<List<Promocion>> obtenerPromocionesDeProducto({
    required int productoId,
    required String tipoCarta,
  }) async {
    final promociones = await obtenerPromocionesActivas(tipoCarta: tipoCarta);
    debugPrint("🔍 [REPO] Verificando si el producto ID $productoId pertenece a alguna de las ${promociones.length} promos...");

    return promociones.where((promo) {
      // 1. Buscar en Principales
      bool enPrincipales = promo.productos?.any((pp) => pp.productoId == productoId) ?? false;
      
      // 2. Buscar en Adicionales
      bool enAdicionales = promo.adicionales?.any((pa) => pa.productoId == productoId) ?? false;

      final match = enPrincipales || enAdicionales;
      if (match) debugPrint("   ✅ ¡EUREKA! Producto $productoId encontrado en Promo '${promo.nombre}'");
      
      return match;
    }).toList();
  }

  /// Calcula el precio y determina si hay promo activa
  Future<PrecioPromocionResult> calcularPrecioConPromocion({
    required int productoId,
    required double precioBase,
    required String tipoCarta,
  }) async {
    final promociones = await obtenerPromocionesDeProducto(
      productoId: productoId,
      tipoCarta: tipoCarta,
    );

    if (promociones.isEmpty) {
      return PrecioPromocionResult(precioFinal: precioBase, tienePromocion: false);
    }

    Promocion? mejorPromo;
    double mejorPrecio = precioBase;

    for (var promo in promociones) {
      final tipoString = promo.tipoPromocion.toString().toLowerCase().replaceAll(RegExp(r'[._]'), '');
      
      // CASO A: DESCUENTO SIMPLE (Solo importa si baja el precio)
      if (tipoString.contains('preciosimple')) {
          if (promo.productos != null) {
             try {
               final productoPromo = promo.productos!.firstWhere((pp) => pp.productoId == productoId);
               // Solo aplicamos si MEJORA el precio base
               if (productoPromo.precioPromocional != null && productoPromo.precioPromocional! < mejorPrecio) {
                  mejorPrecio = productoPromo.precioPromocional!;
                  mejorPromo = promo;
               }
             } catch (_) {}
          }
      }
      
      // CASO B: COMBO PRODUCTO (Alitas + Jarra)
      else if (tipoString.contains('comboproducto')) {
          if (promo.productos != null) {
             try {
               final productoPromo = promo.productos!.firstWhere((pp) => pp.productoId == productoId);
               
               // CORRECCIÓN 2: Usamos 'esPrincipal' en lugar de 'esProductoPrincipal'
               if (productoPromo.esPrincipal) {
                  if (productoPromo.precioPromocional != null) {
                    mejorPrecio = productoPromo.precioPromocional!;
                  }
                  mejorPromo = promo; // ¡GANADOR! Activamos el modal
               }
             } catch (_) {}
          }
      }
      
      // CASO C: COMBO MÚLTIPLE (2 Tragos x 25)
      else if (tipoString.contains('combomultiple')) {
         mejorPromo = promo; // La sola existencia activa el selector
      }
    }

    return PrecioPromocionResult(
      precioFinal: mejorPrecio,
      tienePromocion: mejorPromo != null,
      promocion: mejorPromo,
      descuento: precioBase - mejorPrecio,
    );
  }

  /// Obtiene los adicionales agrupados
  Map<String, List<PromocionAdicional>> obtenerAdicionalesAgrupados(Promocion promocion) {
    if (promocion.adicionales == null || promocion.adicionales!.isEmpty) return {};

    final Map<String, List<PromocionAdicional>> grupos = {};
    for (var adicional in promocion.adicionales!) {
      final grupo = adicional.grupoSeleccion ?? 'default';
      grupos.putIfAbsent(grupo, () => []);
      grupos[grupo]!.add(adicional);
    }
    return grupos;
  }
}

class PrecioPromocionResult {
  final double precioFinal;
  final bool tienePromocion;
  final Promocion? promocion;
  final double descuento;

  PrecioPromocionResult({
    required this.precioFinal,
    required this.tienePromocion,
    this.promocion,
    this.descuento = 0.0,
  });
}

final promocionesRepositoryProvider = Provider((ref) => PromocionesRepository());