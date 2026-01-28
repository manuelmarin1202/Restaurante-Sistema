import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../presentation/providers/carrito_provider.dart';
import '../../../../shared/models/producto_model.dart';

class PedidosRepository {
  final _supabase = Supabase.instance.client;

  // CONSTANTES DE PRECIOS (sincronizadas con carrito_provider.dart)
  static const double precioPromoSegundoSolo = 10.00;
  static const double precioEntradaExtra = 5.00;

  // --- LÓGICA DE NEGOCIO GLOBAL ---
  // --- LÓGICA DE NEGOCIO GLOBAL CON DEBUGGER ---
  List<Map<String, dynamic>> _recalcularPreciosYEstructura(List<CartItem> todosLosItems, int pedidoId) {
    debugPrint("\n🛑 === INICIO DEBUG RECALCULO (Pedido $pedidoId) ===");
    
    // 1. Aplanar todo y CLASIFICAR
    List<Map<String, dynamic>> bolsaEntradas = [];
    List<Map<String, dynamic>> bolsaSegundos = [];
    List<Map<String, dynamic>> bolsaOtros = [];
    List<Map<String, dynamic>> bolsaCortesias = [];

    for (var item in todosLosItems) {
      debugPrint("   -> Item Entrante: ${item.producto.nombre} | Subtipo: ${item.producto.subtipo} | Cant: ${item.cantidad}");
      
      for (int i = 0; i < item.cantidad; i++) {
        final itemMap = {
          'producto': item.producto,
          'notas': item.notas,
          'precio_base': item.precioEfectivo,
        };

        // --- CORRECCIÓN CRÍTICA ---
        // ANTES: final esCortesia = item.precioEfectivo == 0.00 || (item.notas != null ...);
        // El problema era que si venía de un menú anterior, valía 0 y se colaba como cortesía.
        
        // AHORA: Solo es cortesía si la nota lo grita o si el producto base es gratis.
        final bool notaDiceCortesia = item.notas != null && item.notas!.toUpperCase().contains('CORTESÍA');
        final bool productoEsGratisDeFabrica = item.producto.precio == 0.00;

        final esCortesia = notaDiceCortesia || productoEsGratisDeFabrica;

        if (esCortesia) {
          debugPrint("   🎁 Detectado como Cortesía: ${item.producto.nombre}");
          bolsaCortesias.add(itemMap);
        } else if (item.producto.subtipo == 'ENTRADA') {
          bolsaEntradas.add(itemMap);
        } else if (item.producto.subtipo == 'SEGUNDO') {
          bolsaSegundos.add(itemMap);
        } else {
          debugPrint("      ⚠️ ALERTA: ${item.producto.nombre} se fue a OTROS");
          bolsaOtros.add(itemMap);
        }
      }
    }

    debugPrint("📊 CONTEO BOLSAS:");
    debugPrint("   - Entradas: ${bolsaEntradas.length}");
    debugPrint("   - Segundos: ${bolsaSegundos.length}");
    debugPrint("   - Otros: ${bolsaOtros.length}");

    // 2. Emparejar Menús
    int nMenus = (bolsaEntradas.length < bolsaSegundos.length) 
        ? bolsaEntradas.length 
        : bolsaSegundos.length;
    
    debugPrint("🧮 CÁLCULO MENÚS: Se formarán $nMenus menús completos.");

    // Ordenar para priorizar segundos caros en el menú (si los hubiera)
    bolsaSegundos.sort((a, b) => (b['precio_base'] as double).compareTo(a['precio_base'] as double));

    List<Map<String, dynamic>> itemsProcesados = [];

    // Procesar Cortesías
    for (var item in bolsaCortesias) {
      item['precio_final'] = 0.00;
      itemsProcesados.add(item);
    }

    // Procesar Segundos
    for (int i = 0; i < bolsaSegundos.length; i++) {
      var item = bolsaSegundos[i];
      double precioAsignado;
      
      if (i < nMenus) {
        precioAsignado = 13.00; // ES MENÚ
        debugPrint("   ✅ Segundo en Menú (${(item['producto'] as Producto).nombre}): S/. 13.00");
      } else {
        precioAsignado = 10.00; // ES SOLO
        debugPrint("   ⚠️ Segundo Solo (${(item['producto'] as Producto).nombre}): S/. 10.00");
      }
      item['precio_final'] = precioAsignado;
      itemsProcesados.add(item);
    }

    // Procesar Entradas
    for (int i = 0; i < bolsaEntradas.length; i++) {
      var item = bolsaEntradas[i];
      double precioAsignado;

      if (i < nMenus) {
        precioAsignado = 0.00; // DENTRO DE MENÚ
        debugPrint("   ✅ Entrada en Menú (${(item['producto'] as Producto).nombre}): S/. 0.00");
      } else {
        // EXTRA (Huérfana)
        double precioReal = (item['producto'] as Producto).precio;
        if (precioReal <= 0) {
           precioAsignado = 5.00; 
        } else {
           precioAsignado = precioReal;
        }
        debugPrint("   ⚠️ Entrada Sola (${(item['producto'] as Producto).nombre}): S/. $precioAsignado");
      }
      item['precio_final'] = precioAsignado;
      itemsProcesados.add(item);
    }

    // Procesar Otros
    for (var item in bolsaOtros) {
      item['precio_final'] = item['precio_base'];
      itemsProcesados.add(item);
    }

    debugPrint("🛑 === FIN DEBUG RECALCULO ===\n");

    // 3. Re-agrupar para BD (Tu código original sigue aquí)
    Map<String, Map<String, dynamic>> agrupados = {};
    for (var item in itemsProcesados) {
      final prod = item['producto'] as Producto;
      final precio = item['precio_final'] as double;
      final notas = item['notas'] ?? '';
      final key = '${prod.id}|$notas|$precio';

      if (!agrupados.containsKey(key)) {
        agrupados[key] = {
          'pedido_id': pedidoId,
          'producto_id': prod.id,
          'cantidad': 0,
          'precio_unitario': precio,
          'notas': notas,
          'estado': 'en_cola'
        };
      }
      agrupados[key]!['cantidad'] += 1;
    }

    return agrupados.values.toList().cast<Map<String, dynamic>>();
  }

