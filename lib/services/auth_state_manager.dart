import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage authentication state and first launch tracking
class AuthStateManager {
  static const String _firstLaunchKey = 'is_first_launch';
  static const String _hasSeenWelcomeKey = 'has_seen_welcome';

  /// Check if this is the first app launch
  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstLaunchKey) ?? true;
  }

  /// Mark that the app has been launched (not first launch anymore)
  static Future<void> setFirstLaunchComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstLaunchKey, false);
  }

  /// Check if user has seen welcome/onboarding screens
  static Future<bool> hasSeenWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenWelcomeKey) ?? false;
  }

  /// Mark that user has seen welcome/onboarding screens
  static Future<void> setWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenWelcomeKey, true);
  }

  /// Get current Firebase Auth user (returns null if not logged in)
  /// Firebase Auth automatically persists sessions, so this checks the existing session
  static User? getCurrentUser() {
    return FirebaseAuth.instance.currentUser;
  }

  /// Stream of auth state changes (for reactive UI updates)
  static Stream<User?> authStateChanges() {
    return FirebaseAuth.instance.authStateChanges();
  }

  /// Check if user is currently authenticated
  static bool isAuthenticated() {
    return FirebaseAuth.instance.currentUser != null;
  }

  /// Wait for auth state to be determined (useful on app startup)
  /// Returns the user if authenticated, null otherwise
  static Future<User?> waitForAuthState({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      // Firebase Auth state is available immediately on startup
      // But we can wait a bit to ensure Firebase is fully initialized
      await Future.delayed(const Duration(milliseconds: 500));
      return FirebaseAuth.instance.currentUser;
    } catch (e) {
      return null;
    }
  }

  /// Clear all stored preferences (useful for testing or logout)
  static Future<void> clearPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}

