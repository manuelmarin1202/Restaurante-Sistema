import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/pedidos_repository.dart';
// import '../../../../shared/utils/menu_calculator.dart'; // YA NO SE NECESITA

final detalleHistorialProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, pedidoId) {
  return ref.watch(pedidosRepositoryProvider).obtenerPedidoPorId(pedidoId);
});

class DetalleHistorialScreen extends ConsumerWidget {
  final int pedidoId;
  const DetalleHistorialScreen({super.key, required this.pedidoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPedido = ref.watch(detalleHistorialProvider(pedidoId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Histórico Pedido #$pedidoId'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // BOTÓN IMPRIMIR CUENTA
          asyncPedido.when(
            data: (pedido) {
              if (pedido['estado'] == 'cancelado') return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.print),
                tooltip: 'Reimprimir Cuenta',
                onPressed: () async {
                  await ref.read(pedidosRepositoryProvider).reimprimirCuentaFinal(pedidoId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enviando a impresora...')));
                  }
                },
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_,__) => const SizedBox.shrink(),
          )
        ],
      ),
      body: asyncPedido.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (pedido) {
          // 1. OBTENER QUIÉN COBRÓ
          String cajeroNombre = '-';
          final pagos = pedido['pagos'] as List<dynamic>?;
          if (pagos != null && pagos.isNotEmpty) {
            final ultimoPago = pagos.last;
            if (ultimoPago['perfiles'] != null) {
              cajeroNombre = ultimoPago['perfiles']['nombre_completo'] ?? 'Desconocido';
            }
          }

          // 2. AGRUPAR PRODUCTOS
          final detallesRaw = List<dynamic>.from(pedido['detalle_pedido']);
          
          // --- CORRECCIÓN CLAVE: Suma Simple Directa de BD ---
          // No usamos MenuCalculator porque la BD ya tiene los precios finales procesados.
          double totalReal = 0.0;
          
          // Agrupación visual
          final Map<String, Map<String, dynamic>> agrupados = {};

          for (var item in detallesRaw) {
            final prodId = item['producto_id'];
            final precioUnitario = (item['precio_unitario'] as num).toDouble();
            final notas = item['notas'] ?? '';
            
            // Sumar al total global
            totalReal += (item['cantidad'] as num) * precioUnitario;

            // Clave única para agrupar visualmente (incluye precio para no mezclar promos)
            final key = '$prodId|$notas|$precioUnitario';

            if (!agrupados.containsKey(key)) {
              agrupados[key] = {
                'producto': item['productos'],
                'cantidad': 0,
                'precio_unitario': precioUnitario,
                'subtotal': 0.0,
                'notas': notas
              };
            }
            agrupados[key]!['cantidad'] += item['cantidad'] as int;
            agrupados[key]!['subtotal'] += (item['cantidad'] * precioUnitario);
          }
          final listaVisual = agrupados.values.toList();
          
          // ----------------------------------------------------

          final estado = pedido['estado'];
          final esAnulable = estado != 'cancelado'; 

          return Column(
            children: [
              // CABECERA RESUMEN
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[100],
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Mesa: ${pedido['mesas']['numero']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                            Text(DateFormat('dd/MM HH:mm', 'es_PE').format(DateTime.parse(pedido['created_at']).toLocal())),
                          ],
                        ),
                        Text('S/. ${totalReal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // FILA DE PERSONAL Y ESTADO
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text('Cobró: $cajeroNombre', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: estado == 'cancelado' ? Colors.red[50] : Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: estado == 'cancelado' ? Colors.red : Colors.green)
                          ),
                          child: Text(estado.toString().toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: estado == 'cancelado' ? Colors.red : Colors.green)),
                        )
                      ],
                    )
                  ],
                ),
              ),
              const Divider(height: 1),
              
              // LISTA DE ITEMS
              Expanded(
                child: ListView.separated(
                  itemCount: listaVisual.length,
                  separatorBuilder: (_,__) => const Divider(),
                  itemBuilder: (ctx, i) {
                    final itemGroup = listaVisual[i];
                    final producto = itemGroup['producto'];
                    final cantidad = itemGroup['cantidad'];
                    final subtotal = itemGroup['subtotal'];
                    final precioUnit = itemGroup['precio_unitario'];
                    final subtipo = producto['subtipo'] ?? 'CARTA';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey[300],
                        child: Text('$cantidad', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      ),
                      title: Text(producto['nombre']),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${subtipo != 'CARTA' ? "[$subtipo] " : ""}${itemGroup['notas'] ?? ""}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          // Opcional: ver precio unitario
                          Text('Unit: S/. ${precioUnit.toStringAsFixed(2)}', style: TextStyle(fontSize: 10, color: Colors.grey[400]))
                        ],
                      ),
                      trailing: Text('S/. ${subtotal.toStringAsFixed(2)}'),
                    );
                  },
                ),
              ),

              // BOTONES DE ACCIÓN
              if (esAnulable)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Botón Editar Método de Pago (solo si está pagado)
                      if (estado == 'pagado' && pagos != null && pagos.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                            icon: const Icon(Icons.edit),
                            label: const Text('EDITAR MÉTODO DE PAGO'),
                            onPressed: () => _editarMetodoPago(context, ref, pedidoId, pagos),
                          ),
                        ),
                      if (estado == 'pagado' && pagos != null && pagos.isNotEmpty)
                        const SizedBox(height: 10),
                      // Botón Anular
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          icon: const Icon(Icons.cancel),
                          label: const Text('ANULAR PEDIDO HISTÓRICO'),
                          onPressed: () => _confirmarAnulacion(context, ref, pedido),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editarMetodoPago(BuildContext context, WidgetRef ref, int pedidoId, List<dynamic> pagosActuales) async {
    final resultado = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => _DialogoEditarMetodoPago(pagosActuales: pagosActuales),
    );

    if (resultado != null && context.mounted) {
      try {
        // Actualizar los pagos en la base de datos
        await ref.read(pedidosRepositoryProvider).actualizarMetodosPago(pedidoId, resultado);

        if (context.mounted) {
          ref.invalidate(detalleHistorialProvider(pedidoId));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Métodos de pago actualizados'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _confirmarAnulacion(BuildContext context, WidgetRef ref, Map<String, dynamic> pedido) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Anular este pedido?'),
        content: const Text('Esto cambiará el estado a CANCELADO y liberará la mesa si estaba ocupada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, Anular')
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(pedidosRepositoryProvider).anularPedido(pedidoId, pedido['mesa_id']);
      if (context.mounted) {
        ref.invalidate(detalleHistorialProvider(pedidoId));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido anulado con éxito')));
      }
    }
  }
}

