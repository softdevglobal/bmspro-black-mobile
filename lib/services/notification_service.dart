import 'dart:io';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import '../screens/appointment_requests_page.dart';
import '../screens/home_screen.dart';
import 'app_initializer.dart';

/// Top-level function to handle background messages
/// Must be a top-level function, not a class method
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📩 Background FCM message received!');
  print('📩 Message ID: ${message.messageId}');
  print('📩 Notification Title: ${message.notification?.title}');
  print('📩 Notification Body: ${message.notification?.body}');
  print('📩 Data: ${message.data}');
  
  // IMPORTANT: For messages WITH notification payload, FCM automatically shows them
  // when the app is in background/terminated. No action needed.
  
  // For data-only messages, we need to show a local notification
  if (message.notification == null && message.data.isNotEmpty) {
    await _showBackgroundNotification(message);
  }
}

/// Show a local notification for background data messages
/// This is only called for data-only messages (no notification payload)
Future<void> _showBackgroundNotification(RemoteMessage message) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  // Initialize the plugin for background use
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await flutterLocalNotificationsPlugin.initialize(initSettings);
  
  // Create the notification channel for Android (required for Android 8.0+)
  if (Platform.isAndroid) {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'appointments',
      'Booking Notifications',
      description: 'Notifications for booking appointments and updates',
      importance: Importance.high,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
  
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'appointments',
    'Booking Notifications',
    channelDescription: 'Notifications for booking appointments and updates',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    icon: '@mipmap/ic_launcher',
    playSound: true,
    enableVibration: true,
  );
  
  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );
  
  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );
  
  final title = message.data['title'] ?? 'New Notification';
  final body = message.data['message'] ?? message.data['body'] ?? '';
  
  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    title,
    body,
    notificationDetails,
    payload: message.data['bookingId'] ?? '',
  );
  
  print('📩 Background local notification shown: $title');
}

