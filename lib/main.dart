import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'google_fonts_alias.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'auth_gateway.dart';
import 'public_profile_view_screen.dart';
import 'notification_service.dart';

void main() async {
  // Catch Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      print('Flutter Error: ${details.exceptionAsString()}');
    }
  };

  // Run in a guarded zone for asynchronous Dart errors
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize notification service for lock screen alerts
    await NotificationService.init();

    // Initialize Supabase using values from config.dart
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      publishableKey: SupabaseConfig.supabaseAnonKey,
    );

    runApp(const HexaApp());
  }, (Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      print('Uncaught async error: $error');
      print(stackTrace);
    }
  });
}

class HexaApp extends StatelessWidget {
  const HexaApp({super.key});

  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

  @override
  Widget build(BuildContext context) {
    // Premium Light Minimalist Theme Palette
    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF0EFEF),
      primaryColor: const Color(0xFFF05A30),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFF05A30),
        secondary: Color(0xFFFDF0ED),
        surface: Colors.white,
        outline: Color(0xFFE5E5E5),
      ),
      textTheme: GoogleFonts.firaSansTextTheme(ThemeData.light().textTheme).apply(
        bodyColor: const Color(0xFF1E1E1E),
        displayColor: const Color(0xFF1E1E1E),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          side: BorderSide(color: Color(0xFFE5E5E5), width: 1.0),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Color(0xFFE5E5E5), width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Color(0xFFE5E5E5), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Color(0xFFF05A30), width: 1.5),
        ),
        labelStyle: TextStyle(color: Colors.black54),
        hintStyle: TextStyle(color: Colors.black38),
      ),
    );

    // Premium Dark Minimalist Theme Palette
    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F0E13),
      primaryColor: const Color(0xFFF05A30),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFF05A30),
        secondary: Color(0xFF1E1C24),
        surface: Color(0xFF16151A),
        outline: Color(0xFF2C2A35),
      ),
      textTheme: GoogleFonts.firaSansTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: const Color(0xFFF5F5F7),
        displayColor: const Color(0xFFF5F5F7),
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFF16151A),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          side: BorderSide(color: Color(0xFF2C2A35), width: 1.0),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF16151A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Color(0xFF2C2A35), width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Color(0xFF2C2A35), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Color(0xFFF05A30), width: 1.5),
        ),
        labelStyle: TextStyle(color: Colors.white70),
        hintStyle: TextStyle(color: Colors.white38),
      ),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: HexaApp.themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Hexa',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: currentMode,
          home: const AuthGateway(),
          onGenerateRoute: (settings) {
            if (settings.name != null) {
              final uri = Uri.parse(settings.name!);
              String? targetUsername;

              if (uri.scheme == 'seven' && uri.host == 'p') {
                if (uri.pathSegments.isNotEmpty) {
                  targetUsername = uri.pathSegments.first;
                }
              } else {
                final pathSegments = uri.pathSegments;
                if (pathSegments.length >= 2 && pathSegments[pathSegments.length - 2] == 'p') {
                  targetUsername = pathSegments.last;
                }
              }

              if (targetUsername != null) {
                return MaterialPageRoute(
                  settings: settings,
                  builder: (context) => PublicProfileViewScreen(username: targetUsername!),
                );
              }
            }
            return null;
          },
          builder: (context, child) {
            // Global Error Boundary widget for runtime errors
            ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'An unexpected error occurred',
                          style: GoogleFonts.firaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          errorDetails.exceptionAsString(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.firaSans(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            };
            return child ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}
