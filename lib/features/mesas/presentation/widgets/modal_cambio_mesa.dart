import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/mesa_model.dart';

// Provider temporal para cargar mesas libres al abrir el modal
final mesasLibresProvider = FutureProvider.autoDispose<List<Mesa>>((ref) async {
  final supabase = Supabase.instance.client;
  // Traemos solo las LIBRES y ordenadas por ID o Número
  final data = await supabase
      .from('mesas')
      .select('*, zonas(nombre)')
      .eq('estado', 'libre')
      .order('zona_id') // Agrupar visualmente por zona
      .order('id');
  
  return (data as List).map((e) => Mesa.fromJson(e)).toList();
});

class ModalCambioMesa extends ConsumerWidget {
  final int mesaActualId;
  
  const ModalCambioMesa({super.key, required this.mesaActualId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesasLibresAsync = ref.watch(mesasLibresProvider);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.swap_horiz, color: Colors.blue),
          SizedBox(width: 10),
          Text('Mover a...'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300, // Altura fija para scroll
        child: mesasLibresAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (mesas) {
            if (mesas.isEmpty) return const Center(child: Text('No hay mesas libres.'));

            return ListView.separated(
              itemCount: mesas.length,
              separatorBuilder: (_,__) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final mesa = mesas[index];
                final nombreZona = mesa.nombreZona ?? 'General';
                final esParaLlevar = nombreZona.toUpperCase().contains('LLEVAR');

                return ListTile(
                  leading: Icon(
                    esParaLlevar ? Icons.shopping_bag : Icons.table_restaurant,
                    color: Colors.green,
                  ),
                  title: Text(
                    esParaLlevar ? 'Para Llevar #${mesa.numero}' : 'Mesa ${mesa.numero}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(nombreZona),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    // Retornamos la mesa seleccionada
                    Navigator.pop(context, mesa);
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}