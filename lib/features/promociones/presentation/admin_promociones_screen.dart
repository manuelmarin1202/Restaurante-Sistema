import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/app_drawer.dart';
import 'providers/admin_promociones_provider.dart';

class AdminPromocionesScreen extends ConsumerWidget {
  const AdminPromocionesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promocionesAsync = ref.watch(promocionesAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Promociones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(promocionesAdminProvider),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: promocionesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $err'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(promocionesAdminProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        data: (promociones) {
          if (promociones.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_offer_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No hay promociones configuradas',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Las promociones se crean desde Supabase',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: promociones.length,
            itemBuilder: (context, index) {
              final promo = promociones[index];
              return _PromocionCard(promo: promo);
            },
          );
        },
      ),
    );
  }
}

class _PromocionCard extends ConsumerWidget {
  final PromocionAdmin promo;

  const _PromocionCard({required this.promo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUpdating = ref.watch(promocionUpdatingProvider(promo.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: promo.activo ? 2 : 0,
      color: promo.activo ? Colors.white : Colors.grey[100],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: promo.activo ? Colors.green.shade300 : Colors.grey.shade300,
          width: promo.activo ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera con nombre y switch
            Row(
              children: [
                // Icono de tipo de promoción
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getColorTipo(promo.tipoPromocion).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getIconTipo(promo.tipoPromocion),
                    color: _getColorTipo(promo.tipoPromocion),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Nombre y tipo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promo.nombre,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: promo.activo ? Colors.black87 : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _TipoChip(tipo: promo.tipoPromocion),
                          const SizedBox(width: 8),
                          if (promo.tipoCarta != null)
                            _CartaChip(carta: promo.tipoCarta!),
                        ],
                      ),
                    ],
                  ),
                ),
                // Switch de activación
                if (isUpdating)
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  Switch(
                    value: promo.activo,
                    activeColor: Colors.green,
                    onChanged: (value) async {
                      await ref
                          .read(promocionesAdminProvider.notifier)
                          .toggleActivo(promo.id, value);
                    },
                  ),
              ],
            ),

            // Descripción si existe
            if (promo.descripcion != null && promo.descripcion!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                promo.descripcion!,
                style: TextStyle(
                  fontSize: 13,
                  color: promo.activo ? Colors.grey[700] : Colors.grey,
                ),
              ),
            ],

            // Información de horarios y días
            if (promo.horaInicio != null || promo.diasAplicables != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Horario
                  if (promo.horaInicio != null && promo.horaFin != null)
                    _InfoChip(
                      icon: Icons.access_time,
                      label: '${promo.horaInicio} - ${promo.horaFin}',
                    ),
                  // Días
                  if (promo.diasAplicables != null && promo.diasAplicables!.isNotEmpty)
                    _InfoChip(
                      icon: Icons.calendar_today,
                      label: _formatDias(promo.diasAplicables!),
                    ),
                  // Precio combo
                  if (promo.precioCombo != null)
                    _InfoChip(
                      icon: Icons.attach_money,
                      label: 'S/ ${promo.precioCombo!.toStringAsFixed(2)}',
                      color: Colors.green,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getIconTipo(String tipo) {
    switch (tipo) {
      case 'precio_simple':
        return Icons.discount;
      case 'combo_producto':
        return Icons.fastfood;
      case 'combo_multiple':
        return Icons.groups;
      default:
        return Icons.local_offer;
    }
  }

  Color _getColorTipo(String tipo) {
    switch (tipo) {
      case 'precio_simple':
        return Colors.blue;
      case 'combo_producto':
        return Colors.orange;
      case 'combo_multiple':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatDias(List<String> dias) {
    if (dias.length == 7) return 'Todos los días';
    if (dias.length >= 5) {
      final faltantes = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo']
          .where((d) => !dias.contains(d))
          .toList();
      return 'Excepto ${faltantes.map(_abreviarDia).join(', ')}';
    }
    return dias.map(_abreviarDia).join(', ');
  }

  String _abreviarDia(String dia) {
    switch (dia.toLowerCase()) {
      case 'lunes':
        return 'Lun';
      case 'martes':
        return 'Mar';
      case 'miercoles':
        return 'Mié';
      case 'jueves':
        return 'Jue';
      case 'viernes':
        return 'Vie';
      case 'sabado':
        return 'Sáb';
      case 'domingo':
        return 'Dom';
      default:
        return dia.substring(0, 3);
    }
  }
}

class _TipoChip extends StatelessWidget {
  final String tipo;

  const _TipoChip({required this.tipo});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;

    switch (tipo) {
      case 'precio_simple':
        label = 'Descuento';
        color = Colors.blue;
        break;
      case 'combo_producto':
        label = 'Combo';
        color = Colors.orange;
        break;
      case 'combo_multiple':
        label = 'Múltiple';
        color = Colors.purple;
        break;
      default:
        label = tipo;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _CartaChip extends StatelessWidget {
  final String carta;

  const _CartaChip({required this.carta});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (carta.toUpperCase()) {
      case 'MENU':
        icon = Icons.wb_sunny;
        color = Colors.orange;
        break;
      case 'RESTOBAR':
        icon = Icons.nightlight_round;
        color = Colors.indigo;
        break;
      default:
        icon = Icons.restaurant;
        color = Colors.teal;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            carta,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.grey[600]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}
