import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_bottom_nav.dart';
import 'calender_screen.dart';
import 'report_screen.dart';
import 'profile_screen.dart';
import 'notifications_page.dart';
import 'all_appointments_page.dart';
import 'appointment_details_page.dart';
import 'clients_screen.dart';
import 'walk_in_booking_page.dart';
import 'appointment_requests_page.dart';
import 'admin_dashboard.dart';
import 'branch_admin_dashboard.dart';
import 'owner_bookings_page.dart';
import 'more_page.dart';
import '../services/staff_check_in_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/background_location_service.dart';
import '../services/permission_service.dart';
import 'package:geolocator/geolocator.dart';

// --- 1. Theme & Colors (Matching Tailwind Config) ---
class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}

// Default bottom navigation icons (staff / branch admin)
const List<IconData> kDefaultNavIcons = <IconData>[
  Icons.home_rounded,
  Icons.calendar_month_rounded,
  Icons.groups_rounded,
  Icons.bar_chart_rounded,
  Icons.person_rounded,
];

// Salon owner navigation: Home, Calendar, Bookings, Clients, More
const List<IconData> kOwnerNavIcons = <IconData>[
  Icons.home_rounded,
  Icons.calendar_month_rounded,
  Icons.calendar_today_rounded, // Bookings (3rd)
  Icons.groups_rounded,
  Icons.more_horiz_rounded, // More (5th)
];

class HomeScreen extends StatefulWidget {
  /// Optional initial tab index to navigate to on load
  /// For owners: 0=Home, 1=Calendar, 2=Bookings, 3=Clients, 4=More
  /// For staff: 0=Home, 1=Calendar, 2=Clients, 3=Reports, 4=Profile
  final int? initialTabIndex;
  
  const HomeScreen({super.key, this.initialTabIndex});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum ClockStatus { out, clockedIn, onBreak }

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  ClockStatus _status = ClockStatus.out;
  String? _selectedBranch;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late int _navIndex;
  // Work timer (shows elapsed time after clocking in)
  Timer? _workTimer;
  int _workedSeconds = 0;
  bool _timerRunning = false;
  DateTime? _checkInTime; // Store the actual check-in time to prevent recalculation issues
  String? _activeCheckInId; // Store check-in ID for break tracking
  
  // Background location service for auto check-out
  final BackgroundLocationService _backgroundLocationService = BackgroundLocationService();

  // Role state
  String? _userRole;
  String? _branchName; // Store branch name if available
  String? _userName; // Store user's name
  String? _branchId;
  String? _ownerUid;
  String? _photoUrl; // Store user's profile photo URL
  bool _isLoadingRole = true;
  
  // Today's appointments
  List<Map<String, dynamic>> _todayAppointments = [];
  bool _isLoadingAppointments = true;
  
  // Unread notifications count (aggregated from all sources)
  int _unreadNotificationCount = 0;
  StreamSubscription<QuerySnapshot>? _notificationsSub; // staffUid
  StreamSubscription<QuerySnapshot>? _ownerNotificationsSub; // ownerUid
  StreamSubscription<QuerySnapshot>? _branchAdminNotificationsSub; // branchAdminUid
  StreamSubscription<QuerySnapshot>? _customerNotificationsSub; // customerUid
  StreamSubscription<QuerySnapshot>? _targetAdminNotificationsSub; // targetAdminUid
  final Set<String> _staffUnreadIds = {};
  final Set<String> _ownerUnreadIds = {};
  final Set<String> _branchAdminUnreadIds = {};
  final Set<String> _customerUnreadIds = {};
  final Set<String> _targetAdminUnreadIds = {};
  
  // Pending appointment requests count (for staff)
  int _pendingRequestsCount = 0;
  StreamSubscription<QuerySnapshot>? _pendingRequestsSub;

