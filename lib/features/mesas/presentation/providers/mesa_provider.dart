import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/models/mesa_model.dart';
import '../../../../shared/models/zona_model.dart';

// 1. Provider de Zonas (Auxiliar)
final zonasListProvider = FutureProvider<List<Zona>>((ref) async {
  final data = await Supabase.instance.client.from('zonas').select();
  return (data as List).map((e) => Zona.fromJson(e)).toList();
});

// 2. NOTIFIER ROBUSTO PARA MESAS
class MesasNotifier extends StateNotifier<AsyncValue<List<Mesa>>> {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSubscription;
  bool _isReconnecting = false;

  MesasNotifier() : super(const AsyncValue.loading()) {
    _cargarDatosIniciales();
    
    // --- SOLUCIÓN AL "INVALID TOKEN" ---
    // Escuchamos cuando el usuario inicia sesión o se refresca el token vencido.
    // Apenas ocurra, reiniciamos la conexión Realtime con el token fresco.
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.tokenRefreshed) {
        debugPrint("🔐 AUTH EVENT: ${event.name} -> Reconectando Realtime...");
        _iniciarEscuchaRobusta();
      }
    });

    // Intentamos conectar inicialmente por si el token ya es válido
    _iniciarEscuchaRobusta();
  }

  // Carga manual de datos (Pull)
  Future<void> _cargarDatosIniciales() async {
    try {
      final data = await _supabase
          .from('mesas')
          .select('''
            *,
            zonas(nombre),
            pedidos(nombre_cliente, hora_recojo, estado)
          ''')
          // FILTRO CLAVE: Solo queremos los pedidos pendientes para mostrar en el mapa
          // Nota: En Supabase PostgREST, filtrar relaciones anidadas se hace así:
          // Pero para simplificar y no romper el stream, traemos todo y filtramos en Dart 
          // O usamos un filtro !inner si queremos forzar.
          // Lo más seguro en realtime simple es traer la relación y filtrar en el fromJson o aquí.
          .order('id');
      
      // NOTA TÉCNICA: El filtrado de pedidos(estado=eq.pendiente) directo en el select 
      // a veces requiere configuración extra en Supabase. 
      // Una forma robusta es procesar la lista aquí:
      
      final mesas = (data as List).map((m) {
        // Filtramos manualmente los pedidos que no sean 'pendiente' antes de pasar al modelo
        final pedidosRaw = m['pedidos'] as List<dynamic>? ?? [];
        final pedidosPendientes = pedidosRaw.where((p) => p['estado'] == 'pendiente').toList();
        m['pedidos'] = pedidosPendientes; // Reemplazamos para que el fromJson lo lea
        return Mesa.fromJson(m);
      }).toList();
      state = AsyncValue.data(mesas);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  // Escucha con reconexión automática (Push)
  void _iniciarEscuchaRobusta() {
    if (_isReconnecting) return;
    
    // Si ya existe un canal, lo cerramos para abrir uno limpio con el nuevo token
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }

    // Verificamos sesión antes de intentar conectar
    if (_supabase.auth.currentSession == null) {
      debugPrint("⛔ No hay sesión activa. Esperando autenticación...");
      return;
    }

    debugPrint("📡 CONECTANDO TABLERO DE MESAS...");

    _channel = _supabase.channel('public:mesas');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all, 
          schema: 'public',
          table: 'mesas',
          callback: (payload) {
            debugPrint("🔄 CAMBIO EN MESAS DETECTADO: Recargando...");
            _cargarDatosIniciales();
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint("✅ MESAS SINCRONIZADAS.");
            _isReconnecting = false;
          } 
          else if (status == RealtimeSubscribeStatus.channelError) {
            // Este es el error del Token Expirado.
            // No forzamos reconexión aquí inmediatamente, dejamos que el listener de Auth
            // (definido en el constructor) se encargue cuando el token se refresque.
            debugPrint("❌ ERROR DE CANAL (Posible Token Vencido): $error");
          }
          else if (status == RealtimeSubscribeStatus.closed || 
                   status == RealtimeSubscribeStatus.timedOut) {
            debugPrint("⚠️ PÉRDIDA DE CONEXIÓN. Reintentando en 5s...");
            _programarReconexion();
          }
        });
  }

  void _programarReconexion() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    
    Future.delayed(const Duration(seconds: 5), () {
      // Verificamos mounted antes de ejecutar lógica en un objeto que podría estar muerto
      if (!mounted) return; 
      
      _isReconnecting = false;
      _iniciarEscuchaRobusta();
      _cargarDatosIniciales();
    });
  }

  @override
  void dispose() {
    // Limpieza de suscripciones
    _authSubscription?.cancel();
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }
}

final mesasProvider = StateNotifierProvider<MesasNotifier, AsyncValue<List<Mesa>>>((ref) {
  return MesasNotifier();
});