// Widget del diálogo para editar métodos de pago
class _DialogoEditarMetodoPago extends StatefulWidget {
  final List<dynamic> pagosActuales;

  const _DialogoEditarMetodoPago({required this.pagosActuales});

  @override
  State<_DialogoEditarMetodoPago> createState() => _DialogoEditarMetodoPagoState();
}

class _DialogoEditarMetodoPagoState extends State<_DialogoEditarMetodoPago> {
  late List<Map<String, dynamic>> _pagosEditables;
  final List<String> _metodosDisponibles = ['EFECTIVO', 'YAPE', 'PLIN', 'TARJETA'];

  @override
  void initState() {
    super.initState();
    // Convertir los pagos actuales a un formato editable
    _pagosEditables = widget.pagosActuales.map((p) {
      // Soportar tanto 'id' como 'id_pago'
      final pagoId = p['id_pago'] ?? p['id'];

      print('📝 [DIALOGO] Parseando pago: id_pago=$pagoId, metodo=${p['metodo_pago']}');

      return {
        'id_pago': pagoId, // Usar id_pago consistentemente
        'metodo_pago': p['metodo_pago']?.toString().toUpperCase() ?? 'EFECTIVO',
        'total_pagado': (p['total_pagado'] as num).toDouble(),
      };
    }).toList();

    print('✅ [DIALOGO] ${_pagosEditables.length} pagos parseados correctamente');
  }

  @override
  Widget build(BuildContext context) {
    final totalGeneral = _pagosEditables.fold<double>(0, (sum, p) => sum + p['total_pagado']);

    return AlertDialog(
      title: const Text('Editar Métodos de Pago'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total del pedido: S/. ${totalGeneral.toStringAsFixed(2)}',
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _pagosEditables.length,
                itemBuilder: (context, index) {
                  final pago = _pagosEditables[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Pago ${index + 1}:', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const Spacer(),
                              Text('S/. ${pago['total_pagado'].toStringAsFixed(2)}',
                                   style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: pago['metodo_pago'],
                            decoration: const InputDecoration(
                              labelText: 'Método de Pago',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _metodosDisponibles.map((metodo) {
                              IconData icon;
                              Color color;
                              if (metodo == 'EFECTIVO') { icon = Icons.money; color = Colors.green; }
                              else if (metodo == 'YAPE') { icon = Icons.qr_code; color = Colors.purple; }
                              else if (metodo == 'PLIN') { icon = Icons.mobile_friendly; color = Colors.pink; }
                              else { icon = Icons.credit_card; color = Colors.blue; }

                              return DropdownMenuItem(
                                value: metodo,
                                child: Row(
                                  children: [
                                    Icon(icon, size: 20, color: color),
                                    const SizedBox(width: 8),
                                    Text(metodo),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (nuevoMetodo) {
                              if (nuevoMetodo != null) {
                                setState(() {
                                  _pagosEditables[index]['metodo_pago'] = nuevoMetodo;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _pagosEditables),
          child: const Text('Guardar Cambios'),
        ),
      ],
    );
  }
}