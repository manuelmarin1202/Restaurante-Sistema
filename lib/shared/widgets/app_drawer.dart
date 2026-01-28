import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/modo_negocio_provider.dart';

// Mantenemos tu provider de rol tal cual lo tenías (ya que dijiste que funciona)
final userRoleProvider = FutureProvider<String>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return 'mozo';
  try {
    final response = await Supabase.instance.client
        .from('perfiles')
        .select('rol')
        .eq('id', user.id)
        .single();
    return (response['rol'] as String?)?.toLowerCase() ?? 'mozo';
  } catch (e) {
    return 'mozo';
  }
});

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? 'Usuario';
    final rolAsync = ref.watch(userRoleProvider);
    
    // 1. Escuchar el estado global
    final modoActual = ref.watch(modoNegocioProvider);
    final esModoNoche = modoActual == 'RESTOBAR';

    final colorTema = esModoNoche ? Colors.indigo[800]! : Colors.orange[800]!;
    final iconTema = esModoNoche ? Icons.nightlight_round : Icons.wb_sunny_rounded;

    return Drawer(
      child: Column(
        children: [
          // CABECERA
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: colorTema,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: esModoNoche 
                  ? [Colors.indigo[900]!, Colors.indigo[600]!]
                  : [Colors.orange[800]!, Colors.orange[400]!],
              ),
            ),
            accountName: const Text("Sistema Restaurante", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            accountEmail: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 4),
                rolAsync.when(
                  data: (rol) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white30, width: 0.5)
                    ),
                    child: Text(rol.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_,__) => const SizedBox.shrink(),
                )
              ],
            ),
            
          ),

          // CUERPO
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // --- SWITCH DE MODO CORREGIDO ---
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                  leading: CircleAvatar(
                    backgroundColor: colorTema.withOpacity(0.1),
                    child: Icon(iconTema, color: colorTema),
                  ),
                  title: Text(
                    esModoNoche ? 'Modo Noche (Restobar)' : 'Modo Día (Menú)',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800], fontSize: 14),
                  ),
                  subtitle: const Text('Cambiar carta activa', style: TextStyle(fontSize: 11)),
                  trailing: Switch(
                    value: esModoNoche,
                    activeColor: Colors.indigo,
                    activeTrackColor: Colors.indigo.withOpacity(0.3),
                    inactiveThumbColor: Colors.orange,
                    inactiveTrackColor: Colors.orange.withOpacity(0.3),
                    onChanged: (val) {
                      // AQUÍ ESTÁ EL CAMBIO CLAVE:
                      // Usamos el método 'cambiarTurno' para escribir en la DB
                      final nuevoTurno = val ? 'RESTOBAR' : 'MENU';
                      ref.read(modoNegocioProvider.notifier).cambiarTurno(nuevoTurno);
                      
                      // Cerramos el drawer
                      Navigator.pop(context); 
                    },
                  ),
                ),
                const Divider(indent: 20, endIndent: 20),

                // RESTO DE OPCIONES...
                _DrawerItem(
                  icon: Icons.table_restaurant_outlined, 
                  text: 'Control de Mesas',
                  onTap: () { Navigator.pop(context); context.go('/mesas'); },
                ),

                rolAsync.when(
                  data: (rol) {
                    if (rol.toLowerCase() != 'admin') return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 15, 20, 5),
                          child: Text('ADMINISTRACIÓN', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                        ),
                        _DrawerItem(
                          icon: Icons.restaurant_menu,
                          text: 'Administrar Carta',
                          onTap: () { Navigator.pop(context); context.go('/admin/productos'); },
                        ),
                        _DrawerItem(
                          icon: Icons.category_outlined,
                          text: 'Categorías',
                          onTap: () { Navigator.pop(context); context.go('/admin/categorias'); },
                        ),
                        _DrawerItem(
                          icon: Icons.local_offer_outlined,
                          text: 'Promociones',
                          onTap: () { Navigator.pop(context); context.go('/admin/promociones'); },
                        ),
                        _DrawerItem(
                          icon: Icons.bar_chart_rounded,
                          text: 'Historial y Reportes',
                          onTap: () { Navigator.pop(context); context.go('/historial-pedidos'); },
                        ),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // PIE
          const Divider(height: 1),
          Container(
            color: Colors.grey[50],
            child: SafeArea(
              top: false,
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('¿Cerrar Sesión?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: () => Navigator.pop(ctx, true), 
                          child: const Text('Salir')
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _DrawerItem({required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      leading: Icon(icon, size: 22, color: Colors.grey[700]),
      title: Text(text, style: const TextStyle(fontSize: 14)),
      dense: true,
      onTap: onTap,
    );
  }
}