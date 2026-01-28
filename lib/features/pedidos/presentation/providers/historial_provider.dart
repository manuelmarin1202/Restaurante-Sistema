import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/pedidos_repository.dart';
import '../../../../shared/utils/menu_calculator.dart';
import '../../../../shared/providers/modo_negocio_provider.dart'; // <--- IMPORTANTE

// 1. ESTADOS DE FILTRO LOCALES
final fechaSeleccionadaProvider = StateProvider<DateTime>((ref) => DateTime.now());
final filtroEstadoProvider = StateProvider<String>((ref) => 'TODOS'); // TODOS, PAGADO, CANCELADO, PENDIENTE
final filtroMetodoProvider = StateProvider<String>((ref) => 'TODOS'); // TODOS, EFECTIVO, YAPE, PLIN, TARJETA

// 2. DATA CRUDA (Trae TODO lo del día de la BD)
final historialPedidosRawProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final fecha = ref.watch(fechaSeleccionadaProvider);
  final repo = ref.watch(pedidosRepositoryProvider);
  return repo.getPedidosPorFecha(fecha);
});

// 3. DATA FILTRADA (La que usa la UI: Lista de pedidos)
final historialFiltradoProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final todos = ref.watch(historialPedidosRawProvider).asData?.value ?? [];
  
  // Filtros de UI
  final estado = ref.watch(filtroEstadoProvider);
  final metodo = ref.watch(filtroMetodoProvider);
  
  // Filtro de Negocio (Turno)
  final turnoActual = ref.watch(modoNegocioProvider); // 'MENU' o 'RESTOBAR'

  return todos.where((p) {
    // A. FILTRO POR TURNO (TOTALITARIO)
    bool perteneceAlTurno = false;
    final turnoPedido = p['turno'];
    
    if (turnoPedido != null) {
      // Si tiene turno guardado, debe coincidir exacto
      perteneceAlTurno = (turnoPedido == turnoActual);
    } else {
      // Fallback para pedidos viejos: Hora de corte 6:00 PM
      final h = DateTime.parse(p['created_at']).toLocal().hour;
      const horaCorte = 18;
      final esDia = turnoActual == 'MENU';
      perteneceAlTurno = esDia ? (h < horaCorte) : (h >= horaCorte);
    }

    if (!perteneceAlTurno) return false; // Si no es del turno, se oculta

    // B. FILTRO ESTADO
    if (estado != 'TODOS' && p['estado'].toString().toUpperCase() != estado) return false;

    // C. FILTRO MÉTODO
    if (metodo != 'TODOS') {
      final pagos = p['pagos'] as List<dynamic>?;
      if (pagos == null || pagos.isEmpty) return false; // Sin pagos no pasa filtro de método
      
      bool coincide = pagos.any((pago) {
        String m = (pago['metodo_pago'] ?? '').toString().toUpperCase();
        if (metodo == 'YAPE') return m.contains('YAPE');
        if (metodo == 'PLIN') return m.contains('PLIN');
        if (metodo == 'TARJETA') return m.contains('TARJETA') || m.contains('IZI');
        if (metodo == 'EFECTIVO') return m.contains('EFECTIVO');
        return false;
      });
      if (!coincide) return false;
    }
    return true;
  }).toList();
});

// 4. TOTAL FILTRADO (Suma de la lista visible actualmente)
final totalFiltradoProvider = Provider<double>((ref) {
  final lista = ref.watch(historialFiltradoProvider);
  return lista.fold(0.0, (sum, p) {
    if (p['estado'] == 'cancelado') return sum;
    
    final pagos = p['pagos'] as List<dynamic>?;
    // Solo sumamos lo cobrado
    if (pagos != null && pagos.isNotEmpty) {
      return sum + pagos.fold(0.0, (s, pay) => s + ((pay['total_pagado'] ?? 0) as num).toDouble());
    }
    return sum; 
  });
});

// 5. RESUMEN GLOBAL DEL TURNO (Caja Total y Tarjetas de Colores)
// Este provider ahora respeta el TURNO, ignorando filtros de estado/método para mostrar la caja real del turno.
final resumenGlobalProvider = Provider<Map<String, double>>((ref) {
  final todos = ref.watch(historialPedidosRawProvider).asData?.value ?? [];
  final turnoActual = ref.watch(modoNegocioProvider); // <--- FILTRO DE TURNO AQUÍ TAMBIÉN

  Map<String, double> resumen = {
    'EFECTIVO': 0.0, 
    'YAPE': 0.0, 
    'PLIN': 0.0, 
    'TARJETA': 0.0
  };

  for (var p in todos) {
    if (p['estado'] == 'cancelado') continue;

    // 1. Validar Turno
    bool perteneceAlTurno = false;
    final turnoPedido = p['turno'];
    if (turnoPedido != null) {
      perteneceAlTurno = (turnoPedido == turnoActual);
    } else {
      final h = DateTime.parse(p['created_at']).toLocal().hour;
      perteneceAlTurno = (turnoActual == 'MENU') ? (h < 18) : (h >= 18);
    }

    if (!perteneceAlTurno) continue; // Saltamos pedidos de otro turno

    // 2. Sumar Pagos
    final pagos = p['pagos'] as List<dynamic>?;
    if (pagos != null) {
      for (var pago in pagos) {
        String m = (pago['metodo_pago'] ?? '').toString().toUpperCase();
        double v = ((pago['total_pagado'] ?? 0) as num).toDouble();
        
        if (m.contains('PLIN')) resumen['PLIN'] = (resumen['PLIN'] ?? 0) + v;
        else if (m.contains('YAPE')) resumen['YAPE'] = (resumen['YAPE'] ?? 0) + v;
        else if (m.contains('TARJETA') || m.contains('IZI')) resumen['TARJETA'] = (resumen['TARJETA'] ?? 0) + v;
        else resumen['EFECTIVO'] = (resumen['EFECTIVO'] ?? 0) + v;
      }
    }
  }
  return resumen;
});