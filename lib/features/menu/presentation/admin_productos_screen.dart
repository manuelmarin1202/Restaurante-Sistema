import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../shared/widgets/app_drawer.dart';
import '../../../../shared/models/producto_model.dart';
import '../../menu/presentation/providers/categorias_provider.dart';
import 'providers/admin_productos_provider.dart';

class AdminProductosScreen extends ConsumerStatefulWidget {
  const AdminProductosScreen({super.key});

  @override
  ConsumerState<AdminProductosScreen> createState() => _AdminProductosScreenState();
}

class _AdminProductosScreenState extends ConsumerState<AdminProductosScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filtroBusqueda = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriasProvider);
    final productosAsync = ref.watch(productosListProvider);

    return categoriasAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error cargando categorías: $e'))),
      data: (categorias) {
        return DefaultTabController(
          length: categorias.length,
          child: Scaffold(
            drawer: const AppDrawer(),
            appBar: AppBar(
              title: const Text('Administrar Carta'),
              bottom: TabBar(
                isScrollable: true,
                tabs: categorias.map((c) => Tab(text: c.nombre)).toList(),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.refresh(categoriasProvider);
                    ref.refresh(productosListProvider);
                  },
                )
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/admin/productos/nuevo');
                // Al volver, no hace falta refresh manual si usamos StreamProvider, 
                // pero si usas FutureProvider:
                // ref.invalidate(productosListProvider);
              },
              label: const Text('Nuevo Plato'),
              icon: const Icon(Icons.add),
            ),
            body: Column(
              children: [
                // 1. BARRA DE BÚSQUEDA
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.grey[100],
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Buscar plato (ej: Lentejas, Pollo...)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _filtroBusqueda.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _filtroBusqueda = '');
                            },
                          ) 
                        : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    onChanged: (val) => setState(() => _filtroBusqueda = val.toLowerCase()),
                  ),
                ),

                // 2. CONTENIDO (TABS)
                Expanded(
                  child: productosAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error productos: $e')),
                    data: (todosLosProductos) {
                      
                      // Filtro Global por Búsqueda (si hay texto escrito)
                      final productosFiltradosGlobalmente = _filtroBusqueda.isEmpty
                          ? todosLosProductos
                          : todosLosProductos.where((p) => p.nombre.toLowerCase().contains(_filtroBusqueda)).toList();

                      return TabBarView(
                        children: categorias.map((cat) {
                          // FILTRO POR CATEGORÍA (Pestaña actual)
                          final productosDePestana = productosFiltradosGlobalmente
                              .where((p) => p.categoriaId == cat.id)
                              .toList();

                          // CASO VACÍO
                          if (productosDePestana.isEmpty) {
                            if (_filtroBusqueda.isNotEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.search_off, size: 50, color: Colors.grey),
                                    const SizedBox(height: 10),
                                    Text('No encontré "$_filtroBusqueda" en ${cat.nombre}', style: const TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              );
                            }
                            return Center(child: Text('No hay platos en ${cat.nombre}', style: const TextStyle(color: Colors.grey)));
                          }

                          // LISTA DE PRODUCTOS
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                            itemCount: productosDePestana.length,
                            separatorBuilder: (_,__) => const Divider(),
                            itemBuilder: (context, index) {
                              final prod = productosDePestana[index];
                              return _ProductoAdminTile(producto: prod, ref: ref);
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProductoAdminTile extends StatelessWidget {
  final Producto producto;
  final WidgetRef ref;

  const _ProductoAdminTile({required this.producto, required this.ref});

  @override
  Widget build(BuildContext context) {
    // Opacidad visual: Si está activo se ve full, si no, se ve "apagado"
    final opacity = producto.activo ? 1.0 : 0.6;

    return Opacity(
      opacity: opacity,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Stack(
          children: [
            // IMAGEN
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[200],
                image: producto.imagenUrl != null 
                    ? DecorationImage(image: NetworkImage(producto.imagenUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: producto.imagenUrl == null ? const Icon(Icons.restaurant, size: 30, color: Colors.grey) : null,
            ),
            // INDICADOR ROJO SI ESTÁ INACTIVO
            if (!producto.activo)
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.visibility_off, color: Colors.white, size: 24),
              )
          ],
        ),
        title: Text(
          producto.nombre, 
          style: TextStyle(
            fontWeight: FontWeight.bold,
            // Tachado sutil si está inactivo
            decoration: producto.activo ? null : TextDecoration.lineThrough,
            decorationColor: Colors.red,
          ),
        ),
        subtitle: Row(
          children: [
            Text('S/. ${producto.precio.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            // Etiqueta de Estado
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: producto.activo ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: producto.activo ? Colors.green : Colors.red, width: 0.5),
              ),
              child: Text(
                producto.activo ? "ACTIVO" : "INACTIVO",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: producto.activo ? Colors.green[800] : Colors.red[800]),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // SWITCH DE REACTIVACIÓN RÁPIDA
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: producto.activo,
                activeThumbColor: Colors.green,
                inactiveThumbColor: Colors.red,
                inactiveTrackColor: Colors.red[100],
                onChanged: (val) async {
                  // Lógica optimista
                  await ref.read(productosRepoProvider).toggleActivo(producto.id, val);
                  // Si usas StreamProvider, se actualiza solo. Si no, descomenta abajo:
                  // ref.invalidate(productosListProvider);
                },
              ),
            ),
            
            // MENÚ MÁS OPCIONES
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'editar') {
                  await context.push('/admin/productos/editar', extra: producto);
                  // ref.invalidate(productosListProvider);
                } else if (value == 'eliminar') {
                  _confirmarEliminacion(context, ref);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: Row(children: [Icon(Icons.edit, color: Colors.blue, size: 20), SizedBox(width: 10), Text('Editar Datos')]),
                ),
                const PopupMenuItem(
                  value: 'eliminar',
                  child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 20), SizedBox(width: 10), Text('Eliminar Definitivamente')]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarEliminacion(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar plato?'),
        content: Text('Estás a punto de borrar "${producto.nombre}".\n\nSi solo quieres ocultarlo del menú, usa el switch de "ACTIVO/INACTIVO".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('ELIMINAR')
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(productosRepoProvider).eliminarProducto(producto.id, producto.imagenUrl);
      // ref.invalidate(productosListProvider);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado'))
        );
      }
    }
  }
}