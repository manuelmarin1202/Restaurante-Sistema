import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Modelo simple para manejar los pagos parciales internamente
class PagoParcial {
  final String metodo;
  final double monto;
  final double? recibido; 

  PagoParcial({required this.metodo, required this.monto, this.recibido});
}

class PagosRepository {
  final _supabase = Supabase.instance.client;

  Future<void> procesarCobroMultiple({
    required int pedidoId,
    required int mesaId,
    required double totalTotal,
    required List<PagoParcial> listaPagos,
    required bool imprimirTicket,
    String? clienteNombre,
  }) async {
    final user = _supabase.auth.currentUser;
    final userId = user?.id;
    if (userId == null) throw Exception('Usuario no autenticado');

    // DEBUG: Ver qué nombre llega al repositorio
    print('🗄️ [PAGOS_REPO] procesarCobroMultiple llamado');
    print('   - pedidoId: $pedidoId');
    print('   - clienteNombre recibido: "$clienteNombre"');

    // 1. ACTUALIZACIÓN ATÓMICA CON VERIFICACIÓN DE ESTADO
    // Intentamos actualizar SOLO si el estado es 'pendiente'
    // Esto evita la condición de carrera usando una actualización condicional
    final resultadoActualizacion = await _supabase
        .from('pedidos')
        .update({
          'estado': 'pagado',
          'nombre_cliente': clienteNombre,
        })
        .eq('id', pedidoId)
        .eq('estado', 'pendiente') // ← CLAVE: Solo actualiza si está pendiente
        .select();

    print('   ✅ Pedido actualizado en BD con nombre_cliente: "$clienteNombre"');

    // Si no se actualizó ninguna fila, significa que ya estaba pagado o no existe
    if (resultadoActualizacion.isEmpty) {
      // Verificamos el estado actual para dar un mensaje más específico
      final pedidoActual = await _supabase
          .from('pedidos')
          .select('estado')
          .eq('id', pedidoId)
          .maybeSingle();

      if (pedidoActual == null) {
        throw Exception('El pedido no existe.');
      }
      if (pedidoActual['estado'] == 'pagado') {
        throw Exception('Este pedido YA fue cobrado anteriormente.');
      }
      if (pedidoActual['estado'] == 'cancelado') {
        throw Exception('Este pedido fue cancelado y no puede cobrarse.');
      }
      throw Exception('No se pudo procesar el cobro. Intente nuevamente.');
    }

    // 2. Insertar Pagos (solo si la actualización fue exitosa)
    final pagosBatch = listaPagos.map((p) => {
      'id_pedido': pedidoId,
      'total_pagado': p.monto,
      'metodo_pago': p.metodo,
      'tipo_comprobante': 'BOLETA',
      'fecha_hora_pago': DateTime.now().toIso8601String(),
      'cajero_id': userId,
    }).toList();

    try {
      await _supabase.from('pagos').insert(pagosBatch);
    } catch (e) {
      // Si falla la inserción de pagos, revertimos el estado del pedido
      await _supabase.from('pedidos').update({
        'estado': 'pendiente',
        'nombre_cliente': null,
      }).eq('id', pedidoId);
      throw Exception('Error al registrar los pagos: $e');
    }

    // 3. Liberar Mesa
    try {
      await _supabase.from('mesas').update({
        'estado': 'libre'
      }).eq('id', mesaId);
    } catch (e) {
      // Si falla la liberación de mesa, no revertimos (el pedido ya está pagado)
      // Solo registramos el error pero continuamos
      print('Advertencia: No se pudo liberar la mesa $mesaId: $e');
    }

    // 4. Cola de Impresión
    if (imprimirTicket) {
      try {
        final desglosePagos = listaPagos.map((p) => {
          'metodo': p.metodo,
          'monto': p.monto
        }).toList();

        await _supabase.from('cola_impresion').insert({
          'pedido_id': pedidoId,
          'tipo_ticket': 'cuenta',
          'estado': 'pendiente',
          'destino': 'caja_principal',
          'datos_extra': {
            'es_pago_dividido': true,
            'desglose_pagos': desglosePagos,
            'total_cobrado': totalTotal
          }
        });
      } catch (e) {
        // Si falla la impresión, no afecta el cobro exitoso
        print('Advertencia: No se pudo encolar la impresión: $e');
      }
    }
  }
}

final pagosRepositoryProvider = Provider((ref) => PagosRepository());