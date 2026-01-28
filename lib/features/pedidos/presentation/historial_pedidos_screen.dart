import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../../shared/widgets/app_drawer.dart';
import 'providers/historial_provider.dart';
import '../services/reporte_service.dart';
import '../../../../shared/providers/modo_negocio_provider.dart';
import '../../../../shared/utils/menu_calculator.dart';
// Importamos el repositorio solo para el refresh
import '../data/pedidos_repository.dart'; 

class HistorialPedidosScreen extends ConsumerWidget {
  const HistorialPedidosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fecha = ref.watch(fechaSeleccionadaProvider);
    
    // Providers para la data
    final historialRaw = ref.watch(historialPedidosRawProvider); // Para saber si carga
    final pedidosFiltrados = ref.watch(historialFiltradoProvider);
    final resumenGlobal = ref.watch(resumenGlobalProvider);
    
    // Cálculo seguro del total (si está vacío, 0)
    final totalCajaDia = resumenGlobal.values.isNotEmpty 
        ? resumenGlobal.values.reduce((a, b) => a + b) 
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Historial', style: TextStyle(fontSize: 16)),
            Text(
              DateFormat('EEEE d MMMM', 'es_PE').format(fecha).toUpperCase(), 
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(historialPedidosRawProvider),
          ),
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () {
              final modoActual = ref.read(modoNegocioProvider); 
              
              historialRaw.whenData((pedidos) {
                final pedidosFiltradosPrint = pedidos.where((p) {
                  final turnoPedido = p['turno']; 
                  
                  if (turnoPedido != null) {
                    return turnoPedido == modoActual; 
                  } else {
                    final h = DateTime.parse(p['created_at']).toLocal().hour;
                    const horaCorte = 18;
                    final esDia = modoActual == 'MENU';
                    return esDia ? h < horaCorte : h >= horaCorte;
                  }
                }).toList();

                if (pedidosFiltradosPrint.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sin ventas en turno $modoActual'))
                  );
                  return;
                }
                
                final titulo = modoActual == 'MENU' ? 'CIERRE MENÚ (DÍA)' : 'CIERRE RESTOBAR (NOCHE)';
                ReporteService().imprimirCierreDia(pedidosFiltradosPrint, fecha, tituloReporte: titulo);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _seleccionarFecha(context, ref, fecha),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. RESUMEN DE CAJA
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('CAJA TOTAL DEL DÍA', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    Text(
                      'S/. ${totalCajaDia.toStringAsFixed(2)}', 
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.green)
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MiniCard('Efectivo', resumenGlobal['EFECTIVO'] ?? 0, Colors.green),
                    const SizedBox(width: 5),
                    _MiniCard('Yape', resumenGlobal['YAPE'] ?? 0, Colors.purple),
                    const SizedBox(width: 5),
                    _MiniCard('Plin', resumenGlobal['PLIN'] ?? 0, Colors.pink),
                    const SizedBox(width: 5),
                    _MiniCard('Tarjeta', resumenGlobal['TARJETA'] ?? 0, Colors.blue),
                  ],
                )
              ],
            ),
          ),
          
          // 2. FILTROS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Icon(Icons.filter_list, size: 20, color: Colors.grey),
                  const SizedBox(width: 10),
                  _FiltroChip(
                    label: 'Estado', 
                    options: const ['TODOS', 'PAGADO', 'PENDIENTE', 'CANCELADO'], 
                    provider: filtroEstadoProvider
                  ),
                  const SizedBox(width: 10),
                  _FiltroChip(
                    label: 'Método', 
                    options: const ['TODOS', 'EFECTIVO', 'YAPE', 'PLIN', 'TARJETA'], 
                    provider: filtroMetodoProvider
                  ),
                ],
              ),
            ),
          ),

          // 3. LISTADO
          Expanded(
            child: historialRaw.isLoading 
              ? const Center(child: CircularProgressIndicator()) 
              : pedidosFiltrados.isEmpty 
                ? const Center(child: Text('No hay pedidos con estos filtros', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 80),
                    itemCount: pedidosFiltrados.length,
                    itemBuilder: (context, index) {
                      return _PedidoCard(pedido: pedidosFiltrados[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _seleccionarFecha(BuildContext context, WidgetRef ref, DateTime actual) async {
    final picked = await showDatePicker(
      context: context, 
      initialDate: actual, 
      firstDate: DateTime(2023), 
      lastDate: DateTime.now(),
      locale: const Locale("es", "PE")
    );
    if (picked != null) ref.read(fechaSeleccionadaProvider.notifier).state = picked;
  }
}

// TARJETA DE PEDIDO
class _PedidoCard extends StatelessWidget {
  final Map<String, dynamic> pedido;
  const _PedidoCard({required this.pedido});

  @override
  Widget build(BuildContext context) {
    // FECHAS
    final fechaPedido = DateTime.parse(pedido['created_at']).toLocal();
    String horaPedido = DateFormat('HH:mm').format(fechaPedido);
    
    // DATOS DE PAGO Y CAJERO
    String? horaPago;
    String cajeroNombreCompleto = '';
    
    final pagos = pedido['pagos'] as List<dynamic>?;
    if (pagos != null && pagos.isNotEmpty) {
      final ultimoPago = pagos.last;
      
      if (ultimoPago['fecha_hora_pago'] != null) {
        horaPago = DateFormat('HH:mm').format(
          DateTime.parse(ultimoPago['fecha_hora_pago']).toLocal()
        );
      }
      
      final cajeroData = ultimoPago['perfiles']; // <-- Corregido nombre de relación
      if (cajeroData != null && cajeroData is Map<String, dynamic>) {
        cajeroNombreCompleto = cajeroData['nombre_completo'] as String? ?? '';
      }
    }

    // MOZO
    String mozoNombreCompleto = 'Mozo';
    final mozoData = pedido['perfiles'];
    if (mozoData != null && mozoData is Map<String, dynamic>) {
      mozoNombreCompleto = mozoData['nombre_completo'] as String? ?? 'Mozo';
    }

    // TOTAL Y ESTADO
    final estado = (pedido['estado']?.toString() ?? 'PENDIENTE').toUpperCase();
    double total = 0;
    
    // TEXTO MÉTODOS
    Widget widgetMetodos;
    if (pagos != null && pagos.isNotEmpty) {
      total = pagos.fold(0.0, (sum, p) {
        final pagado = (p['total_pagado'] ?? 0) as num;
        return sum + pagado.toDouble();
      });

      List<String> detallesPago = [];
      for (var p in pagos) {
        String m = (p['metodo_pago'] ?? '?').toString().toUpperCase();
        if (m.contains('YAPE')) m = 'YAPE';
        else if (m.contains('PLIN')) m = 'PLIN';
        else if (m.contains('TARJETA')) m = 'TARJETA';
        else m = 'EFECTIVO';
        
        double v = ((p['total_pagado'] ?? 0) as num).toDouble();
        detallesPago.add('$m: ${v.toStringAsFixed(2)}');
      }
      
      widgetMetodos = Text(
        detallesPago.join(' / '), 
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)
      );
    } else {
      // CORRECCIÓN: Suma directa de la BD, no MenuCalculator
      if (pedido['detalle_pedido'] != null) {
        final detalles = List<dynamic>.from(pedido['detalle_pedido']);
        total = detalles.fold(0.0, (sum, item) {
           final cant = (item['cantidad'] ?? 0) as num;
           final prec = (item['precio_unitario'] ?? 0) as num;
           return sum + (cant * prec);
        });
      } else {
        total = ((pedido['total'] ?? 0) as num).toDouble();
      }
      widgetMetodos = const Text('PENDIENTE DE PAGO', style: TextStyle(fontSize: 11, color: Colors.orange));
    }

    Color colorEstado = Colors.blue;
    if (estado == 'PAGADO') colorEstado = Colors.green;
    if (estado == 'CANCELADO') colorEstado = Colors.red;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push('/historial/detalle/${pedido['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. TIEMPOS
              Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.restaurant, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(horaPedido, style: const TextStyle(fontSize: 11, color: Colors.grey))
                    ]
                  ),
                  if (horaPago != null) ...[
                    Container(height: 10, width: 1, color: Colors.grey[300]),
                    Row(
                      children: [
                        const Icon(Icons.payments, size: 14, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(horaPago, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green))
                      ]
                    ),
                  ]
                ],
              ),
              const SizedBox(width: 15),

              // 2. INFO PRINCIPAL
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // TÍTULO CON NOMBRE CLIENTE SI EXISTE
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Mesa ${pedido['mesas']?['numero'] ?? '?'} • #${pedido['id']}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pedido['nombre_cliente'] != null && pedido['nombre_cliente'].toString().trim().isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber[100],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person, size: 12, color: Colors.orange),
                                const SizedBox(width: 3),
                                Text(
                                  pedido['nombre_cliente'].toString(),
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),

                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                        children: [
                          const TextSpan(text: 'Atendió: '),
                          TextSpan(
                            text: mozoNombreCompleto,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)
                          ),
                        ]
                      ),
                    ),
                    
                    if (cajeroNombreCompleto.isNotEmpty && cajeroNombreCompleto != mozoNombreCompleto) 
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                          children: [
                            const TextSpan(text: 'Cobró: '),
                            TextSpan(
                              text: cajeroNombreCompleto, 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)
                            ),
                          ]
                        ),
                      ),
                    ),
                    
                    if (cajeroNombreCompleto.isNotEmpty && cajeroNombreCompleto == mozoNombreCompleto)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                          children: [
                            const TextSpan(text: 'Atendió y Cobró: '),
                            TextSpan(
                              text: mozoNombreCompleto, 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)
                            ),
                          ]
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 4),
                    widgetMetodos,
                  ],
                ),
              ),

              // 3. TOTAL Y ESTADO
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('S/. ${total.toStringAsFixed(2)}', 
                       style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorEstado.withOpacity(0.1), 
                      borderRadius: BorderRadius.circular(4)
                    ),
                    child: Text(
                      estado, 
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorEstado),
                    ),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String label;
  final double val;
  final Color color;
  const _MiniCard(this.label, this.val, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.2))
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
            Text('${val.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }
}

class _FiltroChip extends ConsumerWidget {
  final String label;
  final List<String> options;
  final StateProvider<String> provider;

  const _FiltroChip({required this.label, required this.options, required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valorActual = ref.watch(provider);
    
    return PopupMenuButton<String>(
      initialValue: valorActual,
      onSelected: (val) => ref.read(provider.notifier).state = val,
      itemBuilder: (_) => options.map((opt) => PopupMenuItem(value: opt, child: Text(opt))).toList(),
      child: Chip(
        label: Text('$label: $valorActual'),
        backgroundColor: valorActual == 'TODOS' ? Colors.white : Colors.blue[100],
        deleteIcon: const Icon(Icons.arrow_drop_down),
        onDeleted: () {}, 
      ),
    );
  }
}