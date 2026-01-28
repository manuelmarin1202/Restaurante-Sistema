import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/router.dart';
import 'config/theme.dart';
import 'package:flutter/foundation.dart'; // <--- Esto trae la constante kIsWeb
import 'dart:io' show Platform; // Para Platform
import 'features/printer_server/services/printer_listener_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// TODO: Mueve esto a un archivo .env o config seguro en producción
const supabaseUrl = 'https://gbkiroikfupmvzdyzquq.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdia2lyb2lrZnVwbXZ6ZHl6cXVxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTY0NDEwNjMsImV4cCI6MjA3MjAxNzA2M30.B2MVEGeqrTmhr_LChSsIxBn14tx7F4KdkpWJAnsFHlo';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );

  runApp(
    // ProviderScope es necesario para que Riverpod funcione
    const ProviderScope(
      child: MainApp(),
    ),
  );
}

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  
  @override
  void initState() {
    super.initState();
    // ACTIVAR SERVIDOR DE IMPRESIÓN SOLO EN WINDOWS
    if (!kIsWeb && Platform.isWindows) {
      PrinterListenerService().startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Escuchamos el router provider (que crearemos abajo)
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Sistema Restaurante',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'PE'), // Español Perú
      ],
      locale: const Locale('es', 'PE'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme, // Define tu tema luego
      routerConfig: router,

    );
  }
}

