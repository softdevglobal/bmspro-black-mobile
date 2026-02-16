import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../utils/timezone_helper.dart';
import '../services/audit_log_service.dart';
import '../services/fcm_push_service.dart';

// --- 1. Theme & Colors (Matching HTML/Tailwind) ---
class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF5F5F5);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF9E9E9E);
  static const border = Color(0xFFE0E0E0);
  static const green = Color(0xFF10B981);
  static const purple = Color(0xFF9333EA); // Purple-600
  static const blue = Color(0xFF2563EB); // Blue-600
}

class WalkInBookingPage extends StatefulWidget {
  const WalkInBookingPage({super.key});

  @override
  State<WalkInBookingPage> createState() => _WalkInBookingPageState();
}

class _WalkInBookingPageState extends State<WalkInBookingPage> with TickerProviderStateMixin {
  // State Variables
  int _currentStep = 0; // 0: Branch & Services, 1: Date & Staff, 2: Details

  // Step 1 – branch & services
  String? _selectedBranchLabel;
  Set<String> _selectedServiceIds = {}; // multiple services supported

  // Step 2 – date & per-service time/staff
  DateTime? _selectedDate;
  Map<String, TimeOfDay> _serviceTimeSelections = {}; // serviceId -> time
  Map<String, String> _serviceStaffSelections = {}; // serviceId -> staffId ('any' or actual ID)

  bool _isProcessing = false;

  // Auth / owner context
  String? _ownerUid;
  String? _userRole;
  String? _userBranchId;
  String? _currentUserId;  // Current user's document ID (same as auth UID)
  String? _currentUserName; // Current user's display name
  Map<String, dynamic>? _currentUserWeeklySchedule; // Staff's weekly schedule
  bool _loadingContext = true;
  String? _selectedBranchId;
  String? _selectedBranchTimezone; // Timezone of the selected branch
  
  // Branch current time (updates every minute for accurate slot availability)
  DateTime _branchCurrentTime = DateTime.now();
  Timer? _branchTimeTimer;

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // Animation Controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Live data from Firestore (mirroring admin panel sources)
  List<Map<String, dynamic>> _branches = []; // {id, name, address}
  List<Map<String, dynamic>> _services = []; // {id, name, price, duration, branches, staffIds}
  List<Map<String, dynamic>> _staff = []; // {id, name, status, avatar, branchId}
  List<Map<String, dynamic>> _bookings = []; // Existing bookings for slot blocking
  bool _loadingData = true;
  String? _dataError;

  @override
  void initState() {
    super.initState();
    // Fade Animation
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _loadUserContext();
    
    // Start timer to update branch time every minute
    _startBranchTimeTimer();
  }
  
