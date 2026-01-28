import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../data/pedidos_repository.dart';
import '../../mesas/presentation/widgets/modal_cambio_mesa.dart';
import '../../../shared/models/mesa_model.dart';
import '../../../../shared/utils/menu_calculator.dart'; // Mantenemos import por si acaso, pero no lo usamos en el total visual


final pedidoActivoProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, int>((ref, mesaId) {
  return ref.watch(pedidosRepositoryProvider).obtenerPedidoActual(mesaId);
});

class DetalleMesaScreen extends ConsumerWidget {
  final int mesaId;
  const DetalleMesaScreen({super.key, required this.mesaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidoAsync = ref.watch(pedidoActivoProvider(mesaId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Gestión Mesa $mesaId'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/mesas'), 
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(pedidoActivoProvider(mesaId)),
          )
        ],
      ),
      body: pedidoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (pedido) {
          if (pedido == null) {
            return _VistaMesaVacia(mesaId: mesaId);
          }

          final detallesRaw = List<dynamic>.from(pedido['detalle_pedido']);
          
          // --- 1. LÓGICA DE AGRUPACIÓN PARA LISTA ---
          final Map<String, Map<String, dynamic>> agrupados = {};

          for (var item in detallesRaw) {
            final prodId = item['producto_id'];
            final notas = item['notas'] ?? '';
            // Importante: Agrupar también por precio para no mezclar items de promo con normales
            final precio = (item['precio_unitario'] as num).toDouble();
            final claveAgrupacion = '$prodId|$notas|$precio';

            if (!agrupados.containsKey(claveAgrupacion)) {
              agrupados[claveAgrupacion] = {
                'producto': item['productos'],
                'cantidad': 0,
                'precio_unitario': precio,
                'subtotal': 0.0,
                'ids_detalles': [],
                'notas': notas
              };
            }
            agrupados[claveAgrupacion]!['cantidad'] += item['cantidad'] as int;
            agrupados[claveAgrupacion]!['subtotal'] += (item['cantidad'] * precio);
            (agrupados[claveAgrupacion]!['ids_detalles'] as List).add(item['id']);
          }
          final listaVisual = agrupados.values.toList();

          // --- 2. CÁLCULO DEL TOTAL (CORREGIDO: SUMA SIMPLE) ---
          // Ya no usamos MenuCalculator aquí porque la BD ya tiene los precios procesados.
          // Simplemente sumamos lo que hay para que coincida visualmente 100%.
          double totalCalculado = 0.0;
          for (var item in detallesRaw) {
             totalCalculado += (item['cantidad'] as num) * (item['precio_unitario'] as num);
          }
          
          return Column(
            children: [
              // 1. Cabecera Informativa
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[100],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pedido #${pedido['id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          DateFormat('hh:mm a', 'es_PE').format(
                            DateTime.parse(pedido['created_at']).toLocal()
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'S/. ${totalCalculado.toStringAsFixed(2)}', 
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 2. Lista AGRUPADA
              Expanded(
                child: ListView.separated(
                  itemCount: listaVisual.length,
                  separatorBuilder: (_,__) => const Divider(),
                  itemBuilder: (context, index) {
                    final itemGroup = listaVisual[index];
                    final producto = itemGroup['producto'];
                    final cantidad = itemGroup['cantidad'];
                    final subtotal = itemGroup['subtotal'];
                    final precioUnit = itemGroup['precio_unitario'];
                    final ultimoIdParaBorrar = (itemGroup['ids_detalles'] as List).last;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[50],
                        child: Text('$cantidad', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      title: Text(producto['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (itemGroup['notas'] != null && itemGroup['notas'].toString().isNotEmpty)
                            Text(itemGroup['notas']),
                          // Opcional: Mostrar precio unitario pequeño si ayuda
                          Text('Unit: S/. ${precioUnit.toStringAsFixed(2)}', style: TextStyle(fontSize: 10, color: Colors.grey))
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('S/. ${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () async {
                              await ref.read(pedidosRepositoryProvider).eliminarDetalle(
                                ultimoIdParaBorrar, 
                                pedido['id']
                              );
                              ref.refresh(pedidoActivoProvider(mesaId));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Producto eliminado'), duration: Duration(milliseconds: 500))
                                );
                              }
                            },
                          )
                        ],
                      ),
                    );
                  },
                ),
              ),

