import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:async' show TimeoutException;
import 'walk_in_booking_page.dart';
import '../services/audit_log_service.dart';
import '../services/fcm_push_service.dart';

class OwnerBookingsPage extends StatefulWidget {
  const OwnerBookingsPage({super.key});

  @override
  State<OwnerBookingsPage> createState() => _OwnerBookingsPageState();
}

class _OwnerBookingsPageState extends State<OwnerBookingsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';

  // Live booking data from Firestore (bookings + bookingRequests for this owner)
  List<_Booking> _bookings = [];
  // List of available staff
  List<Map<String, dynamic>> _staffList = [];
  // List of services for staff assignment validation
  List<Map<String, dynamic>> _servicesList = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bookingsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bookingRequestsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _staffSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _servicesSub;

  bool _loading = true;
  String? _error;
  
  // User role and branch for filtering
  String? _userRole;
  String? _userBranchId;
  String? _ownerUid;

  @override
  void initState() {
    super.initState();
    _loadUserContextAndListen();
  }
  
  Future<void> _loadUserContextAndListen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = "Not signed in";
      });
      return;
    }

    // Fetch user document to get role and branchId
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        _userRole = (data['role'] ?? '').toString();
        _userBranchId = (data['branchId'] ?? '').toString();
        
        // Determine ownerUid based on role
        if (_userRole == 'workshop_owner') {
          _ownerUid = user.uid;
        } else if (data['ownerUid'] != null) {
          _ownerUid = data['ownerUid'].toString();
        } else {
          _ownerUid = user.uid;
        }
      } else {
        _ownerUid = user.uid;
      }
    } catch (e) {
      debugPrint('Error loading user context: $e');
      _ownerUid = user.uid;
    }

    // Now start listening with the proper context
    _listenToBookings();
    _listenToStaff();
    _listenToServices();
  }

  @override
  void dispose() {
    _bookingsSub?.cancel();
    _bookingRequestsSub?.cancel();
    _staffSub?.cancel();
    _servicesSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToServices() {
    if (_ownerUid == null) return;

    _servicesSub = FirebaseFirestore.instance
        .collection('services')
        .where('ownerUid', isEqualTo: _ownerUid)
        .snapshots()
        .listen((snap) {
      final List<Map<String, dynamic>> loaded = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        loaded.add({
          'id': doc.id,
          'name': (data['name'] ?? '').toString(),
          'staffIds': List<String>.from(data['staffIds'] ?? []),
        });
      }
      if (mounted) {
        setState(() {
          _servicesList = loaded;
        });
      }
    }, onError: (e) {
      debugPrint("Error fetching services: $e");
    });
  }

  void _listenToStaff() {
    if (_ownerUid == null) return;

    final bool isBranchAdmin = _userRole == 'branch_admin' && _userBranchId != null && _userBranchId!.isNotEmpty;

    // Listen to users where ownerUid matches
    // and role is 'staff' or 'branch_admin'
    _staffSub = FirebaseFirestore.instance
        .collection('users')
        .where('ownerUid', isEqualTo: _ownerUid)
        .snapshots()
        .listen((snap) {
      final List<Map<String, dynamic>> loaded = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        final role = (data['role'] ?? '').toString();
        if (role == 'staff' || role == 'branch_admin') {
          final staffBranchId = (data['branchId'] ?? '').toString();
          final weeklySchedule = data['weeklySchedule'] as Map<String, dynamic>?;
          
          // For branch admins, include staff who either:
          // 1. Have primary branchId matching this branch, OR
          // 2. Work at this branch on ANY day via weeklySchedule
          if (isBranchAdmin) {
            bool worksAtBranch = staffBranchId == _userBranchId;
            
            // Also check weeklySchedule for any day at this branch
            if (!worksAtBranch && weeklySchedule != null) {
              for (var daySchedule in weeklySchedule.values) {
                if (daySchedule is Map) {
                  final scheduledBranchId = (daySchedule['branchId'] ?? '').toString();
                  if (scheduledBranchId == _userBranchId) {
                    worksAtBranch = true;
                    break;
                  }
                }
              }
            }
            
            if (!worksAtBranch) continue;
          }
          
          loaded.add({
            'id': doc.id,
            'name': (data['displayName'] ?? data['name'] ?? 'Unknown').toString(),
            'role': (data['staffRole'] ?? data['role'] ?? 'Staff').toString(),
            'avatarUrl': (data['photoURL'] ?? data['avatarUrl']).toString(),
            'branchId': staffBranchId,
            'weeklySchedule': weeklySchedule,
            'status': (data['status'] ?? 'Active').toString(),
            'branch': (data['branch'] ?? '').toString(), // Branch name for matching
          });
        }
      }
      debugPrint('[StaffList] Loaded ${loaded.length} staff members: ${loaded.map((s) => s['name']).toList()}');
      if (mounted) {
        setState(() {
          _staffList = loaded;
        });
      }
    }, onError: (e) {
      debugPrint("Error fetching staff: $e");
    });
  }

  void _listenToBookings() {
    if (_ownerUid == null) {
      setState(() {
        _loading = false;
        _error = "Not signed in";
      });
      return;
    }

    final bool isBranchAdmin = _userRole == 'branch_admin' && _userBranchId != null && _userBranchId!.isNotEmpty;

    List<_Booking> bookingsData = [];
    List<_Booking> bookingRequestsData = [];

    void mergeAndSet() {
      // Merge and deduplicate by an internal key (client+date+time+service as fallback)
      final Map<String, _Booking> map = {};
      for (final b in bookingsData) {
        // For branch admins, filter by branchId
        if (isBranchAdmin && b.branchId != _userBranchId) continue;
        map[b.mergeKey] = b;
      }
      for (final b in bookingRequestsData) {
        // For branch admins, filter by branchId
        if (isBranchAdmin && b.branchId != _userBranchId) continue;
        map[b.mergeKey] = b;
      }
      final merged = map.values.toList()
        ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

      if (mounted) {
        setState(() {
          _bookings = merged;
          _loading = false;
        });
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    _bookingsSub = FirebaseFirestore.instance
        .collection('bookings')
        .where('ownerUid', isEqualTo: _ownerUid)
        .snapshots()
        .listen(
      (snap) {
        bookingsData = snap.docs
            .map((d) => _Booking.fromDoc(d, collection: 'bookings'))
            .toList();
        mergeAndSet();
      },
      onError: (e) {
        if (mounted) {
          setState(() => _error ??= e.toString());
        }
      },
    );

    _bookingRequestsSub = FirebaseFirestore.instance
        .collection('bookingRequests')
        .where('ownerUid', isEqualTo: _ownerUid)
        .snapshots()
        .listen(
      (snap) {
        bookingRequestsData = snap.docs
            .map((d) => _Booking.fromDoc(d, collection: 'bookingRequests'))
            .toList();
        mergeAndSet();
      },
      onError: (e) {
        if (mounted) {
          setState(() => _error ??= e.toString());
        }
      },
    );
  }

  Future<void> _updateBookingStatus(_Booking booking, String newStatus,
      {List<Map<String, dynamic>>? updatedServices}) async {
    final db = FirebaseFirestore.instance;
    try {
      // Store previous status for email triggering
      final String previousStatus = booking.status;
      
      // Check if services need update
      final bool hasServicesUpdate = updatedServices != null && updatedServices.isNotEmpty;
      
      // Determine if this is admin confirming a pending booking
      // In this case, we send to AwaitingStaffApproval for staff to accept (like admin panel)
      final bool isConfirmingPending = 
          (booking.status == 'pending' || booking.collection == 'bookingRequests') && 
          newStatus == 'confirmed';
      
      // The actual status to set - AwaitingStaffApproval when confirming pending bookings
      final String actualStatus = isConfirmingPending ? 'AwaitingStaffApproval' : newStatus;
      
      // Prepare services with approval status for staff approval workflow
      List<Map<String, dynamic>>? servicesForApproval;
      if (isConfirmingPending && hasServicesUpdate) {
        servicesForApproval = updatedServices!.map((service) {
          final s = Map<String, dynamic>.from(service);
          s['approvalStatus'] = 'pending'; // Each staff needs to approve
          // Remove any previous response data
          s.remove('acceptedAt');
          s.remove('rejectedAt');
          s.remove('rejectionReason');
          s.remove('respondedByStaffUid');
          s.remove('respondedByStaffName');
          return s;
        }).toList();
      }

      // If confirming a booking request, move it to 'bookings' collection
      if (booking.collection == 'bookingRequests' && (newStatus == 'confirmed' || isConfirmingPending)) {
        final newData = Map<String, dynamic>.from(booking.rawData);
        newData['status'] = actualStatus;
        newData['updatedAt'] = FieldValue.serverTimestamp();
        
        // Ensure services are updated in the new booking document
        if (servicesForApproval != null) {
          newData['services'] = servicesForApproval;
        } else if (hasServicesUpdate) {
          newData['services'] = updatedServices;
        }

        if (newData['createdAt'] == null) {
          newData['createdAt'] = FieldValue.serverTimestamp();
        }

        // Remove top-level staff fields if they exist to avoid confusion
        if (hasServicesUpdate || (newData['services'] != null && (newData['services'] as List).isNotEmpty)) {
          newData.remove('staffId');
          newData.remove('staffName');
        }

        // Add to bookings
        final ref = await db.collection('bookings').add(newData);
        // Delete from bookingRequests
        await db.collection('bookingRequests').doc(booking.id).delete();
        
          // Send notifications to staff for approval (not customer yet)
          if (isConfirmingPending) {
            await _createStaffApprovalNotifications(
              db: db,
              bookingId: ref.id,
              booking: booking,
              services: servicesForApproval ?? updatedServices ?? [],
            );
            
            // Audit log for sending to staff
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null && _ownerUid != null) {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .get();
              final userData = userDoc.data();
              final userName = userData?['displayName'] ?? 
                  userData?['name'] ?? 
                  currentUser.email ?? 
                  'Unknown';
              final userRole = userData?['role'] ?? 'unknown';
              
              await AuditLogService.logBookingStatusChanged(
                ownerUid: _ownerUid!,
                bookingId: ref.id,
                bookingCode: booking.rawData['bookingCode']?.toString(),
                clientName: booking.rawData['client']?.toString() ?? 'Customer',
                previousStatus: 'pending',
                newStatus: 'AwaitingStaffApproval',
                performedBy: currentUser.uid,
                performedByName: userName.toString(),
                performedByRole: userRole.toString(),
                details: 'Booking request sent to staff for approval',
                branchName: booking.rawData['branchName']?.toString(),
              );
            }
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Booking sent to staff for approval')),
              );
            }
          } else {
            await _createNotification(
              bookingId: ref.id,
              booking: booking,
              newStatus: 'Confirmed',
              updatedServices: updatedServices,
              previousStatus: previousStatus,
            );
            
            // Audit log for confirmation
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null && _ownerUid != null) {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .get();
              final userData = userDoc.data();
              final userName = userData?['displayName'] ?? 
                  userData?['name'] ?? 
                  currentUser.email ?? 
                  'Unknown';
              final userRole = userData?['role'] ?? 'unknown';
              
              await AuditLogService.logBookingStatusChanged(
                ownerUid: _ownerUid!,
                bookingId: ref.id,
                bookingCode: booking.rawData['bookingCode']?.toString(),
                clientName: booking.rawData['client']?.toString() ?? 'Customer',
                previousStatus: 'pending',
                newStatus: 'confirmed',
                performedBy: currentUser.uid,
                performedByName: userName.toString(),
                performedByRole: userRole.toString(),
                branchName: booking.rawData['branchName']?.toString(),
              );
            }
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Booking marked as ${_capitalise(newStatus)}')),
              );
            }
          }

      } else {
        // Update existing booking
        final Map<String, dynamic> updateData = {'status': actualStatus};
        
        if (servicesForApproval != null) {
          updateData['services'] = servicesForApproval;
          updateData['staffId'] = FieldValue.delete();
          updateData['staffName'] = FieldValue.delete();
        } else if (hasServicesUpdate) {
          updateData['services'] = updatedServices;
          updateData['staffId'] = FieldValue.delete();
          updateData['staffName'] = FieldValue.delete();
        }

        await db
            .collection(booking.collection)
            .doc(booking.id)
            .update(updateData);
        
        // Send appropriate notifications
        if (isConfirmingPending) {
          await _createStaffApprovalNotifications(
            db: db,
            bookingId: booking.id,
            booking: booking,
            services: servicesForApproval ?? updatedServices ?? [],
          );
          
          // Audit log for sending to staff
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null && _ownerUid != null) {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .get();
            final userData = userDoc.data();
            final userName = userData?['displayName'] ?? 
                userData?['name'] ?? 
                currentUser.email ?? 
                'Unknown';
            final userRole = userData?['role'] ?? 'unknown';
            
            await AuditLogService.logBookingStatusChanged(
              ownerUid: _ownerUid!,
              bookingId: booking.id,
              bookingCode: booking.rawData['bookingCode']?.toString(),
              clientName: booking.rawData['client']?.toString() ?? 'Customer',
              previousStatus: booking.status,
              newStatus: 'AwaitingStaffApproval',
              performedBy: currentUser.uid,
              performedByName: userName.toString(),
              performedByRole: userRole.toString(),
              details: 'Sent to staff for approval',
              branchName: booking.rawData['branchName']?.toString(),
            );
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Booking sent to staff for approval')),
            );
          }
        } else {
          String notifStatus = _capitalise(newStatus);
          if (newStatus == 'cancelled') notifStatus = 'Canceled';
          
          await _createNotification(
            bookingId: booking.id,
            booking: booking,
            newStatus: notifStatus,
            updatedServices: updatedServices,
            previousStatus: previousStatus,
          );
          
          // Audit log for status change
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null && _ownerUid != null) {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid)
                .get();
            final userData = userDoc.data();
            final userName = userData?['displayName'] ?? 
                userData?['name'] ?? 
                currentUser.email ?? 
                'Unknown';
            final userRole = userData?['role'] ?? 'unknown';
            
            await AuditLogService.logBookingStatusChanged(
              ownerUid: _ownerUid!,
              bookingId: booking.id,
              bookingCode: booking.rawData['bookingCode']?.toString(),
              clientName: booking.rawData['client']?.toString() ?? 'Customer',
              previousStatus: booking.status,
              newStatus: newStatus,
              performedBy: currentUser.uid,
              performedByName: userName.toString(),
              performedByRole: userRole.toString(),
              branchName: booking.rawData['branchName']?.toString(),
            );
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Booking marked as ${_capitalise(newStatus)}')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
  
  /// Send notifications to each staff member assigned to a service for approval
  Future<void> _createStaffApprovalNotifications({
    required FirebaseFirestore db,
    required String bookingId,
    required _Booking booking,
    required List<Map<String, dynamic>> services,
  }) async {
    try {
      debugPrint("🔔 _createStaffApprovalNotifications called for bookingId: $bookingId");
      debugPrint("🔔 Services count: ${services.length}");
      
      final ownerUid = _ownerUid ?? '';
      final Set<String> notifiedStaffIds = {};
      
      // API base URL for sending push notifications
      const String apiBaseUrl = 'https://black.bmspros.com.au';
      
      if (services.isEmpty) {
        debugPrint("⚠️ No services provided, cannot send notifications");
        return;
      }
      
      for (final service in services) {
        debugPrint("🔔 Processing service: ${service['name']} with staffId: ${service['staffId']}");
        final staffId = (service['staffId'] ?? '').toString();
        final staffName = (service['staffName'] ?? 'Staff').toString();
        final serviceName = (service['name'] ?? service['serviceName'] ?? 'Service').toString();
        
        // Skip if no staff assigned or already notified
        if (staffId.isEmpty || staffId == 'null' || notifiedStaffIds.contains(staffId)) {
          debugPrint("⏭️ Skipping service - staffId: $staffId (empty: ${staffId.isEmpty}, isNull: ${staffId == 'null'}, alreadyNotified: ${notifiedStaffIds.contains(staffId)})");
          continue;
        }
        notifiedStaffIds.add(staffId);
        debugPrint("✅ Processing staff member: $staffName ($staffId)");
        
        // Get all services assigned to this staff member
        final staffServices = services
            .where((s) => s['staffId'] == staffId)
            .map((s) => s['name'] ?? s['serviceName'] ?? 'Service')
            .join(', ');
        
        final time = booking.rawData['time'] ?? '';
        final title = 'Booking Approval Required';
        final message = 'Please review and approve booking for $staffServices with ${booking.customerName} on ${booking.date} at $time.';
        
        // Create Firestore notification
        debugPrint("📝 Creating Firestore notification for $staffName ($staffId)");
        final notificationRef = await db.collection('notifications').add({
          'bookingId': bookingId,
          'type': 'booking_approval_request',
          'title': title,
          'message': message,
          'status': 'AwaitingStaffApproval',
          'ownerUid': ownerUid,
          'staffUid': staffId,
          'staffName': staffName,
          'customerName': booking.customerName,
          'customerEmail': booking.email,
          'serviceName': staffServices,
          'date': booking.date,
          'time': time,
          'branchId': booking.branchId,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint("✅ Firestore notification created with ID: ${notificationRef.id}");
        
        // Send FCM push notification via API
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            debugPrint("📤 Attempting to send FCM push notification to $staffName ($staffId)");
            final token = await user.getIdToken();
            debugPrint("📤 Auth token obtained, calling API: $apiBaseUrl/api/notifications/send-push");
            
            final response = await http.post(
              Uri.parse('$apiBaseUrl/api/notifications/send-push'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'staffUid': staffId,
                'title': title,
                'message': message,
                'data': {
                  'notificationId': notificationRef.id,
                  'type': 'booking_approval_request',
                  'bookingId': bookingId,
                },
              }),
            ).timeout(
              const Duration(seconds: 10),
            );
            
            debugPrint("📥 API Response Status: ${response.statusCode}");
            debugPrint("📥 API Response Body: ${response.body}");
            
            if (response.statusCode == 200) {
              debugPrint("✅ Successfully sent FCM push notification to $staffName ($staffId)");
            } else {
              debugPrint("❌ Failed to send FCM push notification: ${response.statusCode}");
              debugPrint("❌ Response body: ${response.body}");
            }
          } else {
            debugPrint("⚠ No authenticated user found, cannot send FCM push notification");
          }
        } catch (e) {
          // Don't fail the whole operation if push notification fails
          debugPrint("❌ Error sending FCM push notification: $e");
          if (e is TimeoutException) {
            debugPrint("❌ Request timed out - check network connection");
          }
        }
        
        debugPrint("✅ Sent approval request notification to $staffName ($staffId)");
      }
      
      debugPrint("🔔 Completed _createStaffApprovalNotifications - notified ${notifiedStaffIds.length} staff members");
    } catch (e, stackTrace) {
      debugPrint("❌ Error creating staff approval notifications: $e");
      debugPrint("❌ Stack trace: $stackTrace");
    }
  }

  Future<void> _createNotification({
    required String bookingId,
    required _Booking booking,
    required String newStatus,
    List<Map<String, dynamic>>? updatedServices,
    String? previousStatus,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final raw = booking.rawData;
      
      // Determine final values (updated or existing)
      final finalServices = updatedServices ?? booking.items;
      final finalStaffName = (updatedServices != null && updatedServices.isNotEmpty)
          ? (updatedServices.first['staffName'] ?? booking.staff)
          : booking.staff;
      
      // Generate content for CUSTOMER notification
      final content = _getNotificationContent(
        status: newStatus,
        bookingCode: raw['bookingCode']?.toString(),
        staffName: finalStaffName,
        serviceName: booking.service,
        bookingDate: booking.date,
        bookingTime: (raw['time'] ?? '').toString(),
        services: finalServices,
      );

      final notifData = {
        'bookingId': bookingId,
        'type': content['type'],
        'title': content['title'],
        'message': content['message'],
        'status': newStatus,
        'ownerUid': raw['ownerUid'],
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      notifData['staffName'] = finalStaffName;

      // Add optional fields
      if (raw['customerUid'] != null) notifData['customerUid'] = raw['customerUid'];
      if (raw['clientEmail'] != null) notifData['customerEmail'] = raw['clientEmail'];
      if (raw['clientPhone'] != null) notifData['customerPhone'] = raw['clientPhone'];
      if (raw['bookingCode'] != null) notifData['bookingCode'] = raw['bookingCode'];
      
      // Richer details
      notifData['serviceName'] = booking.service;
      if (raw['branchName'] != null) notifData['branchName'] = raw['branchName'];
      if (booking.date.isNotEmpty) notifData['bookingDate'] = booking.date;
      final time = (raw['time'] ?? '').toString();
      if (time.isNotEmpty) notifData['bookingTime'] = time;
      
      if (finalServices.isNotEmpty) {
        notifData['services'] = finalServices.map((s) => {
          'name': s['name'] ?? 'Service',
          'staffName': s['staffName'] ?? 'Any Available',
        }).toList();
      }

      // Create customer notification
      final customerNotifRef = await db.collection('notifications').add(notifData);
      
      // Send FCM push notification to customer if they have a UID
      final customerUid = raw['customerUid']?.toString();
      if (customerUid != null && customerUid.isNotEmpty) {
        try {
          await FcmPushService().sendPushNotification(
            targetUid: customerUid,
            title: content['title'] ?? 'Booking Update',
            message: content['message'] ?? 'Your booking status has been updated.',
            data: {
              'notificationId': customerNotifRef.id,
              'type': content['type'] ?? 'booking_status_changed',
              'bookingId': bookingId,
            },
          );
          debugPrint('✅ FCM push notification sent to customer $customerUid');
        } catch (e) {
          debugPrint('Error sending FCM notification to customer: $e');
        }
      }
      
      // Create STAFF notifications when booking is confirmed with assigned staff
      if (newStatus == 'Confirmed' && finalServices.isNotEmpty) {
        await _createStaffNotifications(
          db: db,
          bookingId: bookingId,
          booking: booking,
          services: finalServices,
          ownerUid: raw['ownerUid']?.toString() ?? '',
        );
      }
      
      // Send email when status changes to Confirmed, Completed, or Canceled
      // This ensures emails are sent even when status is updated directly from mobile app
      // Only send if this is an actual status change (not already at target status)
      final String currentBookingId = bookingId;
      final String currentPreviousStatus = previousStatus ?? booking.status;
      // Normalize status for API call (API expects "Canceled" not "cancelled")
      final String normalizedStatus = (newStatus.toLowerCase() == 'cancelled') ? 'Canceled' : newStatus;
      if ((normalizedStatus == 'Confirmed' || normalizedStatus == 'Completed' || normalizedStatus == 'Canceled') && 
          currentPreviousStatus.toLowerCase() != normalizedStatus.toLowerCase()) {
        await _sendBookingStatusEmail(
          bookingId: currentBookingId,
          status: normalizedStatus,
          booking: booking,
          finalServices: finalServices,
          previousStatus: currentPreviousStatus,
        );
      }
    } catch (e) {
      debugPrint("Error creating notification: $e");
    }
  }
  
  /// Send booking status email via API
  /// This is called when status changes to Confirmed, Completed, or Canceled from mobile app
  Future<void> _sendBookingStatusEmail({
    required String bookingId,
    required String status,
    required _Booking booking,
    required List<Map<String, dynamic>> finalServices,
    required String previousStatus,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint("⚠️ Cannot send email - user not authenticated");
        return;
      }
      
      final token = await user.getIdToken();
      final apiBaseUrl = _getApiBaseUrl();
      
      debugPrint("📧 Triggering email for booking $bookingId: $previousStatus -> $status");
      
      // Call the status update API endpoint which will trigger email sending
      // We pass the previous status in the body so the API knows this is a transition
      final response = await http.patch(
        Uri.parse('$apiBaseUrl/api/bookings/$bookingId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'status': status,
          'previousStatus': previousStatus, // Help API detect this is a transition
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        debugPrint("✅ Email trigger sent successfully for booking $bookingId (status: $status)");
      } else {
        debugPrint("⚠️ Failed to trigger email for booking $bookingId: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("⚠️ Error triggering email for booking $bookingId: $e");
      // Don't fail the operation if email trigger fails
    }
  }
  
  /// Get API base URL
  String _getApiBaseUrl() {
    // Use the same API base URL as other screens
    return 'https://black.bmspros.com.au';
  }

  /// Create notifications for each staff member assigned to a confirmed booking
  Future<void> _createStaffNotifications({
    required FirebaseFirestore db,
    required String bookingId,
    required _Booking booking,
    required List<Map<String, dynamic>> services,
    required String ownerUid,
  }) async {
    try {
      // Collect unique staff IDs from services
      final Set<String> notifiedStaffIds = {};
      
      for (final service in services) {
        final staffId = (service['staffId'] ?? '').toString();
        final staffName = (service['staffName'] ?? '').toString();
        
        // Skip if no valid staff assigned or already notified
        if (staffId.isEmpty || notifiedStaffIds.contains(staffId)) continue;
        if (staffName.toLowerCase().contains('any staff') || 
            staffName.toLowerCase().contains('any available')) continue;
        
        notifiedStaffIds.add(staffId);
        
        // Build list of services assigned to this staff
        final staffServices = services
            .where((s) => s['staffId'] == staffId)
            .map((s) => s['name'] ?? 'Service')
            .toList();
        
        final servicesList = staffServices.join(', ');
        final time = (booking.rawData['time'] ?? '').toString();
        final title = 'New Booking Assigned';
        final message = 'You have been assigned a booking for $servicesList with ${booking.customerName} on ${booking.date} at $time.';
        
        final staffNotifData = {
          'bookingId': bookingId,
          'type': 'booking_assigned',
          'title': title,
          'message': message,
          'status': 'Confirmed',
          'ownerUid': ownerUid,
          'staffUid': staffId, // Key field for staff notifications
          'staffName': staffName,
          'customerName': booking.customerName,
          'customerEmail': booking.email,
          'serviceName': servicesList,
          'branchName': booking.rawData['branchName'],
          'branchId': booking.branchId,
          'bookingDate': booking.date,
          'bookingTime': time,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        };
        
        // Add services array for detailed view
        staffNotifData['services'] = staffServices.map((name) => {'name': name}).toList();
        
        final notificationRef = await db.collection('notifications').add(staffNotifData);
        debugPrint("Created staff notification for $staffName ($staffId)");
        
        // Send FCM push notification to staff
        try {
          await FcmPushService().sendPushNotification(
            targetUid: staffId,
            title: title,
            message: message,
            data: {
              'notificationId': notificationRef.id,
              'type': 'booking_assigned',
              'bookingId': bookingId,
            },
          );
          debugPrint("✅ FCM push notification sent to staff $staffName ($staffId)");
        } catch (e) {
          debugPrint("⚠️ Failed to send FCM push notification to staff: $e");
        }
      }
    } catch (e) {
      debugPrint("Error creating staff notifications: $e");
    }
  }

  Map<String, String> _getNotificationContent({
    required String status,
    String? bookingCode,
    String? staffName,
    String? serviceName,
    String? bookingDate,
    String? bookingTime,
    List<Map<String, dynamic>>? services,
  }) {
    String code = bookingCode != null ? " ($bookingCode)" : "";
    String serviceAndStaff = "";
    String datetime = "";

    if (bookingDate != null && bookingTime != null) {
      datetime = " on $bookingDate at $bookingTime";
    }

    if (services != null && services.length > 1) {
      serviceAndStaff = " for ${services.length} services";
    } else {
      String s = serviceName ?? "Service";
      String st = staffName != null && staffName.isNotEmpty && staffName != 'Any staff' 
          ? " with $staffName" 
          : "";
      serviceAndStaff = " for $s$st";
    }

    switch (status) {
      case "Pending":
        return {
          "title": "Booking Request Received",
          "message": "Your booking request$code$serviceAndStaff has been received successfully! We'll confirm your appointment soon.",
          "type": "booking_status_changed"
        };
      case "Confirmed":
        return {
          "title": "Booking Confirmed",
          "message": "Your booking$code$serviceAndStaff$datetime has been confirmed. We look forward to seeing you!",
          "type": "booking_confirmed"
        };
      case "Completed":
        return {
          "title": "Booking Completed",
          "message": "Your booking$code$serviceAndStaff has been completed. Thank you for visiting us!",
          "type": "booking_completed"
        };
      case "Canceled":
      case "Cancelled":
        return {
          "title": "Booking Canceled",
          "message": "Your booking$code$serviceAndStaff$datetime has been canceled. Please contact us if you have any questions.",
          "type": "booking_canceled"
        };
      default:
        return {
          "title": "Booking Status Updated",
          "message": "Your booking$code status has been updated to $status.",
          "type": "booking_status_changed"
        };
    }
  }

  // New dialog for confirming booking with detailed service-wise staff assignment
  void _showConfirmationWithDetailsDialog(
      BuildContext context, _Booking booking) {
    // Prepare initial state for services
    final List<Map<String, dynamic>> servicesToEdit = [];
    final List<bool> isLocked = [];

    if (booking.items.isNotEmpty) {
      for (var item in booking.items) {
        final m = Map<String, dynamic>.from(item);
        servicesToEdit.add(m);
        final sName = (m['staffName'] ?? '').toString().toLowerCase();
        isLocked.add(sName.isNotEmpty &&
            !sName.contains('any staff') &&
            !sName.contains('any available'));
      }
    } else {
      servicesToEdit.add({
        'name': booking.service,
        'staffName': booking.staff,
        'staffId': booking.rawData['staffId'],
        'price': booking.priceValue,
        'duration': booking.duration,
      });
      final sName = booking.staff.toLowerCase();
      isLocked.add(sName.isNotEmpty &&
          !sName.contains('any staff') &&
          !sName.contains('any available'));
    }

    // Pre-calculate available staff for each service
    String dayName = '';
    try {
      final parts = booking.date.split('-');
      if (parts.length == 3) {
        final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        // 1=Mon, 7=Sun. Map to keys used in DB (Monday, Tuesday...)
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        dayName = days[dt.weekday - 1];
      }
    } catch (_) {}

    List<List<Map<String, dynamic>>> availableStaffPerService = [];
    final bookingBranchName = (booking.rawData['branchName'] ?? '').toString();
    for (var service in servicesToEdit) {
      final sName = (service['name'] ?? '').toString();
      availableStaffPerService.add(_getAvailableStaffForService(sName, booking.branchId, dayName, branchName: bookingBranchName));
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          bool canConfirm = true;
          for (var service in servicesToEdit) {
            final staffName =
                (service['staffName'] ?? '').toString().toLowerCase();
            if (staffName.isEmpty ||
                staffName.contains('any staff') ||
                staffName.contains('any available')) {
              canConfirm = false;
              break;
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          FontAwesomeIcons.calendarCheck,
                          color: Color(0xFFFF2D8F),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Send for Staff Approval',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Assign staff & send for approval",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: servicesToEdit.asMap().entries.map((entry) {
                          final index = entry.key;
                          final service = entry.value;
                          final locked = isLocked[index];
                          final currentStaffId = service['staffId'];
                          final availableStaff = availableStaffPerService[index];

                          // Ensure current staff is in the list even if filtered out (e.g. strict rules changed)
                          // This avoids UI bugs if data is slightly inconsistent
                          List<Map<String, dynamic>> dropdownStaff = [...availableStaff];
                          if (currentStaffId != null && 
                              !dropdownStaff.any((s) => s['id'] == currentStaffId)) {
                             final found = _staffList.firstWhere((s) => s['id'] == currentStaffId, orElse: () => {});
                             if (found.isNotEmpty) dropdownStaff.add(found);
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFF3F4F6)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        service['name'] ?? 'Service',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (locked)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFECFDF5),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.check_circle,
                                                size: 12,
                                                color: Color(0xFF059669)),
                                            SizedBox(width: 4),
                                            Text(
                                              "Assigned",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF059669),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (locked)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF9FAFB),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFFE5E7EB)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(FontAwesomeIcons.userTie,
                                            size: 14, color: Color(0xFF6B7280)),
                                        const SizedBox(width: 12),
                                        Text(
                                          service['staffName'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const Spacer(),
                                        const Icon(Icons.lock_outline,
                                            size: 16, color: Color(0xFF9CA3AF)),
                                      ],
                                    ),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: canConfirm
                                                ? const Color(0xFFE5E7EB)
                                                : const Color(0xFFFEE2E2),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            isExpanded: true,
                                            icon: const Icon(
                                                Icons.keyboard_arrow_down_rounded),
                                            hint: const Row(
                                              children: [
                                                Icon(FontAwesomeIcons.user,
                                                    size: 14,
                                                    color: Color(0xFF9CA3AF)),
                                                SizedBox(width: 12),
                                                Text("Select Staff Member"),
                                              ],
                                            ),
                                            value: dropdownStaff.any((s) =>
                                                    s['id'] == currentStaffId)
                                                ? currentStaffId
                                                : null,
                                            items: dropdownStaff.map((staff) {
                                              final String avatar = (staff['avatarUrl'] ?? '').toString();
                                              final String name = staff['name'];
                                              final String url = (avatar.isNotEmpty && avatar != 'null')
                                                  ? avatar
                                                  : 'https://ui-avatars.com/api/?background=random&color=fff&name=${Uri.encodeComponent(name)}';

                                              return DropdownMenuItem<String>(
                                                value: staff['id'],
                                                child: Row(
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 12,
                                                      backgroundImage: NetworkImage(url),
                                                      backgroundColor: Colors.grey.shade200,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      name,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) {
                                                final selectedStaff =
                                                    _staffList.firstWhere(
                                                        (s) => s['id'] == val);
                                                setState(() {
                                                  service['staffId'] =
                                                      selectedStaff['id'];
                                                  service['staffName'] =
                                                      selectedStaff['name'];
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      if ((service['staffName'] ?? '')
                                              .toString()
                                              .toLowerCase()
                                              .contains('any staff') ||
                                          (service['staffName'] ?? '')
                                              .toString()
                                              .toLowerCase()
                                              .contains('any available'))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 6, left: 4),
                                          child: Row(
                                            children: const [
                                              Icon(Icons.info_outline,
                                                  size: 12,
                                                  color: Color(0xFFEF4444)),
                                              SizedBox(width: 4),
                                              Text(
                                                "Staff assignment required",
                                                style: TextStyle(
                                                  color: Color(0xFFEF4444),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: canConfirm
                              ? () {
                                  Navigator.pop(ctx);
                                  _updateBookingStatus(
                                    booking,
                                    'confirmed',
                                    updatedServices: servicesToEdit,
                                  );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF2D8F),
                            disabledBackgroundColor:
                                const Color(0xFFFF2D8F).withOpacity(0.5),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Send for Approval',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // Show staff assignment dialog for services that need staff
  void _showStaffAssignmentDialog(BuildContext context, _Booking booking) {
    // Prepare initial state for services - only show services that need assignment
    final List<Map<String, dynamic>> servicesToEdit = [];
    final List<bool> needsAssignment = [];

    if (booking.items.isNotEmpty) {
      for (var item in booking.items) {
        final m = Map<String, dynamic>.from(item);
        final staffName = (m['staffName'] ?? '').toString().toLowerCase();
        final staffId = (m['staffId'] ?? '').toString();
        final approvalStatus = (m['approvalStatus'] ?? '').toString().toLowerCase();
        
        // Check if this service needs staff assignment
        final needsStaff = approvalStatus == 'needs_assignment' ||
            staffName.contains('any staff') ||
            staffName.contains('any available') ||
            staffId.isEmpty ||
            staffId == 'null';
        
        servicesToEdit.add(m);
        needsAssignment.add(needsStaff);
      }
    } else {
      // Single service booking
      servicesToEdit.add({
        'name': booking.service,
        'staffName': booking.staff,
        'staffId': booking.rawData['staffId'],
        'price': booking.priceValue,
        'duration': booking.duration,
        'approvalStatus': 'pending',
      });
      final staffName = booking.staff.toLowerCase();
      needsAssignment.add(
        staffName.isEmpty ||
        staffName.contains('any staff') ||
        staffName.contains('any available')
      );
    }

    // Pre-calculate available staff for each service
    String dayName = '';
    try {
      final parts = booking.date.split('-');
      if (parts.length == 3) {
        final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        dayName = days[dt.weekday - 1];
      }
    } catch (_) {}

    List<List<Map<String, dynamic>>> availableStaffPerService = [];
    final bookingBranchName = (booking.rawData['branchName'] ?? '').toString();
    for (var service in servicesToEdit) {
      final sName = (service['name'] ?? '').toString();
      availableStaffPerService.add(_getAvailableStaffForService(sName, booking.branchId, dayName, branchName: bookingBranchName));
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          // Check if all services that need assignment have staff selected
          bool canAssign = true;
          for (int i = 0; i < servicesToEdit.length; i++) {
            if (needsAssignment[i]) {
              final staffName = (servicesToEdit[i]['staffName'] ?? '').toString().toLowerCase();
              final staffId = (servicesToEdit[i]['staffId'] ?? '').toString();
              if (staffName.isEmpty ||
                  staffName.contains('any staff') ||
                  staffName.contains('any available') ||
                  staffId.isEmpty ||
                  staffId == 'null') {
                canAssign = false;
                break;
              }
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          FontAwesomeIcons.userPlus,
                          color: Color(0xFF7C3AED),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assign Staff',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Assign staff to services",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: servicesToEdit.asMap().entries.map((entry) {
                          final index = entry.key;
                          final service = entry.value;
                          final needsStaff = needsAssignment[index];
                          final currentStaffId = service['staffId'];
                          final availableStaff = availableStaffPerService[index];
                          final approvalStatus = (service['approvalStatus'] ?? '').toString().toLowerCase();
                          final isAccepted = approvalStatus == 'accepted';
                          
                          // Check if service has staff assigned and is pending (locked until staff responds)
                          final hasStaffAssigned = currentStaffId != null && 
                              currentStaffId.toString().isNotEmpty && 
                              currentStaffId != 'null';
                          final isPendingWithStaff = approvalStatus == 'pending' && hasStaffAssigned && !needsStaff;
                          final isLocked = isAccepted || isPendingWithStaff;

                          // Ensure current staff is in the list
                          List<Map<String, dynamic>> dropdownStaff = [...availableStaff];
                          if (currentStaffId != null && 
                              currentStaffId.toString().isNotEmpty &&
                              currentStaffId != 'null' &&
                              !dropdownStaff.any((s) => s['id'] == currentStaffId)) {
                            final found = _staffList.firstWhere((s) => s['id'] == currentStaffId, orElse: () => {});
                            if (found.isNotEmpty) dropdownStaff.add(found);
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: needsStaff 
                                  ? const Color(0xFFFEF3F2) 
                                  : (isAccepted 
                                      ? const Color(0xFFECFDF5) 
                                      : (isPendingWithStaff 
                                          ? const Color(0xFFFEF3C7).withOpacity(0.3) 
                                          : Colors.white)),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: needsStaff 
                                    ? const Color(0xFFFCA5A5) 
                                    : (isAccepted 
                                        ? const Color(0xFF10B981) 
                                        : (isPendingWithStaff 
                                            ? const Color(0xFFD97706) 
                                            : const Color(0xFFF3F4F6))),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        service['name'] ?? 'Service',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (needsStaff)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7C3AED).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(FontAwesomeIcons.userPlus, size: 10, color: Color(0xFF7C3AED)),
                                            SizedBox(width: 4),
                                            Text(
                                              "Needs Staff",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF7C3AED),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else if (isAccepted)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFECFDF5),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(FontAwesomeIcons.circleCheck, size: 10, color: Color(0xFF059669)),
                                            SizedBox(width: 4),
                                            Text(
                                              "Accepted",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF059669),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else if (isPendingWithStaff)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(FontAwesomeIcons.clock, size: 10, color: Color(0xFFD97706)),
                                            SizedBox(width: 4),
                                            Text(
                                              "Pending",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFD97706),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(FontAwesomeIcons.clock, size: 10, color: Color(0xFFD97706)),
                                            SizedBox(width: 4),
                                            Text(
                                              "Pending",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFD97706),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Show locked view if accepted or pending with staff assigned
                                if (isLocked)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isAccepted 
                                          ? const Color(0xFFF9FAFB) 
                                          : const Color(0xFFFEF9C3).withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isAccepted 
                                            ? const Color(0xFFE5E7EB) 
                                            : const Color(0xFFD97706).withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          FontAwesomeIcons.userTie,
                                          size: 14,
                                          color: isAccepted 
                                              ? const Color(0xFF6B7280) 
                                              : const Color(0xFFD97706),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            service['staffName'] ?? 'Staff',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: isAccepted 
                                                  ? Colors.black87 
                                                  : const Color(0xFFD97706),
                                            ),
                                          ),
                                        ),
                                        if (isPendingWithStaff)
                                          const Tooltip(
                                            message: 'Waiting for staff to accept or reject',
                                            child: Icon(Icons.hourglass_empty,
                                                size: 16, color: Color(0xFFD97706)),
                                          )
                                        else
                                          const Icon(Icons.lock_outline,
                                              size: 16, color: Color(0xFF9CA3AF)),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: needsStaff ? const Color(0xFFFEE2E2) : const Color(0xFFE5E7EB),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                        hint: const Row(
                                          children: [
                                            Icon(FontAwesomeIcons.user, size: 14, color: Color(0xFF9CA3AF)),
                                            SizedBox(width: 12),
                                            Text("Select Staff Member"),
                                          ],
                                        ),
                                        value: (currentStaffId != null && 
                                                currentStaffId.toString().isNotEmpty && 
                                                currentStaffId != 'null' &&
                                                dropdownStaff.any((s) => s['id'] == currentStaffId)) 
                                            ? currentStaffId 
                                            : null,
                                        items: dropdownStaff.map((staff) {
                                          final String avatar = (staff['avatarUrl'] ?? '').toString();
                                          final String name = staff['name'];
                                          final String url = (avatar.isNotEmpty && avatar != 'null')
                                              ? avatar
                                              : 'https://ui-avatars.com/api/?background=random&color=fff&name=${Uri.encodeComponent(name)}';

                                          return DropdownMenuItem<String>(
                                            value: staff['id'],
                                            child: Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 12,
                                                  backgroundImage: NetworkImage(url),
                                                  backgroundColor: Colors.grey.shade200,
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            final selectedStaff = _staffList.firstWhere((s) => s['id'] == val);
                                            setState(() {
                                              service['staffId'] = selectedStaff['id'];
                                              service['staffName'] = selectedStaff['name'];
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                if (needsStaff && 
                                    ((service['staffId'] ?? '').toString().isEmpty || 
                                     service['staffId'] == 'null'))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6, left: 4),
                                    child: Row(
                                      children: const [
                                        Icon(Icons.info_outline, size: 12, color: Color(0xFFEF4444)),
                                        SizedBox(width: 4),
                                        Text(
                                          "Staff assignment required",
                                          style: TextStyle(
                                            color: Color(0xFFEF4444),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: canAssign
                              ? () {
                                  Navigator.pop(ctx);
                                  _assignStaffToServices(booking, servicesToEdit);
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            disabledBackgroundColor: const Color(0xFF7C3AED).withOpacity(0.5),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(FontAwesomeIcons.userPlus, size: 14, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Assign & Notify Staff',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // Assign staff to services that need assignment
  Future<void> _assignStaffToServices(_Booking booking, List<Map<String, dynamic>> updatedServices) async {
    final db = FirebaseFirestore.instance;
    try {
      // Update services with staff assignment and reset pending status
      final List<Map<String, dynamic>> finalServices = updatedServices.map((service) {
        final s = Map<String, dynamic>.from(service);
        final approvalStatus = (s['approvalStatus'] ?? '').toString().toLowerCase();
        
        // Only reset status for services that were needs_assignment
        if (approvalStatus == 'needs_assignment' || approvalStatus.isEmpty) {
          s['approvalStatus'] = 'pending';
        }
        return s;
      }).toList();

      // Determine status based on services
      final hasAccepted = finalServices.any((s) => (s['approvalStatus'] ?? '').toString().toLowerCase() == 'accepted');
      final allPending = finalServices.every((s) => (s['approvalStatus'] ?? '').toString().toLowerCase() == 'pending');
      
      String newStatus;
      if (allPending) {
        newStatus = 'AwaitingStaffApproval';
      } else if (hasAccepted) {
        newStatus = 'PartiallyApproved';
      } else {
        newStatus = 'AwaitingStaffApproval';
      }

      // Update the booking
      await db.collection('bookings').doc(booking.id).update({
        'services': finalServices,
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Get services that had staff newly assigned
      final List<Map<String, dynamic>> newlyAssignedServices = [];
      for (int i = 0; i < finalServices.length; i++) {
        final originalItem = booking.items.isNotEmpty && i < booking.items.length ? booking.items[i] : null;
        final updatedItem = finalServices[i];
        
        final originalStaffId = (originalItem?['staffId'] ?? '').toString();
        final originalStaffName = (originalItem?['staffName'] ?? '').toString().toLowerCase();
        final updatedStaffId = (updatedItem['staffId'] ?? '').toString();
        
        // Check if staff was newly assigned
        final wasUnassigned = originalStaffId.isEmpty || 
                              originalStaffId == 'null' ||
                              originalStaffName.contains('any staff') ||
                              originalStaffName.contains('any available');
        final isNowAssigned = updatedStaffId.isNotEmpty && updatedStaffId != 'null';
        
        if (wasUnassigned && isNowAssigned) {
          newlyAssignedServices.add(updatedItem);
        }
      }

      // Send notifications to newly assigned staff
      if (newlyAssignedServices.isNotEmpty) {
        await _createStaffApprovalNotifications(
          db: db,
          bookingId: booking.id,
          booking: booking,
          services: newlyAssignedServices,
        );
      }
      
      // Audit log
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && _ownerUid != null) {
        final userDoc = await db.collection('users').doc(currentUser.uid).get();
        final userData = userDoc.data();
        final userName = userData?['displayName'] ?? userData?['name'] ?? currentUser.email ?? 'Unknown';
        final userRole = userData?['role'] ?? 'unknown';
        
        await AuditLogService.logBookingStatusChanged(
          ownerUid: _ownerUid!,
          bookingId: booking.id,
          bookingCode: booking.rawData['bookingCode']?.toString(),
          clientName: booking.rawData['client']?.toString() ?? 'Customer',
          previousStatus: booking.status,
          newStatus: newStatus,
          performedBy: currentUser.uid,
          performedByName: userName.toString(),
          performedByRole: userRole.toString(),
          details: 'Staff assigned: ${newlyAssignedServices.map((s) => '${s['name']} → ${s['staffName']}').join(', ')}',
          branchName: booking.rawData['branchName']?.toString(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Staff assigned! ${newlyAssignedServices.length} staff member(s) have been notified.'),
            backgroundColor: const Color(0xFF7C3AED),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error assigning staff: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning staff: $e')),
        );
      }
    }
  }

  // Show reassignment dialog for staff-rejected bookings
  void _showReassignmentDialog(BuildContext context, _Booking booking) {
    // Prepare initial state for services - only show rejected or pending services
    final List<Map<String, dynamic>> servicesToEdit = [];
    final List<bool> wasRejected = [];

    if (booking.items.isNotEmpty) {
      for (var item in booking.items) {
        final m = Map<String, dynamic>.from(item);
        final approvalStatus = (m['approvalStatus'] ?? 'pending').toString().toLowerCase();
        
        // Only include rejected services or services without assignment
        if (approvalStatus == 'rejected' || approvalStatus == 'needs_assignment' || approvalStatus == 'pending') {
          // Reset approval status for reassignment
          m['approvalStatus'] = 'pending';
          m.remove('acceptedAt');
          m.remove('rejectedAt');
          m.remove('rejectionReason');
          m.remove('respondedByStaffUid');
          m.remove('respondedByStaffName');
          servicesToEdit.add(m);
          wasRejected.add(approvalStatus == 'rejected');
        }
      }
    } else {
      // Single service booking
      servicesToEdit.add({
        'name': booking.service,
        'staffName': booking.staff,
        'staffId': booking.rawData['staffId'],
        'price': booking.priceValue,
        'duration': booking.duration,
        'approvalStatus': 'pending',
      });
      wasRejected.add(true);
    }

    // Pre-calculate available staff for each service
    String dayName = '';
    try {
      final parts = booking.date.split('-');
      if (parts.length == 3) {
        final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        dayName = days[dt.weekday - 1];
      }
    } catch (_) {}

    List<List<Map<String, dynamic>>> availableStaffPerService = [];
    final bookingBranchName = (booking.rawData['branchName'] ?? '').toString();
    for (var service in servicesToEdit) {
      final sName = (service['name'] ?? '').toString();
      availableStaffPerService.add(_getAvailableStaffForService(sName, booking.branchId, dayName, branchName: bookingBranchName));
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          bool canReassign = true;
          for (var service in servicesToEdit) {
            final staffName = (service['staffName'] ?? '').toString().toLowerCase();
            if (staffName.isEmpty ||
                staffName.contains('any staff') ||
                staffName.contains('any available')) {
              canReassign = false;
              break;
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFED7AA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          FontAwesomeIcons.userPlus,
                          color: Color(0xFFEA580C),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reassign Staff',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Select new staff for rejected services",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: servicesToEdit.asMap().entries.map((entry) {
                          final index = entry.key;
                          final service = entry.value;
                          final currentStaffId = service['staffId'];
                          final availableStaff = availableStaffPerService[index];
                          final rejected = wasRejected[index];

                          // Ensure current staff is in the list
                          List<Map<String, dynamic>> dropdownStaff = [...availableStaff];
                          if (currentStaffId != null && 
                              !dropdownStaff.any((s) => s['id'] == currentStaffId)) {
                            final found = _staffList.firstWhere((s) => s['id'] == currentStaffId, orElse: () => {});
                            if (found.isNotEmpty) dropdownStaff.add(found);
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: rejected ? const Color(0xFFFEF2F2) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: rejected ? const Color(0xFFFCA5A5) : const Color(0xFFF3F4F6),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        service['name'] ?? 'Service',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (rejected)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDC2626).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(FontAwesomeIcons.circleXmark, size: 12, color: Color(0xFFDC2626)),
                                            SizedBox(width: 4),
                                            Text(
                                              "Rejected",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFDC2626),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: canReassign ? const Color(0xFFE5E7EB) : const Color(0xFFFEE2E2),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      isExpanded: true,
                                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                      hint: const Row(
                                        children: [
                                          Icon(FontAwesomeIcons.user, size: 14, color: Color(0xFF9CA3AF)),
                                          SizedBox(width: 12),
                                          Text("Select Staff Member"),
                                        ],
                                      ),
                                      value: dropdownStaff.any((s) => s['id'] == currentStaffId) ? currentStaffId : null,
                                      items: dropdownStaff.map((staff) {
                                        final String avatar = (staff['avatarUrl'] ?? '').toString();
                                        final String name = staff['name'];
                                        final String url = (avatar.isNotEmpty && avatar != 'null')
                                            ? avatar
                                            : 'https://ui-avatars.com/api/?background=random&color=fff&name=${Uri.encodeComponent(name)}';

                                        return DropdownMenuItem<String>(
                                          value: staff['id'],
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 12,
                                                backgroundImage: NetworkImage(url),
                                                backgroundColor: Colors.grey.shade200,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          final selectedStaff = _staffList.firstWhere((s) => s['id'] == val);
                                          setState(() {
                                            service['staffId'] = selectedStaff['id'];
                                            service['staffName'] = selectedStaff['name'];
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                if ((service['staffName'] ?? '').toString().toLowerCase().contains('any staff') ||
                                    (service['staffName'] ?? '').toString().toLowerCase().contains('any available'))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6, left: 4),
                                    child: Row(
                                      children: const [
                                        Icon(Icons.info_outline, size: 12, color: Color(0xFFEF4444)),
                                        SizedBox(width: 4),
                                        Text(
                                          "Staff assignment required",
                                          style: TextStyle(
                                            color: Color(0xFFEF4444),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: canReassign
                              ? () {
                                  Navigator.pop(ctx);
                                  _reassignBooking(booking, servicesToEdit);
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1D4ED8),
                            disabledBackgroundColor: const Color(0xFF1D4ED8).withOpacity(0.5),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(FontAwesomeIcons.userPlus, size: 14, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Reassign Staff',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // Reassign a booking via API
  Future<void> _reassignBooking(_Booking booking, List<Map<String, dynamic>> updatedServices) async {
    final db = FirebaseFirestore.instance;
    try {
      // Build updated services array preserving accepted services
      final List<Map<String, dynamic>> allServices = [];
      
      // Get all original services
      if (booking.items.isNotEmpty) {
        for (var originalService in booking.items) {
          final originalId = originalService['id']?.toString() ?? originalService['name']?.toString();
          final approvalStatus = (originalService['approvalStatus'] ?? 'pending').toString().toLowerCase();
          
          // Check if this service was updated in reassignment
          final updatedService = updatedServices.firstWhere(
            (s) => (s['id']?.toString() ?? s['name']?.toString()) == originalId,
            orElse: () => {},
          );
          
          if (updatedService.isNotEmpty) {
            // Use the updated service (reassigned)
            allServices.add(updatedService);
          } else if (approvalStatus == 'accepted') {
            // Keep accepted services as-is
            allServices.add(Map<String, dynamic>.from(originalService));
          } else {
            // Keep other services as-is
            allServices.add(Map<String, dynamic>.from(originalService));
          }
        }
      } else {
        // Single service booking
        allServices.addAll(updatedServices);
      }

      // Determine new status - could be AwaitingStaffApproval or PartiallyApproved
      final hasAccepted = allServices.any((s) => (s['approvalStatus'] ?? '').toString().toLowerCase() == 'accepted');
      final newStatus = hasAccepted ? 'PartiallyApproved' : 'AwaitingStaffApproval';

      // Update the booking
      await db.collection('bookings').doc(booking.id).update({
        'services': allServices,
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        // Clear rejection info
        'lastRejectedByStaffUid': FieldValue.delete(),
        'lastRejectedByStaffName': FieldValue.delete(),
        'lastRejectionReason': FieldValue.delete(),
        'lastRejectedAt': FieldValue.delete(),
        'rejectedByStaffUid': FieldValue.delete(),
        'rejectedByStaffName': FieldValue.delete(),
        'rejectionReason': FieldValue.delete(),
        'rejectedAt': FieldValue.delete(),
      });

      // Send notifications to newly assigned staff
      await _createStaffApprovalNotifications(
        db: db,
        bookingId: booking.id,
        booking: booking,
        services: updatedServices,
      );
      
      // Audit log
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && _ownerUid != null) {
        final userDoc = await db.collection('users').doc(currentUser.uid).get();
        final userData = userDoc.data();
        final userName = userData?['displayName'] ?? userData?['name'] ?? currentUser.email ?? 'Unknown';
        final userRole = userData?['role'] ?? 'unknown';
        
        await AuditLogService.logBookingStatusChanged(
          ownerUid: _ownerUid!,
          bookingId: booking.id,
          bookingCode: booking.rawData['bookingCode']?.toString(),
          clientName: booking.rawData['client']?.toString() ?? 'Customer',
          previousStatus: 'StaffRejected',
          newStatus: newStatus,
          performedBy: currentUser.uid,
          performedByName: userName.toString(),
          performedByRole: userRole.toString(),
          details: 'Booking reassigned to new staff: ${updatedServices.map((s) => s['staffName']).join(', ')}',
          branchName: booking.rawData['branchName']?.toString(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking reassigned to new staff. They have been notified.')),
        );
      }
    } catch (e) {
      debugPrint('Error reassigning booking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reassigning booking: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getAvailableStaffForService(
      String serviceName, String branchId, String dayName, {String branchName = ''}) {
    // 1. Find service definition
    final service = _servicesList.firstWhere(
      (s) => s['name'] == serviceName,
      orElse: () => {},
    );
    final List<String> allowedStaffIds =
        service.isNotEmpty ? List<String>.from(service['staffIds'] ?? []) : [];
    final serviceHasStaffAssigned = allowedStaffIds.isNotEmpty;
    
    debugPrint('[StaffFilter] Service: $serviceName, staffIds: $allowedStaffIds, branchId: $branchId, branchName: $branchName, day: $dayName');

    // Helper function to check if staff works at branch (EXACTLY matching admin panel logic)
    bool staffWorksAtBranch(Map<String, dynamic> staff) {
      if (branchId.isEmpty) return true; // No branch selected = show all
      
      // Check weekly schedule first (day-specific branch assignment)
      // IMPORTANT: If weeklySchedule exists, we RETURN based on schedule, no fallthrough!
      if (dayName.isNotEmpty) {
        final schedule = staff['weeklySchedule'] as Map<String, dynamic>?;
        if (schedule != null) {
          final daySchedule = schedule[dayName];
          if (daySchedule == null) return false; // Staff is off this day
          
          // Check if scheduled at selected branch (by ID or name) - RETURN result, don't fall through!
          final scheduledBranchId = (daySchedule['branchId'] ?? '').toString();
          final scheduledBranchName = (daySchedule['branchName'] ?? '').toString();
          
          // Match by branchId OR branchName (exactly like admin panel)
          return scheduledBranchId == branchId || 
                 (branchName.isNotEmpty && scheduledBranchName.isNotEmpty && scheduledBranchName == branchName);
        }
      }
      
      // Fall back to home branch check ONLY if no weeklySchedule
      final staffBranchId = (staff['branchId'] ?? '').toString();
      final staffBranchName = (staff['branch'] ?? '').toString();
      
      // Staff MUST have a branch assignment matching the selected branch (by ID or name)
      return staffBranchId == branchId || 
             (branchName.isNotEmpty && staffBranchName.isNotEmpty && staffBranchName == branchName);
    }

    // FILTER: Staff must be non-suspended + work at branch + (if service has staffIds, be in that list)
    final result = _staffList.where((staff) {
      // 1. Filter out suspended staff (matching admin panel logic)
      final status = (staff['status'] ?? 'Active').toString();
      if (status == 'Suspended' || status == 'suspended') {
        debugPrint('[StaffFilter] ${staff['name']} filtered out: suspended');
        return false;
      }
      
      // 2. If service has specific staff assigned, ONLY show those
      if (serviceHasStaffAssigned) {
        if (!allowedStaffIds.contains(staff['id'].toString())) {
          debugPrint('[StaffFilter] ${staff['name']} filtered out: not in service staffIds');
          return false;
        }
      }
      
      // 3. Staff must work at the selected branch (mandatory)
      if (!staffWorksAtBranch(staff)) {
        debugPrint('[StaffFilter] ${staff['name']} filtered out: not working at branch on $dayName');
        return false;
      }
      
      debugPrint('[StaffFilter] ${staff['name']} INCLUDED');
      return true;
    }).toList();
    
    debugPrint('[StaffFilter] Result: ${result.map((s) => s['name']).toList()}');
    return result;
  }

  void _showConfirmDialog(BuildContext context, String action,
      VoidCallback onConfirm, {String? subtitle}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '${_capitalise(action)} Booking?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to $action this booking?'),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(color: Colors.grey)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('Yes',
                style: TextStyle(
                    color: Color(0xFFFF2D8F), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _capitalise(String value) {
    if (value.isEmpty) return value;
    
    // Handle camelCase like "AwaitingStaffApproval" -> "Awaiting Approval"
    String formatted = value.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    
    // Return shorter labels for long statuses
    final lower = formatted.toLowerCase();
    if (lower.contains('awaiting')) return 'Awaiting';
    if (lower.contains('partially')) return 'Partial';
    
    // Capitalize first letter
    return formatted[0].toUpperCase() + formatted.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFFFF2D8F);
    const Color background = Color(0xFFFFF5FA);

    // Aggregate stats from all bookings (not filtered by search)
    final totalCount = _bookings.length;
    final confirmedCount =
        _bookings.where((b) => b.status == 'confirmed').length;
    final pendingCount = _bookings.where((b) => b.status == 'pending').length;
    final awaitingStaffCount =
        _bookings.where((b) => b.status == 'awaitingstaffapproval' || b.status == 'partiallyapproved').length;
    final staffRejectedCount =
        _bookings.where((b) => b.status == 'staffrejected').length;
    final completedCount =
        _bookings.where((b) => b.status == 'completed').length;

    double revenue = 0.0;
    for (final b in _bookings) {
      // Only count completed bookings for revenue (not confirmed or cancelled)
      if (b.status == 'completed') {
        revenue += b.priceValue;
      }
    }

    final revenueLabel =
        revenue > 0 ? '\$${revenue.toStringAsFixed(0)}' : '\$0';

    final filtered = _bookings.where((b) {
      bool matchesStatus;
      if (_statusFilter == 'all') {
        matchesStatus = true;
      } else if (_statusFilter == 'pending') {
        // Booking Requests: Show all statuses before confirmed (matching admin panel)
        matchesStatus = b.status == 'pending' ||
            b.status == 'awaitingstaffapproval' ||
            b.status == 'partiallyapproved' ||
            b.status == 'staffrejected';
      } else {
        matchesStatus = b.status == _statusFilter;
      }
      final term = _searchController.text.trim().toLowerCase();
      if (term.isEmpty) return matchesStatus;
      final inText =
          '${b.customerName} ${b.email} ${b.service} ${b.staff}'.toLowerCase();
      return matchesStatus && inText.contains(term);
    }).toList();

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header + Create Booking button
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: background,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Bookings',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        backgroundColor: const Color(0xFFFF2D8F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WalkInBookingPage(),
                          ),
                        );
                      },
                      icon: const Icon(
                        FontAwesomeIcons.calendarPlus,
                        size: 14,
                      ),
                      label: const Text(
                        'New Booking',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Total Bookings',
                            value: '$totalCount',
                            color: Colors.black87,
                            background: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Confirmed Bookings',
                            value: '$confirmedCount',
                            color: const Color(0xFF166534),
                            background: const Color(0xFFD1FAE5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Booking Requests',
                            value: '$pendingCount',
                            color: const Color(0xFF92400E),
                            background: const Color(0xFFFEEFC3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Awaiting Staff',
                            value: '$awaitingStaffCount',
                            color: const Color(0xFF1D4ED8),
                            background: const Color(0xFFDBEAFE),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Staff Rejected',
                            value: '$staffRejectedCount',
                            color: const Color(0xFFEA580C),
                            background: const Color(0xFFFED7AA),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Completed',
                            value: '$completedCount',
                            color: const Color(0xFF5B21B6),
                            background: const Color(0xFFEDE9FE),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Revenue',
                            value: revenueLabel,
                            color: const Color(0xFF059669),
                            background: const Color(0xFFD1FAE5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Filters
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search bookings...',
                          prefixIcon: const Icon(Icons.search,
                              size: 18, color: Color(0xFF9CA3AF)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _statusFilter,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.filter_alt,
                              size: 18, color: Color(0xFF9CA3AF)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: primary),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Row(
                              children: [
                                Icon(FontAwesomeIcons.list,
                                    size: 14, color: Colors.black54),
                                SizedBox(width: 12),
                                Text('All Statuses'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'pending',
                            child: Row(
                              children: [
                                Icon(FontAwesomeIcons.hourglassHalf,
                                    size: 14, color: Color(0xFFD97706)),
                                SizedBox(width: 12),
                                Text('Booking Requests'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'confirmed',
                            child: Row(
                              children: [
                                Icon(FontAwesomeIcons.check,
                                    size: 14, color: Color(0xFF166534)),
                                SizedBox(width: 12),
                                Text('Confirmed Bookings'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'completed',
                            child: Row(
                              children: [
                                Icon(FontAwesomeIcons.checkDouble,
                                    size: 14, color: Color(0xFF1D4ED8)),
                                SizedBox(width: 12),
                                Text('Completed Bookings'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Row(
                              children: [
                                Icon(FontAwesomeIcons.ban,
                                    size: 14, color: Color(0xFFB91C1C)),
                                SizedBox(width: 12),
                                Text('Cancelled Bookings'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _statusFilter = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Bookings list
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: filtered
                      .map((b) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _BookingCard(
                              booking: b,
                              onStatusUpdate: (status) {
                                if (status == 'confirmed') {
                                  // Show detailed service-wise staff assignment dialog
                                  _showConfirmationWithDetailsDialog(context, b);
                                } else if (status == 'reassign') {
                                  // Show reassignment dialog for staff-rejected bookings
                                  _showReassignmentDialog(context, b);
                                } else if (status == 'assign') {
                                  // Show assignment dialog for services that need staff
                                  _showStaffAssignmentDialog(context, b);
                                } else {
                                  _showConfirmDialog(
                                    context,
                                    status,
                                    () => _updateBookingStatus(b, status),
                                  );
                                }
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color background;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            background.withOpacity(0.9),
            background.withOpacity(0.8),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: background.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: background.withOpacity(0.65),
            blurRadius: 18,
            offset: const Offset(0, 10),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.4,
              color: Color(0xFF4B5563),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Booking {
  final String id;
  final String collection;
  final Map<String, dynamic> rawData;
  final String mergeKey;
  final DateTime sortKey;
  final String customerName;
  final String email;
  final String avatarUrl;
  final String status; // confirmed, pending, completed, cancelled, awaitingstaffapproval, partiallyapproved, staffrejected
  final String service;
  final String staff;
  final String branchId;
  final String date; // Keep raw date for schedule checking
  final String dateTime;
  final String duration;
  final String price;
  final double priceValue;
  final IconData icon;
  final List<Map<String, dynamic>> items;

  const _Booking({
    required this.id,
    required this.collection,
    required this.rawData,
    required this.mergeKey,
    required this.sortKey,
    required this.customerName,
    required this.email,
    required this.avatarUrl,
    required this.status,
    required this.service,
    required this.staff,
    required this.branchId,
    required this.date,
    required this.dateTime,
    required this.duration,
    required this.price,
    required this.priceValue,
    required this.icon,
    required this.items,
  });

  /// Normalize booking status to lowercase without underscores
  static String _normalizeStatus(String status) {
    final v = status.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '');
    switch (v) {
      case 'pending':
        return 'pending';
      case 'awaitingstaffapproval':
        return 'awaitingstaffapproval';
      case 'partiallyapproved':
        return 'partiallyapproved';
      case 'staffrejected':
        return 'staffrejected';
      case 'confirmed':
        return 'confirmed';
      case 'completed':
        return 'completed';
      case 'canceled':
      case 'cancelled':
        return 'cancelled';
      default:
        return 'pending';
    }
  }

  // Build a booking model from a Firestore document
  static _Booking fromDoc(DocumentSnapshot<Map<String, dynamic>> doc,
      {String collection = 'bookings'}) {
    final data = doc.data() ?? {};
    final client = (data['client'] ?? 'Walk-in').toString();
    final email = (data['clientEmail'] ?? '').toString();
    final staffName = (data['staffName'] ?? 'Any staff').toString();
    final branchId = (data['branchId'] ?? '').toString();
    
    // Parse items list
    List<Map<String, dynamic>> items = [];
    if (data['services'] is List) {
      final list = data['services'] as List;
      for (var item in list) {
        if (item is Map) {
          items.add(Map<String, dynamic>.from(item));
        }
      }
    }

    String serviceName = (data['serviceName'] ?? '').toString();
    if (serviceName.isEmpty && items.isNotEmpty) {
       serviceName = (items.first['name'] ?? 'Service').toString();
    }
    if (serviceName.isEmpty) serviceName = 'Service';

    final date = (data['date'] ?? '').toString(); // YYYY-MM-DD
    final time = (data['time'] ?? '').toString(); // HH:mm
    String dateTimeLabel;
    DateTime sortKey;
    try {
      if (date.isNotEmpty && time.isNotEmpty) {
        final parts = date.split('-');
        final tParts = time.split(':');
        sortKey = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
          int.parse(tParts[0]),
          tParts.length > 1 ? int.parse(tParts[1]) : 0,
        );
        dateTimeLabel = '$date at $time';
      } else {
        sortKey = DateTime.fromMillisecondsSinceEpoch(0);
        dateTimeLabel = (date + (time.isNotEmpty ? ' $time' : '')).trim();
      }
    } catch (_) {
      sortKey = DateTime.fromMillisecondsSinceEpoch(0);
      dateTimeLabel = (date + (time.isNotEmpty ? ' $time' : '')).trim();
    }

    final durationMinutes = (data['duration'] ?? 0);
    String durationLabel = '';
    if (durationMinutes is num && durationMinutes > 0) {
      if (durationMinutes >= 60 && durationMinutes % 60 == 0) {
        final hours = durationMinutes ~/ 60;
        durationLabel = '$hours hour${hours > 1 ? 's' : ''}';
      } else {
        durationLabel = '${durationMinutes.toString()} minutes';
      }
    }

    final rawPrice = (data['price'] ?? 0);
    double priceValue = 0;
    if (rawPrice is num) {
      priceValue = rawPrice.toDouble();
    } else {
      priceValue = double.tryParse(rawPrice.toString()) ?? 0.0;
    }
    final priceLabel =
        priceValue > 0 ? '\$${priceValue.toStringAsFixed(0)}' : '\$0';

    String status = _normalizeStatus((data['status'] ?? 'pending').toString());

    final avatarUrl = (data['avatarUrl'] ??
            'https://ui-avatars.com/api/?background=FF2D8F&color=fff&name=${Uri.encodeComponent(client)}')
        .toString();

    IconData icon = FontAwesomeIcons.scissors;
    final serviceLower = serviceName.toLowerCase();
    if (serviceLower.contains('nail')) {
      icon = FontAwesomeIcons.handSparkles;
    } else if (serviceLower.contains('facial') ||
        serviceLower.contains('spa')) {
      icon = FontAwesomeIcons.spa;
    } else if (serviceLower.contains('massage')) {
      icon = FontAwesomeIcons.spa;
    } else if (serviceLower.contains('extension')) {
      icon = FontAwesomeIcons.wandMagicSparkles;
    }

    final mergeKey =
        doc.id.isNotEmpty ? doc.id : '$client|$date|$time|$serviceName';

    return _Booking(
      id: doc.id,
      collection: collection,
      rawData: data,
      mergeKey: mergeKey,
      sortKey: sortKey,
      customerName: client,
      email: email,
      avatarUrl: avatarUrl,
      status: status,
      service: serviceName,
      staff: staffName,
      branchId: branchId,
      date: date,
      dateTime: dateTimeLabel,
      duration: durationLabel,
      price: priceLabel,
      priceValue: priceValue,
      icon: icon,
      items: items,
    );
  }
}

class _BookingCard extends StatelessWidget {
  final _Booking booking;
  final Function(String) onStatusUpdate;

  const _BookingCard({required this.booking, required this.onStatusUpdate});

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Color _statusBg(String status) {
    final normalizedStatus = status.toLowerCase().replaceAll('_', '');
    switch (normalizedStatus) {
      case 'confirmed':
        return const Color(0xFFD1FAE5);
      case 'pending':
        return const Color(0xFFFEF3C7);
      case 'awaitingstaffapproval':
        return const Color(0xFFDBEAFE);
      case 'partiallyapproved':
        return const Color(0xFFCFFAFE);
      case 'staffrejected':
        return const Color(0xFFFED7AA);
      case 'completed':
        return const Color(0xFFEDE9FE);
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFFEE2E2);
      default:
        return const Color(0xFFE5E7EB);
    }
  }

  Color _statusColor(String status) {
    final normalizedStatus = status.toLowerCase().replaceAll('_', '');
    switch (normalizedStatus) {
      case 'confirmed':
        return const Color(0xFF166534);
      case 'pending':
        return const Color(0xFF92400E);
      case 'awaitingstaffapproval':
        return const Color(0xFF1D4ED8);
      case 'partiallyapproved':
        return const Color(0xFF0891B2);
      case 'staffrejected':
        return const Color(0xFFEA580C);
      case 'completed':
        return const Color(0xFF5B21B6);
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFF4B5563);
    }
  }

  bool _isAwaitingStatus(String status) {
    final normalized = status.toLowerCase().replaceAll('_', '');
    return normalized == 'awaitingstaffapproval' || normalized == 'partiallyapproved';
  }

  bool _isStaffRejectedStatus(String status) {
    final normalized = status.toLowerCase().replaceAll('_', '');
    return normalized == 'staffrejected';
  }

  /// Check if booking has services that need staff assignment
  bool _hasServicesNeedingAssignment(_Booking booking) {
    if (booking.items.isEmpty) {
      // Single service booking - check staff name
      final staffName = booking.staff.toLowerCase();
      return staffName.isEmpty || 
             staffName.contains('any staff') || 
             staffName.contains('any available');
    }
    // Multi-service booking - check each service
    for (final item in booking.items) {
      final staffName = (item['staffName'] ?? '').toString().toLowerCase();
      final staffId = (item['staffId'] ?? '').toString();
      final approvalStatus = (item['approvalStatus'] ?? '').toString().toLowerCase();
      
      // Service needs assignment if:
      // - approvalStatus is 'needs_assignment'
      // - staffName contains 'any staff' or 'any available'
      // - staffId is empty or null
      if (approvalStatus == 'needs_assignment') return true;
      if (staffName.contains('any staff') || staffName.contains('any available')) return true;
      if (staffId.isEmpty || staffId == 'null') return true;
    }
    return false;
  }

  Widget _buildStaffApprovalSection(List<Map<String, dynamic>> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD34D).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FontAwesomeIcons.userClock, size: 12, color: Colors.amber.shade700),
              const SizedBox(width: 6),
              Text(
                'Staff Approvals',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final serviceName = (item['name'] ?? item['serviceName'] ?? 'Service').toString();
            final staffName = (item['staffName'] ?? 'Any staff').toString();
            final approvalStatus = (item['approvalStatus'] ?? 'pending').toString().toLowerCase();
            
            Color statusColor;
            IconData statusIcon;
            String statusLabel;
            
            switch (approvalStatus) {
              case 'accepted':
                statusColor = const Color(0xFF16A34A);
                statusIcon = FontAwesomeIcons.circleCheck;
                statusLabel = 'Approved';
                break;
              case 'rejected':
                statusColor = const Color(0xFFDC2626);
                statusIcon = FontAwesomeIcons.circleXmark;
                statusLabel = 'Rejected';
                break;
              case 'needs_assignment':
                statusColor = const Color(0xFF7C3AED);
                statusIcon = FontAwesomeIcons.userPlus;
                statusLabel = 'Needs Staff';
                break;
              default:
                statusColor = const Color(0xFFD97706);
                statusIcon = FontAwesomeIcons.clock;
                statusLabel = 'Pending';
            }
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$serviceName • $staffName',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 10, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStaffRejectionSection(_Booking booking) {
    // Get rejection details from rawData
    final rejectedByStaffName = (booking.rawData['lastRejectedByStaffName'] ?? 
                                  booking.rawData['rejectedByStaffName'] ?? 'Staff').toString();
    final rejectionReason = (booking.rawData['lastRejectionReason'] ?? 
                             booking.rawData['rejectionReason'] ?? 'No reason provided').toString();
    
    // Also check for rejected services in items
    final rejectedServices = booking.items.where((item) {
      final status = (item['approvalStatus'] ?? '').toString().toLowerCase();
      return status == 'rejected';
    }).toList();
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFED7AA).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFB923C).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.circleExclamation, size: 12, color: Color(0xFFEA580C)),
              const SizedBox(width: 6),
              const Text(
                'Staff Rejected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEA580C),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Action Required',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEA580C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Show rejected services if available
          if (rejectedServices.isNotEmpty) ...[
            ...rejectedServices.map((service) {
              final serviceName = (service['name'] ?? service['serviceName'] ?? 'Service').toString();
              final staffName = (service['staffName'] ?? 'Staff').toString();
              final reason = (service['rejectionReason'] ?? 'No reason provided').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(FontAwesomeIcons.xmark, size: 10, color: Color(0xFFDC2626)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$serviceName rejected by $staffName',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 4),
                      child: Text(
                        '"$reason"',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ] else ...[
            // Show general rejection info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(FontAwesomeIcons.user, size: 10, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Rejected by: $rejectedByStaffName',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(FontAwesomeIcons.comment, size: 10, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '"$rejectionReason"',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFB923C).withOpacity(0.3)),
            ),
            child: Row(
              children: const [
                Icon(FontAwesomeIcons.circleInfo, size: 12, color: Color(0xFF6B7280)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap "Reassign" to assign this booking to another staff member.',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusBg = _statusBg(booking.status);
    final statusColor = _statusColor(booking.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFFF2D8F).withOpacity(0.15),
                child: Text(
                  _getInitials(booking.customerName),
                  style: const TextStyle(
                    color: Color(0xFFFF2D8F),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      booking.email,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _capitalise(booking.status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(
            icon: booking.icon,
            text: booking.service,
          ),
          _infoRow(
            icon: FontAwesomeIcons.user,
            text: 'with ${booking.staff}',
          ),
          _infoRow(
            icon: FontAwesomeIcons.calendar,
            text: booking.dateTime,
          ),
          _infoRow(
            icon: FontAwesomeIcons.clock,
            text: booking.duration,
          ),
          // Show staff-wise approval status for awaiting bookings
          if (_isAwaitingStatus(booking.status) && booking.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildStaffApprovalSection(booking.items),
          ],
          // Show staff rejection details for rejected bookings
          if (_isStaffRejectedStatus(booking.status)) ...[
            const SizedBox(height: 12),
            _buildStaffRejectionSection(booking),
          ],
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                booking.price,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: booking.status == 'cancelled'
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFFFF2D8F),
                  decoration: booking.status == 'cancelled'
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ActionIcon(
                      icon: FontAwesomeIcons.eye,
                      background: const Color(0xFFE0EDFF),
                      color: const Color(0xFF2563EB),
                      onTap: () => _showBookingDetails(context, booking),
                    ),
                    if (booking.status == 'pending') ...[
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: "Send to Staff",
                        background: const Color(0xFFFEF3C7),
                        color: const Color(0xFFD97706),
                        onTap: () => onStatusUpdate('confirmed'),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: "Decline",
                        background: const Color(0xFFFEE2E2),
                        color: const Color(0xFFB91C1C),
                        onTap: () => onStatusUpdate('cancelled'),
                      ),
                    ] else if (_isAwaitingStatus(booking.status)) ...[
                      // Show "Assign Staff" button if any services need assignment
                      if (_hasServicesNeedingAssignment(booking)) ...[
                        const SizedBox(width: 8),
                        _ActionButton(
                          label: "Assign Staff",
                          background: const Color(0xFFF3E8FF),
                          color: const Color(0xFF7C3AED),
                          icon: FontAwesomeIcons.userPlus,
                          onTap: () => onStatusUpdate('assign'),
                        ),
                      ] else ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDBEAFE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(FontAwesomeIcons.userClock, size: 12, color: Color(0xFF1D4ED8)),
                              SizedBox(width: 6),
                              Text(
                                "Awaiting Staff",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: "Cancel",
                        background: const Color(0xFFFEE2E2),
                        color: const Color(0xFFB91C1C),
                        onTap: () => onStatusUpdate('cancelled'),
                      ),
                    ] else if (_isStaffRejectedStatus(booking.status)) ...[
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: "Reassign",
                        background: const Color(0xFFDBEAFE),
                        color: const Color(0xFF1D4ED8),
                        icon: FontAwesomeIcons.userPlus,
                        onTap: () => onStatusUpdate('reassign'),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: "Cancel",
                        background: const Color(0xFFFEE2E2),
                        color: const Color(0xFFB91C1C),
                        onTap: () => onStatusUpdate('cancelled'),
                      ),
                    ] else if (booking.status == 'confirmed') ...[
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: "Complete",
                        background: const Color(0xFFDBEAFE),
                        color: const Color(0xFF1D4ED8),
                        onTap: () => onStatusUpdate('completed'),
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: "Cancel",
                        background: const Color(0xFFFEE2E2),
                        color: const Color(0xFFB91C1C),
                        onTap: () => onStatusUpdate('cancelled'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBookingDetails(BuildContext context, _Booking booking) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFFFFF5FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // Header with Avatar and Status
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: const Color(0xFFFF2D8F).withOpacity(0.15),
                            child: Text(
                              _getInitials(booking.customerName),
                              style: const TextStyle(
                                color: Color(0xFFFF2D8F),
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            booking.customerName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            booking.email,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _statusBg(booking.status),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _capitalise(booking.status),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _statusColor(booking.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Details Section
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Services",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (booking.items.isEmpty)
                            // Fallback if no items list (legacy bookings)
                            _buildServiceItem(
                              name: booking.service,
                              staff: booking.staff,
                              time: booking.dateTime,
                              duration: booking.duration,
                              price: booking.price,
                            )
                          else
                            ...booking.items.map((item) {
                              final name = (item['name'] ?? 'Service').toString();
                              final staff =
                                  (item['staffName'] ?? booking.staff).toString();
                              final dur = (item['duration'] ?? 0);
                              final durStr = '$dur min';
                              final pr = (item['price'] ?? 0);
                              final prStr = '\$${pr}';
                              
                              // Use booking time if per-service time is missing
                              final time = booking.dateTime; 

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: _buildServiceItem(
                                  name: name,
                                  staff: staff,
                                  time: time, // or specific time if available
                                  duration: durStr,
                                  price: prStr,
                                ),
                              );
                            }).toList(),
                          
                          const Divider(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Total Price",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                booking.price,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF2D8F),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            // Close Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2D8F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Close',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceItem({
    required String name,
    required String staff,
    required String time,
    required String duration,
    required String price,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                price,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF2D8F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _itemDetailRow(FontAwesomeIcons.userTie, staff, const Color(0xFF8B5CF6)),
          const SizedBox(height: 8),
          _itemDetailRow(FontAwesomeIcons.clock, "$time • $duration", const Color(0xFF10B981)),
        ],
      ),
    );
  }

  Widget _itemDetailRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _infoRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF4B5563),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _capitalise(String value) {
    if (value.isEmpty) return value;
    
    // Normalize the status
    final normalized = value.toLowerCase().replaceAll('_', '');
    
    // Return user-friendly labels for statuses
    switch (normalized) {
      case 'awaitingstaffapproval':
        return 'Awaiting Staff';
      case 'partiallyapproved':
        return 'Partial';
      case 'staffrejected':
        return 'Staff Rejected';
      case 'confirmed':
        return 'Confirmed';
      case 'pending':
        return 'Pending';
      case 'completed':
        return 'Completed';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      default:
        // Handle camelCase like "AwaitingStaffApproval" -> "Awaiting Staff Approval"
        String formatted = value.replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        );
        // Capitalize first letter
        return formatted[0].toUpperCase() + formatted.substring(1);
    }
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color color;
  final VoidCallback? onTap;

  const _ActionIcon({
    required this.icon,
    required this.background,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color color;
  final VoidCallback? onTap;
  final IconData? icon;

  const _ActionButton({
    required this.label,
    required this.background,
    required this.color,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