  @override
  void initState() {
    super.initState();
    
    // Initialize nav index from widget parameter or default to 0
    _navIndex = widget.initialTabIndex ?? 0;
    
    // Register app lifecycle observer for foreground/background detection
    WidgetsBinding.instance.addObserver(this);
    
    // Setup Pulse Animation for the "Clock In" button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fetchUserRole();
    _listenToUnreadNotifications();
    _listenToPendingRequests();
    _refreshCheckInStatus(); // Load current check-in status
    
    // Set up background location service callbacks
    _backgroundLocationService.onAutoCheckOut = _handleAutoCheckOut;
    
    // Resume background location monitoring if needed (with immediate check)
    _backgroundLocationService.resumeMonitoringIfNeeded();
    
    // Set up notification service for on-screen notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().setContext(context);
      NotificationService().listenToNotifications();
    });
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // When app comes to foreground, check location immediately
    if (state == AppLifecycleState.resumed) {
      debugPrint('HomeScreen: App resumed - checking location...');
      _backgroundLocationService.checkLocationNow();
      // Also refresh check-in status in case auto clock-out happened
      _refreshCheckInStatus();
    }
  }

  /// Recalculate the total unread count from all source sets
  void _recalcUnreadCount() {
    final allIds = <String>{
      ..._staffUnreadIds,
      ..._ownerUnreadIds,
      ..._branchAdminUnreadIds,
      ..._customerUnreadIds,
      ..._targetAdminUnreadIds,
    };
    if (mounted) {
      setState(() {
        _unreadNotificationCount = allIds.length;
      });
    }
  }

  /// Listen to unread notifications from ALL sources (staff, owner, branch admin, customer, targetAdmin)
  void _listenToUnreadNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Staff notifications (staffUid)
    _notificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('staffUid', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      _staffUnreadIds
        ..clear()
        ..addAll(snapshot.docs.map((d) => d.id));
      _recalcUnreadCount();
    }, onError: (e) {
      debugPrint('Error listening to staff notifications: $e');
    });

    // 2. Owner notifications (ownerUid)
    _ownerNotificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('ownerUid', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      _ownerUnreadIds
        ..clear()
        ..addAll(snapshot.docs.map((d) => d.id));
      _recalcUnreadCount();
    }, onError: (e) {
      debugPrint('Error listening to owner notifications: $e');
    });

    // 3. Branch admin notifications (branchAdminUid)
    _branchAdminNotificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('branchAdminUid', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      _branchAdminUnreadIds
        ..clear()
        ..addAll(snapshot.docs.map((d) => d.id));
      _recalcUnreadCount();
    }, onError: (e) {
      debugPrint('Error listening to branch admin notifications: $e');
    });

    // 4. Customer notifications (customerUid)
    _customerNotificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('customerUid', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      _customerUnreadIds
        ..clear()
        ..addAll(snapshot.docs.map((d) => d.id));
      _recalcUnreadCount();
    }, onError: (e) {
      debugPrint('Error listening to customer notifications: $e');
    });

    // 5. Target admin notifications (targetAdminUid)
    _targetAdminNotificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('targetAdminUid', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      _targetAdminUnreadIds
        ..clear()
        ..addAll(snapshot.docs.map((d) => d.id));
      _recalcUnreadCount();
    }, onError: (e) {
      debugPrint('Error listening to target admin notifications: $e');
    });
  }

  /// Listen to pending appointment requests assigned to this staff
  void _listenToPendingRequests() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Wait for ownerUid to be available
    await Future.delayed(const Duration(milliseconds: 500));
    if (_ownerUid == null || _ownerUid!.isEmpty) return;

    // Listen for both AwaitingStaffApproval AND PartiallyApproved statuses
    _pendingRequestsSub = FirebaseFirestore.instance
        .collection('bookings')
        .where('ownerUid', isEqualTo: _ownerUid)
        .where('status', whereIn: ['AwaitingStaffApproval', 'PartiallyApproved'])
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      
      int count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        
        // Check if assigned to current user (check both staffId and staffAuthUid)
        bool hasPendingService = false;
        
        // Single service booking
        final bookingStaffId = data['staffId']?.toString();
        final bookingStaffAuthUid = data['staffAuthUid']?.toString();
        if (bookingStaffId == user.uid || bookingStaffAuthUid == user.uid) {
          hasPendingService = true;
        }
        
        // Multi-service booking - check for pending services assigned to this staff
        if (data['services'] is List) {
          for (final service in (data['services'] as List)) {
            if (service is Map) {
              final serviceStaffId = service['staffId']?.toString();
              final serviceStaffAuthUid = service['staffAuthUid']?.toString();
              final approvalStatus = service['approvalStatus']?.toString() ?? 'pending';
              
              // Only count if assigned to this staff AND status is pending
              final isMyService = serviceStaffId == user.uid || serviceStaffAuthUid == user.uid;
              if (isMyService && approvalStatus == 'pending') {
                hasPendingService = true;
                break;
              }
            }
          }
        }
        
        if (hasPendingService) count++;
      }
      
      setState(() {
        _pendingRequestsCount = count;
      });
    }, onError: (e) {
      debugPrint('Error listening to pending requests: $e');
    });
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Use real-time listener so profile updates are reflected immediately
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen((doc) {
          if (!mounted) return;
          
          if (doc.exists) {
            final data = doc.data();
            
            // Get name from various possible fields
            String? fetchedName;
            if (data?['displayName'] != null && data!['displayName'].toString().isNotEmpty) {
              fetchedName = data['displayName'].toString();
            } else if (data?['firstName'] != null && data!['firstName'].toString().isNotEmpty) {
              final firstName = data['firstName'].toString();
              final lastName = data['lastName']?.toString() ?? '';
              fetchedName = '$firstName $lastName'.trim();
            } else if (data?['name'] != null && data!['name'].toString().isNotEmpty) {
              fetchedName = data['name'].toString();
            } else if (data?['fullName'] != null && data!['fullName'].toString().isNotEmpty) {
              fetchedName = data['fullName'].toString();
            } else if (user.displayName != null && user.displayName!.isNotEmpty) {
              fetchedName = user.displayName;
            } else if (user.email != null) {
              // Use email prefix as fallback
              fetchedName = user.email!.split('@').first;
            }
            
            // Get photo URL from various possible fields
            String? photoUrl;
            if (data?['photoURL'] != null && data!['photoURL'].toString().isNotEmpty) {
              photoUrl = data['photoURL'].toString();
            } else if (data?['avatarUrl'] != null && data!['avatarUrl'].toString().isNotEmpty) {
              photoUrl = data['avatarUrl'].toString();
            } else if (data?['avatar'] != null && data!['avatar'].toString().startsWith('http')) {
              photoUrl = data['avatar'].toString();
            } else if (user.photoURL != null && user.photoURL!.isNotEmpty) {
              photoUrl = user.photoURL;
            }

            final previousRole = _userRole;
            
            setState(() {
              // Trim and normalize the role to ensure proper comparison
              final rawRole = data?['role'];
              String? normalizedRole = rawRole != null ? rawRole.toString().trim() : null;
              // role is already normalized (staff, branch_admin, workshop_owner)
              _userRole = normalizedRole;
              // Try to find a branch name or branch field
              _branchName = data?['branchName'] ?? data?['branch'];
              _userName = fetchedName ?? 'Staff';
              _branchId = data?['branchId'];
              _ownerUid = data?['ownerUid'] ?? user.uid;
              _photoUrl = photoUrl;
              _isLoadingRole = false;
            });
            
            // Fetch today's appointments for staff (only once on initial load)
            if (previousRole == null && _userRole != 'workshop_owner' && _userRole != 'branch_admin') {
              _fetchTodayAppointments();
            }
          } else {
            // User document doesn't exist, try to get name from Firebase Auth
            setState(() {
              _userName = user.displayName ?? user.email?.split('@').first ?? 'Staff';
              _photoUrl = user.photoURL;
              _ownerUid = user.uid;
              _isLoadingRole = false;
            });
          }
        }, onError: (e) {
          debugPrint('Error listening to user document: $e');
          if (mounted) setState(() => _isLoadingRole = false);
        });
      } else {
        if (mounted) setState(() => _isLoadingRole = false);
      }
    } catch (e) {
      debugPrint('Error fetching role: $e');
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  Future<void> _fetchTodayAppointments() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoadingAppointments = false);
        return;
      }

      // Get today's date in YYYY-MM-DD format
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      debugPrint('Fetching appointments for date: $todayStr, ownerUid: $_ownerUid, staffId: ${user.uid}');

      // Build query - if ownerUid is available, use it; otherwise query by staffId
      Query<Map<String, dynamic>> bookingsQuery;
      
      if (_ownerUid != null && _ownerUid!.isNotEmpty) {
        // Query by ownerUid and date
        bookingsQuery = FirebaseFirestore.instance
            .collection('bookings')
            .where('ownerUid', isEqualTo: _ownerUid)
            .where('date', isEqualTo: todayStr);
      } else {
        // Fallback: Query by staffId directly
        bookingsQuery = FirebaseFirestore.instance
            .collection('bookings')
            .where('staffId', isEqualTo: user.uid)
            .where('date', isEqualTo: todayStr);
      }

      // Listen to bookings
      bookingsQuery.snapshots().listen((snap) {
        final List<Map<String, dynamic>> appointments = [];
        
        debugPrint('Found ${snap.docs.length} bookings for today');
        
        for (final doc in snap.docs) {
          final data = doc.data();
          
          // Check if this booking is assigned to the current staff
          bool isAssigned = false;
          String? serviceName;
          String? duration;
          
          // Check staffId and staffAuthUid at booking level
          final bookingStaffId = data['staffId']?.toString();
          final bookingStaffAuthUid = data['staffAuthUid']?.toString();
          if (bookingStaffId == user.uid || bookingStaffAuthUid == user.uid) {
            isAssigned = true;
            debugPrint('Booking ${doc.id} assigned via staffId');
          }
          
          // Check services array for staff assignment (check both staffId and staffAuthUid)
          if (data['services'] is List) {
            for (final service in (data['services'] as List)) {
              if (service is Map) {
                final serviceStaffId = service['staffId']?.toString();
                final serviceStaffAuthUid = service['staffAuthUid']?.toString();
                if (serviceStaffId == user.uid || serviceStaffAuthUid == user.uid) {
                  isAssigned = true;
                  serviceName ??= service['name']?.toString() ?? service['serviceName']?.toString();
                  duration ??= service['duration']?.toString();
                  debugPrint('Booking ${doc.id} assigned via service staffId');
                }
              }
            }
          }
          
          // If we queried by staffId directly, it's assigned
          if (_ownerUid == null || _ownerUid!.isEmpty) {
            isAssigned = true;
          }
          
          if (!isAssigned) continue;
          
          // Get service name from various possible fields
          if (serviceName == null || serviceName.isEmpty) {
            if (data['services'] is List && (data['services'] as List).isNotEmpty) {
              final firstService = (data['services'] as List).first;
              if (firstService is Map) {
                serviceName = firstService['name']?.toString() ?? firstService['serviceName']?.toString();
                duration = firstService['duration']?.toString();
              }
            }
          }
          serviceName ??= data['serviceName']?.toString() ?? data['service']?.toString() ?? 'Service';
          duration ??= data['duration']?.toString() ?? '';
          
          final time = data['time']?.toString() ?? data['startTime']?.toString() ?? '';
          final status = data['status']?.toString() ?? 'pending';
          
          appointments.add({
            'id': doc.id,
            'serviceName': serviceName,
            'duration': duration,
            'time': time,
            'status': status,
            'client': data['client']?.toString() ?? data['clientName']?.toString() ?? 'Client',
            'data': data,
          });
        }
        
        // Sort by time
        appointments.sort((a, b) {
          final timeA = a['time'] ?? '';
          final timeB = b['time'] ?? '';
          return timeA.compareTo(timeB);
        });
        
        debugPrint('Processed ${appointments.length} appointments assigned to this staff');
        
        if (!mounted) return;
        setState(() {
          _todayAppointments = appointments;
          _isLoadingAppointments = false;
        });
      }, onError: (e) {
        debugPrint('Error fetching appointments: $e');
        if (mounted) setState(() => _isLoadingAppointments = false);
      });
    } catch (e) {
      debugPrint('Error fetching appointments: $e');
      if (mounted) setState(() => _isLoadingAppointments = false);
    }
  }

  /// Handle auto clock-out from background location service
  void _handleAutoCheckOut(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(FontAwesomeIcons.locationCrosshairs, color: Colors.white, size: 18),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _refreshCheckInStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _workTimer?.cancel();
    _backgroundLocationService.stopMonitoring();
    _notificationsSub?.cancel();
    _ownerNotificationsSub?.cancel();
    _branchAdminNotificationsSub?.cancel();
    _customerNotificationsSub?.cancel();
    _targetAdminNotificationsSub?.cancel();
    _pendingRequestsSub?.cancel();
    NotificationService().dispose();
    super.dispose();
  }

  void _handleClockAction() async {
    if (_status == ClockStatus.out) {
      // Single-touch clock-in with location check
      await _performClockIn();
    } else if (_status == ClockStatus.clockedIn) {
      // Direct check-out without navigation
      await _performCheckOut();
    }
  }

  Future<void> _performClockIn() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      // Get available branches for check-in
      final branches = await StaffCheckInService.getBranchesForCheckIn();
      
      if (branches.isEmpty) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No branches with location configured. Please contact your administrator.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      String? branchId;
      
      // Try to get today's scheduled branch first
      if (_branchId != null && _branchId!.isNotEmpty) {
        // Check if this branch is in the available branches
        final scheduledBranch = branches.firstWhere(
          (b) => b.id == _branchId,
          orElse: () => branches.first,
        );
        branchId = scheduledBranch.id;
      } else if (branches.length == 1) {
        // Only one branch available, use it
        branchId = branches.first.id;
      } else {
        // Multiple branches - need to show selection (but for single touch, use first or scheduled)
        // Try to get scheduled branch for today
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            final todayWeekday = _getTodayWeekday();
            final schedule = userData['schedule'];
            String? scheduledBranchId;
            
            if (schedule is Map && schedule[todayWeekday] != null) {
              final todaySchedule = schedule[todayWeekday];
              if (todaySchedule is Map) {
                scheduledBranchId = todaySchedule['branchId']?.toString();
              }
            }
            
            // Also check weeklySchedule format
            final weeklySchedule = userData['weeklySchedule'];
            if (weeklySchedule is Map && weeklySchedule[todayWeekday] != null) {
              final todaySchedule = weeklySchedule[todayWeekday];
              if (todaySchedule is Map) {
                scheduledBranchId ??= todaySchedule['branchId']?.toString();
              }
            }
            
            if (scheduledBranchId != null) {
              final scheduledBranch = branches.firstWhere(
                (b) => b.id == scheduledBranchId,
                orElse: () => branches.first,
              );
              branchId = scheduledBranch.id;
            } else {
              // No scheduled branch, use first available
              branchId = branches.first.id;
            }
          } else {
            branchId = branches.first.id;
          }
        } else {
          branchId = branches.first.id;
        }
      }

      if (branchId == null || branchId.isEmpty) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not determine branch. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Check if location services are enabled
      final isLocationEnabled = await LocationService.isLocationServiceEnabled();
      if (!isLocationEnabled) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location services are disabled. Please enable them in your device settings.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Check permission first - show custom dialog if not granted
      final hasPermission = await LocationService.isLocationPermissionGranted();
      if (!hasPermission) {
        Navigator.pop(context); // Close loading dialog first
        
        // Show custom location disclosure dialog, then request permission
        if (!mounted) return;
        final granted = await PermissionService().requestLocationPermissionWithDialog(context);
        if (!granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required. Please grant location permission to check in.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }
        
        // Show loading dialog again after permission granted
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
      }

      // Get current location
      final position = await LocationService.getCurrentLocation();
      if (position == null) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get your location. Please make sure GPS is enabled and try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Perform check-in
      final result = await StaffCheckInService.checkIn(
        branchId: branchId,
        staffLatitude: position.latitude,
        staffLongitude: position.longitude,
      );

      Navigator.pop(context); // Close loading dialog

      if (result.success) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(FontAwesomeIcons.circleCheck, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(result.message)),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Refresh check-in status
        _refreshCheckInStatus();
      } else {
        // Show error message - check if it's a radius issue
        final isRadiusIssue = !(result.isWithinRadius ?? true);
        if (isRadiusIssue) {
          // Show creative popup dialog for radius issues
          _showRadiusErrorDialog(result.message, result.distanceFromBranch ?? 0);
        } else {
          // Show snackbar for other errors
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(FontAwesomeIcons.circleExclamation, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(result.message)),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showRadiusErrorDialog(String message, double distance) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon container
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  FontAwesomeIcons.locationDot,
                  color: Colors.orange,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              // Title
              const Text(
                'Location Too Far',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Distance display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FontAwesomeIcons.ruler,
                      color: AppColors.muted,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      LocationService.formatDistance(distance),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'away',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Message content
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      FontAwesomeIcons.circleInfo,
                      color: Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.text,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Action button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FontAwesomeIcons.check, size: 18),
                      SizedBox(width: 10),
                      Text(
                        'Got It',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _performCheckOut() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      // Get active check-in ID
      String? checkInId = _activeCheckInId;
      if (checkInId == null) {
        final activeCheckIn = await StaffCheckInService.getActiveCheckIn();
        if (activeCheckIn == null || activeCheckIn.id == null) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active check-in found.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        checkInId = activeCheckIn.id;
      }

      // Perform check-out (checkInId is guaranteed to be non-null at this point)
      final result = await StaffCheckInService.checkOut(checkInId!);

      Navigator.pop(context); // Close loading dialog

      if (result.success) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(FontAwesomeIcons.circleCheck, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${result.message}. Hours worked: ${result.hoursWorked}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Refresh check-in status
        _refreshCheckInStatus();
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(FontAwesomeIcons.circleExclamation, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(result.message)),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _getTodayWeekday() {
    const weekDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return weekDays[DateTime.now().weekday - 1];
  }

  Future<void> _refreshCheckInStatus() async {
    final activeCheckIn = await StaffCheckInService.getActiveCheckIn();
    if (mounted) {
      setState(() {
        if (activeCheckIn != null) {
          _status = ClockStatus.clockedIn;
          _selectedBranch = activeCheckIn.branchName;
          _activeCheckInId = activeCheckIn.id;
          
          // Use workingSeconds from the record (which excludes breaks)
          // Only recalculate if check-in time changed or timer not running
          final newCheckInTime = activeCheckIn.checkInTime;
          if (_checkInTime == null || 
              _checkInTime!.millisecondsSinceEpoch != newCheckInTime.millisecondsSinceEpoch ||
              !_timerRunning) {
            _checkInTime = newCheckInTime;
            // Use workingSeconds from the record which already excludes breaks
            _workedSeconds = activeCheckIn.workingSeconds;
            _startWorkTimer();
          }
          
          // Start background location monitoring for auto check-out
          _startBackgroundLocationMonitoring(activeCheckIn);
        } else {
          _status = ClockStatus.out;
          _selectedBranch = null;
          _checkInTime = null;
          _activeCheckInId = null;
          _resetWorkTimer();
          _backgroundLocationService.stopMonitoring();
        }
      });
    }
  }
  
  /// Start background location monitoring for auto check-out
  Future<void> _startBackgroundLocationMonitoring(StaffCheckInRecord activeCheckIn) async {
    // Skip if already monitoring this check-in
    if (_backgroundLocationService.isMonitoring) {
      return;
    }
    
    try {
      // Get branch details for location monitoring
      final branchDoc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(activeCheckIn.branchId)
          .get();
      
      if (!branchDoc.exists) {
        debugPrint('Branch not found for background monitoring');
        return;
      }
      
      final branchData = branchDoc.data()!;
      final location = branchData['location'] as Map<String, dynamic>?;
      
      if (location == null ||
          location['latitude'] == null ||
          location['longitude'] == null) {
        debugPrint('Branch location not found for background monitoring');
        return;
      }
      
      final branchLat = (location['latitude'] as num).toDouble();
      final branchLon = (location['longitude'] as num).toDouble();
      final allowedRadius = (branchData['allowedCheckInRadius'] ?? 100).toDouble();
      
      // Start background monitoring with context for prominent disclosure dialog
      // The context is passed to show the Google Play required disclosure before
      // requesting background location permission
      await _backgroundLocationService.startMonitoring(
        checkInId: activeCheckIn.id!,
        branchId: activeCheckIn.branchId,
        branchLatitude: branchLat,
        branchLongitude: branchLon,
        allowedRadius: allowedRadius,
        context: mounted ? context : null,
      );
      
      debugPrint('Background location monitoring started for check-in ${activeCheckIn.id}');
    } catch (e) {
      debugPrint('Error starting background location monitoring: $e');
    }
  }

  void _handleBreakAction() async {
    print('Break button clicked. Current status: $_status');
    
    // Get check-in ID if not already set
    String? checkInId = _activeCheckInId;
    if (checkInId == null) {
      print('Check-in ID not set, fetching active check-in...');
      final activeCheckIn = await StaffCheckInService.getActiveCheckIn();
      if (activeCheckIn == null || activeCheckIn.id == null) {
        print('No active check-in found');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active check-in found. Please check in first.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      checkInId = activeCheckIn.id;
      print('Found check-in ID: $checkInId');
      if (mounted) {
        setState(() {
          _activeCheckInId = checkInId;
        });
      }
    } else {
      print('Using existing check-in ID: $checkInId');
    }
    
    final next = _status == ClockStatus.clockedIn
        ? ClockStatus.onBreak
        : ClockStatus.clockedIn;
    
    print('Next status will be: $next');
    
    if (next == ClockStatus.onBreak) {
      // Start break - record in Firestore
      print('Starting break...');
      final success = await StaffCheckInService.startBreak(checkInId!);
      print('Start break result: $success');
      if (success && mounted) {
        setState(() {
          _status = ClockStatus.onBreak;
        });
        _pauseWorkTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Break started'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start break. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (next == ClockStatus.clockedIn) {
      // End break - record in Firestore
      print('Ending break...');
      final success = await StaffCheckInService.endBreak(checkInId!);
      print('End break result: $success');
      if (success && mounted) {
        setState(() {
          _status = ClockStatus.clockedIn;
        });
        // Refresh to get updated working seconds (excluding the break)
        _refreshCheckInStatus();
        _startWorkTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Break ended. Back to work!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to end break. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Simulate network/processing delay
  void _startLoading(VoidCallback onComplete) {
    // Here you would add sound effects logic
    Future.delayed(const Duration(seconds: 1), onComplete);
  }

  // --- Work Timer Helpers ---
  void _startWorkTimer() {
    if (_timerRunning) return;
    _timerRunning = true;
    _workTimer?.cancel();
    _workTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      if (_status == ClockStatus.clockedIn) {
        // Only increment if not on break
        setState(() {
          _workedSeconds += 1;
        });
      }
    });
  }

  void _pauseWorkTimer() {
    _workTimer?.cancel();
    _timerRunning = false;
  }

  void _resetWorkTimer() {
    _pauseWorkTimer();
    setState(() {
      _workedSeconds = 0;
      _checkInTime = null;
    });
  }

  String _formatElapsed(int totalSeconds) {
    final hrs = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final mins = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hrs:$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final bool isOwnerOrBranchAdmin = _userRole == 'workshop_owner' || _userRole == 'branch_admin';
    final List<IconData> icons = isOwnerOrBranchAdmin ? kOwnerNavIcons : kDefaultNavIcons;

    return Scaffold(
      body: _navIndex == 0
          ? _buildHomeTab()
          : _buildTabBody(),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _navIndex,
        onChanged: (index) => setState(() => _navIndex = index),
        icons: icons,
      ),
    );
  }

  Widget _buildHomeTab() {
    // Check if user is admin or owner
    if (_userRole == 'workshop_owner') {
      return AdminDashboard(
        role: _userRole!,
        branchName: _branchName,
      );
    } else if (_userRole == 'branch_admin') {
      return BranchAdminDashboard(
        branchName: _branchName ?? 'Branch',
      );
    }
    // Default to Staff Dashboard
    return _buildStaffDashboard();
  }

  Widget _buildStaffDashboard() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            // Show pending requests alert if there are any
            if (_pendingRequestsCount > 0) ...[
              _buildPendingRequestsAlert(),
              const SizedBox(height: 24),
            ],
            _buildStatusCard(),
            const SizedBox(height: 24),
            _buildAppointmentsSection(),
            const SizedBox(height: 24),
            _buildCreateBookingSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingRequestsAlert() {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AppointmentRequestsPage()),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.orange.shade400,
              Colors.orange.shade600,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      FontAwesomeIcons.userClock,
                      color: Colors.white,
                      size: 24,
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.orange.shade600, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '$_pendingRequestsCount',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pending Requests',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_pendingRequestsCount appointment${_pendingRequestsCount == 1 ? '' : 's'} awaiting your approval',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(
                  FontAwesomeIcons.chevronRight,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBody() {
    final bool isOwnerOrBranchAdmin = _userRole == 'workshop_owner' || _userRole == 'branch_admin';

    if (isOwnerOrBranchAdmin) {
      // For salon owners and branch admins: 3rd tab is Bookings, 5th is More
      switch (_navIndex) {
        case 1:
          return const CalenderScreen();
        case 2:
          return const OwnerBookingsPage(); // Booking page (3rd)
        case 3:
          return const ClientsScreen();
        case 4:
          return const MorePage(); // More page (5th)
        default:
          return const SizedBox.shrink();
      }
    } else {
      // Default mapping for staff (includes Profile tab)
      switch (_navIndex) {
        case 1:
          return const CalenderScreen();
        case 2:
          return const ClientsScreen();
        case 3:
          return const ReportScreen();
        case 4:
          return const ProfileScreen();
        default:
          return const SizedBox.shrink();
      }
    }
  }

  // --- UI Components ---
  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String _formatDate(DateTime date) {
    const weekDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return '${weekDays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  }

  Widget _buildHeader() {
    final displayName = _userName ?? 'Staff';
    final formattedName = displayName.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
    final firstName = formattedName.split(' ').first;
    final initials = _getInitials(displayName);
    final today = DateTime.now();
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;

    // Greeting based on time of day
    final hour = today.hour;
    String greeting;
    IconData greetingIcon;
    if (hour < 12) {
      greeting = 'Good Morning';
      greetingIcon = Icons.wb_sunny_outlined;
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
      greetingIcon = Icons.wb_sunny_rounded;
    } else {
      greeting = 'Good Evening';
      greetingIcon = Icons.nightlight_round;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D), Color(0xFF333333)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar with ring
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
              gradient: hasPhoto
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.15),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
              image: hasPhoto
                  ? DecorationImage(
                      image: NetworkImage(_photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasPhoto
                ? null
                : Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(greetingIcon, color: Colors.white.withOpacity(0.6), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      greeting,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  firstName,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _formatDate(today),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.45),
                  ),
                ),
              ],
            ),
          ),
          // Notification bell
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsPage()),
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    FontAwesomeIcons.bell,
                    color: Colors.white.withOpacity(0.7),
                    size: 20,
                  ),
                  if (_unreadNotificationCount > 0)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF2D2D2D),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    IconData icon;
    Color iconColor;
    Color iconBg;
    String title;
    String subtitle;
    Widget mainButton;
    Widget? secondaryButton;

    switch (_status) {
      case ClockStatus.out:
        icon = FontAwesomeIcons.clock;
        iconColor = Colors.red;
        iconBg = Colors.red.shade100;
        title = 'You are: CLOCKED OUT';
        subtitle = 'Ready to start your day?';

        mainButton = ScaleTransition(
          scale: _pulseAnimation,
          child: _GradientButton(
            text: 'Clock In',
            icon: FontAwesomeIcons.play,
            onPressed: _handleClockAction,
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
            ),
          ),
        );
        break;

      case ClockStatus.clockedIn:
        icon = FontAwesomeIcons.check;
        iconColor = Colors.green;
        iconBg = Colors.green.shade100;
        title = 'Clocked In: $_selectedBranch';
        subtitle = "You're on duty!";

        mainButton = _GradientButton(
          text: 'Clock Out',
          icon: FontAwesomeIcons.stop,
          onPressed: _handleClockAction,
          gradient: LinearGradient(
              colors: [Colors.red.shade500, Colors.red.shade700]),
        );

        secondaryButton = _GradientButton(
          text: 'Take Break',
          icon: FontAwesomeIcons.mugHot,
          onPressed: _handleBreakAction,
          gradient: LinearGradient(
              colors: [Colors.orange.shade400, Colors.orange.shade600]),
          marginTop: 12,
        );
        break;

      case ClockStatus.onBreak:
        icon = FontAwesomeIcons.mugHot;
        iconColor = Colors.orange;
        iconBg = Colors.orange.shade100;
        title = 'On Break';
        subtitle = 'Enjoy your rest!';

        mainButton = _GradientButton(
          text: 'Start Again',
          icon: FontAwesomeIcons.play,
          onPressed: _handleBreakAction,
          gradient: LinearGradient(
              colors: [Colors.green.shade500, Colors.green.shade700]),
        );
        break;
    }

    final bool isClockedIn = _status != ClockStatus.out;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: isClockedIn
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D)],
              )
            : null,
        color: isClockedIn ? null : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isClockedIn ? 0.2 : 0.1),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isClockedIn
                  ? iconColor.withOpacity(0.2)
                  : iconBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(child: Icon(icon, color: iconColor, size: 28)),
          ),
          const SizedBox(height: 0),
          Text(
            title,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isClockedIn ? Colors.white : AppColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
                fontSize: 14,
                color: isClockedIn
                    ? Colors.white.withOpacity(0.6)
                    : AppColors.muted),
          ),
          if (_status != ClockStatus.out) ...[
            const SizedBox(height: 8),
            _buildTimerChip(paused: _status == ClockStatus.onBreak),
          ],
          const SizedBox(height: 16),
          mainButton,
          if (secondaryButton != null) secondaryButton,
        ],
      ),
    );
  }

  Widget _buildTimerChip({required bool paused}) {
    final Gradient gradient = paused
        ? LinearGradient(
            colors: [Colors.orange.shade400, Colors.orange.shade600])
        : const LinearGradient(colors: [AppColors.primary, AppColors.accent]);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(
                paused ? FontAwesomeIcons.pause : FontAwesomeIcons.clock,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatElapsed(_workedSeconds),
            style: GoogleFonts.robotoMono(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          if (paused) ...[
            const SizedBox(width: 8),
            const Text(
              'Paused',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildAppointmentsSection() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // Get pending/confirmed appointments, excluding those where user's services are all completed
    final upcomingAppointments = _todayAppointments.where((a) {
      final status = (a['status'] ?? '').toString().toLowerCase();
      
      // Only include pending or confirmed bookings
      if (status != 'pending' && status != 'confirmed') {
        return false;
      }
      
      // For confirmed bookings, check if user's assigned services are all completed
      if (status == 'confirmed' && currentUserId != null) {
        // Services are stored inside the 'data' field
        final bookingData = a['data'] as Map<String, dynamic>?;
        final services = bookingData?['services'];
        
        if (services is List && services.isNotEmpty) {
          // Find services assigned to this user
          final myServices = services.where((s) {
            if (s is! Map) return false;
            return s['staffId'] == currentUserId || s['staffAuthUid'] == currentUserId;
          }).toList();
          
          // If user has assigned services, check if they're all completed
          if (myServices.isNotEmpty) {
            final allMyServicesCompleted = myServices.every((s) {
              return (s['completionStatus'] ?? '').toString().toLowerCase() == 'completed';
            });
            // If all my services are completed, exclude this booking from the list
            if (allMyServicesCompleted) {
              return false;
            }
          }
        } else {
          // Single-service booking - check if it's assigned to this user and completed
          final bookingStaffId = bookingData?['staffId'];
          final bookingStaffAuthUid = bookingData?['staffAuthUid'];
          final isMyBooking = bookingStaffId == currentUserId || bookingStaffAuthUid == currentUserId;
          if (isMyBooking) {
            final completionStatus = (bookingData?['completionStatus'] ?? '').toString().toLowerCase();
            if (completionStatus == 'completed') {
              return false;
            }
          }
        }
      }
      
      return true;
    }).toList();
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Today's Appointments",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isLoadingAppointments
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text('${upcomingAppointments.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingAppointments)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          else if (upcomingAppointments.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(
                    FontAwesomeIcons.calendarCheck,
                    size: 40,
                    color: AppColors.muted.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No appointments today',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your schedule is clear!',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            )
          else
            ...upcomingAppointments.asMap().entries.map((entry) {
              final index = entry.key;
              final appointment = entry.value;
              final serviceName = appointment['serviceName'] ?? 'Service';
              final duration = appointment['duration'];
              final time = appointment['time'] ?? '';
              final displayTitle = duration != null && duration.isNotEmpty 
                  ? '$serviceName ${duration}min' 
                  : serviceName;
              
              // Get icon and colors based on service name
              final iconData = _getServiceIcon(serviceName);
              final colors = _getServiceColors(index);
              
              return _buildAppointmentItem(
                displayTitle,
                _formatTime(time),
                iconData,
                colors,
                isNext: index == 0,
                appointmentData: appointment,
              );
            }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const AllAppointmentsPage()),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('View All Appointments',
                  style: TextStyle(color: AppColors.primary)),
            ),
          )
        ],
      ),
    );
  }

  IconData _getServiceIcon(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('massage') || name.contains('spa')) {
      return FontAwesomeIcons.spa;
    } else if (name.contains('facial') || name.contains('face')) {
      return FontAwesomeIcons.leaf;
    } else if (name.contains('nail') || name.contains('manicure') || name.contains('pedicure')) {
      return FontAwesomeIcons.handSparkles;
    } else if (name.contains('hair') || name.contains('cut') || name.contains('style')) {
      return FontAwesomeIcons.scissors;
    } else if (name.contains('wax') || name.contains('threading')) {
      return FontAwesomeIcons.feather;
    } else if (name.contains('makeup') || name.contains('beauty')) {
      return FontAwesomeIcons.wandMagicSparkles;
    }
    return FontAwesomeIcons.calendarCheck;
  }

  List<Color> _getServiceColors(int index) {
    final colorSets = [
      [Colors.purple.shade400, Colors.purple.shade600],
      [Colors.grey.shade700, Colors.grey.shade900],
      [AppColors.accent, AppColors.primary],
      [Colors.blue.shade400, Colors.blue.shade600],
      [Colors.teal.shade400, Colors.teal.shade600],
      [Colors.orange.shade400, Colors.orange.shade600],
    ];
    return colorSets[index % colorSets.length];
  }

  String _formatTime(String time) {
    if (time.isEmpty) return '';
    
    // If already formatted (contains AM/PM), return as is
    if (time.toUpperCase().contains('AM') || time.toUpperCase().contains('PM')) {
      return time;
    }
    
    // Try to parse HH:mm format
    try {
      final parts = time.split(':');
      if (parts.length >= 2) {
        int hour = int.parse(parts[0]);
        final minute = parts[1];
        final period = hour >= 12 ? 'PM' : 'AM';
        if (hour > 12) hour -= 12;
        if (hour == 0) hour = 12;
        return '$hour:$minute $period';
      }
    } catch (_) {}
    
    return time;
  }

  Widget _buildAppointmentItem(
    String title,
    String time,
    IconData icon,
    List<Color> gradientColors, {
    bool isNext = false,
    Map<String, dynamic>? appointmentData,
  }) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AppointmentDetailsPage(appointmentData: appointmentData),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
              child: Center(child: Icon(icon, color: Colors.white, size: 14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 14)),
                  Row(
                    children: [
                      Text(time,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                      if (appointmentData != null && appointmentData['client'] != null) ...[
                        const Text(' • ', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        Flexible(
                          child: Text(
                            appointmentData['client'],
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isNext)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Next',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateBookingSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A1A), Color(0xFF333333)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Icon(FontAwesomeIcons.calendarPlus,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create a New Booking',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Choose a date, time & assign a client',
                    style: TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const WalkInBookingPage()),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.1),
                        blurRadius: 15,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded,
                            color: Color(0xFF1A1A1A), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Create Booking',
                          style: TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(String label, IconData icon, List<Color> colors) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 25,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
              ),
              child: Center(child: Icon(icon, color: Colors.white, size: 20)),
            ),
            Text(label,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// --- 3. Branch Selection Modal ---
class BranchSelectionDialog extends StatefulWidget {
  final Function(String) onBranchSelected;
  const BranchSelectionDialog({super.key, required this.onBranchSelected});

  @override
  State<BranchSelectionDialog> createState() => _BranchSelectionDialogState();
}

class _BranchSelectionDialogState extends State<BranchSelectionDialog> {
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = true;
  String? _scheduledBranchName;
  String? _scheduledBranchId;
  
  // Color palette for branches
  final List<List<Color>> _colorPalette = [
    [Colors.purple.shade400, Colors.purple.shade600],
    [Colors.blue.shade400, Colors.blue.shade600],
    [Colors.green.shade400, Colors.green.shade600],
    [Colors.orange.shade400, Colors.orange.shade600],
    [Colors.grey.shade700, Colors.grey.shade900],
    [Colors.teal.shade400, Colors.teal.shade600],
    [Colors.indigo.shade400, Colors.indigo.shade600],
    [Colors.red.shade400, Colors.red.shade600],
  ];

  @override
  void initState() {
    super.initState();
    _loadBranchesAndSchedule();
  }

  String _getTodayWeekday() {
    const weekDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return weekDays[DateTime.now().weekday - 1];
  }

  String _formatDate(DateTime date) {
    const weekDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return '${weekDays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _loadBranchesAndSchedule() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get user document to find ownerUid and schedule
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String? ownerUid;
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        ownerUid = userData['ownerUid']?.toString() ?? user.uid;
        
        // Check today's schedule
        final todayWeekday = _getTodayWeekday();
        final schedule = userData['schedule'];
        if (schedule is Map && schedule[todayWeekday] != null) {
          final todaySchedule = schedule[todayWeekday];
          if (todaySchedule is Map) {
            _scheduledBranchName = todaySchedule['branchName']?.toString();
            _scheduledBranchId = todaySchedule['branchId']?.toString();
          }
        }
        
        // Also check weeklySchedule format
        final weeklySchedule = userData['weeklySchedule'];
        if (weeklySchedule is Map && weeklySchedule[todayWeekday] != null) {
          final todaySchedule = weeklySchedule[todayWeekday];
          if (todaySchedule is Map) {
            _scheduledBranchName ??= todaySchedule['branchName']?.toString();
            _scheduledBranchId ??= todaySchedule['branchId']?.toString();
          }
        }
      }

      // Fetch branches for this owner
      if (ownerUid != null && ownerUid.isNotEmpty) {
        final branchesSnap = await FirebaseFirestore.instance
            .collection('branches')
            .where('ownerUid', isEqualTo: ownerUid)
            .get();

        final branches = branchesSnap.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name']?.toString() ?? data['branchName']?.toString() ?? 'Branch',
            'address': data['address']?.toString() ?? '',
          };
        }).toList();

        if (mounted) {
          setState(() {
            _branches = branches;
            _isLoading = false;
          });
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading branches: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                  child: Icon(FontAwesomeIcons.locationDot,
                      color: Colors.white, size: 28)),
            ),
            const Text(
              'Select Your Branch',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text),
            ),
            const SizedBox(height: 4),
            // Today's date
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _formatDate(today),
                style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 8),
            // Scheduled branch info
            if (_scheduledBranchName != null && _scheduledBranchName!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary.withOpacity(0.1), AppColors.accent.withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FontAwesomeIcons.calendarCheck, size: 14, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Today you work at $_scheduledBranchName',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const Text(
                "Choose the location you're clocking in at",
                style: TextStyle(fontSize: 14, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            // Branches list
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            else if (_branches.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(FontAwesomeIcons.building, size: 32, color: AppColors.muted.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    const Text(
                      'No branches found',
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    children: _branches.asMap().entries.map((entry) {
                      final index = entry.key;
                      final branch = entry.value;
                      final isScheduled = branch['id'] == _scheduledBranchId || 
                                         branch['name'] == _scheduledBranchName;
                      return _buildBranchOption(
                        branch['name'] ?? 'Branch',
                        branch['id'] ?? '',
                        _colorPalette[index % _colorPalette.length],
                        isScheduled: isScheduled,
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.muted,
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchOption(String name, String branchId, List<Color> colors, {bool isScheduled = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => widget.onBranchSelected(name),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isScheduled ? AppColors.primary.withOpacity(0.08) : AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: isScheduled ? Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5) : null,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                    child: Icon(FontAwesomeIcons.building,
                        color: Colors.white, size: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.text),
                    ),
                    if (isScheduled)
                      const Text(
                        'Scheduled today',
                        style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ),
              if (isScheduled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(FontAwesomeIcons.check, size: 10, color: Colors.white),
                )
              else
                const Icon(FontAwesomeIcons.chevronRight,
                    size: 16, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 4. Helper Widgets ---
class _GradientButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onPressed;
  final Gradient gradient;
  final double marginTop;

  const _GradientButton({
    required this.text,
    required this.icon,
    required this.onPressed,
    required this.gradient,
    this.marginTop = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: marginTop),
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