              // 3. Botones de Acción
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))],
                ),
                child: SafeArea(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _ActionButton(
                        icon: Icons.add_shopping_cart,
                        label: 'Agregar',
                        color: Colors.green,
                        onPressed: () async {
                          await context.push('/pedido/$mesaId?pedidoId=${pedido['id']}');
                          ref.invalidate(pedidoActivoProvider(mesaId));
                        },
                      ),
                      
                      _ActionButton(
                        icon: Icons.receipt,
                        label: 'Pre-Cuenta',
                        color: Colors.orange,
                        onPressed: () async {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enviando Pre-cuenta...')));
                          await ref.read(pedidosRepositoryProvider).imprimirPreCuenta(pedido['id']);
                        },
                      ),

                      _ActionButton(
                        icon: Icons.payments,
                        label: 'Cobrar',
                        color: Colors.blue[800]!,
                        onPressed: () {
                          // DEBUG: Ver qué nombre estamos enviando
                          print('🚀 [DETALLE_MESA] Navegando a cobro con:');
                          print('   - pedidoId: ${pedido['id']}');
                          print('   - mesaId: $mesaId');
                          print('   - total: $totalCalculado');
                          print('   - nombreClienteExistente: "${pedido['nombre_cliente']}"');

                          // AL COBRAR, enviamos el total visual calculado aquí
                          context.push('/cobrar', extra: {
                            'pedidoId': pedido['id'],
                            'mesaId': mesaId,
                            'total': totalCalculado, // Enviamos el total sumado de la BD
                            'nombreClienteExistente': pedido['nombre_cliente'], // Preservar nombre existente
                          });
                        },
                      ),

                      _ActionButton(
                        icon: Icons.cancel,
                        label: 'Anular',
                        color: Colors.red,
                        isOutlined: true,
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('¿Anular Pedido?'),
                              content: const Text('Acción irreversible.'),
                              actions: [
                                TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                FilledButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text('SI, ANULAR')),
                              ],
                            ),
                          );

                          if (confirm == true) {
                             await ref.read(pedidosRepositoryProvider).anularPedido(pedido['id'], mesaId);
                             if (context.mounted) context.go('/mesas');
                          }
                        },
                      ),

                      _ActionButton(
                        icon: Icons.move_up,
                        label: 'Mover',
                        color: Colors.indigo,
                        onPressed: () async {
                          final Mesa? mesaDestino = await showDialog(
                            context: context,
                            builder: (ctx) => ModalCambioMesa(mesaActualId: mesaId),
                          );

                          if (mesaDestino == null) return;

                          if (!context.mounted) return;
                          
                          try {
                            await ref.read(pedidosRepositoryProvider).cambiarMesa(
                              pedidoId: pedido['id'], 
                              mesaOrigenId: mesaId, 
                              mesaDestinoId: mesaDestino.id
                            );

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('✅ Movido a Mesa ${mesaDestino.numero}'))
                              );
                              context.go('/mesas'); 
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VistaMesaVacia extends ConsumerWidget {
  final int mesaId;
  const _VistaMesaVacia({required this.mesaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
          const SizedBox(height: 20),
          const Text(
            'Estado inconsistente detectado',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'La mesa figura ocupada pero no tiene pedido activo.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings_backup_restore),
            label: const Text('Liberar Mesa'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            onPressed: () async {
              try {
                await ref.read(pedidosRepositoryProvider).liberarMesaSinPedido(mesaId);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mesa liberada correctamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  context.go('/mesas');
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al liberar mesa: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          )
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool isOutlined;

  const _ActionButton({
    required this.icon, required this.label, required this.color, required this.onPressed, this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: isOutlined ? Colors.white : color,
      foregroundColor: isOutlined ? color : Colors.white,
      side: isOutlined ? BorderSide(color: color) : null,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    );
    return ElevatedButton.icon(style: style, onPressed: onPressed, icon: Icon(icon), label: Text(label));
  }
}