import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/promocion_model.dart';
import '../../../../shared/models/producto_model.dart';
import '../../../pedidos/presentation/providers/carrito_provider.dart';
import '../../data/promociones_repository.dart';

/// Modal para seleccionar adicionales obligatorios de una promoción
/// Ejemplo: Alitas + Gaseosa (el usuario elige cuál gaseosa)
class PromocionAdicionalesSheet extends ConsumerStatefulWidget {
  final Promocion promocion;
  final Producto productoPrincipal;
  final PromocionProducto promoProducto;
  final String? notaInicial;

  const PromocionAdicionalesSheet({
    super.key,
    required this.promocion,
    required this.productoPrincipal,
    required this.promoProducto,
    this.notaInicial,
  });

  @override
  ConsumerState<PromocionAdicionalesSheet> createState() =>
      _PromocionAdicionalesSheetState();
}

class _PromocionAdicionalesSheetState
    extends ConsumerState<PromocionAdicionalesSheet> {
  final Map<String, int?> _seleccionados = {}; // grupoSeleccion -> productoId
  String? _notaProductoPrincipal;

  @override
  void initState() {
    super.initState();
    // Inicializamos con lo que viene de afuera
    _notaProductoPrincipal = widget.notaInicial; 
  }
  
  @override
  Widget build(BuildContext context) {
    final grupos = ref
        .read(promocionesRepositoryProvider)
        .obtenerAdicionalesAgrupados(widget.promocion);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.local_offer, color: Colors.orange, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.promocion.nombre,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.promocion.descripcion ?? '',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Precio
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Precio promocional:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  'S/. ${widget.promoProducto.precioPromocional?.toStringAsFixed(2) ?? "0.00"}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),

          // Producto principal
          Card(
            color: Colors.blue[50],
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.blue),
              title: Text(
                widget.productoPrincipal.nombre,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: TextField(
                decoration: const InputDecoration(
                  hintText: 'Sabor / Observaciones (opcional)',
                  isDense: true,
                  border: InputBorder.none,
                ),
                onChanged: (texto) {
                  _notaProductoPrincipal = texto.isNotEmpty ? texto : null;
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Grupos de adicionales
          Expanded(
            child: ListView(
              children: grupos.entries.map((entry) {
                final grupo = entry.key;
                final adicionales = entry.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nombreGrupo(grupo),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...adicionales.map((adicional) {
                      final productoData = adicional.producto!;
                      final isSelected =
                          _seleccionados[grupo] == adicional.productoId;

                      return Card(
                        color: isSelected ? Colors.green[50] : null,
                        child: RadioListTile<int>(
                          title: Text(productoData['nombre']),
                          subtitle: adicional.cantidad > 1
                              ? Text('${adicional.cantidad} unidades incluidas')
                              : const Text('Incluido gratis'),
                          value: adicional.productoId,
                          groupValue: _seleccionados[grupo],
                          onChanged: (value) {
                            setState(() {
                              _seleccionados[grupo] = value;
                            });
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                );
              }).toList(),
            ),
          ),

          // Botón agregar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _todosGruposSeleccionados() ? () => _confirmar() : null,
              child: const Text(
                'AGREGAR COMBO',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _todosGruposSeleccionados() {
    final grupos = ref
        .read(promocionesRepositoryProvider)
        .obtenerAdicionalesAgrupados(widget.promocion);

    // Verificar que todos los grupos obligatorios tengan selección
    for (var grupo in grupos.keys) {
      if (_seleccionados[grupo] == null) return false;
    }
    return true;
  }

  void _confirmar() {
    // 1. Recolectar adicionales
    final List<Producto> adicionalesSeleccionados = [];
    final gruposDisponibles = ref.read(promocionesRepositoryProvider)
        .obtenerAdicionalesAgrupados(widget.promocion);

    _seleccionados.forEach((grupo, productoIdSeleccionado) {
      if (productoIdSeleccionado != null) {
        final opcionesGrupo = gruposDisponibles[grupo];
        if (opcionesGrupo != null) {
          final match = opcionesGrupo.firstWhere(
            (a) => a.productoId == productoIdSeleccionado,
            orElse: () => opcionesGrupo.first
          );
          
          if (match.producto != null) {
             final p = Producto.fromJson(match.producto!);
             adicionalesSeleccionados.add(p);
             debugPrint("🥤 [MODAL] Gaseosa seleccionada: ${p.nombre}");
          }
        }
      }
    });

    // 2. Enviar al Carrito (Ahora el carrito SÍ lo recibirá)
    ref.read(carritoProvider.notifier).agregarProductoConPromocion(
          producto: widget.productoPrincipal,
          promocionId: widget.promocion.id,
          precioPromocional: widget.promoProducto.precioPromocional ?? widget.productoPrincipal.precio,
          cantidad: 1,
          notas: _notaProductoPrincipal,
          productosAdicionales: adicionalesSeleccionados, // <--- IMPORTANTE
        );

    Navigator.pop(context);
    
    // Feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Agregado con ${adicionalesSeleccionados.length} adicionales'), backgroundColor: Colors.green),
    );
  }

  String _nombreGrupo(String grupo) {
    switch (grupo) {
      case 'gaseosa_vidrio':
        return 'Elige tu gaseosa (incluida)';
      case 'jarra_sabor':
        return 'Elige el sabor de tu jarra (incluida)';
      default:
        return 'Adicionales incluidos';
    }
  }
}
