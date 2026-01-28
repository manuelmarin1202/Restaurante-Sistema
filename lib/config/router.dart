//import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Importa tus pantallas
import '../features/auth/presentation/login_screen.dart';
import '../features/mesas/presentation/mesas_screen.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/pedidos/presentation/toma_pedido_screen.dart';
import '../features/pedidos/presentation/detalle_mesa_screen.dart';
import '../features/menu/presentation/admin_productos_screen.dart';
import '../features/menu/presentation/formulario_producto_screen.dart';
import '../../../shared/models/producto_model.dart';
import '../features/pedidos/presentation/historial_pedidos_screen.dart';
import '../features/mesas/presentation/admin_ambientes_screen.dart';
import '../features/caja/presentation/cobro_screen.dart';
import '../features/menu/presentation/admin_categorias_screen.dart';
import '../features/pedidos/presentation/detalle_historial_screen.dart';
import '../features/promociones/presentation/admin_promociones_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Observamos el estado de autenticación
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    // IMPORTANTE: refreshListenable hace que el router reaccione a cambios de auth
    redirect: (context, state) {
      // Si el stream está cargando, no hacemos nada aún
      if (authState.isLoading || authState.hasError) return null;

      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;
      
      final isLoginRoute = state.uri.toString() == '/login';

      if (!isLoggedIn && !isLoginRoute) {
        return '/login'; // Si no estás logueado y vas a otro lado -> Login
      }

      if (isLoggedIn && isLoginRoute) {
        return '/mesas'; // Si ya estás logueado y vas al login -> Mesas
      }

      return null; // Todo en orden
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/mesas',
        builder: (context, state) => const MesasScreen(),
      ),
      GoRoute(
        path: '/pedido/:mesaId',
        builder: (context, state) {
          final mesaId = int.parse(state.pathParameters['mesaId']!);
          // Capturamos si viene un pedidoId (modo edición)
          final pedidoIdStr = state.uri.queryParameters['pedidoId'];
          final pedidoId = pedidoIdStr != null ? int.parse(pedidoIdStr) : null;
          
          return TomaPedidoScreen(mesaId: mesaId, pedidoExistenteId: pedidoId);
        },
      ),
      GoRoute(
        path: '/detalle-mesa/:mesaId',
        builder: (context, state) {
          final mesaId = int.parse(state.pathParameters['mesaId']!);
          return DetalleMesaScreen(mesaId: mesaId);
        },
      ),
      GoRoute(
        path: '/admin/productos',
        builder: (context, state) => const AdminProductosScreen(),
      ),
      GoRoute(
        path: '/admin/productos/nuevo',
        builder: (context, state) => const FormularioProductoScreen(productoEditar: null),
      ),
      GoRoute(
        path: '/admin/productos/editar',
        builder: (context, state) {
          // Recibimos el objeto Producto a través de 'extra'
          final producto = state.extra as Producto; 
          return FormularioProductoScreen(productoEditar: producto);
        },
      ),
      GoRoute(
        path: '/historial-pedidos',
        builder: (context, state) => const HistorialPedidosScreen(),
      ),
      GoRoute(
        path: '/admin/ambientes',
        builder: (context, state) => const AdminAmbientesScreen(),
      ),
      GoRoute(
        path: '/cobrar',
        builder: (context, state) {
          // Pasamos los datos como objeto 'extra' porque son varios
          final data = state.extra as Map<String, dynamic>;
          return CobroScreen(
            pedidoId: data['pedidoId'],
            mesaId: data['mesaId'],
            total: data['total'],
            nombreClienteExistente: data['nombreClienteExistente'], // Nuevo parámetro
          );
        },
      ),
      GoRoute(
        path: '/admin/categorias',
        builder: (context, state) => const AdminCategoriasScreen(),
      ),
      GoRoute(
        path: '/historial/detalle/:pedidoId',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['pedidoId']!);
          return DetalleHistorialScreen(pedidoId: id);
        },
      ),
      GoRoute(
        path: '/admin/promociones',
        builder: (context, state) => const AdminPromocionesScreen(),
      ),
    ],
  );
});