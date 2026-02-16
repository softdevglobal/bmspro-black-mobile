import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../screens/appointment_requests_page.dart';
import '../screens/home_screen.dart';

/// Service to handle app initialization and notification navigation
class AppInitializer {
  static final AppInitializer _instance = AppInitializer._internal();
  factory AppInitializer() => _instance;
  AppInitializer._internal();

  BuildContext? _rootContext;
  RemoteMessage? _pendingNotification;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Set the root navigator context (should be called from main app widget)
  void setRootContext(BuildContext context) {
    _rootContext = context;
    // If there's a pending notification, handle it now that we have context
    if (_pendingNotification != null) {
      _handlePendingNotification();
    }
  }

  /// Check for initial notification when app starts (called from main.dart)
  Future<void> checkInitialNotification() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _pendingNotification = initialMessage;
        // If context is already available, handle immediately
        if (_rootContext != null) {
          _handlePendingNotification();
        }
      }
    } catch (e) {
      debugPrint('Error checking initial notification: $e');
    }
  }

  /// Handle pending notification navigation
  void _handlePendingNotification() {
    if (_pendingNotification == null) return;

    final message = _pendingNotification!;
    _pendingNotification = null;

    // Wait a bit for the app to fully initialize before navigating
    Future.delayed(const Duration(milliseconds: 2000), () {
      final navigator = navigatorKey.currentState;
      if (navigator == null) return;
      
      final data = message.data;
      final type = data['type']?.toString() ?? '';
      
      // Navigate based on notification type
      if (type == 'booking_approval_request') {
        // Only booking approval requests go to AppointmentRequestsPage (for staff)
        navigator.push(
          MaterialPageRoute(
            builder: (context) => const AppointmentRequestsPage(),
          ),
        );
      } else if (type == 'staff_assignment' || 
                 type == 'staff_reassignment' ||
                 type == 'branch_booking_created' || 
                 type == 'booking_needs_assignment' ||
                 type == 'booking_confirmed' ||
                 type == 'booking_status_changed' ||
                 type == 'staff_booking_created' ||
                 type == 'booking_engine_new_booking' ||
                 type == 'booking_assigned' ||
                 type == 'booking_completed' ||
                 type == 'booking_canceled' ||
                 type == 'staff_rejected') {
        // All booking-related notifications go to HomeScreen with Bookings tab (index 2)
        // This ensures the bottom navigation bar is visible
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const HomeScreen(initialTabIndex: 2),
          ),
          (route) => false,
        );
      } else {
        // Default: go to HomeScreen with Bookings tab for any unrecognized notification
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const HomeScreen(initialTabIndex: 2),
          ),
          (route) => false,
        );
      }
    });
  }

  /// Handle notification tap when app is opened from background
  static void handleNotificationTap(RemoteMessage message, BuildContext? context) {
    if (context == null || !context.mounted) return;

    final data = message.data;
    final type = data['type']?.toString() ?? '';
    
    // Navigate based on notification type
    if (type == 'booking_approval_request') {
      // Only booking approval requests go to AppointmentRequestsPage (for staff)
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const AppointmentRequestsPage(),
        ),
      );
    } else if (type == 'staff_assignment' || 
               type == 'staff_reassignment' ||
               type == 'branch_booking_created' || 
               type == 'booking_needs_assignment' ||
               type == 'booking_confirmed' ||
               type == 'booking_status_changed' ||
               type == 'staff_booking_created' ||
               type == 'booking_engine_new_booking' ||
               type == 'booking_assigned' ||
               type == 'booking_completed' ||
               type == 'booking_canceled' ||
               type == 'staff_rejected') {
      // All booking-related notifications go to HomeScreen with Bookings tab (index 2)
      // This ensures the bottom navigation bar is visible
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const HomeScreen(initialTabIndex: 2),
        ),
        (route) => false,
      );
    } else {
      // Default: go to HomeScreen with Bookings tab for any unrecognized notification
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const HomeScreen(initialTabIndex: 2),
        ),
        (route) => false,
      );
    }
  }
}