  void _startBranchTimeTimer() {
    // Update immediately
    _updateBranchTime();
    
    // Update every minute
    _branchTimeTimer?.cancel();
    _branchTimeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateBranchTime();
    });
  }
  
  void _updateBranchTime() {
    if (!mounted) return;
    final timezone = _selectedBranchTimezone ?? 'Australia/Sydney';
    setState(() {
      _branchCurrentTime = TimezoneHelper.nowInTimezone(timezone);
    });
  }

  @override
  void dispose() {
    _branchTimeTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // --- Logic Helpers ---
  int get _totalPrice {
    int total = 0;
    for (final serviceId in _selectedServiceIds) {
      final service = _services.firstWhere((s) => s['id'] == serviceId, orElse: () => {});
      if (service.isNotEmpty) {
        total += (service['price'] as num).toInt();
      }
    }
    return total;
  }

  int get _totalDuration {
    int total = 0;
    for (final serviceId in _selectedServiceIds) {
      final service = _services.firstWhere((s) => s['id'] == serviceId, orElse: () => {});
      if (service.isNotEmpty && service['duration'] != null) {
        total += (service['duration'] as num).toInt();
      }
    }
    return total;
  }

  void _selectService(String id) {
    debugPrint('[SelectService] Tapped service id: $id');
    debugPrint('[SelectService] Before: $_selectedServiceIds');
    setState(() {
      // Create a new Set to ensure Flutter detects the change
      final newSet = Set<String>.from(_selectedServiceIds);
      if (newSet.contains(id)) {
        newSet.remove(id); // Deselect
        debugPrint('[SelectService] Removed $id');
      } else {
        newSet.add(id); // Add to selection
        debugPrint('[SelectService] Added $id');
      }
      _selectedServiceIds = newSet;
      debugPrint('[SelectService] After: $_selectedServiceIds');
    });
  }

  void _confirmBooking() {
    if (_loadingContext || _ownerUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text("Unable to create booking. Please try again shortly.")),
      );
      return;
    }
    if (_totalPrice == 0 || _selectedServiceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select at least one service to continue.")));
      return;
    }

    setState(() => _isProcessing = true);

    _createFirestoreBooking().then((_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.green,
          content: Text("Booking created successfully."),
        ),
      );
      Navigator.pop(context);
    }).catchError((e) {
      debugPrint('Error creating booking: $e');
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Failed to create booking. Please try again."),
        ),
      );
    });
  }

  Future<void> _loadUserContext() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => _loadingContext = false);
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String? ownerUid = user.uid;
      String? role;
      String? branchId;
      String? userId = user.uid;
      String? userName;
      Map<String, dynamic>? weeklySchedule;

      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>? ?? {};
        role = (data['role'] ?? '').toString();
        branchId = (data['branchId'] ?? '').toString();
        userName = (data['displayName'] ?? data['name'] ?? '').toString();
        weeklySchedule = data['weeklySchedule'] is Map 
            ? Map<String, dynamic>.from(data['weeklySchedule']) 
            : null;

        if (role == 'workshop_owner') {
          ownerUid = user.uid;
        } else if (data['ownerUid'] != null &&
            data['ownerUid'].toString().isNotEmpty) {
          ownerUid = data['ownerUid'].toString();
        }
      }

      if (!mounted) return;
      setState(() {
        _ownerUid = ownerUid;
        _userRole = role;
        _userBranchId = branchId?.isNotEmpty == true ? branchId : null;
        _currentUserId = userId;
        _currentUserName = userName?.isNotEmpty == true ? userName : 'Staff';
        _currentUserWeeklySchedule = weeklySchedule;
      });

      await _loadInitialData();
    } catch (e) {
      debugPrint('Error loading user context: $e');
      if (!mounted) return;
      setState(() {
        _loadingContext = false;
      });
    }
  }

  Future<void> _loadInitialData() async {
    if (_ownerUid == null) {
      setState(() {
        _loadingContext = false;
        _loadingData = false;
      });
      return;
    }
    try {
      final db = FirebaseFirestore.instance;

      final branchesSnap = await db
          .collection('branches')
          .where('ownerUid', isEqualTo: _ownerUid)
          .get();

      final servicesSnap = await db
          .collection('services')
          .where('ownerUid', isEqualTo: _ownerUid)
          .get();

      final staffSnap = await db
          .collection('users')
          .where('ownerUid', isEqualTo: _ownerUid)
          .get();

      // Fetch bookings for time slot blocking (bookings that aren't cancelled/rejected)
      final bookingsSnap = await db
          .collection('bookings')
          .where('ownerUid', isEqualTo: _ownerUid)
          .get();
      
      // Also fetch bookingRequests for time slot blocking (from booking engine)
      QuerySnapshot? bookingRequestsSnap;
      try {
        bookingRequestsSnap = await db
            .collection('bookingRequests')
            .where('ownerUid', isEqualTo: _ownerUid)
            .get();
      } catch (e) {
        // bookingRequests may not be accessible - that's okay, just use main bookings
        debugPrint('[BookingLoad] bookingRequests query failed: $e');
      }

      // Helper to map booking document to common structure
      Map<String, dynamic> mapBookingDoc(DocumentSnapshot d, Map<String, dynamic> data) {
        return {
          'id': d.id,
          'date': (data['date'] ?? '').toString(),
          'time': (data['time'] ?? '').toString(),
          'duration': (data['duration'] ?? 60),
          'staffId': (data['staffId'] ?? '').toString(),
          'staffName': (data['staffName'] ?? '').toString(),
          'branchId': (data['branchId'] ?? '').toString(),
          'status': (data['status'] ?? '').toString(),
          'services': data['services'], // May contain individual service times/staff
        };
      }
      
      // Helper to check if booking status should be included
      bool isActiveBookingStatus(String status) {
        final s = status.toLowerCase();
        return s != 'cancelled' && 
               s != 'canceled' && 
               s != 'staffrejected' &&
               s != 'completed';
      }

      final bookings = bookingsSnap.docs
          .where((d) {
            final status = (d.data()['status'] ?? '').toString();
            return isActiveBookingStatus(status);
          })
          .map((d) => mapBookingDoc(d, d.data()))
          .toList();
      
      // Add booking requests if available
      if (bookingRequestsSnap != null) {
        final existingIds = bookings.map((b) => b['id']).toSet();
        for (final doc in bookingRequestsSnap.docs) {
          if (!existingIds.contains(doc.id)) {
            final data = doc.data() as Map<String, dynamic>;
            final status = (data['status'] ?? '').toString();
            if (isActiveBookingStatus(status)) {
              bookings.add(mapBookingDoc(doc, data));
            }
          }
        }
      }

      final branches = branchesSnap.docs.map((d) {
        final data = d.data();
        debugPrint('[BranchLoad] Branch "${data['name']}" id=${d.id} timezone=${data['timezone']}');
        return {
          'id': d.id,
          'name': (data['name'] ?? 'Branch').toString(),
          'address': (data['address'] ?? '').toString(),
          'hours': data['hours'], // Include branch hours
          'timezone': (data['timezone'] ?? 'Australia/Sydney').toString(), // Include timezone
        };
      }).toList();

      final services = servicesSnap.docs.map((d) {
        final data = d.data();
        final branchesList = (data['branches'] is List)
            ? List<String>.from(
                (data['branches'] as List).map((e) => e.toString()))
            : <String>[];
        debugPrint('[ServiceLoad] Service "${data['name']}" id=${d.id}, branches=$branchesList');
        return {
          'id': d.id,
          'name': (data['name'] ?? 'Service').toString(),
          'price': (data['price'] ?? 0),
          'duration': (data['duration'] ?? 60),
          'imageUrl': data['imageUrl'] ?? data['image'],
          'branches': branchesList,
          'staffIds': (data['staffIds'] is List)
              ? List<String>.from(
                  (data['staffIds'] as List).map((e) => e.toString()))
              : <String>[],
        };
      }).toList();

      final staff = staffSnap.docs.map((d) {
        final data = d.data();
        // Get profile image URL - prioritize photoURL, then avatarUrl, then avatar if it's a URL
        String? avatarUrl;
        if (data['photoURL'] != null && data['photoURL'].toString().trim().isNotEmpty) {
          avatarUrl = data['photoURL'].toString().trim();
        } else if (data['avatarUrl'] != null && data['avatarUrl'].toString().trim().isNotEmpty) {
          avatarUrl = data['avatarUrl'].toString().trim();
        } else if (data['avatar'] != null && data['avatar'].toString().trim().isNotEmpty) {
          final avatar = data['avatar'].toString().trim();
          // Check if avatar is a URL (starts with http/https)
          if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
            avatarUrl = avatar;
          }
        }
        
        // Debug: Log avatar URL extraction
        if (avatarUrl != null) {
          debugPrint('[StaffLoad] Staff ${data['displayName'] ?? data['name'] ?? 'Unknown'}: Found avatar URL: $avatarUrl');
        } else {
          debugPrint('[StaffLoad] Staff ${data['displayName'] ?? data['name'] ?? 'Unknown'}: No avatar URL found. photoURL=${data['photoURL']}, avatarUrl=${data['avatarUrl']}, avatar=${data['avatar']}');
        }
        
        return {
          'id': d.id,
          'name':
              (data['displayName'] ?? data['name'] ?? 'Unknown').toString(),
          'status': (data['status'] ?? 'Active').toString(),
          'avatar': avatarUrl,
          'photoURL': data['photoURL'], // Keep original fields as fallback
          'avatarUrl': data['avatarUrl'], // Keep original fields as fallback
          'branchId': (data['branchId'] ?? '').toString(),
          'weeklySchedule': data['weeklySchedule'], // Include weekly schedule for branch checks
        };
      }).where((m) {
        final status = (m['status'] ?? 'Active').toString();
        return status != 'Suspended';
      }).toList();

      if (!mounted) return;
      
      // Filter branches and services based on user role
      List<Map<String, dynamic>> filteredBranches = branches;
      List<Map<String, dynamic>> filteredServices = services;
      
      // For branch admins, only show their own branch
      if (_userRole == 'branch_admin' && _userBranchId != null) {
        filteredBranches = branches.where((b) => b['id'] == _userBranchId).toList();
      }
      
      // For staff members, filter by their branches and services they can provide
      if (_userRole == 'staff' && _currentUserId != null) {
        // Get branches where staff works (from weeklySchedule or branchId)
        Set<String> staffBranchIds = {};
        
        // Add home branch
        if (_userBranchId != null && _userBranchId!.isNotEmpty) {
          staffBranchIds.add(_userBranchId!);
        }
        
        // Add branches from weekly schedule
        if (_currentUserWeeklySchedule != null) {
          _currentUserWeeklySchedule!.forEach((day, schedule) {
            if (schedule is Map && schedule['branchId'] != null) {
              staffBranchIds.add(schedule['branchId'].toString());
            }
          });
        }
        
        // Filter branches to only those where staff works
        if (staffBranchIds.isNotEmpty) {
          filteredBranches = branches.where((b) => staffBranchIds.contains(b['id'])).toList();
        }
        
        // Filter services to only those the staff can provide
        filteredServices = services.where((s) {
          final staffIds = s['staffIds'] as List<String>? ?? [];
          // If service has no specific staff, any staff can do it
          // If service has specific staff, check if current user is in the list
          return staffIds.isEmpty || staffIds.contains(_currentUserId);
        }).toList();
        
        debugPrint('[StaffBooking] Staff ID: $_currentUserId');
        debugPrint('[StaffBooking] Staff branches: $staffBranchIds');
        debugPrint('[StaffBooking] Filtered branches: ${filteredBranches.length}');
        debugPrint('[StaffBooking] Filtered services: ${filteredServices.length}');
      }
      
      setState(() {
        _branches = filteredBranches;
        _services = filteredServices;
        _bookings = bookings; // Store bookings for time slot blocking
        
        // For staff, don't show "Any Staff" option - they will be auto-assigned
        if (_userRole == 'staff') {
          _staff = staff; // Just the regular staff list for reference
        } else {
          _staff = [
            {'id': 'any', 'name': 'Any Staff', 'avatar': null},
            ...staff,
          ];
        }

        // Auto-select branch for branch admins (they only have one option)
        if (_userRole == 'branch_admin' && _userBranchId != null) {
          final br = filteredBranches.firstWhere(
              (b) => b['id'] == _userBranchId,
              orElse: () => {});
          if (br.isNotEmpty) {
            _selectedBranchId = br['id'] as String;
            _selectedBranchLabel = br['name'] as String;
            _selectedBranchTimezone = (br['timezone'] ?? 'Australia/Sydney').toString();
          }
        }
        
        // Auto-select branch for staff if they only work at one branch
        if (_userRole == 'staff' && filteredBranches.length == 1) {
          _selectedBranchId = filteredBranches.first['id'] as String;
          _selectedBranchLabel = filteredBranches.first['name'] as String;
          _selectedBranchTimezone = (filteredBranches.first['timezone'] ?? 'Australia/Sydney').toString();
        }

        _loadingContext = false;
        _loadingData = false;
      });
    } catch (e) {
      debugPrint('Error loading booking data: $e');
      if (!mounted) return;
      setState(() {
        _dataError = 'Failed to load booking data.';
        _loadingContext = false;
        _loadingData = false;
      });
    }
  }

  // Generate a booking code similar to admin panel
  String _generateBookingCode() {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final dateTime = '$month$day$hour';
    final random = (DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    return 'BK-$year-$dateTime-$random';
  }

  Future<void> _createFirestoreBooking() async {
    final now = DateTime.now();
    final DateTime date = _selectedDate ?? now;

    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    // Get all selected services
    final List<Map<String, dynamic>> selectedServices = _selectedServiceIds
        .map((id) => _services.firstWhere((s) => s['id'] == id, orElse: () => {}))
        .where((s) => s.isNotEmpty)
        .toList();

    // Build service names and IDs as comma-separated strings
    final serviceNames = selectedServices.map((s) => s['name'] ?? 'Service').join(', ');
    final serviceIds = selectedServices.map((s) => s['id']).join(',');

    // Get first service time as main booking time
    final firstServiceId = _selectedServiceIds.isNotEmpty ? _selectedServiceIds.first : '';
    final firstTime = _serviceTimeSelections[firstServiceId] ?? TimeOfDay.fromDateTime(now);
    final mainTimeStr = '${firstTime.hour.toString().padLeft(2, '0')}:${firstTime.minute.toString().padLeft(2, '0')}';

    // Determine main staff
    String? mainStaffId;
    String mainStaffName = 'Any Available';
    
    // For staff, they are always assigned to their own bookings
    if (_userRole == 'staff' && _currentUserId != null) {
      mainStaffId = _currentUserId;
      mainStaffName = _currentUserName ?? 'Staff';
    } else {
      // For other roles, determine from selections
      final uniqueStaffIds = _serviceStaffSelections.values.where((s) => s != 'any').toSet();
      if (uniqueStaffIds.length == 1) {
        mainStaffId = uniqueStaffIds.first;
        final match = _staff.firstWhere((s) => s['id'] == mainStaffId, orElse: () => {});
        if (match.isNotEmpty) {
          mainStaffName = (match['name'] ?? 'Staff').toString();
        }
      } else if (uniqueStaffIds.length > 1) {
        mainStaffName = 'Multiple Staff';
      }
    }

    final clientName = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final notes = _notesController.text.trim();

    // Build services array with per-service time and staff
    final servicesArray = selectedServices.map((service) {
      final svcId = service['id'] as String;
      final svcTime = _serviceTimeSelections[svcId] ?? firstTime;
      final svcTimeStr = '${svcTime.hour.toString().padLeft(2, '0')}:${svcTime.minute.toString().padLeft(2, '0')}';
      
      String? staffId;
      String staffName = 'Any Available';
      
      // For staff, auto-assign themselves to all services
      if (_userRole == 'staff' && _currentUserId != null) {
        staffId = _currentUserId;
        staffName = _currentUserName ?? 'Staff';
      } else {
        // For other roles, use the selected staff
        final svcStaffId = _serviceStaffSelections[svcId];
        if (svcStaffId != null && svcStaffId != 'any') {
          staffId = svcStaffId;
          final match = _staff.firstWhere((s) => s['id'] == svcStaffId, orElse: () => {});
          if (match.isNotEmpty) {
            staffName = (match['name'] ?? 'Staff').toString();
          }
        }
      }
      
      // Build service data
      final serviceData = {
        'duration': (service['duration'] as num?)?.toInt() ?? 60,
        'id': service['id'],
        'name': service['name'],
        'price': (service['price'] as num?)?.toInt() ?? 0,
        'staffId': staffId,
        'staffName': staffName,
        'time': svcTimeStr,
      };
      
      // Set approval status based on user role and staff assignment
      if (_userRole == 'staff' && staffId != null) {
        // Staff bookings: auto-accept the service and store auth UID
        serviceData['approvalStatus'] = 'accepted';
        serviceData['staffAuthUid'] = staffId; // Store auth UID for calendar matching
      } else if (_userRole == 'workshop_owner' || _userRole == 'branch_admin') {
        // Owner/Admin bookings: set approval status based on staff assignment
        // Services with valid staff get "pending" approval status
        // Services without staff (Any Available) get "needs_assignment" status
        final hasStaff = staffId != null && 
                        staffId != 'null' && 
                        staffId != 'any' &&
                        !staffId.toLowerCase().contains('any');
        serviceData['approvalStatus'] = hasStaff ? 'pending' : 'needs_assignment';
      }
      // For other roles, leave approvalStatus unset (will be handled by backend)
      
      return serviceData;
    }).toList();

    final bookingCode = _generateBookingCode();
    
    // Determine booking source based on user role
    String bookingSource = 'AdminBooking';
    if (_userRole == 'branch_admin') {
      bookingSource = 'Branch Admin Booking - $_selectedBranchLabel';
    } else if (_userRole == 'workshop_owner') {
      bookingSource = 'Workshop Owner Booking';
    } else if (_userRole == 'staff') {
      // For staff bookings, show the staff member's name (use mainStaffName as it's more reliable)
      final staffDisplayName = mainStaffName != 'Any Available' && mainStaffName != 'Multiple Staff' 
          ? mainStaffName 
          : (_currentUserName ?? 'Staff');
      bookingSource = 'Staff Booking - $staffDisplayName';
    }
    
    // Get branch timezone (fallback to Australia/Sydney if not set)
    final branchTimezone = _selectedBranchTimezone ?? 'Australia/Sydney';
    
    // Create UTC timestamp from local date/time for consistent storage
    String? dateTimeUtc;
    try {
      // Parse the local date and time
      final year = _selectedDate!.year;
      final month = _selectedDate!.month;
      final day = _selectedDate!.day;
      final hour = firstTime.hour;
      final minute = firstTime.minute;
      final localDateTime = DateTime(year, month, day, hour, minute);
      
      // Convert to UTC for storage
      final utcDateTime = TimezoneHelper.localToUtc(localDateTime, branchTimezone);
      dateTimeUtc = utcDateTime.toIso8601String();
    } catch (e) {
      debugPrint('Error converting to UTC: $e');
    }
    
    final bookingData = <String, dynamic>{
      'bookingCode': bookingCode,
      'bookingSource': bookingSource,
      'branchId': _selectedBranchId,
      'branchName': _selectedBranchLabel,
      'branchTimezone': branchTimezone, // Store branch timezone
      'client': clientName,
      'clientEmail': email.isNotEmpty ? email : null,
      'clientPhone': phone.isNotEmpty ? phone : null,
      'createdAt': FieldValue.serverTimestamp(),
      'customerUid': null, // Walk-in customers don't have UID
      'date': dateStr, // Local date for backward compatibility
      'dateTimeUtc': dateTimeUtc, // UTC timestamp for accurate storage
      'duration': _totalDuration,
      'notes': notes.isNotEmpty ? notes : null,
      'ownerUid': _ownerUid,
      'price': _totalPrice,
      'serviceId': serviceIds,
      'serviceName': serviceNames,
      'services': servicesArray,
      'staffId': mainStaffId,
      'staffName': mainStaffName,
      if (_userRole == 'staff' && mainStaffId != null) 'staffAuthUid': mainStaffId, // Store auth UID for calendar matching
      // Determine booking status:
      // - staff: Confirmed (all services auto-accepted)
      // - workshop_owner/branch_admin: AwaitingStaffApproval (skip Pending, go directly to staff approval)
      // - Other roles: Pending
      'status': _userRole == 'staff' 
          ? 'Confirmed' 
          : (_userRole == 'workshop_owner' || _userRole == 'branch_admin')
              ? 'AwaitingStaffApproval'
              : 'Pending',
      'time': mainTimeStr, // Local time for backward compatibility
      'updatedAt': FieldValue.serverTimestamp(),
    };

    debugPrint('Creating booking with data: $bookingData');
    debugPrint('📧 Email field check: email="${email}", isEmpty=${email.isEmpty}, clientEmail in bookingData=${bookingData['clientEmail']}');

    // Create booking via API endpoint to ensure emails are sent
    String bookingId;
    try {
      // Get auth token
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }
      final token = await user.getIdToken();
      
      // Prepare booking data for API (remove Firestore-specific fields and fields generated by API)
      final apiBookingData = Map<String, dynamic>.from(bookingData);
      apiBookingData.remove('createdAt');
      apiBookingData.remove('updatedAt');
      apiBookingData.remove('bookingCode'); // API generates this
      apiBookingData.remove('bookingSource'); // API generates this based on user role
      
      // Ensure clientEmail is included (even if null, so API knows to skip email)
      // Don't remove it - the API needs it to send emails
      if (!apiBookingData.containsKey('clientEmail')) {
        apiBookingData['clientEmail'] = email.isNotEmpty ? email : null;
      }
      
      debugPrint('📤 Sending booking to API with clientEmail: ${apiBookingData['clientEmail']}');
      debugPrint('📤 API booking data keys: ${apiBookingData.keys.toList()}');
      
      // Call the API endpoint
      const apiBaseUrl = 'https://black.bmspros.com.au';
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/bookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(apiBookingData),
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('📥 API response status: ${response.statusCode}');
      debugPrint('📥 API response body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        bookingId = responseData['id']?.toString() ?? '';
        debugPrint('✅ Booking created successfully via API: $bookingId');
      } else {
        debugPrint('❌ API error response: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to create booking: ${response.statusCode} - ${response.body}');
      }
    } catch (apiError) {
      debugPrint('⚠️ API call failed, falling back to direct Firestore write: $apiError');
      // Fallback to direct Firestore write if API fails
      final bookingRef = await FirebaseFirestore.instance
          .collection('bookings')
          .add(bookingData);
      bookingId = bookingRef.id;
      debugPrint('⚠️ Booking created via Firestore fallback (emails may not be sent): $bookingId');
    }

    // Log audit trail for staff and branch admin created bookings
    if ((_userRole == 'staff' || _userRole == 'branch_admin') && _ownerUid != null && _currentUserId != null) {
      try {
        await AuditLogService.logWalkInBookingCreated(
          ownerUid: _ownerUid,
          bookingId: bookingId,
          bookingCode: bookingCode,
          clientName: clientName,
          serviceName: serviceNames,
          performedBy: _currentUserId!,
          performedByName: _currentUserName,
          performedByRole: _userRole,
          branchId: _selectedBranchId,
          branchName: _selectedBranchLabel,
          bookingDate: dateStr,
          bookingTime: mainTimeStr,
          price: _totalPrice.toDouble(),
          duration: _totalDuration,
          notes: notes.isNotEmpty ? notes : null,
          bookingSource: bookingSource,
          clientEmail: email.isNotEmpty ? email : null,
          clientPhone: phone.isNotEmpty ? phone : null,
          staffName: mainStaffName != 'Any Available' && mainStaffName != 'Multiple Staff' ? mainStaffName : null,
        );
      } catch (e) {
        debugPrint('Failed to create audit log for walk-in booking: $e');
        // Don't fail the booking creation if audit log fails
      }
    }
    
    // Check if any services need staff assignment (Any Available)
    final hasUnassignedServices = servicesArray.any((service) {
      final staffId = service['staffId'];
      final staffName = (service['staffName'] ?? '').toString();
      final approvalStatus = service['approvalStatus'];
      return approvalStatus == 'needs_assignment' ||
             staffId == null ||
             staffId == 'null' ||
             staffId == 'any' ||
             staffName.toLowerCase().contains('any available') ||
             staffName.toLowerCase().contains('any staff');
    });
    
    // Send notification to salon owner for all staff/branch admin created bookings
    // (but not when owner creates their own booking)
    if (_ownerUid != null && _currentUserId != null && _currentUserId != _ownerUid) {
      try {
        // Send notification to owner
        await _sendOwnerNotification(
          bookingId: bookingId,
          bookingCode: bookingCode,
          clientName: clientName,
          serviceNames: serviceNames,
          dateStr: dateStr,
          timeStr: mainTimeStr,
          branchName: _selectedBranchLabel ?? 'Branch',
          creatorName: _currentUserName ?? 'Staff',
          creatorRole: _userRole ?? 'staff',
          services: servicesArray,
          needsStaffAssignment: hasUnassignedServices,
        );
      } catch (e) {
        debugPrint('Failed to send owner notification: $e');
        // Don't fail booking creation if notification fails
      }
    }
    
    // ALWAYS send notification to branch admin(s) for ANY STAFF bookings
    // This is critical - branch admins need to know about bookings that need staff assignment
    // regardless of who created the booking (owner, staff, or branch admin themselves)
    if (_ownerUid != null && _selectedBranchId != null && hasUnassignedServices) {
      try {
        await _sendBranchAdminNotifications(
          bookingId: bookingId,
          bookingCode: bookingCode,
          clientName: clientName,
          serviceNames: serviceNames,
          dateStr: dateStr,
          timeStr: mainTimeStr,
          branchName: _selectedBranchLabel ?? 'Branch',
          creatorName: _currentUserName ?? 'Staff',
          creatorRole: _userRole ?? 'staff',
          services: servicesArray,
          needsStaffAssignment: hasUnassignedServices,
        );
        debugPrint('✅ Branch admin notification sent for ANY STAFF booking');
      } catch (e) {
        debugPrint('Failed to send branch admin notification: $e');
        // Don't fail booking creation if notification fails
      }
    }
  }
  
  /// Send notification to salon owner when booking is created by staff
  Future<void> _sendOwnerNotification({
    required String bookingId,
    required String bookingCode,
    required String clientName,
    required String serviceNames,
    required String dateStr,
    required String timeStr,
    required String branchName,
    required String creatorName,
    required String creatorRole,
    required List<Map<String, dynamic>> services,
    required bool needsStaffAssignment,
  }) async {
    if (_ownerUid == null) return;
    
    final roleLabel = creatorRole == 'branch_admin' ? 'Branch Admin' : 'Staff';
    
    // Determine notification type and message based on whether staff assignment is needed
    final String notificationType;
    final String title;
    final String message;
    
    if (needsStaffAssignment) {
      // Check if all services need assignment or just some
      final unassignedServices = services.where((service) {
        final staffId = service['staffId'];
        final staffName = (service['staffName'] ?? '').toString();
        final approvalStatus = service['approvalStatus'];
        return approvalStatus == 'needs_assignment' ||
               staffId == null ||
               staffId == 'null' ||
               staffId == 'any' ||
               staffName.toLowerCase().contains('any available') ||
               staffName.toLowerCase().contains('any staff');
      }).toList();
      
      final allUnassigned = unassignedServices.length == services.length;
      final unassignedServiceNames = unassignedServices
          .map((s) => s['name'] ?? 'Service')
          .join(', ');
      
      notificationType = 'booking_needs_assignment';
      title = allUnassigned 
          ? 'New Booking - Staff Assignment Required'
          : 'Booking - Partial Staff Assignment Required';
      message = allUnassigned
          ? '$creatorName ($roleLabel) created a booking for $clientName - $unassignedServiceNames on $dateStr at $timeStr. Please assign staff to all services.'
          : '$creatorName ($roleLabel) created a booking for $clientName. Staff assignment needed for: $unassignedServiceNames. Other services have been sent to assigned staff.';
    } else {
      notificationType = 'staff_booking_created';
      title = 'New Booking Created by $roleLabel';
      message = '$creatorName created a booking for $clientName - $serviceNames at $branchName on $dateStr at $timeStr';
    }
    
    // Create notification in Firestore for the owner
    final notificationData = {
      'type': notificationType,
      'title': title,
      'message': message,
      'ownerUid': _ownerUid,
      'targetOwnerUid': _ownerUid, // Explicitly target the owner
      'targetRole': 'admin',
      'staffUid': _currentUserId,
      'bookingId': bookingId,
      'bookingCode': bookingCode,
      'clientName': clientName,
      'serviceName': serviceNames,
      'services': services.map((s) {
        final staffId = s['staffId'];
        final staffName = (s['staffName'] ?? '').toString();
        final approvalStatus = s['approvalStatus'];
        final needsAssignment = approvalStatus == 'needs_assignment' ||
                                 staffId == null ||
                                 staffId == 'null' ||
                                 staffId == 'any' ||
                                 staffName.toLowerCase().contains('any available') ||
                                 staffName.toLowerCase().contains('any staff');
        return {
          'name': s['name'] ?? 'Service',
          'staffName': needsAssignment ? 'Needs Assignment' : (staffName != 'Any Available' ? staffName : null),
          'staffId': staffId,
          'needsAssignment': needsAssignment,
        };
      }).toList(),
      'branchName': branchName,
      'branchId': _selectedBranchId, // Include branchId for branch filtering
      'bookingDate': dateStr,
      'bookingTime': timeStr,
      'status': _userRole == 'staff' 
          ? 'Confirmed' 
          : (_userRole == 'workshop_owner' || _userRole == 'branch_admin')
              ? 'AwaitingStaffApproval'
              : 'Pending',
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    };
    
    final notificationRef = await FirebaseFirestore.instance.collection('notifications').add(notificationData);
    
    // Send FCM push notification to owner
    try {
      await FcmPushService().sendPushNotification(
        targetUid: _ownerUid!,
        title: title,
        message: message,
        data: {
          'notificationId': notificationRef.id,
          'type': notificationType,
          'bookingId': bookingId,
          'bookingCode': bookingCode,
        },
      );
      debugPrint('✅ FCM push notification sent to owner $_ownerUid (type: $notificationType)');
    } catch (e) {
      debugPrint('Error sending FCM notification to owner: $e');
    }
    
    // Also send notification to branch admin(s) of this branch (if any)
    await _sendBranchAdminNotifications(
      bookingId: bookingId,
      bookingCode: bookingCode,
      clientName: clientName,
      serviceNames: serviceNames,
      dateStr: dateStr,
      timeStr: timeStr,
      branchName: branchName,
      creatorName: creatorName,
      creatorRole: creatorRole,
      services: services,
      needsStaffAssignment: needsStaffAssignment,
    );
  }
  
  /// Send notification to branch admin(s) when booking is created at their branch
  Future<void> _sendBranchAdminNotifications({
    required String bookingId,
    required String bookingCode,
    required String clientName,
    required String serviceNames,
    required String dateStr,
    required String timeStr,
    required String branchName,
    required String creatorName,
    required String creatorRole,
    required List<Map<String, dynamic>> services,
    required bool needsStaffAssignment,
  }) async {
    if (_ownerUid == null || _selectedBranchId == null) return;
    
    try {
      // Find branch admin(s) for this branch
      final branchAdminQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('ownerUid', isEqualTo: _ownerUid)
          .where('role', isEqualTo: 'branch_admin')
          .where('branchId', isEqualTo: _selectedBranchId)
          .get();
      
      if (branchAdminQuery.docs.isEmpty) {
        debugPrint('No branch admin found for branch $_selectedBranchId');
        return;
      }
      
      final roleLabel = creatorRole == 'branch_admin' ? 'Branch Admin' : 'Staff';
      
      // Determine notification type and message based on whether staff assignment is needed
      final String notificationType;
      final String title;
      final String message;
      
      if (needsStaffAssignment) {
        // Check if all services need assignment or just some
        final unassignedServices = services.where((service) {
          final staffId = service['staffId'];
          final staffName = (service['staffName'] ?? '').toString();
          final approvalStatus = service['approvalStatus'];
          return approvalStatus == 'needs_assignment' ||
                 staffId == null ||
                 staffId == 'null' ||
                 staffId == 'any' ||
                 staffName.toLowerCase().contains('any available') ||
                 staffName.toLowerCase().contains('any staff');
        }).toList();
        
        final allUnassigned = unassignedServices.length == services.length;
        final unassignedServiceNames = unassignedServices
            .map((s) => s['name'] ?? 'Service')
            .join(', ');
        
        notificationType = 'booking_needs_assignment';
        title = allUnassigned 
            ? 'New Booking - Staff Assignment Required'
            : 'Booking - Partial Staff Assignment Required';
        message = allUnassigned
            ? '$creatorName ($roleLabel) created a booking for $clientName - $unassignedServiceNames on $dateStr at $timeStr. Please assign staff to all services.'
            : '$creatorName ($roleLabel) created a booking for $clientName. Staff assignment needed for: $unassignedServiceNames. Other services have been sent to assigned staff.';
      } else {
        notificationType = 'staff_booking_created';
        title = 'New Booking at Your Branch';
        message = '$creatorName ($roleLabel) created a booking for $clientName - $serviceNames on $dateStr at $timeStr';
      }
      
      for (final adminDoc in branchAdminQuery.docs) {
        final branchAdminUid = adminDoc.id;
        
        // Don't skip - branch admin should receive notifications even if they created the booking
        // This is important for "ANY STAFF" bookings where they need to assign staff
        // Only skip if it's a regular booking (not needing assignment) and they created it
        if (branchAdminUid == _currentUserId && !needsStaffAssignment) {
          debugPrint('Skipping notification to self (branch admin created booking with assigned staff)');
          continue;
        }
        
        // Create notification for branch admin
        final notificationData = {
          'type': notificationType,
          'title': title,
          'message': message,
          'ownerUid': _ownerUid,
          'branchAdminUid': branchAdminUid, // Target branch admin
          'targetAdminUid': branchAdminUid, // For targeting
          'targetRole': 'admin',
          'staffUid': _currentUserId,
          'bookingId': bookingId,
          'bookingCode': bookingCode,
          'clientName': clientName,
          'serviceName': serviceNames,
          'services': services.map((s) {
            final staffId = s['staffId'];
            final staffName = (s['staffName'] ?? '').toString();
            final approvalStatus = s['approvalStatus'];
            final needsAssignment = approvalStatus == 'needs_assignment' ||
                                     staffId == null ||
                                     staffId == 'null' ||
                                     staffId == 'any' ||
                                     staffName.toLowerCase().contains('any available') ||
                                     staffName.toLowerCase().contains('any staff');
            return {
              'name': s['name'] ?? 'Service',
              'staffName': needsAssignment ? 'Needs Assignment' : (staffName != 'Any Available' ? staffName : null),
              'staffId': staffId,
              'needsAssignment': needsAssignment,
            };
          }).toList(),
          'branchName': branchName,
          'branchId': _selectedBranchId,
          'bookingDate': dateStr,
          'bookingTime': timeStr,
          'status': _userRole == 'staff' 
              ? 'Confirmed' 
              : (_userRole == 'workshop_owner' || _userRole == 'branch_admin')
                  ? 'AwaitingStaffApproval'
                  : 'Pending',
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        };
        
        final notificationRef = await FirebaseFirestore.instance.collection('notifications').add(notificationData);
        
        // Send FCM push notification to branch admin
        try {
          await FcmPushService().sendPushNotification(
            targetUid: branchAdminUid,
            title: title,
            message: message,
            data: {
              'notificationId': notificationRef.id,
              'type': notificationType,
              'bookingId': bookingId,
              'bookingCode': bookingCode,
            },
          );
          debugPrint('✅ FCM push notification sent to branch admin $branchAdminUid (type: $notificationType)');
        } catch (e) {
          debugPrint('Error sending FCM notification to branch admin: $e');
        }
      }
    } catch (e) {
      debugPrint('Error sending branch admin notifications: $e');
    }
  }

  // --- UI Building ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loadingContext || _loadingData
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildStepContent(),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      bottomSheet: _buildBottomBar(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(FontAwesomeIcons.xmark, color: AppColors.text, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Column(
            children: [
              Text(
                _userRole == 'staff' ? 'Create My Booking' : 'Create Booking',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text)),
              const SizedBox(height: 4),
              Text(
                _userRole == 'staff' 
                    ? (_currentStep == 0 
                        ? 'Step 1: Date, Branch & Services'
                        : _currentStep == 1 
                            ? 'Step 2: Select Times'
                            : 'Step 3: Customer Details')
                    : 'Step ${_currentStep + 1} of 3',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _currentStep = 0;
                _selectedBranchId = null;
                _selectedBranchLabel = null;
                _selectedBranchTimezone = null;
                _selectedServiceIds = {};
                _selectedDate = null;
                _serviceTimeSelections = {};
                _serviceStaffSelections = {};
                _nameController.clear();
                _phoneController.clear();
                _emailController.clear();
                _notesController.clear();
              });
            },
            child: const Text('Reset',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerForm() {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 8))],
        ),
        child: Column(
          children: [
            TextField(
            controller: _nameController,
            decoration: _inputDecoration("Full Name *", "Enter customer name"),
              style: const TextStyle(color: AppColors.text),
            onChanged: (_) => setState(() {}), // Trigger rebuild for validation
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: _inputDecoration("Phone *", "Enter phone number"),
            style: const TextStyle(color: AppColors.text),
            onChanged: (_) => setState(() {}), // Trigger rebuild for validation
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDecoration("Email Address *", "john@example.com"),
            style: const TextStyle(color: AppColors.text),
            onChanged: (_) => setState(() {}), // Trigger rebuild for validation
          ),
            const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: _inputDecoration("Additional Notes (optional)", "Any special requests or notes..."),
            style: const TextStyle(color: AppColors.text),
          ),
          ],
        ),
      );
  }

  Widget _buildServiceGrid() {
    // Require branch selection first
    if (_selectedBranchId == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(FontAwesomeIcons.mapLocationDot,
                size: 40, color: AppColors.muted.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text(
              'Select a branch first',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose a location above to see available services',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    if (_services.isEmpty) {
      return Text(
        _userRole == 'staff' 
            ? 'You are not assigned to any services yet.\nPlease contact your manager.'
            : 'No services found. Please add services in the admin panel.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.muted),
      );
    }

    // Filter services by selected branch.
    // Service.branches is a List<String> of branch document IDs.
    // - If the list is empty or null → service is NOT available (must be assigned to at least one branch).
    // - If the list is non-empty → service is only available for those specific branch IDs.
    final List<Map<String, dynamic>> visibleServices = _services.where((srv) {
      final dynamic branchesRaw = srv['branches'];
      // If branches field is missing, null, or empty list → NOT available (must be assigned to branches)
      if (branchesRaw == null) return false;
      if (branchesRaw is! List) return false;
      if (branchesRaw.isEmpty) return false;

      // branches is non-empty → check if selected branch is in the list
      final List<String> branchIds = branchesRaw.map((e) => e.toString()).toList();
      debugPrint('[ServiceFilter] Service "${srv['name']}" branches=$branchIds, selectedBranch=$_selectedBranchId');
      return branchIds.contains(_selectedBranchId);
    }).toList();

    debugPrint('[ServiceFilter] Total services=${_services.length}, visible=${visibleServices.length}, selectedBranch=$_selectedBranchId');

    if (visibleServices.isEmpty) {
      return Text(
        _userRole == 'staff'
            ? 'No services you can provide at this branch.'
            : 'No services available for this branch.',
        style: const TextStyle(fontSize: 13, color: AppColors.muted),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: visibleServices.length,
      itemBuilder: (context, index) {
        return _buildServiceCard(visibleServices[index]);
      },
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final serviceId = service['id'];
    final isSelected = _selectedServiceIds.contains(serviceId);
    debugPrint('[ServiceCard] Building card for ${service['name']} (id: $serviceId), isSelected: $isSelected, selectedIds: $_selectedServiceIds');
    final Color color = AppColors.primary;
    final int durationMinutes =
        (service['duration'] is num) ? (service['duration'] as num).toInt() : 0;
    final String durationLabel =
        durationMinutes >= 60 && durationMinutes % 60 == 0
            ? '${durationMinutes ~/ 60}h'
            : '${durationMinutes}m';
    final String? imageUrl =
        service['imageUrl'] != null && service['imageUrl'].toString().isNotEmpty
            ? service['imageUrl'].toString()
            : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint('[ServiceCard] Tapped: ${service['name']} (id: $serviceId)');
        _selectService(serviceId);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 4))],
          border: isSelected ? null : Border.all(color: AppColors.border),
          gradient: isSelected ? const LinearGradient(colors: [AppColors.primary, AppColors.accent]) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Large Image Section with checkmark
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 1.2,
              child: imageUrl != null
                        ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: isSelected ? Colors.white.withOpacity(0.2) : color.withOpacity(0.1),
                              child: Center(
                                child: Icon(
                                  FontAwesomeIcons.scissors,
                                  color: isSelected ? Colors.white : color,
                                  size: 32,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: isSelected ? Colors.white.withOpacity(0.2) : color.withOpacity(0.1),
                            child: Center(
                      child: Icon(
                        FontAwesomeIcons.scissors,
                        color: isSelected ? Colors.white : color,
                                size: 32,
                      ),
                    ),
            ),
                  ),
                ),
                // Checkmark badge for selected services
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check,
                          color: AppColors.primary,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Service Info Section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service['name'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppColors.text,
                      fontSize: 13,
                  ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                ),
                  const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white.withOpacity(0.2) : AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                      durationLabel,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ),
                    Text(
                      '\$${service['price']}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                    ),
                  ],
                )
              ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // Get staff who can perform a specific service and work at the selected branch
  List<Map<String, dynamic>> _getAvailableStaffForService(String serviceId) {
    // For staff, they can only book themselves
    if (_userRole == 'staff' && _currentUserId != null) {
      final currentStaff = _staff.firstWhere(
        (s) => s['id'] == _currentUserId,
        orElse: () => {},
      );
      if (currentStaff.isNotEmpty) {
        return [currentStaff];
      }
      return [];
    }
    
    final service = _services.firstWhere((s) => s['id'] == serviceId, orElse: () => {});
    if (service.isEmpty) return [];

    final List<String> serviceStaffIds = service['staffIds'] != null
        ? (service['staffIds'] as List).map((e) => e.toString()).toList()
        : [];
    
    // Get day of week from selected date for schedule check
    String? dayOfWeek;
    if (_selectedDate != null) {
      final days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      dayOfWeek = days[_selectedDate!.weekday % 7];
    }

    debugPrint('[StaffFilter] serviceId=$serviceId, serviceStaffIds=$serviceStaffIds, selectedBranch=$_selectedBranchId, dayOfWeek=$dayOfWeek');
    debugPrint('[StaffFilter] Total staff in list: ${_staff.length}');
    
    final filtered = _staff.where((staff) {
      final staffId = staff['id'];
      final staffName = staff['name'];
      
      // Check if staff is active (not suspended)
      final status = (staff['status'] ?? 'Active').toString();
      if (status == 'Suspended' || status == 'suspended') {
        debugPrint('[StaffFilter] $staffName ($staffId) - REJECTED: suspended');
        return false;
      }
      
      // Check if staff can perform this service (if service has staffIds restriction)
      if (serviceStaffIds.isNotEmpty && !serviceStaffIds.contains(staff['id'])) {
        debugPrint('[StaffFilter] $staffName ($staffId) - REJECTED: not in service staffIds');
        return false;
      }
      
      // Check if staff works at selected branch (via branchId or weeklySchedule)
      if (_selectedBranchId != null && _selectedBranchId!.isNotEmpty) {
        final staffBranchId = staff['branchId']?.toString() ?? '';
        bool worksAtBranch = staffBranchId == _selectedBranchId;
        
        debugPrint('[StaffFilter] $staffName ($staffId) - branchId=$staffBranchId, worksAtBranch=$worksAtBranch');
        
        // Also check weeklySchedule for the selected day
        if (!worksAtBranch && dayOfWeek != null && staff['weeklySchedule'] is Map) {
          final weeklySchedule = staff['weeklySchedule'] as Map;
          final daySchedule = weeklySchedule[dayOfWeek];
          debugPrint('[StaffFilter] $staffName ($staffId) - checking weeklySchedule[$dayOfWeek]=$daySchedule');
          if (daySchedule is Map && daySchedule['branchId'] != null) {
            worksAtBranch = daySchedule['branchId'].toString() == _selectedBranchId;
            debugPrint('[StaffFilter] $staffName ($staffId) - schedule branchId=${daySchedule['branchId']}, worksAtBranch=$worksAtBranch');
          }
        }
        
        if (!worksAtBranch) {
          debugPrint('[StaffFilter] $staffName ($staffId) - REJECTED: not at selected branch');
          return false;
        }
      }
      
      debugPrint('[StaffFilter] $staffName ($staffId) - ACCEPTED');
      return true;
    }).toList();
    
    debugPrint('[StaffFilter] Filtered result: ${filtered.length} staff');
    return filtered;
  }

  Widget _buildDatePicker() {
    final dateText = _selectedDate != null
        ? '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}'
        : 'Select date';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ListTile(
        leading: const Icon(FontAwesomeIcons.calendarDay,
            color: AppColors.primary, size: 18),
        title: const Text(
          'Date',
          style: TextStyle(
              fontWeight: FontWeight.w600, color: AppColors.text),
        ),
        subtitle: Text(
          dateText,
          style: const TextStyle(color: AppColors.muted),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _selectedDate ?? now,
            firstDate: now,
            lastDate: now.add(const Duration(days: 365)),
          );
          if (picked != null) {
            setState(() {
              _selectedDate = picked;
              // Clear time/staff selections when date changes
              _serviceTimeSelections = {};
              _serviceStaffSelections = {};
            });
          }
        },
      ),
    );
  }

  /// Build timezone indicator showing branch's current time
  Widget _buildTimezoneIndicator() {
    final timezone = _selectedBranchTimezone ?? 'Australia/Sydney';
    final branchNow = TimezoneHelper.nowInTimezone(timezone);
    final timeStr = DateFormat('HH:mm').format(branchNow);
    
    // Get timezone display name (last part of IANA timezone)
    final tzLabel = timezone.split('/').last.replaceAll('_', ' ');
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.blue.withOpacity(0.1),
            AppColors.purple.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(FontAwesomeIcons.globe, size: 14, color: AppColors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Branch Time Zone: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.blue.withOpacity(0.8),
                    ),
                  ),
                  Text(
                    tzLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FontAwesomeIcons.clock, size: 10, color: AppColors.blue),
                    const SizedBox(width: 6),
                    Text(
                      'Current: $timeStr',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(FontAwesomeIcons.circleInfo, size: 10, color: AppColors.blue.withOpacity(0.6)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Times are in branch\'s local timezone. Past slots are hidden.',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.blue.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerServiceTimeStaffSelector() {
    if (_selectedDate == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
              child: Column(
          children: [
            Icon(FontAwesomeIcons.calendarDay,
                size: 40, color: AppColors.muted.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text(
              'Select a date first',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    final selectedServices = _selectedServiceIds
        .map((id) => _services.firstWhere((s) => s['id'] == id, orElse: () => {}))
        .where((s) => s.isNotEmpty)
        .toList();

    if (selectedServices.isEmpty) {
      return const Text('No services selected', style: TextStyle(color: AppColors.muted));
    }

    return Column(
      children: [
        // Branch Timezone Indicator
        if (_selectedBranchId != null) _buildTimezoneIndicator(),
        const SizedBox(height: 16),
        ...selectedServices.map((service) {
          final serviceId = service['id'] as String;
          final serviceName = service['name'] ?? 'Service';
          final duration = (service['duration'] as num?)?.toInt() ?? 60;
          final selectedTime = _serviceTimeSelections[serviceId];
          final selectedStaffId = _serviceStaffSelections[serviceId] ?? 'any';
          final availableStaff = _getAvailableStaffForService(serviceId);

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(FontAwesomeIcons.scissors, color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serviceName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          '${duration}min • \$${service['price']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selectedTime != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.check, color: AppColors.green, size: 16),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Staff selector - hidden for staff (they are auto-assigned)
              if (_userRole == 'staff') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(FontAwesomeIcons.userCheck, size: 16, color: AppColors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You will be assigned to this service',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.green.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const Text(
                  'Select Staff',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                _buildStaffChips(serviceId, availableStaff, selectedStaffId),
              ],

              const SizedBox(height: 16),

              // Time selector
              const Text(
                'Select Time',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              _buildTimeSlots(serviceId, duration),
            ],
          ),
        );
      }).toList(),
      ],
    );
  }

  Widget _buildTimeSlots(String serviceId, int durationMinutes) {
    // Get branch hours for the selected date
    final selectedBranch = _branches.firstWhere(
      (b) => b['id'] == _selectedBranchId,
      orElse: () => <String, dynamic>{},
    );
    
    // Get day of week from selected date
    String? dayOfWeek;
    if (_selectedDate != null) {
      final days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      dayOfWeek = days[_selectedDate!.weekday % 7];
    }
    
    // Get branch hours for this day
    int startHour = 9; // Default fallback
    int startMinute = 0;
    int endHour = 18; // Default fallback
    int endMinute = 0;
    bool isClosed = false;
    
    if (selectedBranch.isNotEmpty && selectedBranch['hours'] != null) {
      final hours = selectedBranch['hours'];
      if (hours is Map && dayOfWeek != null) {
        final dayHours = hours[dayOfWeek];
        if (dayHours is Map) {
          if (dayHours['closed'] == true) {
            isClosed = true;
          } else {
            if (dayHours['open'] != null) {
              final openTime = dayHours['open'].toString();
              final openParts = openTime.split(':');
              if (openParts.length >= 2) {
                startHour = int.tryParse(openParts[0]) ?? 9;
                startMinute = int.tryParse(openParts[1]) ?? 0;
              }
            }
            if (dayHours['close'] != null) {
              final closeTime = dayHours['close'].toString();
              final closeParts = closeTime.split(':');
              if (closeParts.length >= 2) {
                endHour = int.tryParse(closeParts[0]) ?? 18;
                endMinute = int.tryParse(closeParts[1]) ?? 0;
              }
            }
          }
        }
      }
    }
    
    if (isClosed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: const Text(
          'Branch is closed on this day',
          style: TextStyle(color: Colors.red, fontSize: 13),
        ),
      );
    }
    
    // Calculate the latest possible slot start time
    // The service must finish by closing time, so: slotStart + duration <= endTime
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;
    final latestSlotStart = endMinutes - durationMinutes;
    
    // Use BRANCH timezone to check if date is today (not user's local time)
    // This ensures Sri Lankan users booking Perth branch see correct available slots
    final branchTimezone = _selectedBranchTimezone ?? 'Australia/Sydney';
    final branchNow = TimezoneHelper.nowInTimezone(branchTimezone);
    final branchTodayDateStr = DateFormat('yyyy-MM-dd').format(branchNow);
    
    // Check if selected date is today IN THE BRANCH'S TIMEZONE
    final selectedDateStr = _selectedDate != null
        ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
        : '';
    final isToday = selectedDateStr == branchTodayDateStr;
    
    // Calculate current minutes based on branch's local time
    final currentMinutes = isToday ? (branchNow.hour * 60 + branchNow.minute) : -1;
    
    // Generate time slots using branch hours (including slots that exceed closing time for display purposes)
    final List<Map<String, dynamic>> slotsWithStatus = [];
    const interval = 15;
    
    // Helper to format closing time
    String formatClosingTime() {
      final h = endHour.toString().padLeft(2, '0');
      final m = endMinute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    
    for (int slotMinutes = startMinutes; slotMinutes < endMinutes; slotMinutes += interval) {
      // Skip past times if date is today
      if (isToday && slotMinutes <= currentMinutes) {
        continue;
      }
      
      final hour = slotMinutes ~/ 60;
      final minute = slotMinutes % 60;
      final time = TimeOfDay(hour: hour, minute: minute);
      
      // Check if service would extend past closing time
      if (slotMinutes + durationMinutes > endMinutes) {
        slotsWithStatus.add({
          'time': time,
          'available': false,
          'reason': 'closes_before_finish',
          'message': 'Service ends after closing (${formatClosingTime()})',
        });
      } else {
        slotsWithStatus.add({
          'time': time,
          'available': true,
        });
      }
    }

    final selectedTime = _serviceTimeSelections[serviceId];
    final selectedStaffId = _serviceStaffSelections[serviceId];
    
    // Get current staff ID for staff-specific blocking
    final String? staffIdToCheck = _userRole == 'staff' 
        ? _currentUserId 
        : (selectedStaffId != null && selectedStaffId != 'any' ? selectedStaffId : null);
    
    // Determine if "Any Staff" is selected
    final bool isAnyStaffSelected = staffIdToCheck == null || staffIdToCheck.isEmpty;
    
    // For "Any Staff" bookings, get all eligible staff IDs for this service+branch.
    // A slot is only blocked when ALL eligible staff are occupied at that time.
    final List<String> eligibleStaffIds = [];
    if (isAnyStaffSelected && _userRole != 'staff') {
      final eligible = _getAvailableStaffForService(serviceId);
      for (final st in eligible) {
        final id = st['id']?.toString() ?? '';
        // Exclude the synthetic "Any Staff" entry and empty IDs
        if (id.isNotEmpty && id != 'any') {
          eligibleStaffIds.add(id);
        }
      }
    }
    
    // Get the selected date string for comparison (for booking filtering)
    final bookingDateStr = _selectedDate != null
        ? '${_selectedDate!.year.toString().padLeft(4, '0')}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
        : null;

    // Helper: detect "Any Staff" staffId values (null, empty, "any", etc.)
    bool isAnyStaffValue(String? sid) {
      if (sid == null || sid.isEmpty) return true;
      final s = sid.toLowerCase().trim();
      if (s == 'null') return true;
      if (s.contains('any')) return true;
      return false;
    }

    // Helper: check if a specific staff member has a conflicting booking at a given time slot
    bool isStaffOccupiedAtSlot(int slotMinutes, String targetStaffId) {
      if (bookingDateStr == null) return false;
      final newServiceEndMinutes = slotMinutes + durationMinutes;
      
      for (final booking in _bookings) {
        if (booking['date'] != bookingDateStr) continue;
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        if (status == 'cancelled' || status == 'canceled' || status == 'staffrejected') continue;
        
        if (booking['services'] is List && (booking['services'] as List).isNotEmpty) {
          for (final svc in (booking['services'] as List)) {
            if (svc is Map) {
              final svcStaffId = svc['staffId']?.toString() ?? '';
              if (svcStaffId != targetStaffId) continue;
              
              final svcTime = svc['time']?.toString() ?? '';
              if (svcTime.isEmpty) continue;
              final svcTimeParts = svcTime.split(':');
              if (svcTimeParts.length < 2) continue;
              
              final svcStartMinutes = (int.tryParse(svcTimeParts[0]) ?? 0) * 60 + (int.tryParse(svcTimeParts[1]) ?? 0);
              final svcDuration = (svc['duration'] ?? 60) as int;
              final svcEndMinutes = svcStartMinutes + svcDuration;
              
              if (slotMinutes < svcEndMinutes && svcStartMinutes < newServiceEndMinutes) {
                return true;
              }
            }
          }
        } else {
          final bookingStaffId = booking['staffId']?.toString() ?? '';
          if (bookingStaffId != targetStaffId) continue;
          
          final bookingTime = booking['time']?.toString() ?? '';
          if (bookingTime.isEmpty) continue;
          final timeParts = bookingTime.split(':');
          if (timeParts.length < 2) continue;
          
          final bookingStartMinutes = (int.tryParse(timeParts[0]) ?? 0) * 60 + (int.tryParse(timeParts[1]) ?? 0);
          final bookingDuration = (booking['duration'] ?? 60) as int;
          final bookingEndMinutes = bookingStartMinutes + bookingDuration;
          
          if (slotMinutes < bookingEndMinutes && bookingStartMinutes < newServiceEndMinutes) {
            return true;
          }
        }
      }
      return false;
    }

    // Helper: Count how many eligible staff slots are consumed at a given time
    // by existing bookings (both specific-staff and any-staff bookings).
    // This mirrors the server-side logic in booking-requests and slot-holds APIs.
    Map<String, dynamic> countConsumedStaffAtSlot(int slotMinutes) {
      if (bookingDateStr == null) return {'bookedStaffIds': <String>{}, 'anyStaffCount': 0};
      final newServiceEndMinutes = slotMinutes + durationMinutes;
      final Set<String> bookedStaffIds = {};
      int anyStaffCount = 0;

      for (final booking in _bookings) {
        if (booking['date'] != bookingDateStr) continue;
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        if (status == 'cancelled' || status == 'canceled' || status == 'staffrejected') continue;

        if (booking['services'] is List && (booking['services'] as List).isNotEmpty) {
          for (final svc in (booking['services'] as List)) {
            if (svc is! Map) continue;
            final svcTime = svc['time']?.toString() ?? '';
            if (svcTime.isEmpty) continue;
            final svcTimeParts = svcTime.split(':');
            if (svcTimeParts.length < 2) continue;

            final svcStartMinutes = (int.tryParse(svcTimeParts[0]) ?? 0) * 60 + (int.tryParse(svcTimeParts[1]) ?? 0);
            final svcDuration = (svc['duration'] ?? 60) as int;
            final svcEndMinutes = svcStartMinutes + svcDuration;

            if (!(slotMinutes < svcEndMinutes && svcStartMinutes < newServiceEndMinutes)) continue;

            final svcStaffId = svc['staffId']?.toString() ?? '';
            if (!isAnyStaffValue(svcStaffId)) {
              // Specific staff booking — mark that staff as busy
              if (eligibleStaffIds.contains(svcStaffId)) {
                bookedStaffIds.add(svcStaffId);
              }
            } else {
              // "Any Staff" booking — consumes one staff slot from the pool
              anyStaffCount++;
            }
          }
        } else {
          final bookingTime = booking['time']?.toString() ?? '';
          if (bookingTime.isEmpty) continue;
          final timeParts = bookingTime.split(':');
          if (timeParts.length < 2) continue;

          final bStartMinutes = (int.tryParse(timeParts[0]) ?? 0) * 60 + (int.tryParse(timeParts[1]) ?? 0);
          final bDuration = (booking['duration'] ?? 60) as int;
          final bEndMinutes = bStartMinutes + bDuration;

          if (!(slotMinutes < bEndMinutes && bStartMinutes < newServiceEndMinutes)) continue;

          final bStaffId = booking['staffId']?.toString() ?? '';
          if (!isAnyStaffValue(bStaffId)) {
            if (eligibleStaffIds.contains(bStaffId)) {
              bookedStaffIds.add(bStaffId);
            }
          } else {
            anyStaffCount++;
          }
        }
      }

      return {'bookedStaffIds': bookedStaffIds, 'anyStaffCount': anyStaffCount};
    }

    // Helper function to check if a time slot is OCCUPIED (booking in progress at that time)
    // Also checks if the NEW service would OVERLAP with any existing booking
    // Returns: {'occupied': bool, 'reason': String?}
    Map<String, dynamic> isSlotOccupied(TimeOfDay slotTime) {
      if (bookingDateStr == null) return {'occupied': false};
      
      final slotMinutes = slotTime.hour * 60 + slotTime.minute;
      
      if (isAnyStaffSelected) {
        // "Any Staff" mode: slot is occupied only if ALL eligible staff slots are consumed.
        // Count both specific-staff bookings AND "any staff" bookings that consume from the pool.
        if (eligibleStaffIds.isEmpty) return {'occupied': false};
        
        final consumed = countConsumedStaffAtSlot(slotMinutes);
        final bookedStaffIds = consumed['bookedStaffIds'] as Set<String>;
        final anyStaffCount = consumed['anyStaffCount'] as int;
        final freeStaff = eligibleStaffIds.length - bookedStaffIds.length - anyStaffCount;
        
        if (freeStaff <= 0) {
          return {'occupied': true, 'reason': 'all_staff_booked'};
        }
        return {'occupied': false};
      }
      
      // Specific staff mode
      if (staffIdToCheck == null || staffIdToCheck.isEmpty) return {'occupied': false};
      
      // Calculate when this new service would END
      final newServiceEndMinutes = slotMinutes + durationMinutes;
      
      for (final booking in _bookings) {
        if (booking['date'] != bookingDateStr) continue;
        
        final status = (booking['status']?.toString() ?? '').toLowerCase();
        if (status == 'cancelled' || status == 'canceled' || status == 'staffrejected') continue;
        
        if (booking['services'] is List && (booking['services'] as List).isNotEmpty) {
          for (final svc in (booking['services'] as List)) {
            if (svc is Map) {
              final svcStaffId = svc['staffId']?.toString() ?? '';
              if (svcStaffId != staffIdToCheck) continue;
              
              final svcTime = svc['time']?.toString() ?? '';
              if (svcTime.isEmpty) continue;
              final svcTimeParts = svcTime.split(':');
              if (svcTimeParts.length < 2) continue;
              
              final svcStartMinutes = (int.tryParse(svcTimeParts[0]) ?? 0) * 60 + (int.tryParse(svcTimeParts[1]) ?? 0);
              final svcDuration = (svc['duration'] ?? 60) as int;
              final svcEndMinutes = svcStartMinutes + svcDuration;
              
              if (slotMinutes < svcEndMinutes && svcStartMinutes < newServiceEndMinutes) {
                if (slotMinutes >= svcStartMinutes && slotMinutes < svcEndMinutes) {
                  return {'occupied': true, 'reason': 'booked'};
                } else {
                  return {'occupied': true, 'reason': 'insufficient_time'};
                }
              }
            }
          }
        } else {
          final bookingStaffId = booking['staffId']?.toString() ?? '';
          if (bookingStaffId != staffIdToCheck) continue;
          
          final bookingTime = booking['time']?.toString() ?? '';
          if (bookingTime.isEmpty) continue;
          final timeParts = bookingTime.split(':');
          if (timeParts.length < 2) continue;
          
          final bookingStartMinutes = (int.tryParse(timeParts[0]) ?? 0) * 60 + (int.tryParse(timeParts[1]) ?? 0);
          final bookingDuration = (booking['duration'] ?? 60) as int;
          final bookingEndMinutes = bookingStartMinutes + bookingDuration;
          
          if (slotMinutes < bookingEndMinutes && bookingStartMinutes < newServiceEndMinutes) {
            if (slotMinutes >= bookingStartMinutes && slotMinutes < bookingEndMinutes) {
              return {'occupied': true, 'reason': 'booked'};
            } else {
              return {'occupied': true, 'reason': 'insufficient_time'};
            }
          }
        }
      }
      
      return {'occupied': false};
    }
    
    // Helper function to check if slot is blocked by OTHER services in current booking session (same staff)
    // Also checks if the NEW service would OVERLAP with other selected services
    // Returns: {'blocked': bool, 'reason': String?}
    Map<String, dynamic> isSlotBlockedByCurrentSelection(TimeOfDay slotTime) {
      // For staff bookings, always check for conflicts since staff are auto-assigned to all services
      // For other roles, handle "Any Staff" aggregate check or specific staff check
      
      if (isAnyStaffSelected && _userRole != 'staff') {
        // "Any Staff" mode: check if enough free staff remain after existing bookings
        // (including other "any staff" bookings) AND other services in the current booking session
        if (eligibleStaffIds.isEmpty) return {'blocked': false};
        
        final slotMinutes = slotTime.hour * 60 + slotTime.minute;
        final newServiceEndMinutes = slotMinutes + durationMinutes;
        
        // Count how many eligible staff slots are consumed by existing bookings
        // This includes both specific-staff bookings AND "any staff" bookings
        final consumed = countConsumedStaffAtSlot(slotMinutes);
        final bookedStaffIds = consumed['bookedStaffIds'] as Set<String>;
        final anyStaffCount = consumed['anyStaffCount'] as int;
        final occupiedByExisting = bookedStaffIds.length + anyStaffCount;
        
        int overlappingCurrentServices = 0;
        for (final otherServiceId in _selectedServiceIds) {
          if (otherServiceId == serviceId) continue;
          
          final otherTime = _serviceTimeSelections[otherServiceId];
          if (otherTime == null) continue;
          
          final otherStaffId = _serviceStaffSelections[otherServiceId];
          final otherIsAny = isAnyStaffValue(otherStaffId);
          
          if (!otherIsAny && !eligibleStaffIds.contains(otherStaffId)) continue;
          
          final otherService = _services.firstWhere(
            (s) => s['id'] == otherServiceId,
            orElse: () => {},
          );
          final otherDuration = (otherService['duration'] ?? 60) as int;
          
          final otherStartMinutes = otherTime.hour * 60 + otherTime.minute;
          final otherEndMinutes = otherStartMinutes + otherDuration;
          
          if (slotMinutes < otherEndMinutes && otherStartMinutes < newServiceEndMinutes) {
            overlappingCurrentServices++;
          }
        }
        
        // Free staff = total eligible - occupied by existing bookings (specific + any-staff)
        final freeStaff = eligibleStaffIds.length - occupiedByExisting;
        if (freeStaff <= overlappingCurrentServices) {
          return {'blocked': true, 'reason': 'all_staff_booked'};
        }
        
        return {'blocked': false};
      }
      
      final bool shouldCheckConflicts;
      if (_userRole == 'staff' && _currentUserId != null) {
        shouldCheckConflicts = true;
      } else {
        if (staffIdToCheck == null || staffIdToCheck.isEmpty) return {'blocked': false};
        shouldCheckConflicts = true;
      }
      
      if (!shouldCheckConflicts) return {'blocked': false};
      
      final slotMinutes = slotTime.hour * 60 + slotTime.minute;
      // Calculate when this new service would END
      final newServiceEndMinutes = slotMinutes + durationMinutes;
      
      for (final otherServiceId in _selectedServiceIds) {
        if (otherServiceId == serviceId) continue;
        
        // For staff bookings, check all other services since staff is assigned to all
        // For other roles, only check if the other service has the same staff assigned
        if (_userRole == 'staff') {
          // Staff is assigned to all services, so always check
        } else {
          final otherStaffId = _serviceStaffSelections[otherServiceId];
          if (otherStaffId == null || otherStaffId == 'any' || otherStaffId != staffIdToCheck) {
            continue; // Different staff or no staff assigned, no conflict
          }
        }
        
        final otherTime = _serviceTimeSelections[otherServiceId];
        if (otherTime == null) continue;
        
        // Get duration of other service
        final otherService = _services.firstWhere(
          (s) => s['id'] == otherServiceId,
          orElse: () => {},
        );
        final otherDuration = (otherService['duration'] ?? 60) as int;
        
        final otherStartMinutes = otherTime.hour * 60 + otherTime.minute;
        final otherEndMinutes = otherStartMinutes + otherDuration;
        
        // Check for ANY overlap between new service and other selected service
        if (slotMinutes < otherEndMinutes && otherStartMinutes < newServiceEndMinutes) {
          if (slotMinutes >= otherStartMinutes && slotMinutes < otherEndMinutes) {
            return {'blocked': true, 'reason': 'selected'};
          } else {
            return {'blocked': true, 'reason': 'insufficient_time_selected'};
          }
        }
      }
      
      return {'blocked': false};
    }

    // Check if any slots have duration constraint issues (for showing legend)
    final hasClosingTimeIssue = slotsWithStatus.any((s) => s['reason'] == 'closes_before_finish');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: slotsWithStatus.map((slotData) {
            final time = slotData['time'] as TimeOfDay;
            final isPreDisabled = slotData['available'] == false;
            final preReason = slotData['reason'] as String?;
            
            final isSelected = selectedTime != null &&
                selectedTime.hour == time.hour &&
                selectedTime.minute == time.minute;
            final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
            
            // Check booking and selection conflicts
            final occupiedResult = isSlotOccupied(time);
            final blockedResult = isSlotBlockedByCurrentSelection(time);
            
            final isOccupiedByBooking = occupiedResult['occupied'] == true;
            final isBlockedBySelection = blockedResult['blocked'] == true;
            final isClosesBeforeFinish = preReason == 'closes_before_finish';
            final isInsufficientTime = occupiedResult['reason'] == 'insufficient_time' || 
                                        blockedResult['reason'] == 'insufficient_time_selected';
            
            final isDisabled = isPreDisabled || isOccupiedByBooking || isBlockedBySelection;
            
            // Determine colors based on reason
            Color bgColor;
            Color borderColor;
            Color textColor;
            
            if (isSelected) {
              bgColor = AppColors.primary;
              borderColor = AppColors.primary;
              textColor = Colors.white;
            } else if (isClosesBeforeFinish) {
              bgColor = Colors.orange.shade50;
              borderColor = Colors.orange.shade200;
              textColor = Colors.orange.shade400;
            } else if (isInsufficientTime) {
              bgColor = Colors.yellow.shade50;
              borderColor = Colors.yellow.shade300;
              textColor = Colors.yellow.shade700;
            } else if (isOccupiedByBooking) {
              bgColor = Colors.red.shade50;
              borderColor = Colors.red.shade200;
              textColor = Colors.red.shade400;
            } else if (isBlockedBySelection) {
              bgColor = Colors.amber.shade50;
              borderColor = Colors.amber.shade200;
              textColor = Colors.amber.shade600;
            } else {
              bgColor = AppColors.background;
              borderColor = AppColors.border;
              textColor = AppColors.text;
            }

            return GestureDetector(
              onTap: isDisabled ? null : () {
                setState(() {
                  _serviceTimeSelections = Map.from(_serviceTimeSelections);
                  _serviceTimeSelections[serviceId] = time;
                });
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        decoration: isOccupiedByBooking && occupiedResult['reason'] == 'booked' 
                            ? TextDecoration.lineThrough 
                            : null,
                      ),
                    ),
                  ),
                  // Warning badge for time constraint issues
                  if (isClosesBeforeFinish || isInsufficientTime)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Center(
                          child: Text(
                            '!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
        // Legend for unavailable slot reasons
        if (hasClosingTimeIssue || slotsWithStatus.any((s) {
          final time = s['time'] as TimeOfDay;
          final result = isSlotOccupied(time);
          return result['reason'] == 'insufficient_time';
        }))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Closes before service ends',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.yellow.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Overlaps with next booking',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStaffChips(String serviceId, List<Map<String, dynamic>> availableStaff, String selectedStaffId) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // "Any Available" option
        GestureDetector(
          onTap: () {
            setState(() {
              _serviceStaffSelections = Map.from(_serviceStaffSelections);
              _serviceStaffSelections[serviceId] = 'any';
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selectedStaffId == 'any' ? AppColors.primary : AppColors.background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selectedStaffId == 'any' ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FontAwesomeIcons.shuffle,
                  size: 12,
                  color: selectedStaffId == 'any' ? Colors.white : AppColors.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  'Any',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selectedStaffId == 'any' ? Colors.white : AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Individual staff members
        ...availableStaff.map((staff) {
          final staffId = staff['id'] as String;
          final staffName = staff['name'] ?? 'Staff';
          final isSelected = selectedStaffId == staffId;
          
          // Debug: Log staff data to see what avatar field contains
          debugPrint('[StaffChips] Staff: $staffName (ID: $staffId), avatar: ${staff['avatar']}, photoURL: ${staff['photoURL']}, avatarUrl: ${staff['avatarUrl']}');

          return GestureDetector(
            onTap: () {
              setState(() {
                _serviceStaffSelections = Map.from(_serviceStaffSelections);
                _serviceStaffSelections[serviceId] = staffId;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.background,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStaffAvatar(
                    staff['avatar'] ?? staff['photoURL'] ?? staff['avatarUrl'],
                    isSelected,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    staffName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        if (availableStaff.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Text(
              'No specific staff available',
              style: TextStyle(fontSize: 12, color: AppColors.muted, fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  Widget _buildStaffAvatar(dynamic avatarData, bool isSelected) {
    // Get avatar URL - handle various data types
    String? avatarUrl;
    
    if (avatarData != null) {
      String avatarStr;
      if (avatarData is String) {
        avatarStr = avatarData.trim();
      } else {
        avatarStr = avatarData.toString().trim();
      }
      
      // Check if it's a valid URL
      if (avatarStr.isNotEmpty && 
          avatarStr != 'null' &&
          (avatarStr.startsWith('http://') || avatarStr.startsWith('https://'))) {
        avatarUrl = avatarStr;
        debugPrint('[StaffAvatar] ✓ Found valid avatar URL: $avatarUrl');
      } else if (avatarStr.isNotEmpty && avatarStr != 'null') {
        debugPrint('[StaffAvatar] ✗ Avatar data is not a valid URL: "$avatarStr"');
      }
    }

    // Use a StatefulBuilder to track image loading state
    return _StaffAvatarWidget(
      avatarUrl: avatarUrl,
      isSelected: isSelected,
    );
  }

  Widget _buildBottomBar() {
    String primaryLabel;
    VoidCallback? onPrimary;

    final canStep0Next =
        _selectedBranchLabel != null && _selectedServiceIds.isNotEmpty;
    // All services must have a time selected
    final allServicesHaveTime = _selectedServiceIds.every((id) => _serviceTimeSelections.containsKey(id));
    final canStep1Next =
        _selectedDate != null && allServicesHaveTime;

    if (_currentStep == 0) {
      primaryLabel = 'Next';
      if (canStep0Next && !_isProcessing) {
        onPrimary = () => setState(() => _currentStep = 1);
      }
    } else if (_currentStep == 1) {
      primaryLabel = 'Next';
      if (canStep1Next && !_isProcessing) {
        onPrimary = () => setState(() => _currentStep = 2);
      }
    } else {
      primaryLabel = 'Confirm Booking';
      // Require name, email, and phone
      final hasRequiredFields = _nameController.text.trim().isNotEmpty && 
                                _emailController.text.trim().isNotEmpty &&
                                _phoneController.text.trim().isNotEmpty;
      if (!_isProcessing && hasRequiredFields) {
        onPrimary = _confirmBooking;
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
              Text('\$${_totalPrice.toInt()}',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text)),
            ],
          ),
          SizedBox(
            width: 200,
            height: 56,
            child: ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    onPrimary == null ? Colors.grey.shade300 : Colors.transparent,
                shadowColor: Colors.transparent,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: onPrimary == null
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent]),
                  color: onPrimary == null
                      ? Colors.grey.shade300
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: onPrimary == null
                      ? []
                      : [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Center(
                  child: _isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_currentStep == 2)
                              const Icon(FontAwesomeIcons.check,
                                  color: Colors.white, size: 18),
                            if (_currentStep == 2) const SizedBox(width: 8),
                            Text(
                              primaryLabel,
                              style: TextStyle(
                                color: onPrimary == null
                                    ? Colors.grey.shade600
                                    : Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Step content helpers ---

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        // For staff, show date first because their branch depends on the day
        if (_userRole == 'staff') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Step 1: Select Date First (for staff)
              const Text(
                "Select Date",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text),
              ),
              const SizedBox(height: 8),
              Text(
                "Your working branch depends on the day",
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              _buildDatePicker(),
              const SizedBox(height: 24),
              
              // Step 2: Show Branch (based on selected date)
              if (_selectedDate != null) ...[
                _buildStaffBranchForDate(),
                const SizedBox(height: 24),
              ],
              
              // Step 3: Select Services (only after branch is determined)
              if (_selectedDate != null && _selectedBranchId != null) ...[
                Row(
                  children: [
                    const Text(
                      "Select Services",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text),
                    ),
                    if (_selectedServiceIds.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_selectedServiceIds.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _buildServiceGrid(),
              ],
              const SizedBox(height: 100),
            ],
          );
        }
        
        // Default flow for owner and branch admin
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              "Select Branch",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text),
            ),
            const SizedBox(height: 12),
            _buildBranchSelector(),
            const SizedBox(height: 24),
            Row(
              children: [
            const Text(
              "Select Services",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text),
                ),
                if (_selectedServiceIds.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedServiceIds.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _buildServiceGrid(),
            const SizedBox(height: 100),
          ],
        );
      case 1:
        // For staff, date was already selected in Step 0
        if (_userRole == 'staff') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Show selected date summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(FontAwesomeIcons.calendarCheck, size: 20, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Selected Date',
                            style: TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                          Text(
                            _selectedDate != null 
                                ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                                : 'No date selected',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                            ),
                          ),
                          Text(
                            'at $_selectedBranchLabel',
                            style: TextStyle(fontSize: 12, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Select Time for Each Service",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text),
              ),
              const SizedBox(height: 16),
              _buildPerServiceTimeStaffSelector(),
              const SizedBox(height: 100),
            ],
          );
        }
        
        // Default flow for owner and branch admin
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              "Select Date",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text),
            ),
            const SizedBox(height: 16),
            _buildDatePicker(),
            const SizedBox(height: 24),
            Text(
              "Select Time & Staff for Each Service",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _selectedDate == null ? AppColors.muted : AppColors.text),
            ),
            const SizedBox(height: 16),
            _buildPerServiceTimeStaffSelector(),
            const SizedBox(height: 100),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              "Customer Details",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text),
            ),
            const SizedBox(height: 16),
            _buildCustomerForm(),
            const SizedBox(height: 24),
            _buildSummaryCard(),
            const SizedBox(height: 100),
          ],
        );
    }
  }

  /// For staff: Determine and display the branch they work at on the selected date
  Widget _buildStaffBranchForDate() {
    if (_selectedDate == null) {
      return const SizedBox.shrink();
    }
    
    // Get day name from selected date
    final dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final selectedDayName = dayNames[_selectedDate!.weekday % 7];
    // Note: DateTime.weekday returns 1=Monday...7=Sunday, but our schedule uses Sunday=0
    final adjustedDayName = dayNames[_selectedDate!.weekday == 7 ? 0 : _selectedDate!.weekday];
    
    debugPrint('[StaffBranch] Selected date: $_selectedDate, day: $adjustedDayName');
    debugPrint('[StaffBranch] Weekly schedule: $_currentUserWeeklySchedule');
    
    // Find the branch for this day from weekly schedule
    String? branchIdForDay;
    String? branchNameForDay;
    
    if (_currentUserWeeklySchedule != null && _currentUserWeeklySchedule!.containsKey(adjustedDayName)) {
      final daySchedule = _currentUserWeeklySchedule![adjustedDayName];
      if (daySchedule is Map) {
        branchIdForDay = daySchedule['branchId']?.toString();
        branchNameForDay = daySchedule['branchName']?.toString();
      }
    }
    
    // Fallback to home branch if no schedule for this day
    if (branchIdForDay == null && _userBranchId != null) {
      branchIdForDay = _userBranchId;
      // Find branch name from branches list
      final homeBranch = _branches.firstWhere(
        (b) => b['id'] == _userBranchId,
        orElse: () => {},
      );
      branchNameForDay = homeBranch.isNotEmpty ? homeBranch['name']?.toString() : 'Your Branch';
    }
    
    debugPrint('[StaffBranch] Branch for day: $branchIdForDay, $branchNameForDay');
    
    // If no branch found for this day, staff is not working
    if (branchIdForDay == null) {
      // Clear any previously selected branch
      if (_selectedBranchId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _selectedBranchId = null;
              _selectedBranchLabel = null;
              _selectedBranchTimezone = null;
              _selectedServiceIds = {};
            });
          }
        });
      }
      
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(FontAwesomeIcons.calendarXmark, size: 24, color: Colors.orange.shade700),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Day Off',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'You are not scheduled to work on $adjustedDayName.\nPlease select another date.',
                    style: TextStyle(fontSize: 13, color: Colors.orange.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    // Auto-select the branch for this day
    if (_selectedBranchId != branchIdForDay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Find branch timezone
          final branchData = _branches.firstWhere(
            (b) => b['id'] == branchIdForDay,
            orElse: () => {},
          );
          final branchTimezoneForDay = branchData.isNotEmpty
              ? (branchData['timezone'] ?? 'Australia/Sydney').toString()
              : 'Australia/Sydney';
          
          setState(() {
            _selectedBranchId = branchIdForDay;
            _selectedBranchLabel = branchNameForDay;
            _selectedBranchTimezone = branchTimezoneForDay;
            // Clear services when branch changes
            _selectedServiceIds = {};
          });
        }
      });
    }
    
    // Show the working branch
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(FontAwesomeIcons.building, size: 20, color: AppColors.green),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Working Branch',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  branchNameForDay ?? 'Unknown Branch',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  'On $adjustedDayName',
                  style: TextStyle(fontSize: 12, color: AppColors.green),
                ),
              ],
            ),
          ),
          Icon(FontAwesomeIcons.circleCheck, size: 20, color: AppColors.green),
        ],
      ),
    );
  }

  Widget _buildBranchSelector() {
    if (_branches.isEmpty) {
      return const Text(
        'No branches found. Please create a branch in the admin panel.',
        style: TextStyle(fontSize: 13, color: AppColors.muted),
      );
    }
    return Column(
      children: _branches.map((branch) {
        final name = (branch['name'] ?? 'Branch').toString();
        final address = (branch['address'] ?? '').toString();
        final isSelected = _selectedBranchId == branch['id'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () {
              debugPrint('[BranchSelect] Selected branch id=${branch['id']}, name=$name, timezone=${branch['timezone']}');
              setState(() {
                _selectedBranchId = branch['id'] as String;
                _selectedBranchLabel = name;
                _selectedBranchTimezone = (branch['timezone'] ?? 'Australia/Sydney').toString();
                // Clear service selection when branch changes
                _selectedServiceIds = {};
              });
              // Update branch time immediately when branch changes
              _updateBranchTime();
            },
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color:
                        isSelected ? AppColors.primary : AppColors.border),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  Icon(
                    FontAwesomeIcons.locationDot,
                    size: 14,
                    color:
                        isSelected ? Colors.white : AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : AppColors.text,
                          ),
                        ),
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? Colors.white70
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      FontAwesomeIcons.check,
                      size: 14,
                      color: Colors.white,
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummaryCard() {
    final branch = _selectedBranchLabel ?? 'Not selected';
    
    // Get selected services
    final selectedServices = _selectedServiceIds
        .map((id) => _services.firstWhere((s) => s['id'] == id, orElse: () => {}))
        .where((s) => s.isNotEmpty)
        .toList();
    
    final dateText = _selectedDate != null
        ? '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}'
        : 'Not selected';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Summary',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text),
          ),
          const SizedBox(height: 12),
          _summaryRow('Branch', branch),
          _summaryRow('Date', dateText),
          const Divider(height: 20),
          
          // Services section with per-service time/staff
          Text(
            'Services (${selectedServices.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
          ),
          const SizedBox(height: 8),
          ...selectedServices.map((service) {
            final svcId = service['id'] as String;
            final svcTime = _serviceTimeSelections[svcId];
            final svcStaffId = _serviceStaffSelections[svcId];
            
            String staffName = 'Any Available';
            if (svcStaffId != null && svcStaffId != 'any') {
              final match = _staff.firstWhere((s) => s['id'] == svcStaffId, orElse: () => {});
              if (match.isNotEmpty) {
                staffName = match['name'] ?? 'Staff';
              }
            }
            
            final timeStr = svcTime != null
                ? '${svcTime.hour.toString().padLeft(2, '0')}:${svcTime.minute.toString().padLeft(2, '0')}'
                : 'Not set';
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          service['name'] ?? 'Service',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
                        ),
                      ),
                      Text(
                        '\$${service['price']}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(FontAwesomeIcons.clock, size: 10, color: AppColors.muted),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                      const SizedBox(width: 12),
                      const Icon(FontAwesomeIcons.user, size: 10, color: AppColors.muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          staffName,
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          
          const Divider(height: 20),
          _summaryRow('Total Duration', '${_totalDuration}min'),
          _summaryRow('Total Price', '\$$_totalPrice'),
          const Divider(height: 20),
          _summaryRow(
            'Customer',
            _nameController.text.isNotEmpty ? _nameController.text : 'Not entered',
          ),
          _summaryRow('Email', _emailController.text.isNotEmpty ? _emailController.text : 'Not entered'),
          _summaryRow('Phone', _phoneController.text.isNotEmpty ? _phoneController.text : 'Not entered'),
          if (_notesController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Notes:', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _notesController.text,
                style: const TextStyle(fontSize: 12, color: AppColors.text),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 13, color: AppColors.muted),
          ),
          Text(
            value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String? label, String? hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
    );
  }
}

// Separate widget to handle image loading state
class _StaffAvatarWidget extends StatefulWidget {
  final String? avatarUrl;
  final bool isSelected;

  const _StaffAvatarWidget({
    required this.avatarUrl,
    required this.isSelected,
  });

  @override
  State<_StaffAvatarWidget> createState() => _StaffAvatarWidgetState();
}

class _StaffAvatarWidgetState extends State<_StaffAvatarWidget> {
  bool _imageError = false;
  bool _imageLoaded = false;

  @override
  Widget build(BuildContext context) {
    // If no URL or error occurred, show icon
    if (widget.avatarUrl == null || _imageError) {
      return ClipOval(
        child: Container(
          width: 20,
          height: 20,
          color: AppColors.muted.withOpacity(0.3),
          child: Icon(
            Icons.person,
            size: 12,
            color: widget.isSelected ? Colors.white : AppColors.muted,
          ),
        ),
      );
    }

    // Show image
    return ClipOval(
      child: Container(
        width: 20,
        height: 20,
        color: AppColors.muted.withOpacity(0.3),
        child: Image.network(
          widget.avatarUrl!,
          width: 20,
          height: 20,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('[StaffAvatar] Image error for ${widget.avatarUrl}: $error');
            if (!_imageError) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _imageError = true;
                  });
                }
              });
            }
            return Icon(
              Icons.person,
              size: 12,
              color: widget.isSelected ? Colors.white : AppColors.muted,
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              if (!_imageLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _imageLoaded = true;
                    });
                  }
                });
              }
              return child;
            }
            return Center(
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


