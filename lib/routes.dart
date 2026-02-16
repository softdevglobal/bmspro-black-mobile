import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
// import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/staff_check_in_page.dart';
import 'screens/branch_location_picker_page.dart';

class AppRoutes {
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String staffCheckIn = '/staff-check-in';
  static const String branchLocationPicker = '/branch-location-picker';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case welcome:
        return MaterialPageRoute(builder: (_) => const WelcomeScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      // case register:
      //   return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case staffCheckIn:
        return MaterialPageRoute(builder: (_) => const StaffCheckInPage());
      // Note: branchLocationPicker requires arguments, use Navigator.push with MaterialPageRoute
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Route not found')),
          ),
        );
    }
  }
}
