import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'location_service.dart';
import 'audit_log_service.dart';

/// Break period model
class BreakPeriod {
  final DateTime startTime;
  final DateTime? endTime;

  BreakPeriod({required this.startTime, this.endTime});

  Duration get duration {
    if (endTime == null) return Duration.zero;
    return endTime!.difference(startTime);
  }

  factory BreakPeriod.fromMap(Map<String, dynamic> map) {
    return BreakPeriod(
      startTime: (map['startTime'] as Timestamp).toDate(),
      endTime: map['endTime'] != null
          ? (map['endTime'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'startTime': Timestamp.fromDate(startTime),
      if (endTime != null) 'endTime': Timestamp.fromDate(endTime!),
    };
  }
}

/// Staff check-in record model
class StaffCheckInRecord {
  final String? id;
  final String staffId;
  final String staffName;
  final String? staffRole;
  final String branchId;
  final String branchName;
  final String ownerUid;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final double staffLatitude;
  final double staffLongitude;
  final double branchLatitude;
  final double branchLongitude;
  final double distanceFromBranch;
  final bool isWithinRadius;
  final double allowedRadius;
  final String status;
  final String? note;
  final List<BreakPeriod> breakPeriods;

  StaffCheckInRecord({
    this.id,
    required this.staffId,
    required this.staffName,
    this.staffRole,
    required this.branchId,
    required this.branchName,
    required this.ownerUid,
    required this.checkInTime,
    this.checkOutTime,
    required this.staffLatitude,
    required this.staffLongitude,
    required this.branchLatitude,
    required this.branchLongitude,
    required this.distanceFromBranch,
    required this.isWithinRadius,
    required this.allowedRadius,
    required this.status,
    this.note,
    this.breakPeriods = const [],
  });

  factory StaffCheckInRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Parse break periods
    List<BreakPeriod> breaks = [];
    if (data['breakPeriods'] != null && data['breakPeriods'] is List) {
      breaks = (data['breakPeriods'] as List)
          .map((b) => BreakPeriod.fromMap(b as Map<String, dynamic>))
          .toList();
    }
    
    // Parse status - support checked_in, checked_out, and auto_checked_out
    String status = data['status'] ?? 'checked_in';
    if (status != 'checked_in' && status != 'checked_out' && status != 'auto_checked_out') {
      // Handle legacy status values
      status = status == 'checked_in' ? 'checked_in' : 'checked_out';
    }
    
    return StaffCheckInRecord(
      id: doc.id,
      staffId: data['staffId'] ?? '',
      staffName: data['staffName'] ?? '',
      staffRole: data['staffRole'],
      branchId: data['branchId'] ?? '',
      branchName: data['branchName'] ?? '',
      ownerUid: data['ownerUid'] ?? '',
      checkInTime: (data['checkInTime'] as Timestamp).toDate(),
      checkOutTime: data['checkOutTime'] != null
          ? (data['checkOutTime'] as Timestamp).toDate()
          : null,
      staffLatitude: (data['staffLatitude'] ?? 0).toDouble(),
      staffLongitude: (data['staffLongitude'] ?? 0).toDouble(),
      branchLatitude: (data['branchLatitude'] ?? 0).toDouble(),
      branchLongitude: (data['branchLongitude'] ?? 0).toDouble(),
      distanceFromBranch: (data['distanceFromBranch'] ?? 0).toDouble(),
      isWithinRadius: data['isWithinRadius'] ?? false,
      allowedRadius: (data['allowedRadius'] ?? 100).toDouble(),
      status: status,
      note: data['note'],
      breakPeriods: breaks,
    );
  }

  String get hoursWorked {
    if (checkOutTime == null) return 'In progress';
    
    // Calculate total time
    final totalDiff = checkOutTime!.difference(checkInTime);
    
    // Calculate total break time
    int totalBreakSeconds = 0;
    for (final breakPeriod in breakPeriods) {
      if (breakPeriod.endTime != null) {
        totalBreakSeconds += breakPeriod.duration.inSeconds;
      }
    }
    
    // Subtract break time from total time
    final workingSeconds = totalDiff.inSeconds - totalBreakSeconds;
    if (workingSeconds < 0) return '0h 0m';
    
    final hours = workingSeconds ~/ 3600;
    final minutes = (workingSeconds % 3600) ~/ 60;
    return '${hours}h ${minutes}m';
  }
  
  /// Get total working time in seconds (excluding breaks)
  int get workingSeconds {
    if (checkOutTime == null) {
      // For active check-ins, calculate from check-in time to now
      final now = DateTime.now();
      final totalDiff = now.difference(checkInTime);
      
      // Calculate total break time (including active break if any)
      int totalBreakSeconds = 0;
      for (final breakPeriod in breakPeriods) {
        if (breakPeriod.endTime != null) {
          totalBreakSeconds += breakPeriod.duration.inSeconds;
        } else {
          // Active break - calculate from start to now
          totalBreakSeconds += now.difference(breakPeriod.startTime).inSeconds;
        }
      }
      
      final workingSeconds = totalDiff.inSeconds - totalBreakSeconds;
      return workingSeconds > 0 ? workingSeconds : 0;
    }
    
    // For completed check-ins
    final totalDiff = checkOutTime!.difference(checkInTime);
    
    int totalBreakSeconds = 0;
    for (final breakPeriod in breakPeriods) {
      if (breakPeriod.endTime != null) {
        totalBreakSeconds += breakPeriod.duration.inSeconds;
      }
    }
    
    final workingSeconds = totalDiff.inSeconds - totalBreakSeconds;
    return workingSeconds > 0 ? workingSeconds : 0;
  }
}

/// Branch model for check-in
class BranchForCheckIn {
  final String id;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final double allowedRadius;
  final String ownerUid;

