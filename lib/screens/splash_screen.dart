import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../routes.dart';
import '../services/auth_state_manager.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Show splash screen for at least 1.5 seconds for smooth UX
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    // Check if this is the first launch
    final isFirstLaunch = await AuthStateManager.isFirstLaunch();
    
    if (isFirstLaunch) {
      // First launch - show welcome/onboarding screens
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.welcome);
    } else {
      // Not first launch - check auth state and navigate accordingly
      final user = await AuthStateManager.waitForAuthState();
      
      if (!mounted) return;

      if (user != null) {
        // User is logged in - go directly to home
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      } else {
        // User is not logged in - go to login
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color accent = Theme.of(context).colorScheme.secondary;
    const Color background = Color(0xFFFFF5FA);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: background,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: primary.withOpacity(0.18),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      )
                    ],
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/icons/bmsblack-icon.jpeg',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'BMS Pro Black',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
