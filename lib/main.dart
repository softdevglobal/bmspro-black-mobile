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
  
  runApp(const BmsproBlackApp());
}

class BmsproBlackApp extends StatelessWidget {
  const BmsproBlackApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Design palette - premium black theme
    const Color primaryBlack = Color(0xFF1A1A1A); // Deep black
    const Color accentGray = Color(0xFF333333); // Dark gray
    const Color backgroundLight = Color(0xFFF7F7F8); // Slightly warm off-white
    const Color surfaceWhite = Color(0xFFFFFFFF);
    const Color borderColor = Color(0xFFE8E8E8);

    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: primaryBlack,
      brightness: Brightness.light,
      primary: primaryBlack,
      secondary: accentGray,
      background: backgroundLight,
      surface: surfaceWhite,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
    );

    return MaterialApp(
      title: 'BMSPRO BLACK',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppInitializer().navigatorKey,
      builder: (context, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AppInitializer().setRootContext(context);
        });
        return child ?? const SizedBox();
      },
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: backgroundLight,
        fontFamily: GoogleFonts.dmSans().fontFamily,
        // ── Snackbar theme ──
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        // ── Text button ──
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryBlack,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        // ── Text theme ──
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
          headlineMedium: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          titleLarge: TextStyle(fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(height: 1.5),
          bodyMedium: TextStyle(height: 1.5),
        ),
        // ── Input decoration ──
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F8F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryBlack, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        // ── Elevated button (dark fill) ──
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlack,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          ),
        ),
        // ── Outlined button ──
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryBlack,
            side: const BorderSide(color: borderColor, width: 1.5),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          ),
        ),
        // ── App bar ──
        appBarTheme: AppBarTheme(
          backgroundColor: backgroundLight,
          foregroundColor: primaryBlack,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: primaryBlack,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: GoogleFonts.dmSans().fontFamily,
          ),
        ),
        // ── Card theme ──
        cardTheme: CardThemeData(
          color: surfaceWhite,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        // ── Divider ──
        dividerTheme: const DividerThemeData(
          color: borderColor,
          thickness: 1,
        ),
        // ── Dialog ──
        dialogTheme: DialogThemeData(
          backgroundColor: surfaceWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 10,
        ),
        // ── Bottom sheet ──
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: surfaceWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      ),
      onGenerateRoute: AppRoutes.onGenerateRoute,
      home: const SplashScreen(),
    );
  }
}
