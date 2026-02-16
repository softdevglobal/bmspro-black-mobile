import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'location_service.dart';
import 'staff_check_in_service.dart';
import 'audit_log_service.dart';
import 'fcm_push_service.dart';

/// Service for foreground location tracking and auto clock-out
/// This service monitors the user's location when the app is in the foreground (open)
/// and automatically clocks them out if they exceed the branch radius
/// Note: Background location is NOT used to comply with App Store/Play Store guidelines
class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();
  
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicCheckTimer;
  String? _activeCheckInId;
  String? _activeBranchId;
  double? _branchLatitude;
  double? _branchLongitude;
  double? _allowedRadius;
  bool _isMonitoring = false;
  bool _isCheckingLocation = false; // Prevent concurrent checks
  bool _hasNetworkConnection = true; // Track network connection status
  Timer? _networkLossGracePeriodTimer; // Timer for grace period before auto clock-out
  bool _isInNetworkLossGracePeriod = false; // Track if we're in grace period
  
  // Callbacks
  Function(String message)? onAutoCheckOut;
  Function(double distance, double allowedRadius)? onDistanceUpdate;
  
  /// Check if monitoring is active
  bool get isMonitoring => _isMonitoring;
  
  /// Get active check-in ID
  String? get activeCheckInId => _activeCheckInId;
  
  /// Start monitoring location for auto clock-out
  /// Call this when the user checks in
  /// Note: Location monitoring only works when the app is in the foreground (open)
  /// Background location is not used to comply with App Store guidelines
  Future<bool> startMonitoring({
    required String checkInId,
    required String branchId,
    required double branchLatitude,
    required double branchLongitude,
    required double allowedRadius,
    BuildContext? context,
  }) async {
    // Stop any existing monitoring first
    await stopMonitoring();
    
    // Check for location permission (while in use only - no background)
    final hasBasicPermission = await LocationService.isLocationPermissionGranted();
    if (!hasBasicPermission) {
      debugPrint('BackgroundLocationService: No location permission');
      final permission = await LocationService.requestLocationPermission();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        debugPrint('BackgroundLocationService: Failed to get location permission');
        return false;
      }
    }
    
    // Note: We only use "When In Use" location permission now
    // Background location is not requested to comply with both App Store and Play Store guidelines
    // Auto clock-out will only work when the app is open
    
    _activeCheckInId = checkInId;
    _activeBranchId = branchId;
    _branchLatitude = branchLatitude;
    _branchLongitude = branchLongitude;
    _allowedRadius = allowedRadius;
    
    try {
      // Start listening to position stream for movement-based updates
      _positionSubscription = LocationService.getPositionStream(
        distanceFilter: 20, // Update every 20 meters movement
        intervalDuration: 30000, // Check every 30 seconds minimum
      ).listen(
        _onPositionUpdate,
        onError: _onPositionError,
        cancelOnError: false,
      );
      
      // Start periodic timer for regular checks (every 2 minutes)
      // This ensures checks happen even when user is not moving
      _startPeriodicCheck();
      
      // Start monitoring network connectivity
      _startConnectivityMonitoring();
      
      _isMonitoring = true;
      debugPrint('BackgroundLocationService: Started monitoring for check-in $checkInId');
      
      // Perform immediate location check
      await _performImmediateLocationCheck();
      
      // Check initial connectivity status
      await _checkInitialConnectivity();
      
      return true;
    } catch (e) {
      debugPrint('BackgroundLocationService: Error starting monitoring: $e');
      return false;
    }
  }
  
  /// Start periodic timer for regular location checks
  void _startPeriodicCheck() {
    _periodicCheckTimer?.cancel();
    // Check every 2 minutes to catch out-of-radius cases when user is not moving
    _periodicCheckTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _performImmediateLocationCheck();
    });
    debugPrint('BackgroundLocationService: Started periodic check timer (every 2 min)');
  }
  
  /// Perform an immediate location check
  Future<void> _performImmediateLocationCheck() async {
    if (_activeCheckInId == null ||
        _branchLatitude == null ||
        _branchLongitude == null ||
        _allowedRadius == null) {
      return;
    }
    
    // Prevent concurrent checks
    if (_isCheckingLocation) {
      debugPrint('BackgroundLocationService: Already checking location, skipping...');
      return;
    }
    
    _isCheckingLocation = true;
    
    try {
      debugPrint('BackgroundLocationService: Performing immediate location check...');
      
      final position = await LocationService.getCurrentLocation();
      if (position == null) {
        debugPrint('BackgroundLocationService: Could not get current location');
        return;
      }
      
      // Calculate distance from branch
      final distance = LocationService.calculateDistance(
        position.latitude,
        position.longitude,
        _branchLatitude!,
        _branchLongitude!,
      );
      
      // Get GPS accuracy (in meters), use default buffer if not available
      final gpsAccuracy = position.accuracy > 0 ? position.accuracy : 15.0;
      // Use GPS accuracy as buffer, with minimum of 10m and maximum of 30m for safety
      final gpsAccuracyBuffer = gpsAccuracy.clamp(10.0, 30.0);
      
      debugPrint('BackgroundLocationService: Immediate check - Distance: ${distance.toStringAsFixed(1)}m, allowed: ${_allowedRadius!.toStringAsFixed(1)}m, GPS accuracy: ${gpsAccuracy.toStringAsFixed(1)}m');
      
      // Notify about distance update
      onDistanceUpdate?.call(distance, _allowedRadius!);
      
      // Check if outside radius (with buffer for GPS accuracy)
      // Only trigger auto check-out if distance exceeds radius by more than GPS accuracy buffer
      final threshold = _allowedRadius! + gpsAccuracyBuffer;
      if (distance > threshold) {
        debugPrint('BackgroundLocationService: Outside radius! Auto clock-out triggered (immediate check) - Distance: ${distance.toStringAsFixed(1)}m, Threshold: ${threshold.toStringAsFixed(1)}m (radius: ${_allowedRadius!.toStringAsFixed(1)}m + buffer: ${gpsAccuracyBuffer.toStringAsFixed(1)}m)');
        await _performAutoCheckOut(position, distance);
      } else if (distance > _allowedRadius!) {
        debugPrint('BackgroundLocationService: Near radius boundary but within GPS accuracy buffer - Distance: ${distance.toStringAsFixed(1)}m, Allowed: ${_allowedRadius!.toStringAsFixed(1)}m, Buffer: ${gpsAccuracyBuffer.toStringAsFixed(1)}m');
      }
    } catch (e) {
      debugPrint('BackgroundLocationService: Error in immediate location check: $e');
    } finally {
      _isCheckingLocation = false;
    }
  }
  
  /// Start monitoring network connectivity
  void _startConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _handleConnectivityChange(results);
      },
      onError: (error) {
        debugPrint('BackgroundLocationService: Connectivity stream error: $error');
        // If there's an error reading connectivity, assume connection is lost
        _handleConnectivityLost();
      },
    );
    
    debugPrint('BackgroundLocationService: Started connectivity monitoring');
  }
  
  /// Check initial connectivity status
  Future<void> _checkInitialConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _handleConnectivityChange(results);
    } catch (e) {
      debugPrint('BackgroundLocationService: Error checking initial connectivity: $e');
      // Don't auto clock-out on initial check error - just log it
      // The connectivity stream will handle actual connection loss
    }
  }
  
  /// Handle connectivity changes
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final hasConnection = results.any((result) => 
      result != ConnectivityResult.none
    );
    
    if (!hasConnection && _hasNetworkConnection) {
      // Connection was lost
      debugPrint('BackgroundLocationService: Network connection lost!');
      _hasNetworkConnection = false;
      _handleConnectivityLost();
    } else if (hasConnection && !_hasNetworkConnection) {
      // Connection was restored
      debugPrint('BackgroundLocationService: Network connection restored');
      _hasNetworkConnection = true;
      // Cancel any pending auto clock-out if connection is restored
      _cancelNetworkLossAutoCheckOut();
    }
  }
  
  /// Handle network connection loss - wait for grace period before auto check-out
  Future<void> _handleConnectivityLost() async {
    if (_activeCheckInId == null || !_isMonitoring) {
      return;
    }
    
    // If already in grace period, don't start another one
    if (_isInNetworkLossGracePeriod) {
      debugPrint('BackgroundLocationService: Already in network loss grace period');
      return;
    }
    
    debugPrint('BackgroundLocationService: Connection lost! Starting grace period (60 seconds) before auto clock-out');
    
    // Cancel any existing grace period timer
    _networkLossGracePeriodTimer?.cancel();
    _isInNetworkLossGracePeriod = true;
    
    // Wait 60 seconds before auto clocking out
    // This gives time for brief network interruptions to recover
    _networkLossGracePeriodTimer = Timer(const Duration(seconds: 60), () async {
      // Check if connection is still lost before clocking out
      if (!_hasNetworkConnection && _isInNetworkLossGracePeriod) {
        debugPrint('BackgroundLocationService: Grace period expired, connection still lost. Auto clock-out triggered');
        
        try {
          // Try to get last known location if available
          Position? lastKnownPosition;
          try {
            lastKnownPosition = await LocationService.getCurrentLocation();
          } catch (e) {
            debugPrint('BackgroundLocationService: Could not get location for check-out: $e');
          }
          
          // Perform auto check-out due to network loss
          await _performAutoCheckOutDueToNetworkLoss(lastKnownPosition);
        } catch (e) {
          debugPrint('BackgroundLocationService: Error during network loss check-out: $e');
        }
      } else {
        debugPrint('BackgroundLocationService: Connection restored during grace period, cancelling auto clock-out');
      }
      
      _isInNetworkLossGracePeriod = false;
    });
  }
  
  /// Cancel network loss auto check-out if connection is restored
  void _cancelNetworkLossAutoCheckOut() {
    if (_isInNetworkLossGracePeriod) {
      debugPrint('BackgroundLocationService: Cancelling network loss auto check-out - connection restored');
      _networkLossGracePeriodTimer?.cancel();
      _networkLossGracePeriodTimer = null;
      _isInNetworkLossGracePeriod = false;
    }
  }
  
  /// Perform auto check-out due to network connection loss
  Future<void> _performAutoCheckOutDueToNetworkLoss(Position? position) async {
    if (_activeCheckInId == null) return;
    
    final checkInId = _activeCheckInId!;
    
    try {
      // Get check-in document
      final checkInDoc = await FirebaseFirestore.instance
          .collection('staff_check_ins')
          .doc(checkInId)
          .get();
      
      if (!checkInDoc.exists) {
        debugPrint('BackgroundLocationService: Check-in document not found');
        await stopMonitoring();
        return;
      }
      
      final checkInData = checkInDoc.data()!;
      
      // Only process if still checked in
      if (checkInData['status'] != 'checked_in') {
        debugPrint('BackgroundLocationService: Check-in already completed');
        await stopMonitoring();
        return;
      }
      
      // Calculate hours worked (excluding breaks)
      final checkInTime = (checkInData['checkInTime'] as Timestamp).toDate();
      final now = DateTime.now();
      final totalDiff = now.difference(checkInTime);
      
      // Calculate total break time
      int totalBreakSeconds = 0;
      if (checkInData['breakPeriods'] != null && checkInData['breakPeriods'] is List) {
        final breaks = checkInData['breakPeriods'] as List;
        for (final breakData in breaks) {
          if (breakData is Map) {
            final breakStart = (breakData['startTime'] as Timestamp).toDate();
            final breakEnd = breakData['endTime'] != null
                ? (breakData['endTime'] as Timestamp).toDate()
                : null;
            if (breakEnd != null) {
              totalBreakSeconds += breakEnd.difference(breakStart).inSeconds;
            }
          }
        }
      }
      
      // Subtract break time
      final workingSeconds = totalDiff.inSeconds - totalBreakSeconds;
      final hours = workingSeconds > 0 ? workingSeconds ~/ 3600 : 0;
      final minutes = workingSeconds > 0 ? (workingSeconds % 3600) ~/ 60 : 0;
      final hoursWorked = '${hours}h ${minutes}m';
      
      // Update check-in record with auto check-out due to network loss
      final updateData = <String, dynamic>{
        'checkOutTime': FieldValue.serverTimestamp(),
        'status': 'auto_checked_out',
        'updatedAt': FieldValue.serverTimestamp(),
        'autoCheckOutReason': 'Network connection lost',
        'autoCheckOutLocation': position != null
            ? {
                'latitude': position.latitude,
                'longitude': position.longitude,
              }
            : null,
      };
      
      await FirebaseFirestore.instance
          .collection('staff_check_ins')
          .doc(checkInId)
          .update(updateData);
      
      debugPrint('BackgroundLocationService: Auto check-out successful (network loss)');
      
      // Get check-in details for audit log
      final staffName = checkInData['staffName'] ?? 'Unknown';
      final branchId = checkInData['branchId'] ?? '';
      final branchName = checkInData['branchName'] ?? 'Unknown Branch';
      final ownerUid = checkInData['ownerUid'] ?? '';
      final staffRole = checkInData['staffRole'] ?? 'Staff';
      
      // Try to log to audit log (may fail if still offline)
      try {
        await AuditLogService.logStaffCheckOut(
          ownerUid: ownerUid,
          checkInId: checkInId,
          staffId: checkInData['staffId'] ?? '',
          staffName: staffName,
          branchId: branchId,
          branchName: branchName,
          performedBy: 'system',
          performedByName: 'System (Auto)',
          performedByRole: 'System',
          hoursWorked: hoursWorked,
        );
      } catch (e) {
        debugPrint('BackgroundLocationService: Could not log to audit (offline): $e');
        // This is expected when network is lost - Firestore update will sync when connection is restored
      }
      
      // Create notification for the user (may fail if offline, but will sync when back online)
      try {
        await _createAutoCheckOutNotification(0, 'Network connection lost');
      } catch (e) {
        debugPrint('BackgroundLocationService: Could not create notification (offline): $e');
      }
      
      // Notify callback
      onAutoCheckOut?.call(
        'You have been automatically clocked out because your network connection was lost',
      );
      
      // Stop monitoring since user is checked out
      await stopMonitoring();
    } catch (e) {
      debugPrint('BackgroundLocationService: Error during network loss auto check-out: $e');
      // Even if update fails (e.g., still offline), stop monitoring to prevent retries
      await stopMonitoring();
    }
  }
  
  /// Stop monitoring location
  Future<void> stopMonitoring() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    _networkLossGracePeriodTimer?.cancel();
    _networkLossGracePeriodTimer = null;
    _isInNetworkLossGracePeriod = false;
    _activeCheckInId = null;
    _activeBranchId = null;
    _branchLatitude = null;
    _branchLongitude = null;
    _allowedRadius = null;
    _isMonitoring = false;
    _isCheckingLocation = false;
    _hasNetworkConnection = true;
    debugPrint('BackgroundLocationService: Stopped monitoring');
  }
  
  /// Handle position updates
  void _onPositionUpdate(Position position) async {
    if (_activeCheckInId == null ||
        _branchLatitude == null ||
        _branchLongitude == null ||
        _allowedRadius == null) {
      return;
    }
    
    // Calculate distance from branch
    final distance = LocationService.calculateDistance(
      position.latitude,
      position.longitude,
      _branchLatitude!,
      _branchLongitude!,
    );
    
    // Get GPS accuracy (in meters), use default buffer if not available
    final gpsAccuracy = position.accuracy > 0 ? position.accuracy : 15.0;
    // Use GPS accuracy as buffer, with minimum of 10m and maximum of 30m for safety
    final gpsAccuracyBuffer = gpsAccuracy.clamp(10.0, 30.0);
    
    debugPrint('BackgroundLocationService: Distance from branch: ${distance.toStringAsFixed(1)}m, allowed: ${_allowedRadius!.toStringAsFixed(1)}m, GPS accuracy: ${gpsAccuracy.toStringAsFixed(1)}m');
    
    // Notify about distance update
    onDistanceUpdate?.call(distance, _allowedRadius!);
    
    // Check if outside radius (with buffer for GPS accuracy)
    // Only trigger auto check-out if distance exceeds radius by more than GPS accuracy buffer
    final threshold = _allowedRadius! + gpsAccuracyBuffer;
    if (distance > threshold) {
      debugPrint('BackgroundLocationService: Outside radius! Auto clock-out triggered - Distance: ${distance.toStringAsFixed(1)}m, Threshold: ${threshold.toStringAsFixed(1)}m (radius: ${_allowedRadius!.toStringAsFixed(1)}m + buffer: ${gpsAccuracyBuffer.toStringAsFixed(1)}m)');
      await _performAutoCheckOut(position, distance);
    } else if (distance > _allowedRadius!) {
      debugPrint('BackgroundLocationService: Near radius boundary but within GPS accuracy buffer - Distance: ${distance.toStringAsFixed(1)}m, Allowed: ${_allowedRadius!.toStringAsFixed(1)}m, Buffer: ${gpsAccuracyBuffer.toStringAsFixed(1)}m');
    }
  }
  
  /// Handle position stream errors
  void _onPositionError(dynamic error) {
    debugPrint('BackgroundLocationService: Position stream error: $error');
    // Don't stop monitoring on error, let it retry
  }
  
  /// Perform auto check-out
  Future<void> _performAutoCheckOut(Position position, double distance) async {
    if (_activeCheckInId == null) return;
    
    final checkInId = _activeCheckInId!;
    
    try {
      // Use the existing auto check-out method
      final wasCheckedOut = await StaffCheckInService.autoCheckOutIfExceededRadius(
        checkInId: checkInId,
        currentLatitude: position.latitude,
        currentLongitude: position.longitude,
      );
      
      if (wasCheckedOut) {
        debugPrint('BackgroundLocationService: Auto check-out successful');
        
        // Create a notification in Firestore for the user
        await _createAutoCheckOutNotification(distance);
        
        // Notify callback
        onAutoCheckOut?.call(
          'You have been automatically clocked out because you exceeded the branch radius (${distance.toStringAsFixed(0)}m away)',
        );
        
        // Stop monitoring since user is checked out
        await stopMonitoring();
      }
    } catch (e) {
      debugPrint('BackgroundLocationService: Error during auto check-out: $e');
    }
  }
  
  /// Create a notification for the auto check-out
  Future<void> _createAutoCheckOutNotification(double distance, [String? reason]) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Get branch name
      String branchName = 'Unknown Branch';
      if (_activeBranchId != null) {
        final branchDoc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(_activeBranchId)
            .get();
        if (branchDoc.exists) {
          branchName = branchDoc.data()?['name'] ?? 'Unknown Branch';
        }
      }
      
      String message;
      if (reason != null && reason.contains('Network')) {
        message = 'You were automatically clocked out from $branchName because your network connection was lost.';
      } else {
        message = 'You were automatically clocked out from $branchName because you exceeded the branch radius (${distance.toStringAsFixed(0)}m away).';
      }
      
      final notificationRef = await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'auto_clock_out',
        'title': 'Auto Clock-Out',
        'message': message,
        'staffUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        'data': {
          'checkInId': _activeCheckInId,
          'branchId': _activeBranchId,
          'distance': distance,
          'reason': reason ?? 'Exceeded branch radius',
        },
      });
      
      // Send FCM push notification to the staff member
      try {
        await FcmPushService().sendPushNotification(
          targetUid: user.uid,
          title: 'Auto Clock-Out',
          message: message,
          data: {
            'notificationId': notificationRef.id,
            'type': 'auto_clock_out',
            'checkInId': _activeCheckInId ?? '',
            'branchId': _activeBranchId ?? '',
          },
        );
        debugPrint('BackgroundLocationService: FCM push notification sent for auto clock-out');
      } catch (e) {
        debugPrint('BackgroundLocationService: Error sending FCM notification: $e');
      }
    } catch (e) {
      debugPrint('BackgroundLocationService: Error creating notification: $e');
    }
  }
  
  /// Resume monitoring for an active check-in
  /// Call this when the app starts to check if there's an active check-in that needs monitoring
  Future<void> resumeMonitoringIfNeeded() async {
    try {
      debugPrint('BackgroundLocationService: Checking for active check-in to resume monitoring...');
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('BackgroundLocationService: No authenticated user');
        return;
      }
      
      final activeCheckIn = await StaffCheckInService.getActiveCheckIn();
      if (activeCheckIn == null) {
        debugPrint('BackgroundLocationService: No active check-in to monitor');
        // Make sure monitoring is stopped if no active check-in
        await stopMonitoring();
        return;
      }
      
      debugPrint('BackgroundLocationService: Found active check-in: ${activeCheckIn.id}');
      
      // Get branch details
      final branchDoc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(activeCheckIn.branchId)
          .get();
      
      if (!branchDoc.exists) {
        debugPrint('BackgroundLocationService: Branch not found');
        return;
      }
      
      final branchData = branchDoc.data()!;
      final location = branchData['location'] as Map<String, dynamic>?;
      
      if (location == null ||
          location['latitude'] == null ||
          location['longitude'] == null) {
        debugPrint('BackgroundLocationService: Branch location not found');
        return;
      }
      
      final branchLat = (location['latitude'] as num).toDouble();
      final branchLon = (location['longitude'] as num).toDouble();
      final allowedRadius = (branchData['allowedCheckInRadius'] ?? 100).toDouble();
      
      // Check if activeCheckIn has a valid id
      final checkInId = activeCheckIn.id;
      if (checkInId == null) {
        debugPrint('BackgroundLocationService: Check-in ID is null');
        return;
      }
      
      // If already monitoring this check-in, just perform an immediate check
      if (_isMonitoring && _activeCheckInId == checkInId) {
        debugPrint('BackgroundLocationService: Already monitoring this check-in, performing immediate check');
        await _performImmediateLocationCheck();
        return;
      }
      
      // Start monitoring (this will perform an immediate check)
      final success = await startMonitoring(
        checkInId: checkInId,
        branchId: activeCheckIn.branchId,
        branchLatitude: branchLat,
        branchLongitude: branchLon,
        allowedRadius: allowedRadius,
      );
      
      if (success) {
        debugPrint('BackgroundLocationService: Resumed monitoring for check-in $checkInId');
      } else {
        debugPrint('BackgroundLocationService: Failed to resume monitoring');
      }
    } catch (e) {
      debugPrint('BackgroundLocationService: Error resuming monitoring: $e');
    }
  }
  
  /// Check location immediately and auto clock-out if needed
  /// This is a public method that can be called from anywhere
  Future<void> checkLocationNow() async {
    if (!_isMonitoring) {
      // Try to resume monitoring first
      await resumeMonitoringIfNeeded();
    } else {
      await _performImmediateLocationCheck();
    }
  }
}