/// Notification service for handling FCM and on-screen notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  String? _fcmToken;
  StreamSubscription<QuerySnapshot>? _notificationSubscription;
  StreamSubscription<QuerySnapshot>? _adminNotificationSubscription;
  StreamSubscription<QuerySnapshot>? _branchAdminNotificationSubscription;
  StreamSubscription<QuerySnapshot>? _branchIdNotificationSubscription; // For branch-filtered notifications
  StreamSubscription<QuerySnapshot>? _customerNotificationSubscription; // For customer notifications
  StreamSubscription<QuerySnapshot>? _targetAdminNotificationSubscription; // For targetAdminUid notifications
  BuildContext? _context;
  final Set<String> _shownNotificationIds = {};
  bool _isInitialized = false;
  String? _userBranchId; // Cached branchId for branch admins
  String? _userRole; // Cached user role

  /// Initialize notification service
  Future<void> initialize() async {
    if (_isInitialized) {
      print('NotificationService already initialized');
      return;
    }
    
    try {
      // Initialize local notifications first
      await _initializeLocalNotifications();
      
      // Request permission for iOS
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        announcement: true,
        carPlay: false,
        criticalAlert: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ User granted notification permission');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ User granted provisional notification permission');
      } else {
        print('❌ User declined or has not accepted notification permission');
        // Continue anyway - we can still set up Firestore listeners for in-app notifications
      }

      // For iOS: Disable automatic foreground notification display
      // We handle foreground notifications manually via onMessage listener
      // to avoid duplicate notifications (system auto-show + our local notification)
      if (Platform.isIOS) {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );
        print('✅ iOS foreground notification options set (alert disabled - handled manually)');
        
        // Get APNs token first (critical for iOS push notifications)
        final apnsToken = await _messaging.getAPNSToken();
        print('🍎 APNs Token: ${apnsToken != null ? "Present (${apnsToken.length} chars)" : "NULL - Push notifications will NOT work!"}');
        
        if (apnsToken == null) {
          print('⚠️ WARNING: APNs token is null. Retrying in 3 seconds...');
          await Future.delayed(const Duration(seconds: 3));
          final retryApnsToken = await _messaging.getAPNSToken();
          print('🍎 APNs Token (retry): ${retryApnsToken != null ? "Present" : "Still NULL"}');
        }
      }

      // Get FCM token
      _fcmToken = await _messaging.getToken();
      print('📱 FCM Token: $_fcmToken');
      
      if (_fcmToken == null) {
        print('⚠️ WARNING: FCM token is null! Push notifications will NOT work.');
      } else {
        print('📱 FCM Token length: ${_fcmToken!.length} characters');
      }

      // Save token to user document
      await _saveFcmToken(_fcmToken);

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        _saveFcmToken(newToken);
        print('📱 FCM Token refreshed: $newToken');
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📩 Received foreground message: ${message.messageId}');
        print('📩 Title: ${message.notification?.title}');
        print('📩 Body: ${message.notification?.body}');
        print('📩 Data: ${message.data}');
        _handleForegroundMessage(message);
      });

      // Handle background messages (when app is opened from notification while in background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('📩 Notification opened app from background: ${message.messageId}');
        _handleNotificationTap(message);
      });

      // Note: Background message handler is registered in main.dart
      // FirebaseMessaging.onBackgroundMessage must be called before runApp()
      
      // Subscribe to topics for broader notification targeting
      await _subscribeToTopics();
      
      _isInitialized = true;
      print('✅ NotificationService initialized successfully');
    } catch (e) {
      print('❌ Error initializing notification service: $e');
    }
  }
  
  /// Initialize flutter_local_notifications
  Future<void> _initializeLocalNotifications() async {
    // Android initialization
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS initialization
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );
    
    // Create notification channels for Android
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        // High priority channel for bookings
        const AndroidNotificationChannel appointmentsChannel = AndroidNotificationChannel(
          'appointments',
          'Booking Notifications',
          description: 'Notifications for booking appointments and updates',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );
        await androidPlugin.createNotificationChannel(appointmentsChannel);
        
        // High priority channel for urgent notifications
        const AndroidNotificationChannel urgentChannel = AndroidNotificationChannel(
          'urgent',
          'Urgent Notifications',
          description: 'Important notifications that require immediate attention',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );
        await androidPlugin.createNotificationChannel(urgentChannel);
        
        // Request exact alarm permission for scheduled notifications (Android 12+)
        await androidPlugin.requestExactAlarmsPermission();
        
        // Request notification permission for Android 13+
        await androidPlugin.requestNotificationsPermission();
      }
    }
    
    print('✅ Local notifications initialized');
  }
  
  /// Handle local notification tap
  void _onLocalNotificationTap(NotificationResponse response) {
    print('📩 Local notification tapped: ${response.payload}');
    
    if (_context == null || !_context!.mounted) return;
    if (response.payload == null || response.payload!.isEmpty) return;
    
    // Try to parse the payload as JSON to get notification details
    String? notificationType;
    String? bookingId;
    
    try {
      // Payload might be JSON with type and bookingId
      if (response.payload!.startsWith('{')) {
        final Map<String, dynamic> payloadData = 
            Map<String, dynamic>.from(
              (response.payload! as String).isNotEmpty 
                ? _parsePayload(response.payload!) 
                : {}
            );
        notificationType = payloadData['type']?.toString();
        bookingId = payloadData['bookingId']?.toString();
      } else {
        // Legacy: payload is just the bookingId
        bookingId = response.payload;
      }
    } catch (e) {
      // If parsing fails, treat payload as bookingId
      bookingId = response.payload;
    }
    
    print('📩 Notification type: $notificationType, bookingId: $bookingId');
    
    // Navigate based on notification type
    // Owner/Admin notifications go to HomeScreen with Bookings tab (index 2)
    if (notificationType == 'booking_needs_assignment' ||
        notificationType == 'booking_engine_new_booking' ||
        notificationType == 'staff_booking_created' ||
        notificationType == 'branch_booking_created' ||
        notificationType == 'staff_assignment' ||
        notificationType == 'staff_reassignment' ||
        notificationType == 'booking_assigned' ||
        notificationType == 'booking_confirmed' ||
        notificationType == 'booking_status_changed' ||
        notificationType == 'booking_completed' ||
        notificationType == 'booking_canceled' ||
        notificationType == 'staff_rejected') {
      // Navigate to HomeScreen with Bookings tab selected (index 2 for owners)
      // This ensures the bottom navigation bar is visible
      Navigator.of(_context!).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const HomeScreen(initialTabIndex: 2),
        ),
        (route) => false, // Remove all previous routes
      );
    } else if (notificationType == 'booking_approval_request') {
      // Staff approval requests go to AppointmentRequestsPage
      Navigator.of(_context!).push(
        MaterialPageRoute(
          builder: (context) => const AppointmentRequestsPage(),
        ),
      );
    } else {
      // Default: go to HomeScreen with Bookings tab for any booking-related notification
      Navigator.of(_context!).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const HomeScreen(initialTabIndex: 2),
        ),
        (route) => false,
      );
    }
  }
  
  /// Helper to parse JSON payload
  Map<String, dynamic> _parsePayload(String payload) {
    try {
      if (payload.isEmpty) return {};
      return Map<String, dynamic>.from(jsonDecode(payload));
    } catch (e) {
      print('Error parsing notification payload: $e');
      return {};
    }
  }
  
  /// Subscribe to FCM topics
  Future<void> _subscribeToTopics() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    try {
      // Subscribe to user-specific topic
      await _messaging.subscribeToTopic('user_${user.uid}');
      print('📢 Subscribed to topic: user_${user.uid}');
    } catch (e) {
      print('⚠️ Error subscribing to topics: $e');
    }
  }

  /// Save FCM token to user document (and salon_staff if exists)
  Future<void> _saveFcmToken(String? token) async {
    if (token == null) {
      print('⚠️ _saveFcmToken: Token is null, skipping save');
      return;
    }
    
    final user = _auth.currentUser;
    if (user == null) {
      print('⚠️ _saveFcmToken: No user logged in, skipping save');
      return;
    }

    print('💾 Saving FCM token for user ${user.uid}');
    print('💾 Token: ${token.substring(0, 20)}...${token.substring(token.length - 20)}');
    print('💾 Platform: ${Platform.isAndroid ? 'android' : 'ios'}');

    try {
      // Save to users collection with additional metadata
      await _db.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'deviceInfo': {
          'os': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
          'lastActive': FieldValue.serverTimestamp(),
        },
      });
      print('✅ FCM token saved to users collection');
    } catch (e) {
      print('⚠️ Error saving FCM token to users collection: $e');
      // Try to create the document if it doesn't exist
      try {
        await _db.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'deviceInfo': {
            'os': Platform.operatingSystem,
            'osVersion': Platform.operatingSystemVersion,
            'lastActive': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
        print('✅ FCM token saved to users collection (merged)');
      } catch (e2) {
        print('❌ Error saving FCM token (merge attempt): $e2');
      }
    }
    
    // Also try to save to salon_staff collection (for branch admins and staff)
    try {
      final staffDoc = await _db.collection('salon_staff').doc(user.uid).get();
      if (staffDoc.exists) {
        await _db.collection('salon_staff').doc(user.uid).update({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          'platform': Platform.isAndroid ? 'android' : 'ios',
        });
        print('✅ FCM token also saved to salon_staff collection');
      }
    } catch (e) {
      // It's okay if this fails - user might not be in salon_staff collection
      print('⚠️ Could not save FCM token to salon_staff (user may not be staff): $e');
    }
  }
  
  /// Force refresh the FCM token - useful if notifications aren't working
  Future<String?> forceRefreshToken() async {
    print('🔄 Force refreshing FCM token...');
    try {
      // Delete the current token
      await _messaging.deleteToken();
      print('🗑️ Old FCM token deleted');
      
      // Wait a moment
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Get a new token
      _fcmToken = await _messaging.getToken();
      print('📱 New FCM Token: $_fcmToken');
      
      if (_fcmToken != null) {
        await _saveFcmToken(_fcmToken);
        print('✅ New FCM token saved');
      }
      
      return _fcmToken;
    } catch (e) {
      print('❌ Error refreshing FCM token: $e');
      return null;
    }
  }
  
  /// Get the current FCM token
  String? get fcmToken => _fcmToken;
  
  /// Verify FCM token is valid and saved
  Future<bool> verifyFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      print('⚠️ verifyFcmToken: No user logged in');
      return false;
    }
    
    try {
      // Get the current device token
      final currentToken = await _messaging.getToken();
      print('📱 Current device FCM token: ${currentToken != null ? "Present" : "NULL"}');
      
      // Get the saved token from Firestore
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final savedToken = userDoc.data()?['fcmToken']?.toString();
      print('💾 Saved FCM token in Firestore: ${savedToken != null ? "Present" : "NULL"}');
      
      // Check if they match
      if (currentToken == null) {
        print('❌ Current FCM token is null!');
        return false;
      }
      
      if (savedToken == null) {
        print('⚠️ No saved token in Firestore, saving current token...');
        await _saveFcmToken(currentToken);
        return true;
      }
      
      if (currentToken != savedToken) {
        print('⚠️ Token mismatch! Updating Firestore with current token...');
        await _saveFcmToken(currentToken);
      } else {
        print('✅ FCM tokens match');
      }
      
      return true;
    } catch (e) {
      print('❌ Error verifying FCM token: $e');
      return false;
    }
  }

  /// Set context for showing on-screen notifications
  void setContext(BuildContext context) {
    _context = context;
  }

  /// Listen to Firestore notifications and show on-screen notifications
  /// Only shows NEW notifications that arrive while app is running, not old unread ones
  void listenToNotifications() async {
    final user = _auth.currentUser;
    if (user == null) {
      print('⚠️ listenToNotifications: No user logged in, skipping');
      return;
    }

    print('🔔 listenToNotifications: Starting for user: ${user.uid}');
    
    // Cancel existing subscriptions
    _notificationSubscription?.cancel();
    _adminNotificationSubscription?.cancel();
    _branchAdminNotificationSubscription?.cancel();
    _branchIdNotificationSubscription?.cancel();
    _customerNotificationSubscription?.cancel();
    _targetAdminNotificationSubscription?.cancel();
    _shownNotificationIds.clear();
    
    print('🔔 listenToNotifications: Cancelled existing subscriptions, starting fresh');
    
    // Fetch user role and branchId for branch admin filtering
    try {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        _userRole = userData?['role']?.toString();
        _userBranchId = userData?['branchId']?.toString();
        print('📱 User role: $_userRole, branchId: $_userBranchId');
      }
    } catch (e) {
      print('⚠️ Error fetching user role/branchId: $e');
    }
    
    // Track if this is the first snapshot (initial load) - we skip showing those notifications
    bool isInitialLoad = true;
    
    // Query for staff notifications - only listen for NEW ones (created after we started listening)
    // Note: Removed orderBy to avoid needing composite indexes - we only care about new docs
    _notificationSubscription = _db
        .collection('notifications')
        .where('staffUid', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      // Skip the initial snapshot - only process changes that happen AFTER we start listening
      if (isInitialLoad) {
        isInitialLoad = false;
        // Don't show any notifications from the initial load
        return;
      }
      
      // Only process NEW notifications (documents that were added after we started listening)
      for (final change in snapshot.docChanges) {
        // Only show if it's a new document (added), not modified or existing
        if (change.type == DocumentChangeType.added) {
          final doc = change.doc;
          final data = doc.data();
          
          // Skip if data is null
          if (data == null) continue;
          
          // Skip if we've already shown this notification
          if (_shownNotificationIds.contains(doc.id)) continue;
          
          final type = data['type']?.toString() ?? '';
          
          // Show all notification types to staff
          // Only skip if already read
          if (data['read'] == true) continue;
          
          _shownNotificationIds.add(doc.id);
          _showOnScreenNotification(
            title: data['title']?.toString() ?? 'New Notification',
            message: data['message']?.toString() ?? '',
            notificationId: doc.id,
            notificationData: data,
          );
          
          // Also show a local notification for better visibility
          _showLocalNotification(
            id: doc.id.hashCode,
            title: data['title']?.toString() ?? 'New Notification',
            body: data['message']?.toString() ?? '',
            bookingId: data['bookingId']?.toString(),
            notificationType: type,
          );
        }
      }
    }, onError: (e) {
      print('❌ Error listening to staff notifications: $e');
    });
    
    // Query for admin notifications (ownerUid) - only listen for NEW ones
    // This includes notifications where owner is directly the recipient (staff created bookings, etc.)
    // Note: Removed orderBy to avoid needing composite indexes
    bool isInitialAdminLoad = true;
    _adminNotificationSubscription = _db
        .collection('notifications')
        .where('ownerUid', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      // Skip the initial snapshot
      if (isInitialAdminLoad) {
        isInitialAdminLoad = false;
        return;
      }
      
      // Only process NEW notifications
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final doc = change.doc;
          final data = doc.data();
          
          // Skip if data is null
          if (data == null) continue;
          
          // Skip if we've already shown this notification
          if (_shownNotificationIds.contains(doc.id)) continue;
          
          final type = data['type']?.toString() ?? '';
          final staffUid = data['staffUid']?.toString();
          final targetAdminUid = data['targetAdminUid']?.toString();
          final targetOwnerUid = data['targetOwnerUid']?.toString();
          
          // Show notification if:
          // 1. It's explicitly targeted to the owner (targetOwnerUid matches)
          // 2. It's a staff_booking_created or booking_engine_new_booking notification
          // 3. It's a booking_needs_assignment notification (unassigned bookings)
          // 4. It's a staff_rejected notification (staff rejected booking, needs reassignment)
          bool shouldShow = false;
          
          if (targetOwnerUid == user.uid) {
            shouldShow = true;
          } else if (type == 'staff_booking_created' || 
                     type == 'booking_engine_new_booking' ||
                     type == 'booking_needs_assignment' ||
                     type == 'staff_rejected') {
            shouldShow = true;
          } else if ((staffUid == null || staffUid != user.uid) && 
              (targetAdminUid == null || targetAdminUid == user.uid)) {
            // General admin notification
            shouldShow = true;
          }
          
          if (shouldShow) {
            // Only show if unread
            if (data['read'] == true) continue;
            
            _shownNotificationIds.add(doc.id);
            _showOnScreenNotification(
              title: data['title']?.toString() ?? 'New Notification',
              message: data['message']?.toString() ?? '',
              notificationId: doc.id,
              notificationData: data,
            );
            
            // Also show a local notification for better visibility
            _showLocalNotification(
              id: doc.id.hashCode,
              title: data['title']?.toString() ?? 'New Notification',
              body: data['message']?.toString() ?? '',
              bookingId: data['bookingId']?.toString(),
              notificationType: type,
            );
          }
        }
      }
    }, onError: (e) {
      print('❌ Error listening to admin notifications: $e');
    });
    
    // Query for branch admin notifications (branchAdminUid)
    // IMPORTANT: This listener is set up for ALL users, not just branch admins
    // It will only match notifications where branchAdminUid == user.uid
    // Note: Removed orderBy to avoid needing composite indexes
    bool isInitialBranchAdminLoad = true;
    print('🔔 Setting up branch admin notification listener for user: ${user.uid}');
    _branchAdminNotificationSubscription = _db
        .collection('notifications')
        .where('branchAdminUid', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      print('🔔 Branch admin notification snapshot received - total docs: ${snapshot.docs.length}, changes: ${snapshot.docChanges.length}, isInitial: $isInitialBranchAdminLoad');
      
      // Log all documents in snapshot for debugging
      for (final doc in snapshot.docs) {
        final data = doc.data();
        print('🔔 Branch admin notification doc - id: ${doc.id}, type: ${data['type']}, branchAdminUid: ${data['branchAdminUid']}, branchId: ${data['branchId']}, read: ${data['read']}');
      }
      
      // Skip the initial snapshot
      if (isInitialBranchAdminLoad) {
        print('🔔 Skipping initial branch admin notification snapshot (${snapshot.docs.length} existing notifications)');
        isInitialBranchAdminLoad = false;
        return;
      }
      
      // Only process NEW notifications
      for (final change in snapshot.docChanges) {
        print('🔔 Branch admin notification change - type: ${change.type}, docId: ${change.doc.id}');
        
        if (change.type == DocumentChangeType.added) {
          final doc = change.doc;
          final data = doc.data();
          
          print('🔔 Branch admin notification added - docId: ${doc.id}');
          print('🔔   - type: ${data?['type']}');
          print('🔔   - branchAdminUid: ${data?['branchAdminUid']} (expected: ${user.uid})');
          print('🔔   - targetAdminUid: ${data?['targetAdminUid']}');
          print('🔔   - branchId: ${data?['branchId']}');
          print('🔔   - read: ${data?['read']}');
          print('🔔   - title: ${data?['title']}');
          
          // Skip if data is null
          if (data == null) {
            print('⚠️ Branch admin notification data is null, skipping');
            continue;
          }
          
          // Verify branchAdminUid matches (should always be true due to query, but double-check)
          final notifBranchAdminUid = data['branchAdminUid']?.toString();
          if (notifBranchAdminUid != user.uid) {
            print('⚠️ Branch admin notification branchAdminUid mismatch! Expected: ${user.uid}, Got: $notifBranchAdminUid');
            continue;
          }
          
          // Skip if we've already shown this notification
          if (_shownNotificationIds.contains(doc.id)) {
            print('⚠️ Branch admin notification already shown: ${doc.id}');
            continue;
          }
          
          // Only show if unread
          if (data['read'] == true) {
            print('⚠️ Branch admin notification already read: ${doc.id}');
            continue;
          }
          
          print('✅ Showing branch admin notification: ${doc.id}');
          _shownNotificationIds.add(doc.id);
          _showOnScreenNotification(
            title: data['title']?.toString() ?? 'New Booking',
            message: data['message']?.toString() ?? '',
            notificationId: doc.id,
            notificationData: data,
          );
          
          // Also show a local notification for better visibility
          final notifType = data['type']?.toString() ?? 'branch_booking_created';
          _showLocalNotification(
            id: doc.id.hashCode,
            title: data['title']?.toString() ?? 'New Booking',
            body: data['message']?.toString() ?? '',
            bookingId: data['bookingId']?.toString(),
            notificationType: notifType,
          );
        } else if (change.type == DocumentChangeType.modified) {
          print('🔔 Branch admin notification modified: ${change.doc.id}');
        } else if (change.type == DocumentChangeType.removed) {
          print('🔔 Branch admin notification removed: ${change.doc.id}');
        }
      }
    }, onError: (e) {
      print('❌ Error listening to branch admin notifications: $e');
      print('❌ Error stack: ${e.toString()}');
    });
    
    // Also listen for targetAdminUid notifications (for reassignments, etc.)
    // Note: Removed orderBy to avoid needing composite indexes
    // FIX: Store subscription so it can be cancelled in dispose()
    bool isInitialTargetAdminLoad = true;
    _targetAdminNotificationSubscription = _db
        .collection('notifications')
        .where('targetAdminUid', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      // Skip the initial snapshot
      if (isInitialTargetAdminLoad) {
        isInitialTargetAdminLoad = false;
        return;
      }
      
      // Only process NEW notifications
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final doc = change.doc;
          final data = doc.data();
          
          // Skip if data is null
          if (data == null) continue;
          
          // Skip if we've already shown this notification
          if (_shownNotificationIds.contains(doc.id)) continue;
          
          // Skip if it was already shown via branchAdminUid query
          final branchAdminUid = data['branchAdminUid']?.toString();
          if (branchAdminUid == user.uid) continue;
          
          // Only show if unread
          if (data['read'] == true) continue;
          
          _shownNotificationIds.add(doc.id);
          _showOnScreenNotification(
            title: data['title']?.toString() ?? 'New Notification',
            message: data['message']?.toString() ?? '',
            notificationId: doc.id,
            notificationData: data,
          );
          
          // Also show a local notification for better visibility
          final notifType = data['type']?.toString() ?? 'admin_notification';
          _showLocalNotification(
            id: doc.id.hashCode,
            title: data['title']?.toString() ?? 'New Notification',
            body: data['message']?.toString() ?? '',
            bookingId: data['bookingId']?.toString(),
            notificationType: notifType,
          );
        }
      }
    }, onError: (e) {
      print('❌ Error listening to target admin notifications: $e');
    });
    
    // For branch admins: Listen for notifications by branchId
    // This allows branch admins to receive the same notifications as owners for their branch
    if (_userRole == 'salon_branch_admin' && _userBranchId != null && _userBranchId!.isNotEmpty) {
      print('🏢 Setting up branch-filtered notifications for branch: $_userBranchId');
      bool isInitialBranchIdLoad = true;
      _branchIdNotificationSubscription = _db
          .collection('notifications')
          .where('branchId', isEqualTo: _userBranchId)
          .limit(50)
          .snapshots()
          .listen((snapshot) {
        // Skip the initial snapshot
        if (isInitialBranchIdLoad) {
          isInitialBranchIdLoad = false;
          return;
        }
        
        // Only process NEW notifications
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final doc = change.doc;
            final data = doc.data();
            
            // Skip if data is null
            if (data == null) continue;
            
            // Skip if we've already shown this notification
            if (_shownNotificationIds.contains(doc.id)) continue;
            
            // Only show if unread
            if (data['read'] == true) continue;
            
            final type = data['type']?.toString() ?? '';
            final staffUid = data['staffUid']?.toString();
            
            // Skip if the notification was created by the current user
            if (staffUid == user.uid) continue;
            
            // Show these notification types (same as what owners receive)
            bool shouldShow = false;
            if (type == 'staff_booking_created' || 
                type == 'booking_engine_new_booking' ||
                type == 'booking_needs_assignment' ||
                type == 'branch_booking_created' ||
                type == 'booking_confirmed' ||
                type == 'booking_status_changed' ||
                type == 'booking_assigned' ||
                type == 'booking_completed' ||
                type == 'booking_canceled' ||
                type == 'staff_rejected') {
              shouldShow = true;
            }
            
            if (shouldShow) {
              _shownNotificationIds.add(doc.id);
              _showOnScreenNotification(
                title: data['title']?.toString() ?? 'New Notification',
                message: data['message']?.toString() ?? '',
                notificationId: doc.id,
                notificationData: data,
              );
              
              // Also show a local notification for better visibility
              _showLocalNotification(
                id: doc.id.hashCode,
                title: data['title']?.toString() ?? 'New Notification',
                body: data['message']?.toString() ?? '',
                bookingId: data['bookingId']?.toString(),
                notificationType: type,
              );
              
              print('🔔 Branch admin notification shown for branch $_userBranchId: $type');
            }
          }
        }
      }, onError: (e) {
        print('❌ Error listening to branch-filtered notifications: $e');
      });
    }
    
    // Query for customer notifications (customerUid)
    // Note: Removed orderBy to avoid needing composite indexes
    bool isInitialCustomerLoad = true;
    _customerNotificationSubscription = _db
        .collection('notifications')
        .where('customerUid', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      // Skip the initial snapshot
      if (isInitialCustomerLoad) {
        isInitialCustomerLoad = false;
        return;
      }
      
      // Only process NEW notifications
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final doc = change.doc;
          final data = doc.data();
          
          // Skip if data is null
          if (data == null) continue;
          
          // Skip if we've already shown this notification
          if (_shownNotificationIds.contains(doc.id)) continue;
          
          // Only show if unread
          if (data['read'] == true) continue;
          
          _shownNotificationIds.add(doc.id);
          _showOnScreenNotification(
            title: data['title']?.toString() ?? 'New Notification',
            message: data['message']?.toString() ?? '',
            notificationId: doc.id,
            notificationData: data,
          );
          
          // Also show a local notification for better visibility
          final notifType = data['type']?.toString() ?? 'customer_notification';
          _showLocalNotification(
            id: doc.id.hashCode,
            title: data['title']?.toString() ?? 'New Notification',
            body: data['message']?.toString() ?? '',
            bookingId: data['bookingId']?.toString(),
            notificationType: notifType,
          );
          
          print('🔔 Customer notification shown: $notifType');
        }
      }
    }, onError: (e) {
      print('❌ Error listening to customer notifications: $e');
    });
  }
  
  /// Show a local notification using flutter_local_notifications
  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? bookingId,
    String? notificationType,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'appointments',
      'Booking Notifications',
      channelDescription: 'Notifications for booking appointments and updates',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    // Create JSON payload with type and bookingId for navigation
    final payloadData = {
      'type': notificationType ?? 'booking_notification',
      'bookingId': bookingId ?? '',
    };
    final payload = jsonEncode(payloadData);
    
    await _localNotifications.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// Show on-screen notification overlay
  void _showOnScreenNotification({
    required String title,
    required String message,
    required String notificationId,
    Map<String, dynamic>? notificationData,
  }) {
    if (_context == null || !_context!.mounted) return;

    // Show a snackbar or overlay notification
    final overlay = Overlay.of(_context!);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => _NotificationOverlay(
        title: title,
        message: message,
        onTap: () {
          _handleNotificationTapFromData(notificationData);
          overlayEntry.remove();
        },
        onDismiss: () {
          overlayEntry.remove();
        },
      ),
    );

    overlay.insert(overlayEntry);

    // Auto-dismiss after 5 seconds
    Timer(const Duration(seconds: 5), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  /// Handle foreground message from FCM
  /// 
  /// DESIGN: The Firestore real-time listener is the SINGLE source of truth for 
  /// foreground notifications (both overlay + local notification). This avoids
  /// duplicate notifications that occurred when both FCM and Firestore listener
  /// each tried to show notifications independently.
  /// 
  /// FCM still handles background/terminated states automatically via the system.
  void _handleForegroundMessage(RemoteMessage message) {
    print('📩 FCM foreground message received (handled by Firestore listener): ${message.messageId}');
    // No action needed - Firestore listener will show overlay + local notification
    // for this same notification document, ensuring exactly one display.
  }

  /// Handle notification tap (when app is opened from background)
  void _handleNotificationTap(RemoteMessage message) {
    // Mark notification as read
    _handleNotificationTapFromData(message.data);
    
    // Use AppInitializer for consistent navigation handling
    if (_context != null && _context!.mounted) {
      AppInitializer.handleNotificationTap(message, _context);
    } else {
      // If context is not available, try to get it from navigator key
      final navigator = AppInitializer().navigatorKey.currentState;
      if (navigator != null) {
        AppInitializer.handleNotificationTap(message, navigator.context);
      }
    }
  }

  /// Handle notification tap from data (marks notification as read and navigates)
  void _handleNotificationTapFromData(Map<String, dynamic>? data) {
    if (data == null) return;

    final notificationId = data['notificationId']?.toString() ?? '';
    final type = data['type']?.toString() ?? '';
    
    // Mark notification as read in Firestore
    if (notificationId.isNotEmpty) {
      _db.collection('notifications').doc(notificationId).update({'read': true}).catchError((e) {
        debugPrint('Error marking notification as read: $e');
      });
    }
    
    // Navigate based on notification type
    if (_context != null && _context!.mounted) {
      if (type == 'booking_approval_request') {
        // Only booking approval requests go to AppointmentRequestsPage (for staff)
        Navigator.of(_context!).push(
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
        Navigator.of(_context!).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const HomeScreen(initialTabIndex: 2),
          ),
          (route) => false,
        );
      }
    }
  }

  /// Dispose resources
  void dispose() {
    _notificationSubscription?.cancel();
    _adminNotificationSubscription?.cancel();
    _branchAdminNotificationSubscription?.cancel();
    _branchIdNotificationSubscription?.cancel();
    _customerNotificationSubscription?.cancel();
    _targetAdminNotificationSubscription?.cancel();
    _shownNotificationIds.clear();
    _context = null;
    _userBranchId = null;
    _userRole = null;
  }
}

/// Overlay widget for on-screen notifications
class _NotificationOverlay extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationOverlay({
    required this.title,
    required this.message,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<_NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFFFF2D8F).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2D8F).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications_active,
                        color: Color(0xFFFF2D8F),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.message,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF9E9E9E),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: widget.onDismiss,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