  // --- CREAR PEDIDO ---
  Future<void> crearPedido({
    required int mesaId,
    required List<CartItem> items,
    required double total,
    String? nombreCliente,
    String? horaRecojo,
    bool imprimirTicket = true,
    required String turno,
  }) async {
    final userId = _supabase.auth.currentUser!.id;

    final pedido = await _supabase.from('pedidos').insert({
      'mesa_id': mesaId,
      'usuario_id': userId,
      'estado': 'pendiente',
      'total': total,
      'nombre_cliente': nombreCliente,
      'hora_recojo': horaRecojo,
      'turno': turno,
    }).select().single();

    final int pedidoId = pedido['id'];

    final filasAInsertar = _recalcularPreciosYEstructura(items, pedidoId);
    await _supabase.from('detalle_pedido').insert(filasAInsertar);

    await _supabase.from('mesas').update({'estado': 'ocupada'}).eq('id', mesaId);

    // Detectar si es para llevar (tiene hora de recojo)
    final bool esParaLlevar = horaRecojo != null;
    // SIEMPRE registrar en cola (para bitácora), pero con estado diferente si no debe imprimir
    await _registrarEnCola(pedidoId, items, esAdicional: false, esParaLlevar: esParaLlevar, debeImprimir: imprimirTicket);
  }

  // --- AGREGAR A PEDIDO (SINCRONIZADO) ---
  Future<void> agregarItemsAPedido({
    required int pedidoId,
    required List<CartItem> items,
    bool imprimirTicket = true,
    bool esParaLlevar = false,  // NUEVO: Para indicar en la comanda
  }) async {
    debugPrint("🔄 [REPO] Recalculando pedido #$pedidoId...");

    // 1. Obtener lo viejo
    final existingData = await _supabase
        .from('detalle_pedido')
        .select('*, productos(*)')
        .eq('pedido_id', pedidoId);

    List<CartItem> itemsViejos = existingData.map((d) {
      final prodJson = d['productos'];
      prodJson['id'] = d['producto_id'];
      return CartItem(
        producto: Producto.fromJson(prodJson),
        cantidad: d['cantidad'],
        notas: d['notas'],
        precioPromocional: (d['precio_unitario'] as num).toDouble(),
      );
    }).toList();

    // 2. Unir con lo nuevo
    List<CartItem> todos = [...itemsViejos, ...items]; // <--- Usamos 'items'

    // 3. Recalcular
    final filasCorregidas = _recalcularPreciosYEstructura(todos, pedidoId);

    // 4. Reemplazar en BD
    await _supabase.from('detalle_pedido').delete().eq('pedido_id', pedidoId);
    await _supabase.from('detalle_pedido').insert(filasCorregidas);

    // 5. Actualizar Total
    double nuevoTotal = 0;
    for(var f in filasCorregidas) nuevoTotal += (f['cantidad'] * f['precio_unitario']);
    
    await _supabase.from('pedidos').update({
      'total': nuevoTotal,
      'updated_at': DateTime.now().toIso8601String()
    }).eq('id', pedidoId);

    // 6. Registrar en cola (SIEMPRE para bitácora, con estado diferente si no debe imprimir)
    await _registrarEnCola(pedidoId, items, esAdicional: true, esParaLlevar: esParaLlevar, debeImprimir: imprimirTicket);
  }

