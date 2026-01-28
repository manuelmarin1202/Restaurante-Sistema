import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/promocion_model.dart';
import '../../../../shared/models/producto_model.dart';
import '../../../pedidos/presentation/providers/carrito_provider.dart';

/// Modal para seleccionar productos de un combo múltiple con cantidades
/// Ejemplo: 2 Tragos x S/25 (Puede ser 2 del mismo o combinados)
class ComboMultipleSheet extends ConsumerStatefulWidget {
  final Promocion promocion;
  final List<Producto> productosDisponibles;

  const ComboMultipleSheet({
    super.key,
    required this.promocion,
    required this.productosDisponibles,
  });

  @override
  ConsumerState<ComboMultipleSheet> createState() => _ComboMultipleSheetState();
}

class _ComboMultipleSheetState extends ConsumerState<ComboMultipleSheet> {
  // Mapa para controlar cantidad por producto: ID -> Cantidad
  final Map<int, int> _cantidades = {}; 
  final Map<int, String> _notasProductos = {}; // productoId -> nota (Ojo: nota aplica a todos los de ese tipo)

  int get _totalSeleccionados => _cantidades.values.fold(0, (sum, qty) => sum + qty);

  @override
  Widget build(BuildContext context) {
    final cantidadRequerida = widget.promocion.cantidadItems ?? 2;
    final precioTotal = widget.promocion.precioCombo ?? 0.0;
    final seleccionados = _totalSeleccionados;
    final faltantes = cantidadRequerida - seleccionados;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 1. Header con info del combo
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.purple[50], borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.local_bar, color: Colors.purple, size: 32),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.promocion.nombre,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (widget.promocion.descripcion != null)
                      Text(
                        widget.promocion.descripcion!,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                  const Text('Precio Total', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text(
                    'S/. ${precioTotal.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.purple),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 15),

          // 2. Barra de Progreso
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: seleccionados == cantidadRequerida ? Colors.green[50] : Colors.orange[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: seleccionados == cantidadRequerida ? Colors.green : Colors.orange[200]!
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  seleccionados == cantidadRequerida 
                    ? '¡Listo para agregar!' 
                    : 'Elige $faltantes más...',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: seleccionados == cantidadRequerida ? Colors.green[800] : Colors.orange[900]
                  ),
                ),
                Text(
                  '$seleccionados / $cantidadRequerida',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 10),

          // 3. Lista de productos con contadores
          Expanded(
            child: ListView.separated(
              itemCount: widget.productosDisponibles.length,
              separatorBuilder: (_,__) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final producto = widget.productosDisponibles[index];
                final cantidadActual = _cantidades[producto.id] ?? 0;
                final bool puedeAgregar = seleccionados < cantidadRequerida;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      // Nombre y Precio
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(producto.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              'Normal: S/. ${producto.precio.toStringAsFixed(2)}',
                              style: TextStyle(color: Colors.grey[500], fontSize: 11, decoration: TextDecoration.lineThrough),
                            ),
                          ],
                        ),
                      ),

                      // Contador
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[300]!)
                        ),
                        child: Row(
                          children: [
                            _BotonContador(
                              icon: Icons.remove,
                              color: Colors.red,
                              enabled: cantidadActual > 0,
                              onTap: () {
                                if (cantidadActual > 0) {
                                  setState(() {
                                    _cantidades[producto.id] = cantidadActual - 1;
                                    if (_cantidades[producto.id] == 0) {
                                      _cantidades.remove(producto.id);
                                      _notasProductos.remove(producto.id);
                                    }
                                  });
                                }
                              },
                            ),
                            SizedBox(
                              width: 30,
                              child: Text(
                                '$cantidadActual',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            _BotonContador(
                              icon: Icons.add,
                              color: Colors.green,
                              enabled: puedeAgregar,
                              onTap: () {
                                if (puedeAgregar) {
                                  setState(() {
                                    _cantidades[producto.id] = cantidadActual + 1;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 4. Botón Agregar
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: seleccionados == cantidadRequerida ? Colors.purple : Colors.grey[400],
              ),
              onPressed: seleccionados == cantidadRequerida
                  ? _confirmar
                  : null,
              child: Text(
                seleccionados == cantidadRequerida 
                  ? 'AGREGAR COMBO' 
                  : 'FALTA COMPLETAR',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmar() {
    // Construir lista plana de productos (si eligió 2 veces Chilcano, se agregan 2 objetos Chilcano)
    List<Producto> productosFinales = [];
    
    _cantidades.forEach((prodId, cantidad) {
      final producto = widget.productosDisponibles.firstWhere((p) => p.id == prodId);
      for (int i = 0; i < cantidad; i++) {
        productosFinales.add(producto);
      }
    });

    debugPrint("🍹 [COMBO] Enviando ${productosFinales.length} items (con repetidos)");

    ref.read(carritoProvider.notifier).agregarCombo(
          productos: productosFinales,
          promocionId: widget.promocion.id,
          precioTotal: widget.promocion.precioCombo!,
          notasPorProducto: _notasProductos, // Ojo: las notas aplican igual a todos los del mismo ID
        );

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ ${widget.promocion.nombre} agregado'),
        backgroundColor: Colors.green,
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }
}

class _BotonContador extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _BotonContador({required this.icon, required this.color, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(
          icon, 
          size: 20, 
          color: enabled ? color : Colors.grey[300]
        ),
      ),
    );
  }
}