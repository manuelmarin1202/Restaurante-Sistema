import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
//import 'package:go_router/go_router.dart';
import '../../../../shared/models/categoria_model.dart';
import '../../../../shared/widgets/app_drawer.dart'; // Para el menú lateral
import '../data/categorias_repository.dart';

// Providers
final adminCategoriasRepoProvider = Provider((ref) => CategoriasRepository());

final categoriasListProvider = FutureProvider((ref) async {
  return ref.watch(adminCategoriasRepoProvider).getCategorias();
});

class AdminCategoriasScreen extends ConsumerWidget {
  const AdminCategoriasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriasAsync = ref.watch(categoriasListProvider);

    return Scaffold(
      drawer: const AppDrawer(), // Menú hamburguesa
      appBar: AppBar(
        title: const Text('Administrar Categorías'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(categoriasListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarDialogo(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: categoriasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (categorias) {
          if (categorias.isEmpty) {
            return const Center(child: Text('No hay categorías registradas'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: categorias.length,
            separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (context, index) {
              final cat = categorias[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cat.activo ? Colors.blue : Colors.grey,
                  child: Text(
                    '${cat.orden}', 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                  ),
                ),
                title: Text(
                  cat.nombre,
                  style: TextStyle(
                    decoration: cat.activo ? null : TextDecoration.lineThrough,
                    color: cat.activo ? Colors.black : Colors.grey,
                  ),
                ),
                subtitle: Text(cat.activo ? 'Activa' : 'Inactiva (Oculta)'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.orange),
                      onPressed: () => _mostrarDialogo(context, ref, cat),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmarBorrado(context, ref, cat),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _mostrarDialogo(BuildContext context, WidgetRef ref, Categoria? categoria) {
    final nombreCtrl = TextEditingController(text: categoria?.nombre);
    final ordenCtrl = TextEditingController(text: categoria?.orden.toString() ?? '0');
    bool activo = categoria?.activo ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(categoria == null ? 'Nueva Categoría' : 'Editar Categoría'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre (Ej. Bebidas)'),
                  autofocus: true,
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: ordenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Orden de visualización',
                    helperText: '1 sale primero, 10 sale último',
                  ),
                ),
                const SizedBox(height: 15),
                SwitchListTile(
                  title: const Text('Visible en Menú'),
                  value: activo,
                  onChanged: (val) => setState(() => activo = val),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  final orden = int.tryParse(ordenCtrl.text) ?? 0;
                  if (nombreCtrl.text.isEmpty) return;

                  await ref.read(adminCategoriasRepoProvider).upsertCategoria(
                    id: categoria?.id,
                    nombre: nombreCtrl.text,
                    orden: orden,
                    activo: activo,
                  );
                  
                  ref.refresh(categoriasListProvider);
                  if (context.mounted) Navigator.pop(ctx);
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmarBorrado(BuildContext context, WidgetRef ref, Categoria cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Categoría?'),
        content: Text('Estás a punto de borrar "${cat.nombre}".\n\nSi tiene productos asociados, esto dará error. Mejor desactívala.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Eliminar')
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(adminCategoriasRepoProvider).deleteCategoria(cat.id);
        ref.refresh(categoriasListProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ No se pudo borrar. Tiene productos asociados.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}