  BranchForCheckIn({
    required this.id,
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
    required this.allowedRadius,
    required this.ownerUid,
  });

  bool get hasLocation => latitude != null && longitude != null;

  factory BranchForCheckIn.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final location = data['location'] as Map<String, dynamic>?;
    return BranchForCheckIn(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      latitude: location?['latitude']?.toDouble(),
      longitude: location?['longitude']?.toDouble(),
      allowedRadius: (data['allowedCheckInRadius'] ?? 100).toDouble(),
      ownerUid: data['ownerUid'] ?? '',
    );
  }
}

/// Check-in result
class CheckInResult {
  final bool success;
  final String message;
  final String? checkInId;
  final double? distanceFromBranch;
  final bool? isWithinRadius;

  CheckInResult({
    required this.success,
    required this.message,
    this.checkInId,
    this.distanceFromBranch,
    this.isWithinRadius,
  });
}

/// Check-out result
class CheckOutResult {
  final bool success;
  final String message;
  final String? hoursWorked;

  CheckOutResult({
    required this.success,
    required this.message,
    this.hoursWorked,
  });
}

/// Staff check-in service
class StaffCheckInService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get available branches for check-in
  static Future<List<BranchForCheckIn>> getBranchesForCheckIn() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      // Get user's ownerUid
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return [];

      final userData = userDoc.data()!;
      final ownerUid = userData['ownerUid'] ?? user.uid;

      // Get branches for this owner
      final branchesQuery = await _db
          .collection('branches')
          .where('ownerUid', isEqualTo: ownerUid)
          .where('status', isEqualTo: 'Active')
          .get();

      return branchesQuery.docs
          .map((doc) => BranchForCheckIn.fromFirestore(doc))
          .where((b) => b.hasLocation)
          .toList();
    } catch (e) {
      print('Error getting branches: $e');
      return [];
    }
  }

  /// Perform staff check-in
  static Future<CheckInResult> checkIn({
    required String branchId,
    required double staffLatitude,
    required double staffLongitude,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return CheckInResult(success: false, message: 'Not authenticated');
      }

      // Get user data
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        return CheckInResult(success: false, message: 'User data not found');
      }

      final userData = userDoc.data()!;
      final staffName = userData['displayName'] ?? userData['name'] ?? 'Unknown';
      final staffRole = userData['staffRole'] ?? userData['role'] ?? 'Staff';
      final ownerUid = userData['ownerUid'] ?? user.uid;

      // Get branch data
      final branchDoc = await _db.collection('branches').doc(branchId).get();
      if (!branchDoc.exists) {
        return CheckInResult(success: false, message: 'Branch not found');
      }

      final branchData = branchDoc.data()!;
      final branchName = branchData['name'] ?? 'Unknown Branch';
      final location = branchData['location'] as Map<String, dynamic>?;

      if (location == null ||
          location['latitude'] == null ||
          location['longitude'] == null) {
        return CheckInResult(
          success: false,
          message: 'Branch location not configured. Please contact your administrator.',
        );
      }

      final branchLat = location['latitude'].toDouble();
      final branchLon = location['longitude'].toDouble();
      final allowedRadius =
          (branchData['allowedCheckInRadius'] ?? 100).toDouble();

      // Calculate distance
      final distance = LocationService.calculateDistance(
        staffLatitude,
        staffLongitude,
        branchLat,
        branchLon,
      );
      final isWithinRadius = distance <= allowedRadius;

      // Check for existing active check-in
      final activeCheckIn = await _db
          .collection('staff_check_ins')
          .where('staffId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'checked_in')
          .get();

      if (activeCheckIn.docs.isNotEmpty) {
        final existingBranch = activeCheckIn.docs.first.data()['branchName'];
        return CheckInResult(
          success: false,
          message:
              'You already have an active check-in at $existingBranch. Please check out first.',
          isWithinRadius: isWithinRadius,
          distanceFromBranch: distance,
        );
      }

      // Validate location
      if (!isWithinRadius) {
        return CheckInResult(
          success: false,
          message:
              'You are ${LocationService.formatDistance(distance)} away from $branchName. Please go to the branch location (within ${LocationService.formatDistance(allowedRadius)}) to check in.',
          isWithinRadius: false,
          distanceFromBranch: distance,
        );
      }

      // Create check-in record
      final checkInDoc = await _db.collection('staff_check_ins').add({
        'staffId': user.uid,
        'staffName': staffName,
        'staffRole': staffRole,
        'branchId': branchId,
        'branchName': branchName,
        'ownerUid': ownerUid,
        'checkInTime': FieldValue.serverTimestamp(),
        'checkOutTime': null,
        'staffLatitude': staffLatitude,
        'staffLongitude': staffLongitude,
        'branchLatitude': branchLat,
        'branchLongitude': branchLon,
        'distanceFromBranch': distance.round(),
        'isWithinRadius': true,
        'allowedRadius': allowedRadius,
        'status': 'checked_in',
        'breakPeriods': [], // Initialize break periods array
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Log check-in to audit log
      await AuditLogService.logStaffCheckIn(
        ownerUid: ownerUid.toString(),
        checkInId: checkInDoc.id,
        staffId: user.uid,
        staffName: staffName,
        branchId: branchId,
        branchName: branchName,
        performedBy: user.uid,
        performedByName: staffName,
        performedByRole: staffRole,
        details: 'Distance from branch: ${distance.toStringAsFixed(1)}m',
      );

      return CheckInResult(
        success: true,
        message: 'Successfully checked in at $branchName',
        checkInId: checkInDoc.id,
        isWithinRadius: true,
        distanceFromBranch: distance,
      );
    } catch (e) {
      print('Check-in error: $e');
      return CheckInResult(
        success: false,
        message: 'Failed to check in. Please try again.',
      );
    }
  }

  /// Perform staff check-out
  static Future<CheckOutResult> checkOut(String checkInId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return CheckOutResult(success: false, message: 'Not authenticated');
      }

      final checkInDoc =
          await _db.collection('staff_check_ins').doc(checkInId).get();
      if (!checkInDoc.exists) {
        return CheckOutResult(success: false, message: 'Check-in not found');
      }

      final checkInData = checkInDoc.data()!;
      if (checkInData['staffId'] != user.uid) {
        return CheckOutResult(
          success: false,
          message: 'This check-in does not belong to you',
        );
      }

      if (checkInData['status'] != 'checked_in') {
        return CheckOutResult(success: false, message: 'Already checked out');
      }

      await _db.collection('staff_check_ins').doc(checkInId).update({
        'checkOutTime': FieldValue.serverTimestamp(),
        'status': 'checked_out',
        'updatedAt': FieldValue.serverTimestamp(),
      });

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

      // Get check-in details for audit log
      final staffName = checkInData['staffName'] ?? 'Unknown';
      final branchId = checkInData['branchId'] ?? '';
      final branchName = checkInData['branchName'] ?? 'Unknown Branch';
      final ownerUid = checkInData['ownerUid'] ?? user.uid;
      final staffRole = checkInData['staffRole'] ?? 'Staff';

      // Log check-out to audit log
      await AuditLogService.logStaffCheckOut(
        ownerUid: ownerUid.toString(),
        checkInId: checkInId,
        staffId: user.uid,
        staffName: staffName,
        branchId: branchId,
        branchName: branchName,
        performedBy: user.uid,
        performedByName: staffName,
        performedByRole: staffRole,
        hoursWorked: hoursWorked,
      );

      return CheckOutResult(
        success: true,
        message: 'Successfully checked out',
        hoursWorked: hoursWorked,
      );
    } catch (e) {
      print('Check-out error: $e');
      return CheckOutResult(
        success: false,
        message: 'Failed to check out. Please try again.',
      );
    }
  }

  /// Get active check-in for current user
  static Future<StaffCheckInRecord?> getActiveCheckIn() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final query = await _db
          .collection('staff_check_ins')
          .where('staffId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'checked_in')
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;

      return StaffCheckInRecord.fromFirestore(query.docs.first);
    } catch (e) {
      print('Error getting active check-in: $e');
      return null;
    }
  }

  /// Get check-in history for current user
  static Future<List<StaffCheckInRecord>> getCheckInHistory({int limit = 30}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final query = await _db
          .collection('staff_check_ins')
          .where('staffId', isEqualTo: user.uid)
          .orderBy('checkInTime', descending: true)
          .limit(limit)
          .get();

      return query.docs
          .map((doc) => StaffCheckInRecord.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error getting check-in history: $e');
      return [];
    }
  }

  /// Stream active check-in status
  static Stream<StaffCheckInRecord?> streamActiveCheckIn() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    return _db
        .collection('staff_check_ins')
        .where('staffId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'checked_in')
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return StaffCheckInRecord.fromFirestore(snap.docs.first);
    });
  }

  /// Start a break period
  static Future<bool> startBreak(String checkInId) async {
    try {
      print('startBreak called with checkInId: $checkInId');
      final checkInDoc = await _db.collection('staff_check_ins').doc(checkInId).get();
      if (!checkInDoc.exists) {
        print('Check-in document does not exist');
        return false;
      }

      final checkInData = checkInDoc.data()!;
      print('Check-in status: ${checkInData['status']}');
      if (checkInData['status'] != 'checked_in') {
        print('Check-in is not active');
        return false;
      }

      // Check if there's already an active break
      List<dynamic> breakPeriods = List.from(checkInData['breakPeriods'] ?? []);
      for (final breakPeriod in breakPeriods) {
        if (breakPeriod is Map && breakPeriod['endTime'] == null) {
          print('Break already in progress');
          return false; // Already on break
        }
      }
      
      // Add new break period - use Timestamp.now() instead of FieldValue.serverTimestamp()
      // because Firestore doesn't support serverTimestamp() inside arrays
      breakPeriods.add({
        'startTime': Timestamp.now(),
        'endTime': null,
      });

      print('Updating check-in with break period...');
      await _db.collection('staff_check_ins').doc(checkInId).update({
        'breakPeriods': breakPeriods,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('Break started successfully');
      return true;
    } catch (e) {
      print('Error starting break: $e');
      return false;
    }
  }

  /// End a break period
  static Future<bool> endBreak(String checkInId) async {
    try {
      print('endBreak called with checkInId: $checkInId');
      final checkInDoc = await _db.collection('staff_check_ins').doc(checkInId).get();
      if (!checkInDoc.exists) {
        print('Check-in document does not exist');
        return false;
      }

      final checkInData = checkInDoc.data()!;
      print('Check-in status: ${checkInData['status']}');
      if (checkInData['status'] != 'checked_in') {
        print('Check-in is not active');
        return false;
      }

      // Get existing break periods
      List<dynamic> breakPeriods = List.from(checkInData['breakPeriods'] ?? []);
      print('Current break periods: ${breakPeriods.length}');
      
      // Find the last break without an end time and close it
      bool found = false;
      for (int i = breakPeriods.length - 1; i >= 0; i--) {
        final breakPeriod = breakPeriods[i];
        if (breakPeriod is Map && breakPeriod['endTime'] == null) {
          // Use Timestamp.now() instead of FieldValue.serverTimestamp()
          // because Firestore doesn't support serverTimestamp() inside arrays
          breakPeriods[i] = {
            ...breakPeriod,
            'endTime': Timestamp.now(),
          };
          found = true;
          print('Found active break at index $i');
          break;
        }
      }

      if (!found) {
        print('No active break found to end');
        return false;
      }

      print('Updating check-in to end break...');
      await _db.collection('staff_check_ins').doc(checkInId).update({
        'breakPeriods': breakPeriods,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('Break ended successfully');
      return true;
    } catch (e) {
      print('Error ending break: $e');
      return false;
    }
  }

  /// Auto check-out when staff exceeds branch radius
  /// This function checks if the staff member is still within the allowed radius
  /// and automatically checks them out if they've exceeded it
  static Future<bool> autoCheckOutIfExceededRadius({
    required String checkInId,
    required double currentLatitude,
    required double currentLongitude,
  }) async {
    try {
      final checkInDoc = await _db.collection('staff_check_ins').doc(checkInId).get();
      if (!checkInDoc.exists) {
        return false;
      }

      final checkInData = checkInDoc.data()!;
      
      // Only process if still checked in
      if (checkInData['status'] != 'checked_in') {
        return false;
      }

      // Get branch location and radius
      final branchId = checkInData['branchId'] as String;
      final branchDoc = await _db.collection('branches').doc(branchId).get();
      
      if (!branchDoc.exists) {
        return false;
      }

      final branchData = branchDoc.data()!;
      final location = branchData['location'] as Map<String, dynamic>?;
      
      if (location == null ||
          location['latitude'] == null ||
          location['longitude'] == null) {
        return false;
      }

      final branchLat = location['latitude'].toDouble();
      final branchLon = location['longitude'].toDouble();
      final allowedRadius = (branchData['allowedCheckInRadius'] ?? 100).toDouble();

      // Calculate current distance from branch
      final distance = LocationService.calculateDistance(
        currentLatitude,
        currentLongitude,
        branchLat,
        branchLon,
      );

      // If outside radius, auto check-out (with buffer for GPS accuracy - typically 10-15m error)
      // Only trigger auto check-out if distance exceeds radius by more than 15 meters
      const gpsAccuracyBuffer = 15.0; // meters
      if (distance > (allowedRadius + gpsAccuracyBuffer)) {
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

        // Update check-in record with auto check-out
        await _db.collection('staff_check_ins').doc(checkInId).update({
          'checkOutTime': FieldValue.serverTimestamp(),
          'status': 'auto_checked_out',
          'updatedAt': FieldValue.serverTimestamp(),
          'autoCheckOutReason': 'Exceeded branch radius',
          'autoCheckOutDistance': distance.round(),
          'autoCheckOutLocation': {
            'latitude': currentLatitude,
            'longitude': currentLongitude,
          },
        });

        // Get check-in details for audit log
        final staffName = checkInData['staffName'] ?? 'Unknown';
        final branchName = checkInData['branchName'] ?? 'Unknown Branch';
        final ownerUid = checkInData['ownerUid'] ?? '';
        final staffRole = checkInData['staffRole'] ?? 'Staff';
        final user = _auth.currentUser;

        // Log auto check-out to audit log
        await AuditLogService.logStaffCheckOut(
          ownerUid: ownerUid.toString(),
          checkInId: checkInId,
          staffId: checkInData['staffId'] ?? '',
          staffName: staffName,
          branchId: branchId,
          branchName: branchName,
          performedBy: user?.uid ?? 'system',
          performedByName: 'System (Auto)',
          performedByRole: 'System',
          hoursWorked: hoursWorked,
        );

        return true;
      }

      return false;
    } catch (e) {
      print('Error in auto check-out: $e');
      return false;
    }
  }
}
