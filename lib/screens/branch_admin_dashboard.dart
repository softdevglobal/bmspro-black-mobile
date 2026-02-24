import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_screen.dart' as profile_screen;
import 'appointment_requests_page.dart';
import 'all_appointments_page.dart';
import 'other_staff_appointments_page.dart';
import 'appointment_details_page.dart';
import 'notifications_page.dart';
import '../services/staff_check_in_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/background_location_service.dart';
import '../services/permission_service.dart';
import 'package:geolocator/geolocator.dart';

enum ClockStatus { out, clockedIn, onBreak }

class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const green = Color(0xFF10B981);
  static const blue = Color(0xFF3B82F6);
  static const purple = Color(0xFF8B5CF6);
  static const yellow = Color(0xFFFFD700);
  static const orange = Color(0xFFF97316);
}

class BranchAdminDashboard extends StatefulWidget {
  final String branchName;

  const BranchAdminDashboard({super.key, required this.branchName});

  @override
  State<BranchAdminDashboard> createState() => _BranchAdminDashboardState();
}

class _BranchAdminDashboardState extends State<BranchAdminDashboard> with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _loading = true;
  String? _branchId;
  String? _ownerUid;
  
  // Pending approval requests
  int _pendingRequestsCount = 0;
  StreamSubscription<QuerySnapshot>? _pendingRequestsSub;
  
  // Unread notifications count (aggregated from all sources)
  int _unreadNotificationCount = 0;
  StreamSubscription<QuerySnapshot>? _staffNotificationsSub;
  StreamSubscription<QuerySnapshot>? _branchAdminNotifsSub;
  StreamSubscription<QuerySnapshot>? _customerNotifsSub;
  StreamSubscription<QuerySnapshot>? _targetAdminNotifsSub;
  final Set<String> _staffUnreadIds = {};
  final Set<String> _branchAdminUnreadIds = {};
  final Set<String> _customerUnreadIds = {};
  final Set<String> _targetAdminUnreadIds = {};

  // Clock In/Out state
  ClockStatus _clockStatus = ClockStatus.out;
  Timer? _workTimer;
  int _workedSeconds = 0;
  bool _timerRunning = false;
  DateTime? _checkInTime; // Store the actual check-in time to prevent recalculation issues
  String? _selectedBranch;
  String? _activeCheckInId; // Store check-in ID for break tracking
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Background location service for auto check-out
  final BackgroundLocationService _backgroundLocationService = BackgroundLocationService();

  // KPI Data
  double _totalRevenue = 0;
  double _lastMonthRevenue = 0;
  int _totalBookings = 0;
  int _completedBookings = 0;
  int _totalClients = 0;
  int _returningClients = 0;
  
  // Staff data
  List<Map<String, dynamic>> _staffPerformance = [];
  
  // Service breakdown
  Map<String, double> _serviceRevenue = {};
  
  // Revenue by day (last 30 days)
  List<double> _dailyRevenue = [];
  
  // Today's appointments
  List<Map<String, dynamic>> _todayAppointments = [];
  List<Map<String, dynamic>> _myTodayAppointments = []; // Only branch admin's appointments
  List<Map<String, dynamic>> _otherStaffAppointments = []; // Other staff's appointments in the branch
  bool _isLoadingAppointments = true;

  // Weekly calendar (branch-only)
  DateTime _calendarWeekStart = _getWeekStart(DateTime.now());
  final List<Map<String, dynamic>> _calendarBookings = [];
  StreamSubscription<QuerySnapshot>? _calendarBookingsSub;
  String _calendarStaffFilter = 'all';

  @override
  void initState() {
    super.initState();
    
    // Register app lifecycle observer for foreground/background detection
    WidgetsBinding.instance.addObserver(this);
    
    // Setup pulse animation for clock in button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _loadData();
    _listenToPendingRequests();
    _listenToUnreadNotifications();
    _fetchTodayAppointments();
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
      debugPrint('BranchAdminDashboard: App resumed - checking location...');
      _backgroundLocationService.checkLocationNow();
      // Also refresh check-in status in case auto clock-out happened
      _refreshCheckInStatus();
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
    _calendarBookingsSub?.cancel();
    _pulseController.dispose();
    _workTimer?.cancel();
    _backgroundLocationService.stopMonitoring();
    _pendingRequestsSub?.cancel();
    _staffNotificationsSub?.cancel();
    _branchAdminNotifsSub?.cancel();
    _customerNotifsSub?.cancel();
    _targetAdminNotifsSub?.cancel();
    NotificationService().dispose();
    super.dispose();
  }
  
  // Clock in/out handlers
  void _handleClockAction() async {
    if (_clockStatus == ClockStatus.out) {
      // Single-touch clock-in with location check
      await _performClockIn();
    } else if (_clockStatus == ClockStatus.clockedIn) {
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
      // Check if branch ID is available
      if (_branchId == null || _branchId!.isEmpty) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch information not available. Please try again.'),
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
        branchId: _branchId!,
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
                    Icon(
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

  Future<void> _refreshCheckInStatus() async {
    final activeCheckIn = await StaffCheckInService.getActiveCheckIn();
    if (mounted) {
      setState(() {
        if (activeCheckIn != null) {
          _clockStatus = ClockStatus.clockedIn;
          _selectedBranch = activeCheckIn.branchName;
          _activeCheckInId = activeCheckIn.id;
          
          // Use workingSeconds from the record (which excludes breaks)
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
          _clockStatus = ClockStatus.out;
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
      
      // Start background monitoring
      await _backgroundLocationService.startMonitoring(
        checkInId: activeCheckIn.id!,
        branchId: activeCheckIn.branchId,
        branchLatitude: branchLat,
        branchLongitude: branchLon,
        allowedRadius: allowedRadius,
      );
      
      debugPrint('Background location monitoring started for check-in ${activeCheckIn.id}');
    } catch (e) {
      debugPrint('Error starting background location monitoring: $e');
    }
  }
  
  void _handleBreakAction() async {
    print('Break button clicked. Current status: $_clockStatus');
    
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
    
    final next = _clockStatus == ClockStatus.clockedIn
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
          _clockStatus = ClockStatus.onBreak;
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
          _clockStatus = ClockStatus.clockedIn;
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
  
  void _startWorkTimer() {
    if (_timerRunning) return;
    _timerRunning = true;
    _workTimer?.cancel();
    _workTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_clockStatus == ClockStatus.clockedIn) {
        setState(() => _workedSeconds += 1);
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
  
  String get _formattedWorkTime {
    final hours = _workedSeconds ~/ 3600;
    final minutes = (_workedSeconds % 3600) ~/ 60;
    final seconds = _workedSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatElapsed(int totalSeconds) {
    final hrs = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final mins = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hrs:$mins:$secs';
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
  
  /// Recalculate total unread notification count from all sources
  void _recalcUnreadCount() {
    final allIds = <String>{
      ..._staffUnreadIds,
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

  /// Listen to unread notifications from all relevant sources for branch admin
  void _listenToUnreadNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Staff notifications (staffUid) - branch admin can also be assigned as staff
    _staffNotificationsSub = FirebaseFirestore.instance
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

    // 2. Branch admin notifications (branchAdminUid)
    _branchAdminNotifsSub = FirebaseFirestore.instance
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

    // 3. Customer notifications (customerUid)
    _customerNotifsSub = FirebaseFirestore.instance
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

    // 4. Target admin notifications (targetAdminUid)
    _targetAdminNotifsSub = FirebaseFirestore.instance
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

  /// Listen to pending appointment requests for branch admin approval
  void _listenToPendingRequests() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Wait for data to load to get ownerUid and branchId
    await Future.delayed(const Duration(milliseconds: 800));
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
        
        // Branch admin sees requests for their branch
        final bookingBranchId = data['branchId']?.toString();
        if (_branchId != null && bookingBranchId != _branchId) continue;
        
        // Check if assigned to current user (branch admin can also be staff)
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

  Future<void> _fetchTodayAppointments() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoadingAppointments = false);
        return;
      }

      // Wait for data to load to get ownerUid and branchId
      await Future.delayed(const Duration(milliseconds: 800));
      if (_ownerUid == null || _ownerUid!.isEmpty || _branchId == null) {
        setState(() => _isLoadingAppointments = false);
        return;
      }

      // Get today's date in YYYY-MM-DD format
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      debugPrint('Fetching branch admin appointments for date: $todayStr, branchId: $_branchId');

      // Query bookings for this branch today
      FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerUid', isEqualTo: _ownerUid)
          .where('branchId', isEqualTo: _branchId)
          .where('date', isEqualTo: todayStr)
          .snapshots()
          .listen((snap) {
        final List<Map<String, dynamic>> appointments = [];
        
        debugPrint('Found ${snap.docs.length} bookings for today in branch');
        
        for (final doc in snap.docs) {
          final data = doc.data();
          
          // Get service name from various possible fields
          String? serviceName;
          String? duration;
          
          if (data['services'] is List && (data['services'] as List).isNotEmpty) {
            final firstService = (data['services'] as List).first;
            if (firstService is Map) {
              serviceName = firstService['name']?.toString() ?? firstService['serviceName']?.toString();
              duration = firstService['duration']?.toString();
            }
          }
          serviceName ??= data['serviceName']?.toString() ?? data['service']?.toString() ?? 'Service';
          duration ??= data['duration']?.toString() ?? '';
          
          final time = data['time']?.toString() ?? data['startTime']?.toString() ?? '';
          final status = data['status']?.toString() ?? 'pending';
          final staffName = data['staffName']?.toString() ?? 'Unassigned';
          
          appointments.add({
            'id': doc.id,
            'serviceName': serviceName,
            'duration': duration,
            'time': time,
            'status': status,
            'client': data['client']?.toString() ?? data['clientName']?.toString() ?? 'Client',
            'staffName': staffName,
            'data': data,
          });
        }
        
        // Sort by time
        appointments.sort((a, b) {
          final timeA = a['time'] ?? '';
          final timeB = b['time'] ?? '';
          return timeA.compareTo(timeB);
        });
        
        // Separate appointments: branch admin's own vs other staff's
        final List<Map<String, dynamic>> myAppointments = [];
        final List<Map<String, dynamic>> otherStaffAppointments = [];
        final currentUserId = user.uid;
        
        for (var appointment in appointments) {
          final appointmentData = appointment['data'] as Map<String, dynamic>?;
          if (appointmentData == null) continue;
          
          // Check if assigned to current branch admin
          bool isMyAppointment = false;
          
          // Check top-level staffId
          final staffId = appointmentData['staffId']?.toString();
          final staffAuthUid = appointmentData['staffAuthUid']?.toString();
          if (staffId == currentUserId || staffAuthUid == currentUserId) {
            isMyAppointment = true;
          }
          
          // Check services array for multi-service bookings
          if (!isMyAppointment && appointmentData['services'] is List) {
            final services = appointmentData['services'] as List;
            for (var service in services) {
              if (service is Map) {
                final svcStaffId = service['staffId']?.toString();
                final svcStaffAuthUid = service['staffAuthUid']?.toString();
                if (svcStaffId == currentUserId || svcStaffAuthUid == currentUserId) {
                  isMyAppointment = true;
                  break;
                }
              }
            }
          }
          
          if (isMyAppointment) {
            myAppointments.add(appointment);
          } else {
            otherStaffAppointments.add(appointment);
          }
        }
        
        debugPrint('Processed ${appointments.length} appointments: ${myAppointments.length} mine, ${otherStaffAppointments.length} other staff');
        
        if (!mounted) return;
        setState(() {
          _todayAppointments = appointments; // Keep all for reference
          _myTodayAppointments = myAppointments;
          _otherStaffAppointments = otherStaffAppointments;
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

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      // Get user's branch and owner info
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        setState(() => _loading = false);
        return;
      }

      final userData = userDoc.data()!;
      _branchId = userData['branchId']?.toString();
      _ownerUid = userData['ownerUid']?.toString() ?? user.uid;

      if (_branchId == null || _branchId!.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      _listenToCalendarBookings();

      // Fetch all bookings for this branch
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final sixtyDaysAgo = now.subtract(const Duration(days: 60));

      final bookingsSnap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerUid', isEqualTo: _ownerUid)
          .where('branchId', isEqualTo: _branchId)
          .get();

      // Process bookings
      double totalRevenue = 0;
      double lastMonthRevenue = 0;
      int completedBookings = 0;
      Set<String> uniqueClients = {};
      Map<String, int> clientBookingCount = {};
      Map<String, double> serviceRevenue = {};
      Map<String, double> staffRevenue = {};
      Map<String, int> staffBookingCount = {};
      List<double> dailyRevenue = List.filled(30, 0);

      for (var doc in bookingsSnap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        
        // Check if this booking is assigned to the branch admin (current user)
        bool isMyBooking = false;
        
        // Check top-level staffId
        if (data['staffId'] == user.uid || data['staffAuthUid'] == user.uid) {
          isMyBooking = true;
        }
        
        // Check services array for multi-service bookings
        if (data['services'] is List) {
          final servicesList = data['services'] as List;
          for (final item in servicesList) {
            if (item is Map) {
              final svcStaffId = item['staffId']?.toString();
              final svcStaffAuthUid = item['staffAuthUid']?.toString();
              if (svcStaffId == user.uid || svcStaffAuthUid == user.uid) {
                isMyBooking = true;
                break;
              }
            }
          }
        }
        
        // Only count bookings assigned to the branch admin
        if (!isMyBooking) {
          continue;
        }
        
        // For multi-service bookings, check individual service completion status
        double completedServiceRevenue = 0;
        List<String> completedServiceNames = [];
        
        if (data['services'] is List && (data['services'] as List).isNotEmpty) {
          // Multi-service booking - check individual service completion
          final servicesList = data['services'] as List;
          for (final item in servicesList) {
            if (item is Map) {
              final svcStaffId = item['staffId']?.toString();
              final svcStaffAuthUid = item['staffAuthUid']?.toString();
              if (svcStaffId == user.uid || svcStaffAuthUid == user.uid) {
                final completionStatus = (item['completionStatus'] ?? '').toString().toLowerCase();
                // Count service if:
                // 1. Service has completionStatus = 'completed', OR
                // 2. Booking status is 'completed' (fallback for bookings where service completionStatus wasn't set)
                if (completionStatus == 'completed' || status == 'completed') {
                  final servicePrice = (item['price'] as num?)?.toDouble() ?? 0;
                  completedServiceRevenue += servicePrice;
                  
                  // Get service name
                  final svcName = (item['serviceName'] ?? item['name'] ?? '').toString();
                  if (svcName.isNotEmpty) {
                    completedServiceNames.add(svcName);
                  }
                }
              }
            }
          }
          
          // Fallback: If booking is assigned to me and status is completed, 
          // but no services were found with completionStatus, count it as completed
          if (completedServiceRevenue == 0 && status == 'completed') {
            // Check if booking is assigned to me
            if (data['staffId'] == user.uid || data['staffAuthUid'] == user.uid) {
              final bookingPrice = (data['price'] as num?)?.toDouble() ?? 0;
              completedServiceRevenue = bookingPrice;
              debugPrint('  Booking ${doc.id}: Fallback - counted as completed (booking status=completed), price=$bookingPrice');
            }
          }
        } else {
          // Single service booking - check both booking status and completionStatus
          // A booking can be "confirmed" but the service might have completionStatus = "completed"
          final bookingCompletionStatus = (data['completionStatus'] ?? '').toString().toLowerCase();
          final isCompleted = status == 'completed' || bookingCompletionStatus == 'completed';
          
          if (isCompleted) {
            // Only count if assigned to me
            if (data['staffId'] == user.uid || data['staffAuthUid'] == user.uid) {
              final bookingPrice = (data['price'] as num?)?.toDouble() ?? 0;
              // Count even if price is 0, as long as it's completed
              completedServiceRevenue = bookingPrice;
              
              // Get service name for single-service bookings
              final serviceName = (data['serviceName'] ?? '').toString();
              if (serviceName.isNotEmpty) {
                completedServiceNames.addAll(serviceName.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
              }
            }
          }
        }
        
        // Only count if there are completed services
        if (completedServiceRevenue == 0) {
          continue;
        }
        
        final dateStr = (data['date'] ?? '').toString();
        final client = (data['client'] ?? '').toString();

        // Parse date - handle multiple formats
        DateTime? bookingDate;
        try {
          if (dateStr.isNotEmpty) {
            // Try parsing as ISO string first
            try {
              bookingDate = DateTime.parse(dateStr);
            } catch (_) {
              // Try parsing as date string (YYYY-MM-DD)
              final parts = dateStr.split('-');
              if (parts.length == 3) {
                bookingDate = DateTime(
                  int.parse(parts[0]),
                  int.parse(parts[1]),
                  int.parse(parts[2]),
                );
              }
            }
            
            // Also check dateTimeUtc field if date parsing failed
            if (bookingDate == null && data['dateTimeUtc'] != null) {
              try {
                if (data['dateTimeUtc'] is Timestamp) {
                  bookingDate = (data['dateTimeUtc'] as Timestamp).toDate();
                } else {
                  bookingDate = DateTime.parse(data['dateTimeUtc'].toString());
                }
              } catch (_) {}
            }
          }
        } catch (e) {
          debugPrint('Error parsing booking date: $e, dateStr: $dateStr');
        }

        // Count only completed bookings/services for revenue
        completedBookings++;
        totalRevenue += completedServiceRevenue;

        // Track client by email (primary) or name (fallback)
        // Use email as the unique identifier for client retention
        final clientEmail = (data['clientEmail'] ?? data['email'] ?? '').toString().trim().toLowerCase();
        final clientName = client.trim().toLowerCase();
        
        // Use email as primary identifier, fallback to name if email is not available
        String clientIdentifier = '';
        if (clientEmail.isNotEmpty) {
          clientIdentifier = clientEmail;
        } else if (clientName.isNotEmpty) {
          clientIdentifier = clientName;
        }
        
        if (clientIdentifier.isNotEmpty) {
          uniqueClients.add(clientIdentifier);
          clientBookingCount[clientIdentifier] = 
              (clientBookingCount[clientIdentifier] ?? 0) + 1;
          debugPrint('Tracked client: $clientIdentifier (email: $clientEmail, name: $clientName), booking count: ${clientBookingCount[clientIdentifier]}');
        }

        // Service revenue - only count completed services assigned to branch admin
        for (var svcName in completedServiceNames) {
          if (svcName.isNotEmpty) {
            // Distribute revenue evenly across services if multiple
            final servicePrice = completedServiceNames.length > 1 
                ? completedServiceRevenue / completedServiceNames.length 
                : completedServiceRevenue;
            serviceRevenue[svcName] = (serviceRevenue[svcName] ?? 0) + servicePrice;
          }
        }

        // Daily revenue (last 30 days)
        // Index 0 = 30 days ago, Index 29 = today
        if (bookingDate != null) {
          // Normalize booking date to start of day for accurate comparison
          final bookingDateOnly = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);
          final thirtyDaysAgoOnly = DateTime(thirtyDaysAgo.year, thirtyDaysAgo.month, thirtyDaysAgo.day);
          final nowOnly = DateTime(now.year, now.month, now.day);
          
          if (bookingDateOnly.isAfter(thirtyDaysAgoOnly.subtract(const Duration(days: 1))) && 
              bookingDateOnly.isBefore(nowOnly.add(const Duration(days: 1)))) {
            // Calculate days difference
            final daysDiff = nowOnly.difference(bookingDateOnly).inDays;
            if (daysDiff >= 0 && daysDiff < 30) {
              // Index 0 = 29 days ago, Index 29 = today
              final arrayIndex = 29 - daysDiff;
              if (arrayIndex >= 0 && arrayIndex < 30) {
                dailyRevenue[arrayIndex] += completedServiceRevenue;
                debugPrint('Added revenue $completedServiceRevenue to day ${daysDiff} days ago (index $arrayIndex)');
              }
            }
          }
        }

        // Last month revenue (30-60 days ago)
        if (bookingDate != null && 
            bookingDate.isAfter(sixtyDaysAgo) && 
            bookingDate.isBefore(thirtyDaysAgo)) {
          lastMonthRevenue += completedServiceRevenue;
        }
      }

      // Calculate returning clients
      // A returning client is one who has booked more than once (tracked by email or name)
      int returningClients = clientBookingCount.values.where((c) => c > 1).length;
      debugPrint('Client retention calculation:');
      debugPrint('  Total unique clients: ${uniqueClients.length}');
      debugPrint('  Returning clients (booked > 1 time): $returningClients');
      debugPrint('  Client retention: ${uniqueClients.length > 0 ? (returningClients / uniqueClients.length * 100).toStringAsFixed(1) : 0}%');

      // Build staff performance list
      List<Map<String, dynamic>> staffPerformance = [];
      staffRevenue.forEach((name, revenue) {
        staffPerformance.add({
          'name': name,
          'revenue': revenue,
          'bookings': staffBookingCount[name] ?? 0,
        });
      });
      staffPerformance.sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));

      if (mounted) {
        setState(() {
          _totalRevenue = totalRevenue;
          _lastMonthRevenue = lastMonthRevenue;
          _totalBookings = bookingsSnap.docs.length;
          _completedBookings = completedBookings;
          _totalClients = uniqueClients.length;
          _returningClients = returningClients;
          _serviceRevenue = serviceRevenue;
          _staffPerformance = staffPerformance.take(5).toList();
          _dailyRevenue = dailyRevenue;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  double get _revenueGrowth {
    if (_lastMonthRevenue == 0) return 0;
    return ((_totalRevenue - _lastMonthRevenue) / _lastMonthRevenue) * 100;
  }

  double get _clientRetention {
    if (_totalClients == 0) return 0;
    return (_returningClients / _totalClients) * 100;
  }

  double get _avgTicketValue {
    if (_completedBookings == 0) return 0;
    return _totalRevenue / _completedBookings;
  }

  static DateTime _getWeekStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final diff = (d.weekday - DateTime.monday) % 7;
    return d.subtract(Duration(days: diff));
  }

  String _normalizeDateKey(dynamic raw) {
    if (raw == null) return '';
    if (raw is Timestamp) {
      final d = raw.toDate();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    if (s.contains('-')) {
      final p = s.split('-');
      if (p.length >= 3 && p[0].length == 4) {
        return '${p[0]}-${p[1].padLeft(2, '0')}-${p[2].padLeft(2, '0')}';
      }
    }
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    return s;
  }

  int _calParseDuration(dynamic value) {
    if (value is num) return value.toInt();
    final s = (value ?? '').toString();
    final m = RegExp(r'(\d+)').firstMatch(s);
    if (m != null) return int.tryParse(m.group(1) ?? '') ?? 60;
    return 60;
  }

  String _pickStaffName(Map<String, dynamic> booking, [Map<String, dynamic>? service]) {
    final candidates = <dynamic>[
      service?['staffName'],
      service?['staff'],
      service?['staffFullName'],
      service?['assignedStaffName'],
      service?['technicianName'],
      booking['staffName'],
      booking['staff'],
      booking['staffFullName'],
      booking['assignedStaffName'],
      booking['technicianName'],
    ];
    for (final raw in candidates) {
      final name = (raw ?? '').toString().trim();
      if (name.isNotEmpty &&
          !name.toLowerCase().contains('any') &&
          name.toLowerCase() != 'unassigned' &&
          name.toLowerCase() != 'not assigned') {
        return name;
      }
    }
    return '';
  }

  ({int hour, int minute}) _calParseTime(String raw) {
    final input = raw.trim().toUpperCase();
    if (input.isEmpty) return (hour: 9, minute: 0);
    final ampm = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*([AP]M)$').firstMatch(input);
    if (ampm != null) {
      var h = int.tryParse(ampm.group(1) ?? '0') ?? 0;
      final m = int.tryParse(ampm.group(2) ?? '0') ?? 0;
      final ap = ampm.group(3) ?? 'AM';
      if (ap == 'PM' && h < 12) h += 12;
      if (ap == 'AM' && h == 12) h = 0;
      return (hour: h, minute: m);
    }
    final hm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(input);
    if (hm != null) {
      return (
        hour: int.tryParse(hm.group(1) ?? '9') ?? 9,
        minute: int.tryParse(hm.group(2) ?? '0') ?? 0,
      );
    }
    return (hour: 9, minute: 0);
  }

  String _calFormat12h(int hour, int minute) {
    final safeH = ((hour % 24) + 24) % 24;
    final suffix = safeH >= 12 ? 'PM' : 'AM';
    final h12 = safeH % 12 == 0 ? 12 : safeH % 12;
    return '$h12:${minute.toString().padLeft(2, '0')} $suffix';
  }

  void _goPrevWeek() {
    setState(() => _calendarWeekStart = _calendarWeekStart.subtract(const Duration(days: 7)));
  }

  void _goNextWeek() {
    setState(() => _calendarWeekStart = _calendarWeekStart.add(const Duration(days: 7)));
  }

  void _goThisWeek() {
    setState(() => _calendarWeekStart = _getWeekStart(DateTime.now()));
  }

  void _listenToCalendarBookings() {
    if (_ownerUid == null || _ownerUid!.isEmpty) return;
    _calendarBookingsSub?.cancel();
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('bookings')
        .where('ownerUid', isEqualTo: _ownerUid);
    if (_branchId != null && _branchId!.isNotEmpty) {
      query = query.where('branchId', isEqualTo: _branchId);
    }
    _calendarBookingsSub = query.snapshots().listen((snap) {
      final all = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = d.data();
        final branchName = (data['branchName'] ?? '').toString().trim();
        if (widget.branchName.isNotEmpty &&
            _branchId == null &&
            branchName.toLowerCase() != widget.branchName.toLowerCase()) {
          continue;
        }
        final dateKey = _normalizeDateKey(data['date']);
        if (dateKey.isEmpty) continue;
        final services = data['services'];
        if (services is List && services.isNotEmpty) {
          for (final item in services) {
            if (item is! Map) continue;
            final svc = Map<String, dynamic>.from(item);
            final serviceName = (svc['serviceName'] ?? svc['name'] ?? data['serviceName'] ?? 'Service').toString();
            final staffName = _pickStaffName(data, svc);
            final duration = _calParseDuration(svc['duration'] ?? data['duration']);
            all.add({
              'id': d.id,
              'bookingCode': data['bookingCode']?.toString() ?? '',
              'date': dateKey,
              'time': (svc['time'] ?? data['time'] ?? '09:00').toString(),
              'duration': duration,
              'status': (svc['completionStatus'] ?? data['status'] ?? '').toString(),
              'client': (data['name'] ?? data['customerName'] ?? 'Customer').toString(),
              'serviceName': serviceName,
              'staffName': staffName,
              'branchName': branchName,
              'pickupTime': (data['pickupTime'] ?? '').toString(),
              'price': (svc['price'] as num?) ?? (data['price'] as num?) ?? 0,
            });
          }
        } else {
          all.add({
            'id': d.id,
            'bookingCode': data['bookingCode']?.toString() ?? '',
            'date': dateKey,
            'time': (data['time'] ?? '09:00').toString(),
            'duration': _calParseDuration(data['duration']),
            'status': (data['status'] ?? '').toString(),
            'client': (data['name'] ?? data['customerName'] ?? 'Customer').toString(),
            'serviceName': (data['serviceName'] ?? 'Service').toString(),
            'staffName': _pickStaffName(data),
            'branchName': branchName,
            'pickupTime': (data['pickupTime'] ?? '').toString(),
            'price': (data['price'] as num?) ?? 0,
          });
        }
      }
      if (!mounted) return;
      setState(() {
        _calendarBookings
          ..clear()
          ..addAll(all);
      });
    });
  }

  Widget _buildCalendarSection() {
    const startHour = 7;
    const endHour = 19;
    const slotHeight = 26.0;
    const timeColWidth = 34.0;
    final gridHeight = (endHour - startHour) * slotHeight;
    final weekDates = List.generate(7, (i) => _calendarWeekStart.add(Duration(days: i)));
    final weekSet = weekDates
        .map((d) =>
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}')
        .toSet();
    final staffOptions = _calendarBookings
        .map((b) => (b['staffName'] ?? '').toString())
        .where((s) =>
            s.isNotEmpty &&
            !s.toLowerCase().contains('any') &&
            s.toLowerCase() != 'unassigned' &&
            s.toLowerCase() != 'not assigned')
        .toSet()
        .toList()
      ..sort();
    final staffFilterValid =
        _calendarStaffFilter == 'all' || staffOptions.contains(_calendarStaffFilter);
    final weekBookings = _calendarBookings
        .where((b) =>
            weekSet.contains((b['date'] ?? '').toString()) &&
            (!staffFilterValid ||
                _calendarStaffFilter == 'all' ||
                (b['staffName'] ?? '') == _calendarStaffFilter))
        .toList();
    final weekLabel =
        '${weekDates.first.day}/${weekDates.first.month} - ${weekDates.last.day}/${weekDates.last.month}';
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final statusColors = <String, (Color bg, Color border, Color text)>{
      'completed': (const Color(0xFFDCEAFE), const Color(0xFF93C5FD), const Color(0xFF1D4ED8)),
      'confirmed': (const Color(0xFFDCFCE7), const Color(0xFF86EFAC), const Color(0xFF166534)),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF5F3FF), Color(0xFFECFEFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(FontAwesomeIcons.calendarWeek, size: 12, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Branch Calendar',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(weekLabel, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
              ),
              _calNavBtn(icon: FontAwesomeIcons.chevronLeft, onTap: _goPrevWeek),
              const SizedBox(width: 4),
              _calNavBtn(icon: FontAwesomeIcons.calendarDay, onTap: _goThisWeek),
              const SizedBox(width: 4),
              _calNavBtn(icon: FontAwesomeIcons.chevronRight, onTap: _goNextWeek),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(widget.branchName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: staffFilterValid ? _calendarStaffFilter : 'all',
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      style: const TextStyle(fontSize: 12, color: AppColors.text, fontWeight: FontWeight.w600),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All Staff')),
                        ...staffOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                      ],
                      onChanged: (v) => setState(() => _calendarStaffFilter = v ?? 'all'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: timeColWidth),
              ...weekDates.map((d) {
                final key =
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                final isToday = key == todayKey;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isToday ? AppColors.primary : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1],
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isToday ? Colors.white70 : AppColors.muted)),
                        Text('${d.day}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isToday ? Colors.white : AppColors.text)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: gridHeight,
            child: Row(
              children: [
                SizedBox(
                  width: timeColWidth,
                  child: Stack(
                    children: List.generate(endHour - startHour, (i) {
                      final hour = startHour + i;
                      final lbl = hour == 12 ? '12 PM' : hour > 12 ? '${hour - 12} PM' : '$hour AM';
                      return Positioned(
                        top: i * slotHeight - 5,
                        right: 2,
                        child: Text(lbl, style: const TextStyle(fontSize: 8, color: AppColors.muted)),
                      );
                    }),
                  ),
                ),
                ...weekDates.map((d) {
                  final key =
                      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                  final dayBookings = weekBookings.where((b) => (b['date'] ?? '') == key).toList();
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: key == todayKey ? const Color(0xFFFEFCE8) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Stack(
                        children: [
                          ...List.generate(endHour - startHour, (i) {
                            return Positioned(
                              top: i * slotHeight,
                              left: 0,
                              right: 0,
                              child: Divider(
                                height: 1,
                                thickness: 0.6,
                                color: AppColors.border.withOpacity(0.65),
                              ),
                            );
                          }),
                          ...dayBookings.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final bk = entry.value;
                            final tm = _calParseTime((bk['time'] ?? '09:00').toString());
                            final dur = (bk['duration'] as int?) ?? 60;
                            final top = ((tm.hour - startHour) * slotHeight) + ((tm.minute / 60) * slotHeight);
                            if (top < 0 || top > gridHeight - 8) return const SizedBox.shrink();
                            final height = ((dur / 60) * slotHeight).clamp(22.0, 90.0);
                            final endMins = tm.hour * 60 + tm.minute + dur;
                            final eHour = endMins ~/ 60;
                            final eMin = endMins % 60;
                            final status = (bk['status'] ?? '').toString().toLowerCase();
                            final palette = statusColors[status] ??
                                (idx.isEven
                                    ? (const Color(0xFFFCE7F3), const Color(0xFFF9A8D4), const Color(0xFF9D174D))
                                    : (const Color(0xFFE0F2FE), const Color(0xFF7DD3FC), const Color(0xFF075985)));
                            return Positioned(
                              top: top + 1,
                              left: 1.5,
                              right: 1.5,
                              height: height,
                              child: GestureDetector(
                                onTap: () => _showCalendarBookingDetails(bk),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
                                  decoration: BoxDecoration(
                                    color: palette.$1,
                                    border: Border.all(color: palette.$2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text((bk['client'] ?? 'Customer').toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 8, fontWeight: FontWeight.w700, color: palette.$3)),
                                      Text((bk['serviceName'] ?? 'Service').toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 7, color: palette.$3.withOpacity(0.85))),
                                      const Spacer(),
                                      Text(
                                        '${_calFormat12h(tm.hour, tm.minute)} - ${_calFormat12h(eHour, eMin)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 7, fontWeight: FontWeight.w600, color: palette.$3.withOpacity(0.9)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCalendarBookingDetails(Map<String, dynamic> bk) {
    final start = _calParseTime((bk['time'] ?? '09:00').toString());
    final duration = (bk['duration'] as int?) ?? 60;
    final endTotalMins = start.hour * 60 + start.minute + duration;
    final endHour = endTotalMins ~/ 60;
    final endMin = endTotalMins % 60;
    final pickupRaw = (bk['pickupTime'] ?? '').toString().trim();
    final pickup = pickupRaw.isNotEmpty
        ? (() {
            final p = _calParseTime(pickupRaw);
            return _calFormat12h(p.hour, p.minute);
          })()
        : _calFormat12h(endHour, endMin);
    final status = (bk['status'] ?? 'Pending').toString();
    final bookingCode = (bk['bookingCode'] ?? '').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Booking Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${(bk['serviceName'] ?? 'Service').toString()} • ${(bk['staffName'] ?? 'Unassigned').toString()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            if (bookingCode.isNotEmpty) _detailRow('Booking Code', bookingCode),
            _detailRow('Customer', (bk['client'] ?? 'Customer').toString()),
            _detailRow('Service', (bk['serviceName'] ?? 'Service').toString()),
            _detailRow('Date', (bk['date'] ?? '').toString()),
            _detailRow('Time', '${_calFormat12h(start.hour, start.minute)} - ${_calFormat12h(endHour, endMin)}'),
            _detailRow('Pick-up Time', pickup),
            _detailRow('Duration', '$duration min'),
            _detailRow('Staff', (bk['staffName'] ?? 'Not assigned').toString()),
            _detailRow('Branch', (bk['branchName'] ?? widget.branchName).toString()),
            _detailRow('Status', status),
            _detailRow('Price', '\$${(bk['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    final icon = _detailIconForLabel(label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 6, top: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 10, color: const Color(0xFF2563EB)),
          ),
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: AppColors.text, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  IconData _detailIconForLabel(String label) {
    final key = label.toLowerCase();
    if (key.contains('booking')) return FontAwesomeIcons.hashtag;
    if (key.contains('customer')) return FontAwesomeIcons.user;
    if (key.contains('service')) return FontAwesomeIcons.screwdriverWrench;
    if (key.contains('date')) return FontAwesomeIcons.calendar;
    if (key.contains('pick-up')) return FontAwesomeIcons.clockRotateLeft;
    if (key == 'time') return FontAwesomeIcons.clock;
    if (key.contains('duration')) return FontAwesomeIcons.hourglassHalf;
    if (key.contains('staff')) return FontAwesomeIcons.userGroup;
    if (key.contains('branch')) return FontAwesomeIcons.locationDot;
    if (key.contains('status')) return FontAwesomeIcons.circleCheck;
    if (key.contains('price')) return FontAwesomeIcons.dollarSign;
    return FontAwesomeIcons.circleInfo;
  }

  Widget _calNavBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 11, color: AppColors.muted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildClockInCard(),
              const SizedBox(height: 24),
              if (_pendingRequestsCount > 0) ...[
                _buildPendingRequestsAlert(),
                const SizedBox(height: 24),
              ],
              _buildAppointmentsSection(),
              const SizedBox(height: 24),
              _buildOtherStaffAppointmentsSection(),
              const SizedBox(height: 24),
              _buildCalendarSection(),
              const SizedBox(height: 24),
              _buildKpiSection(),
              const SizedBox(height: 24),
              _buildRevenueChartSection(),
              const SizedBox(height: 24),
              _buildServiceBreakdownSection(),
              const SizedBox(height: 24),
              _buildStaffPerformanceSection(),
              const SizedBox(height: 24),
              _buildInsightsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
          // Profile button
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: AppColors.background,
                      body: const profile_screen.ProfileScreen(
                        showBackButton: true,
                      ),
                    ),
                  ),
                );
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    FontAwesomeIcons.user,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Dashboard title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Analytics & insights',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.5),
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
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(FontAwesomeIcons.bell,
                      color: Colors.white.withOpacity(0.6), size: 20),
                ),
                if (_unreadNotificationCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Admin role pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FontAwesomeIcons.crown,
                    size: 10, color: Colors.white.withOpacity(0.8)),
                const SizedBox(width: 5),
                Text(
                  widget.branchName.isNotEmpty ? '${widget.branchName}' : 'Branch Admin',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.amber.shade400, Colors.orange.shade500],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(
                  FontAwesomeIcons.bellConcierge,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_pendingRequestsCount Pending Approval${_pendingRequestsCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to review and approve bookings',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                FontAwesomeIcons.chevronRight,
                color: Colors.white,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClockInCard() {
    IconData icon;
    Color iconColor;
    Color iconBg;
    String title;
    String subtitle;
    Widget mainButton;
    Widget? secondaryButton;

    switch (_clockStatus) {
      case ClockStatus.out:
        icon = FontAwesomeIcons.clock;
        iconColor = Colors.red;
        iconBg = Colors.red.shade100;
        title = 'You are: CLOCKED OUT';
        subtitle = 'Ready to start your shift?';

        mainButton = ScaleTransition(
          scale: _pulseAnimation,
          child: _buildClockButton(
            text: 'Clock In',
            icon: FontAwesomeIcons.play,
            onPressed: _handleClockAction,
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
          ),
        );
        break;

      case ClockStatus.clockedIn:
        icon = FontAwesomeIcons.check;
        iconColor = Colors.green;
        iconBg = Colors.green.shade100;
        title = 'Clocked In: ${_selectedBranch ?? widget.branchName}';
        subtitle = "You're on duty!";

        mainButton = _buildClockButton(
          text: 'Clock Out',
          icon: FontAwesomeIcons.stop,
          onPressed: _handleClockAction,
          gradient: LinearGradient(colors: [Colors.red.shade500, Colors.red.shade700]),
        );

        secondaryButton = _buildClockButton(
          text: 'Take Break',
          icon: FontAwesomeIcons.mugHot,
          onPressed: _handleBreakAction,
          gradient: LinearGradient(colors: [Colors.orange.shade400, Colors.orange.shade600]),
        );
        break;

      case ClockStatus.onBreak:
        icon = FontAwesomeIcons.mugHot;
        iconColor = Colors.orange;
        iconBg = Colors.orange.shade100;
        title = 'On Break';
        subtitle = 'Time worked: $_formattedWorkTime';

        mainButton = _buildClockButton(
          text: 'Resume Work',
          icon: FontAwesomeIcons.play,
          onPressed: _handleBreakAction,
          gradient: LinearGradient(colors: [Colors.green.shade500, Colors.green.shade700]),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_clockStatus != ClockStatus.out) ...[
            const SizedBox(height: 12),
            _buildTimerChip(paused: _clockStatus == ClockStatus.onBreak),
          ],
          const SizedBox(height: 16),
          mainButton,
          if (secondaryButton != null) ...[
            const SizedBox(height: 8),
            secondaryButton,
          ],
        ],
      ),
    );
  }

  Widget _buildClockButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
    required Gradient gradient,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (gradient as LinearGradient).colors.first.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  // --- Appointments Section Methods ---
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

  Widget _buildAppointmentsSection() {
    // Get pending/confirmed appointments - only branch admin's own appointments
    final upcomingAppointments = _myTodayAppointments.where((a) {
      final status = (a['status'] ?? '').toString().toLowerCase();
      return status == 'pending' || status == 'confirmed' || status == 'awaitingstaffapproval' || status == 'partiallyapproved';
    }).toList();
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(FontAwesomeIcons.calendarDay, color: AppColors.primary, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    "Today's Appointments",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isLoadingAppointments
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        '${upcomingAppointments.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                    'Your branch schedule is clear!',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            )
          else
            ...upcomingAppointments.take(5).toList().asMap().entries.map((entry) {
              final index = entry.key;
              final appointment = entry.value;
              final serviceName = appointment['serviceName'] ?? 'Service';
              final duration = appointment['duration'];
              final time = appointment['time'] ?? '';
              final staffName = appointment['staffName'] ?? 'Unassigned';
              final displayTitle = duration != null && duration.isNotEmpty 
                  ? '$serviceName ${duration}min' 
                  : serviceName;
              
              // Get icon and colors based on service name
              final iconData = _getServiceIcon(serviceName);
              final colors = _getServiceColors(index);
              
              return _buildAppointmentItem(
                displayTitle,
                _formatTime(time),
                staffName,
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
                  MaterialPageRoute(builder: (_) => const AllAppointmentsPage()),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'View All Appointments',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildOtherStaffAppointmentsSection() {
    // Get only confirmed appointments for other staff (no pending)
    final otherStaffAppointments = _otherStaffAppointments.where((a) {
      final status = (a['status'] ?? '').toString().toLowerCase();
      return status == 'confirmed' || status == 'completed';
    }).toList();
    
    if (otherStaffAppointments.isEmpty) {
      return const SizedBox.shrink(); // Don't show section if no other staff appointments
    }
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(FontAwesomeIcons.users, color: AppColors.primary, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    "Other Staff Appointments",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${otherStaffAppointments.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 16),
          ...otherStaffAppointments.take(5).toList().asMap().entries.map((entry) {
            final index = entry.key;
            final appointment = entry.value;
            final serviceName = appointment['serviceName'] ?? 'Service';
            final duration = appointment['duration'];
            final time = appointment['time'] ?? '';
            final staffName = appointment['staffName'] ?? 'Unassigned';
            final displayTitle = duration != null && duration.isNotEmpty 
                ? '$serviceName ${duration}min' 
                : serviceName;
            
            // Get icon and colors based on service name
            final iconData = _getServiceIcon(serviceName);
            final colors = _getServiceColors(index + 10); // Offset to get different colors
            
            return _buildAppointmentItem(
              displayTitle,
              _formatTime(time),
              staffName,
              iconData,
              colors,
              isNext: false,
              appointmentData: appointment,
            );
          }),
          if (otherStaffAppointments.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  if (_branchId != null && _ownerUid != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OtherStaffAppointmentsPage(
                          branchId: _branchId!,
                          ownerUid: _ownerUid!,
                        ),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  otherStaffAppointments.length > 5
                      ? 'View All (${otherStaffAppointments.length - 5} more)'
                      : 'View All',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildAppointmentItem(
    String title,
    String time,
    String staffName,
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
              child: Center(child: Icon(icon, color: Colors.white, size: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        time,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
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
                  if (staffName.isNotEmpty && staffName != 'Unassigned')
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(FontAwesomeIcons.userTag, size: 10, color: AppColors.muted),
                          const SizedBox(width: 4),
                          Text(
                            staffName,
                            style: TextStyle(
                              color: AppColors.muted.withOpacity(0.8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
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
                child: const Text(
                  'Next',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiSection() {
    final growthPercent = _revenueGrowth;
    final isPositiveGrowth = growthPercent >= 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                title: 'Total Revenue',
                value: '\$${_totalRevenue.toStringAsFixed(0)}',
                icon: FontAwesomeIcons.dollarSign,
                iconColor: AppColors.green,
                iconBg: AppColors.green.withOpacity(0.1),
                trend: '${isPositiveGrowth ? '+' : ''}${growthPercent.toStringAsFixed(0)}%',
                trendUp: isPositiveGrowth,
                trendColor: isPositiveGrowth ? AppColors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                title: 'Bookings',
                value: '$_completedBookings',
                icon: FontAwesomeIcons.calendarCheck,
                iconColor: AppColors.purple,
                iconBg: AppColors.purple.withOpacity(0.1),
                subtitle: 'of $_totalBookings total',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                title: 'Client Retention',
                value: '${_clientRetention.toStringAsFixed(0)}%',
                icon: FontAwesomeIcons.heart,
                iconColor: AppColors.blue,
                iconBg: AppColors.blue.withOpacity(0.1),
                subtitle: '$_returningClients returning',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                title: 'Avg Ticket Value',
                value: '\$${_avgTicketValue.toStringAsFixed(0)}',
                icon: FontAwesomeIcons.ticket,
                iconColor: AppColors.orange,
                iconBg: AppColors.orange.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    String? trend,
    bool? trendUp,
    Color? trendColor,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(icon, color: iconColor, size: 18),
                ),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: trendColor?.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    trend,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: trendColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRevenueChartSection() {
    // Convert daily revenue to chart spots
    // Show all 30 days, but sample every 5 days for cleaner display (6 points)
    List<FlSpot> spots = [];
    double maxRevenueValue = 0;
    
    // Find max revenue for scaling
    for (double revenue in _dailyRevenue) {
      if (revenue > maxRevenueValue) maxRevenueValue = revenue;
    }
    
    // Create 6 data points (every 5 days: 0, 5, 10, 15, 20, 25, 29)
    for (int i = 0; i < 7; i++) {
      final dayIndex = i == 6 ? 29 : i * 5; // Last point is day 29 (today)
      if (dayIndex < _dailyRevenue.length) {
        // Average revenue for the 5-day period around this point
        double sum = 0;
        int count = 0;
        int start = (i == 0) ? 0 : (dayIndex - 2).clamp(0, 29);
        int end = (i == 6) ? 29 : (dayIndex + 2).clamp(0, 29);
        
        for (int j = start; j <= end && j < _dailyRevenue.length; j++) {
          sum += _dailyRevenue[j];
          count++;
        }
        
        final avgRevenue = count > 0 ? sum / count : 0;
        // Scale down for chart display (divide by 10 for better visualization)
        final scaledRevenue = avgRevenue / 10;
        spots.add(FlSpot(i.toDouble(), scaledRevenue));
      }
    }

    // If no data, show empty chart
    if (spots.isEmpty || maxRevenueValue == 0) {
      spots = List.generate(7, (i) => FlSpot(i.toDouble(), 0));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.chartLine, color: AppColors.green, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Revenue Trends (Last 30 Days)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          maxRevenueValue == 0
              ? SizedBox(
                  height: 200,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.show_chart, size: 48, color: AppColors.muted.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'No revenue data for the last 30 days',
                          style: TextStyle(color: AppColors.muted, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: maxRevenueValue > 0 ? (maxRevenueValue / 10) * 1.2 : 10, // Add 20% padding at top
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              const titles = ['Day 1', '5', '10', '15', '20', '25', '30'];
                              if (value.toInt() >= 0 && value.toInt() < titles.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(titles[value.toInt()], style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                                );
                              }
                              return const Text('');
                            },
                            interval: 1,
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: AppColors.green,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.green.withOpacity(0.1),
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

  Widget _buildServiceBreakdownSection() {
    if (_serviceRevenue.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(FontAwesomeIcons.chartPie, color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Revenue by Service Type',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('No service data available', style: TextStyle(color: AppColors.muted)),
          ],
        ),
      );
    }

    // Calculate percentages
    final total = _serviceRevenue.values.fold(0.0, (a, b) => a + b);
    final sortedServices = _serviceRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topServices = sortedServices.take(4).toList();

    final colors = [
      const Color(0xFF1A1A1A),
      const Color(0xFF8B5CF6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
    ];

    List<PieChartSectionData> sections = [];
    List<Widget> legends = [];

    for (int i = 0; i < topServices.length; i++) {
      final entry = topServices[i];
      final percent = (entry.value / total) * 100;
      sections.add(PieChartSectionData(
        color: colors[i % colors.length],
        value: percent,
        title: '${percent.toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      ));
      legends.add(_buildLegendItem(colors[i % colors.length], entry.key));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.chartPie, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Revenue by Service Type',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 0,
                centerSpaceRadius: 40,
                sections: sections,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: legends,
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          text.length > 15 ? '${text.substring(0, 15)}...' : text,
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
      ],
    );
  }

  Widget _buildStaffPerformanceSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.trophy, color: AppColors.yellow, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Top Performing Staff',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_staffPerformance.isEmpty)
            const Text('No staff performance data', style: TextStyle(color: AppColors.muted))
          else
            ...List.generate(_staffPerformance.length, (index) {
              final staff = _staffPerformance[index];
              final isFirst = index == 0;
              return Padding(
                padding: EdgeInsets.only(bottom: index < _staffPerformance.length - 1 ? 12 : 0),
                child: _buildStaffItem(
                  staff['name'],
                  '\$${(staff['revenue'] as double).toStringAsFixed(0)} • ${staff['bookings']} services',
                  index + 1,
                  isFirst ? Colors.yellow.shade50 : Colors.grey.shade50,
                  isFirst ? Colors.yellow.shade100 : Colors.transparent,
                  isFirst ? AppColors.yellow : Colors.grey.shade400,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildStaffItem(
      String name, String details, int rank, Color bgColor, Color borderColor, Color badgeColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor == Colors.transparent ? Colors.transparent : borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey.shade200,
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.text)),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.length > 20 ? '${name.substring(0, 20)}...' : name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    details,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsSection() {
    // Generate dynamic insights based on data
    List<Map<String, dynamic>> insights = [];

    // Revenue insight
    if (_revenueGrowth > 0) {
      insights.add({
        'title': 'Revenue Growth',
        'description': '${_revenueGrowth.toStringAsFixed(0)}% increase compared to last month',
        'icon': FontAwesomeIcons.arrowUp,
        'iconColor': Colors.green.shade500,
        'bgColor': Colors.green.shade50,
      });
    } else if (_revenueGrowth < 0) {
      insights.add({
        'title': 'Revenue Decline',
        'description': '${_revenueGrowth.abs().toStringAsFixed(0)}% decrease compared to last month',
        'icon': FontAwesomeIcons.arrowDown,
        'iconColor': Colors.red.shade500,
        'bgColor': Colors.red.shade50,
      });
    }

    // Top service insight
    if (_serviceRevenue.isNotEmpty) {
      final topService = _serviceRevenue.entries.reduce((a, b) => a.value > b.value ? a : b);
      insights.add({
        'title': 'Top Service',
        'description': '${topService.key} generates most revenue',
        'icon': FontAwesomeIcons.star,
        'iconColor': Colors.blue.shade500,
        'bgColor': Colors.blue.shade50,
      });
    }

    // Client retention insight
    if (_clientRetention > 50) {
      insights.add({
        'title': 'Great Retention',
        'description': '${_clientRetention.toStringAsFixed(0)}% of clients are returning customers',
        'icon': FontAwesomeIcons.heart,
        'iconColor': Colors.grey.shade800,
        'bgColor': Colors.grey.shade100,
      });
    } else if (_totalClients > 0) {
      insights.add({
        'title': 'Retention Opportunity',
        'description': 'Consider loyalty programs to increase repeat visits',
        'icon': FontAwesomeIcons.circleExclamation,
        'iconColor': Colors.orange.shade500,
        'bgColor': Colors.orange.shade50,
      });
    }

    if (insights.isEmpty) {
      insights.add({
        'title': 'Getting Started',
        'description': 'Complete more bookings to see insights',
        'icon': FontAwesomeIcons.lightbulb,
        'iconColor': Colors.blue.shade500,
        'bgColor': Colors.blue.shade50,
      });
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.lightbulb, color: AppColors.blue, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Business Insights',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...insights.asMap().entries.map((entry) {
            final index = entry.key;
            final insight = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: index < insights.length - 1 ? 12 : 0),
              child: _buildInsightItem(
                insight['title'],
                insight['description'],
                insight['icon'],
                insight['iconColor'],
                insight['bgColor'],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInsightItem(
      String title, String description, IconData icon, Color iconColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(icon, color: Colors.white, size: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