  // --- ELIMINAR DETALLE ---
  Future<void> eliminarDetalle(int detalleId, int pedidoId) async {
    final existingData = await _supabase
        .from('detalle_pedido')
        .select('*, productos(*)')
        .eq('pedido_id', pedidoId);
    
    final itemsParaConservar = existingData.where((d) => d['id'] != detalleId).toList();

    if (itemsParaConservar.isEmpty) {
       await _supabase.from('detalle_pedido').delete().eq('pedido_id', pedidoId);
       await _supabase.from('pedidos').update({'total': 0}).eq('id', pedidoId);
       return;
    }

    List<CartItem> itemsRecalculo = itemsParaConservar.map((d) {
      final prodJson = d['productos'];
      prodJson['id'] = d['producto_id'];
      return CartItem(
        producto: Producto.fromJson(prodJson),
        cantidad: d['cantidad'],
        notas: d['notas'],
        precioPromocional: (d['precio_unitario'] as num).toDouble(),
      );
    }).toList();

    final filasCorregidas = _recalcularPreciosYEstructura(itemsRecalculo, pedidoId);

    await _supabase.from('detalle_pedido').delete().eq('pedido_id', pedidoId);
    await _supabase.from('detalle_pedido').insert(filasCorregidas);

    double nuevoTotal = 0;
    for(var f in filasCorregidas) nuevoTotal += (f['cantidad'] * f['precio_unitario']);
    await _supabase.from('pedidos').update({'total': nuevoTotal}).eq('id', pedidoId);
  }

  // Helper impresión - SIEMPRE registra en la cola (para bitácora)

  Future<void> _registrarEnCola(
    int pedidoId,
    List<CartItem> items,
    {required bool esAdicional, bool esParaLlevar = false, bool debeImprimir = true}
  ) async {
    final itemsTicket = items.map((item) => {
      'nombre_producto_temporal': item.producto.nombre,
      'cantidad': item.cantidad,
      'notas': item.notas,
      'categoria_id': item.producto.categoriaId,
    }).toList();

    // Si debeImprimir=false, guardamos con estado 'omitido' para que sirva de registro
    // pero el listener de impresión no lo procese
    final String estadoInicial = debeImprimir ? 'pendiente' : 'omitido';

    await _supabase.from('cola_impresion').insert({
      'pedido_id': pedidoId,
      'tipo_ticket': 'comanda',
      'estado': estadoInicial,
      'datos_extra': {
        'es_adicional': esAdicional,
        'items_nuevos': itemsTicket,
        'es_para_llevar': esParaLlevar,
        'impresion_solicitada': debeImprimir,  // Registro de la decisión del usuario
      }
    });
  }

  // --- MÉTODOS AUXILIARES ---
  Future<Map<String, dynamic>?> obtenerPedidoActual(int mesaId) async {
    return await _supabase.from('pedidos').select('*, detalle_pedido(*, productos(nombre, subtipo, precio))')
        .eq('mesa_id', mesaId).eq('estado', 'pendiente').order('created_at', ascending: false).limit(1).maybeSingle();
  }

  Future<void> anularPedido(int pedidoId, int mesaId) async {
    await _supabase.from('pedidos').update({'estado': 'cancelado'}).eq('id', pedidoId);
    await _supabase.from('mesas').update({'estado': 'libre'}).eq('id', mesaId);
  }

  Future<void> imprimirPreCuenta(int pedidoId) async {
    await _supabase.from('cola_impresion').insert({
      'pedido_id': pedidoId, 'tipo_ticket': 'cuenta', 'estado': 'pendiente', 'destino': 'caja_principal', 'datos_extra': {'es_precuenta': true}
    });
  }

