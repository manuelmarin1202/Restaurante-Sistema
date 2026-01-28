import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
//import 'package:go_router/go_router.dart';
import '../data/admin_mesas_repository.dart';
import '../../../shared/models/mesa_model.dart';
import '../../../shared/models/zona_model.dart';
import '../../../../shared/widgets/app_drawer.dart';

// Providers locales para esta pantalla
final adminMesasRepoProvider = Provider((ref) => AdminMesasRepository());

final zonasListProvider = FutureProvider((ref) async {
  return ref.watch(adminMesasRepoProvider).getZonas();
});

final mesasListProvider = FutureProvider((ref) async {
  return ref.watch(adminMesasRepoProvider).getMesasConZona();
});

class AdminAmbientesScreen extends ConsumerWidget {
  const AdminAmbientesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: const Text('Configuración de Ambientes'),
          
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.view_quilt), text: 'Zonas & Áreas'),
              Tab(icon: Icon(Icons.table_bar), text: 'Mesas'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ZonasTab(),
            _MesasTab(),
          ],
        ),
      ),
    );
  }
}

// --- TAB 1: GESTIÓN DE ZONAS ---
class _ZonasTab extends ConsumerWidget {
  const _ZonasTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonasAsync = ref.watch(zonasListProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarDialogoZona(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: zonasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (zonas) {
          return ListView.separated(
            itemCount: zonas.length,
            separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (context, index) {
              final zona = zonas[index];
              return ListTile(
                leading: Icon(
                  zona.tipo == 'virtual' ? Icons.shopping_bag : Icons.store,
                  color: zona.tipo == 'virtual' ? Colors.purple : Colors.blue,
                ),
                title: Text(zona.nombre),
                subtitle: Text(zona.tipo == 'virtual' ? 'Zona Virtual (Para Llevar/Delivery)' : 'Zona Física'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.orange),
                      onPressed: () => _mostrarDialogoZona(context, ref, zona),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        await ref.read(adminMesasRepoProvider).deleteZona(zona.id);
                        ref.refresh(zonasListProvider);
                      },
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

  void _mostrarDialogoZona(BuildContext context, WidgetRef ref, Zona? zona) {
    final nombreCtrl = TextEditingController(text: zona?.nombre);
    bool esVirtual = zona?.tipo == 'virtual';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(zona == null ? 'Nueva Zona' : 'Editar Zona'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre (ej. Terraza)'),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: const Text('Es Zona Virtual'),
                  subtitle: const Text('Para pedidos Para Llevar o Delivery'),
                  value: esVirtual,
                  onChanged: (val) => setState(() => esVirtual = val),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  await ref.read(adminMesasRepoProvider).upsertZona(
                    zona?.id, 
                    nombreCtrl.text, 
                    esVirtual ? 'virtual' : 'fisica'
                  );
                  ref.refresh(zonasListProvider);
                  if(context.mounted) Navigator.pop(context);
                }, 
                child: const Text('Guardar')
              ),
            ],
          );
        }
      ),
    );
  }
}

// --- TAB 2: GESTIÓN DE MESAS ---
class _MesasTab extends ConsumerWidget {
  const _MesasTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesasAsync = ref.watch(mesasListProvider);
    final zonasAsync = ref.watch(zonasListProvider); // Necesitamos zonas para el dropdown

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarDialogoMesa(context, ref, null, zonasAsync.value ?? []),
        child: const Icon(Icons.add),
      ),
      body: mesasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (mesas) {
          return ListView.separated(
            itemCount: mesas.length,
            separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (context, index) {
              final mesa = mesas[index];
              return ListTile(
                leading: CircleAvatar(child: Text(mesa.numero)),
                title: Text('Mesa ${mesa.numero}'),
                subtitle: Text('Zona: ${mesa.nombreZona}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.orange),
                      onPressed: () => _mostrarDialogoMesa(context, ref, mesa, zonasAsync.value ?? []),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        await ref.read(adminMesasRepoProvider).deleteMesa(mesa.id);
                        ref.refresh(mesasListProvider);
                      },
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

  void _mostrarDialogoMesa(BuildContext context, WidgetRef ref, Mesa? mesa, List<Zona> zonas) {
    final numeroCtrl = TextEditingController(text: mesa?.numero);
    int? zonaIdSeleccionada = mesa?.zonaId ?? (zonas.isNotEmpty ? zonas.first.id : null);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(mesa == null ? 'Nueva Mesa' : 'Editar Mesa'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numeroCtrl,
                  decoration: const InputDecoration(labelText: 'Número o Código (ej. T1)'),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<int>(
                  value: zonaIdSeleccionada,
                  decoration: const InputDecoration(labelText: 'Ubicación / Zona'),
                  items: zonas.map((z) => DropdownMenuItem(
                    value: z.id, 
                    child: Text(z.nombre + (z.tipo == 'virtual' ? ' (Virtual)' : ''))
                  )).toList(),
                  onChanged: (val) => setState(() => zonaIdSeleccionada = val),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  if (zonaIdSeleccionada == null) return;
                  await ref.read(adminMesasRepoProvider).upsertMesa(
                    mesa?.id, 
                    numeroCtrl.text, 
                    zonaIdSeleccionada!
                  );
                  ref.refresh(mesasListProvider);
                  if(context.mounted) Navigator.pop(context);
                }, 
                child: const Text('Guardar')
              ),
            ],
          );
        }
      ),
    );
  }
}