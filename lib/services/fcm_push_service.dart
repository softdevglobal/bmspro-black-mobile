import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// Service for sending FCM push notifications via the admin panel API
class FcmPushService {
  static final FcmPushService _instance = FcmPushService._internal();
  factory FcmPushService() => _instance;
  FcmPushService._internal();

  // Admin panel API base URL
  static const String _apiBaseUrl = 'https://black.bmspros.com.au';
  
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Send FCM push notification to a specific user (staff, owner, etc.)
  /// 
  /// [targetUid] - The UID of the user to send the notification to
  /// [title] - Notification title
  /// [message] - Notification body message
  /// [data] - Additional data payload (optional)
  Future<bool> sendPushNotification({
    required String targetUid,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ FcmPushService: No authenticated user, cannot send push notification');
        return false;
      }

      final token = await user.getIdToken();
      if (token == null) {
        debugPrint('⚠️ FcmPushService: Could not get auth token');
        return false;
      }

      debugPrint('📤 FcmPushService: Sending push notification to $targetUid');
      debugPrint('📤 Title: $title');
      
      // Try to get the target user's FCM token directly from Firestore
      // This helps the server if it doesn't have access to Firestore
      String? targetFcmToken;
      String? targetPlatform;
      try {
        final userDoc = await _db.collection('users').doc(targetUid).get();
        if (userDoc.exists) {
          targetFcmToken = userDoc.data()?['fcmToken']?.toString();
          targetPlatform = userDoc.data()?['platform']?.toString();
          debugPrint('📤 Target FCM Token found: ${targetFcmToken != null ? "Yes (${targetFcmToken.length} chars)" : "No"}');
          debugPrint('📤 Target Platform: $targetPlatform');
        } else {
          debugPrint('⚠️ FcmPushService: Target user document not found');
        }
      } catch (e) {
        debugPrint('⚠️ FcmPushService: Could not fetch target FCM token: $e');
      }
      
      if (targetFcmToken == null || targetFcmToken.isEmpty) {
        debugPrint('⚠️ FcmPushService: No FCM token for user $targetUid - push notification will likely fail');
      }
      
      final requestBody = {
        'staffUid': targetUid, // API expects staffUid but works for any user
        'targetUid': targetUid, // Also include as targetUid for clarity
        'title': title,
        'message': message,
        'body': message, // Some APIs expect 'body' instead of 'message'
        'data': data ?? {},
        // Include FCM token directly so server doesn't have to look it up
        'fcmToken': targetFcmToken,
        'platform': targetPlatform,
        // For iOS, ensure proper APNs configuration
        'apns': {
          'payload': {
            'aps': {
              'alert': {
                'title': title,
                'body': message,
              },
              'sound': 'default',
              'badge': 1,
              'content-available': 1, // For background delivery
              'mutable-content': 1, // For notification service extension
            },
          },
          'headers': {
            'apns-priority': '10', // High priority
            'apns-push-type': 'alert',
          },
        },
        // For Android
        'android': {
          'priority': 'high',
          'notification': {
            'channel_id': 'appointments',
            'sound': 'default',
          },
        },
      };
      
      debugPrint('📤 FcmPushService: Request URL: $_apiBaseUrl/api/notifications/send-push');
      debugPrint('📤 FcmPushService: Request body: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/notifications/send-push'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('❌ FcmPushService: Request timed out');
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      debugPrint('📤 FcmPushService: Response status: ${response.statusCode}');
      debugPrint('📤 FcmPushService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ FcmPushService: Push notification API call successful for $targetUid');
        
        // Try to parse response to check if FCM was actually sent
        try {
          final responseData = jsonDecode(response.body);
          if (responseData['success'] == true) {
            debugPrint('✅ FcmPushService: Server confirmed FCM message sent');
          } else if (responseData['error'] != null) {
            debugPrint('⚠️ FcmPushService: Server returned error: ${responseData['error']}');
          }
        } catch (e) {
          // Response might not be JSON, that's okay
        }
        
        return true;
      } else {
        debugPrint('❌ FcmPushService: Failed to send push notification: ${response.statusCode}');
        debugPrint('❌ Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ FcmPushService: Error sending push notification: $e');
      return false;
    }
  }

  /// Send booking notification to salon owner when staff creates a booking
  Future<bool> sendOwnerBookingNotification({
    required String ownerUid,
    required String bookingId,
    required String bookingCode,
    required String clientName,
    required String serviceNames,
    required String dateStr,
    required String timeStr,
    required String branchName,
    required String creatorName,
    required String creatorRole,
  }) async {
    final roleLabel = creatorRole == 'branch_admin' ? 'Branch Admin' : 'Staff';
    final title = 'New Booking Created by $roleLabel';
    final message = '$creatorName created a booking for $clientName - $serviceNames at $branchName on $dateStr at $timeStr';

    return sendPushNotification(
      targetUid: ownerUid,
      title: title,
      message: message,
      data: {
        'type': 'staff_booking_created',
        'bookingId': bookingId,
        'bookingCode': bookingCode,
      },
    );
  }

  /// Send booking notification to assigned staff member
  Future<bool> sendStaffAssignmentNotification({
    required String staffUid,
    required String bookingId,
    required String bookingCode,
    required String clientName,
    required String serviceNames,
    required String dateStr,
    required String timeStr,
    required String branchName,
  }) async {
    final title = 'New Appointment Request';
    final message = 'You have a new appointment request from $clientName for $serviceNames on $dateStr at $timeStr at $branchName. Please accept or reject this booking.';

    return sendPushNotification(
      targetUid: staffUid,
      title: title,
      message: message,
      data: {
        'type': 'staff_assignment',
        'bookingId': bookingId,
        'bookingCode': bookingCode,
      },
    );
  }

  /// Send booking confirmation notification to staff
  Future<bool> sendStaffBookingConfirmedNotification({
    required String staffUid,
    required String bookingId,
    required String bookingCode,
    required String clientName,
    required String serviceNames,
    required String dateStr,
    required String timeStr,
  }) async {
    final title = 'Booking Confirmed';
    final message = 'Your booking with $clientName for $serviceNames on $dateStr at $timeStr has been confirmed.';

    return sendPushNotification(
      targetUid: staffUid,
      title: title,
      message: message,
      data: {
        'type': 'booking_confirmed',
        'bookingId': bookingId,
        'bookingCode': bookingCode,
      },
    );
  }

  /// Send notification to owner about unassigned booking
  Future<bool> sendUnassignedBookingNotification({
    required String ownerUid,
    required String bookingId,
    required String bookingCode,
    required String clientName,
    required String serviceNames,
    required String dateStr,
    required String timeStr,
    required String branchName,
    required String source, // 'booking_engine' or 'admin_panel'
  }) async {
    final sourceLabel = source == 'booking_engine' ? 'Booking Engine' : 'Admin Panel';
    final title = 'New Unassigned Booking';
    final message = 'New booking from $clientName for $serviceNames on $dateStr at $timeStr at $branchName needs staff assignment. Source: $sourceLabel';

    return sendPushNotification(
      targetUid: ownerUid,
      title: title,
      message: message,
      data: {
        'type': 'booking_needs_assignment',
        'bookingId': bookingId,
        'bookingCode': bookingCode,
        'source': source,
      },
    );
  }
}

