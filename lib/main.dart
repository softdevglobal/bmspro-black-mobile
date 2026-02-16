import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'routes.dart';
import 'screens/splash_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'utils/timezone_helper.dart';
import 'services/notification_service.dart';
import 'services/app_initializer.dart';
import 'services/background_location_service.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize timezone data for proper timezone conversions
  TimezoneHelper.initialize();
  
  // Initialize Firebase FIRST
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // CRITICAL: Register background message handler IMMEDIATELY after Firebase init
  // This MUST be done before any other Firebase operations
  // This handler runs when the app is in background or terminated
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  // Initialize notification service (sets up foreground handlers, FCM token, etc.)
  // This will request notification permission
  await NotificationService().initialize();
  
  // Request location permission at startup
  // This will show the system permission dialog for location access
  await PermissionService().requestLocationPermission();
  
  // Check if app was opened from a notification (when app was closed)
  await AppInitializer().checkInitialNotification();
  
  // Resume background location monitoring if there's an active check-in
  // This ensures auto clock-out continues working after app restart
  // Also performs an immediate location check to handle out-of-radius cases
  await BackgroundLocationService().resumeMonitoringIfNeeded();
  
  runApp(const BmsproPinkApp());
}

class BmsproPinkApp extends StatelessWidget {
  const BmsproPinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Design palette to match the provided mockup
    const Color primaryPink = Color(0xFFFF2D8F); // #FF2D8F
    const Color accentPink = Color(0xFFFF6FB5); // #FF6FB5
    const Color backgroundPink = Color(0xFFFFF5FA); // #FFF5FA

    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: primaryPink,
      brightness: Brightness.light,
      primary: primaryPink,
      secondary: accentPink,
      background: backgroundPink,
      surface: Colors.white,
    );

    return MaterialApp(
      title: 'BMSPRO PINK',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppInitializer().navigatorKey,
      builder: (context, child) {
        // Set root context for notification handling when app builds
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AppInitializer().setRootContext(context);
        });
        return child ?? const SizedBox();
      },
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: backgroundPink,
        // Use DM Sans app-wide
        fontFamily: GoogleFonts.dmSans().fontFamily,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryPink,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(height: 1.4),
          bodyMedium: TextStyle(height: 1.4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: const Color(0xFFF2D2E9)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFF2D2E9)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: primaryPink, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryPink,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryPink,
            side: BorderSide(color: primaryPink.withOpacity(0.5)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: const SplashScreen(),
    );
  }
}