  Future<void> cambiarMesa({required int pedidoId, required int mesaOrigenId, required int mesaDestinoId}) async {
      try {
      final mesaDestino = await _supabase.from('mesas').select('id, estado').eq('id', mesaDestinoId).maybeSingle();
      if (mesaDestino == null || mesaDestino['estado'] != 'libre') throw Exception('Mesa destino ocupada o no existe.');
      
      await _supabase.from('pedidos').update({'mesa_id': mesaDestinoId}).eq('id', pedidoId);
      await _supabase.from('mesas').update({'estado': 'ocupada'}).eq('id', mesaDestinoId);
      await _supabase.from('mesas').update({'estado': 'libre'}).eq('id', mesaOrigenId);
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  Future<void> liberarMesaSinPedido(int mesaId) async {
    await _supabase.from('mesas').update({'estado': 'libre'}).eq('id', mesaId);
  }
  
  Future<void> reimprimirCuentaFinal(int pedidoId) async {
    final pagosData = await _supabase.from('pagos').select('metodo_pago, total_pagado').eq('id_pedido', pedidoId);
    double totalCobrado = 0.0;
    final List<Map<String, dynamic>> desglosePagos = [];
    for (var p in pagosData) {
      final monto = (p['total_pagado'] as num).toDouble();
      totalCobrado += monto;
      desglosePagos.add({'metodo': p['metodo_pago'], 'monto': monto});
    }
    await _supabase.from('cola_impresion').insert({
      'pedido_id': pedidoId,
      'tipo_ticket': 'cuenta',
      'estado': 'pendiente',
      'destino': 'caja_principal',
      'datos_extra': {
        'es_pago_dividido': true,
        'desglose_pagos': desglosePagos,
        'total_cobrado': totalCobrado
      }
    });
  }

  Future<Map<String, dynamic>> obtenerPedidoPorId(int pedidoId) async {
    return await _supabase.from('pedidos').select('''
          *,
          detalle_pedido(*, productos(*)),
          mesas(numero),
          perfiles(nombre_completo),
          pagos(id_pago, metodo_pago, total_pagado, fecha_hora_pago, cajero_id, perfiles:cajero_id ( nombre_completo ))
        ''').eq('id', pedidoId).single();
  }

  Future<List<Map<String, dynamic>>> getPedidosPorFecha(DateTime fechaSeleccionada) async {
    final inicio = DateTime(fechaSeleccionada.year, fechaSeleccionada.month, fechaSeleccionada.day, 0, 0, 0);
    final fin = DateTime(fechaSeleccionada.year, fechaSeleccionada.month, fechaSeleccionada.day, 23, 59, 59);
    try {
      final data = await _supabase.from('pedidos').select('''
            *, mesas(numero), perfiles!usuario_id(id, nombre_completo),
            pagos(metodo_pago, total_pagado, fecha_hora_pago, cajero_id, cajero:cajero_id(id, nombre_completo)),
            detalle_pedido(cantidad, precio_unitario, productos(nombre, subtipo, categorias(nombre, orden)))
          ''')
          .gte('created_at', inicio.toUtc().toIso8601String())
          .lte('created_at', fin.toUtc().toIso8601String())
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      throw Exception('Error cargando historial: $e');
    }
  }

  // Método para actualizar los métodos de pago de un pedido existente
  Future<void> actualizarMetodosPago(int pedidoId, List<Map<String, dynamic>> nuevosPagos) async {
    try {
      // DEBUG: Ver qué datos llegan
      print('🔄 [REPO] actualizarMetodosPago - pedidoId: $pedidoId');
      print('   Cantidad de pagos a actualizar: ${nuevosPagos.length}');

      // Actualizar cada pago en la base de datos
      for (var pago in nuevosPagos) {
        final pagoId = pago['id'] ?? pago['id_pago']; // Soportar ambos nombres
        final nuevoMetodo = pago['metodo_pago'];

        print('   - Actualizando pago ID: $pagoId a método: $nuevoMetodo');

        if (pagoId == null) {
          print('   ⚠️ ERROR: No se encontró ID del pago en: $pago');
          continue; // Saltar este pago
        }

        await _supabase
            .from('pagos')
            .update({
              'metodo_pago': nuevoMetodo,
            })
            .eq('id_pago', pagoId); // Usar id_pago en lugar de id

        print('   ✅ Pago $pagoId actualizado correctamente');
      }

      print('✅ [REPO] Todos los pagos actualizados exitosamente');
    } catch (e) {
      print('❌ [REPO] Error actualizando métodos de pago: $e');
      throw Exception('Error actualizando métodos de pago: $e');
    }
  }
}

final pedidosRepositoryProvider = Provider((ref) => PedidosRepository());