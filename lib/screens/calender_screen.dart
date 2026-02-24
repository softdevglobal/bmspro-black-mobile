import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/animated_toggle.dart';

class ServiceDetail {
  final String name;
  final double price;
  final String staffName;
  final String staffId;
  final int duration;
  
  ServiceDetail({
    required this.name,
    this.price = 0,
    this.staffName = '',
    this.staffId = '',
    this.duration = 0,
  });
}

class BookingTask {
  final String id;
  final String name;
  final String description;
  final String serviceName;
  final bool done;
  final String staffNote;
  final String completedByStaffName;

  BookingTask({
    this.id = '',
    this.name = '',
    this.description = '',
    this.serviceName = '',
    this.done = false,
    this.staffNote = '',
    this.completedByStaffName = '',
  });

  factory BookingTask.fromMap(Map<String, dynamic> m) {
    return BookingTask(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      serviceName: (m['serviceName'] ?? '').toString(),
      done: m['done'] == true,
      staffNote: (m['staffNote'] ?? '').toString(),
      completedByStaffName: (m['completedByStaffName'] ?? '').toString(),
    );
  }
}

class Appointment {
  final String time;
  final String client;
  final String service;
  final String room;
  final IconData icon;
  final String staffId;
  final String status;
  final double price;
  final String staffName;
  final String phone;
  final String email;
  final String bookingId;
  final List<ServiceDetail> services;
  final String? branchName;
  final String bookingCode;
  final String pickupTime;
  final String notes;
  final String date;
  final int totalDuration;
  final String createdAt;
  final List<BookingTask> tasks;
  final int taskProgress;
  final Map<String, dynamic>? finalSubmission;
  
  Appointment({
    required this.time,
    required this.client,
    required this.service,
    required this.room,
    required this.icon,
    required this.staffId,
    this.status = 'Confirmed',
    this.price = 0,
    this.staffName = '',
    this.phone = '',
    this.email = '',
    this.bookingId = '',
    this.services = const [],
    this.branchName,
    this.bookingCode = '',
    this.pickupTime = '',
    this.notes = '',
    this.date = '',
    this.totalDuration = 0,
    this.createdAt = '',
    this.tasks = const [],
    this.taskProgress = 0,
    this.finalSubmission,
  });
}

class DaySchedule {
  final String? branch; // 'Main St', 'Downtown', 'Westside'
  final bool isOffDay;
  final List<Appointment> items;
  DaySchedule({this.branch, this.isOffDay = false, this.items = const []});
}

class BranchTheme {
  final Color color;
  final Color lightBg;
  final List<Color> gradient;
  BranchTheme({
    required this.color,
    required this.lightBg,
    required this.gradient,
  });
}

class AppConfig {
  static const primary = Color(0xFF1A1A1A);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const surface = Color(0xFFF1F3F5);
  static final Map<String, BranchTheme> branches = {
    'Main St': BranchTheme(
      color: Color(0xFF1A1A1A),
      lightBg: Color(0xFFF5F5F5),
      gradient: [Color(0xFF1A1A1A), Color(0xFF333333)],
    ),
    'Downtown': BranchTheme(
      color: Color(0xFF3B82F6),
      lightBg: Color(0xFFEFF6FF),
      gradient: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
    ),
    'Westside': BranchTheme(
      color: Color(0xFF10B981),
      lightBg: Color(0xFFECFDF5),
      gradient: [Color(0xFF10B981), Color(0xFF34D399)],
    ),
  };
}

class CalenderScreen extends StatefulWidget {
  const CalenderScreen({super.key});

  @override
  State<CalenderScreen> createState() => _CalenderScreenState();
}

class _CalenderScreenState extends State<CalenderScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  Map<int, DaySchedule> _scheduleData = {};
  
  // Role & filtering state
  String? _currentUserRole;
  String? _currentUserId;
  String? _ownerUid;
  String? _branchId;
  bool _isBranchView = false; // false = My Schedule, true = Branch Schedule
  bool _isLoadingRole = true;

  // Live bookings state
  bool _isLoadingBookings = true;
  String? _bookingsError;
  final List<Map<String, dynamic>> _allBookings = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bookingsSub;
  
  // Branches state
  final Map<String, BranchTheme> _branchThemes = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _branchesSub;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _currentUserId = user.uid;
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (mounted && doc.exists) {
          final userData = doc.data();
          setState(() {
            String? rawRole = userData?['role'];
            // role is already normalized (staff, branch_admin, workshop_owner)
            _currentUserRole = rawRole;
            _ownerUid = (userData?['ownerUid'] ?? user.uid).toString();
            _branchId = (userData?['branchId'] ?? '').toString();
            _isLoadingRole = false;
          });

          _startBookingsListener();
          _startBranchesListener();
        }
      } else {
         if (mounted) setState(() => _isLoadingRole = false);
      }
    } catch (e) {
      debugPrint('Error fetching role: $e');
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  @override
  void dispose() {
    _bookingsSub?.cancel();
    _bookingRequestsSub?.cancel();
    _branchesSub?.cancel();
    super.dispose();
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bookingRequestsSub;
  
  // Predefined color palette for branches
  static final List<Color> _branchColorPalette = [
    const Color(0xFF1A1A1A), // Black
    const Color(0xFF3B82F6), // Blue
    const Color(0xFF10B981), // Green
    const Color(0xFF8B5CF6), // Purple
    const Color(0xFFF59E0B), // Amber
    const Color(0xFFEF4444), // Red
    const Color(0xFF06B6D4), // Cyan
    const Color(0xFF1A1A1A), // Rose-500
    const Color(0xFF6366F1), // Indigo
    const Color(0xFF14B8A6), // Teal
  ];
  
  void _startBranchesListener() {
    final ownerUid = _ownerUid;
    if (ownerUid == null || ownerUid.isEmpty) {
      return;
    }
    
    _branchesSub?.cancel();
    _branchesSub = FirebaseFirestore.instance
        .collection('branches')
        .where('ownerUid', isEqualTo: ownerUid)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      
      final Map<String, BranchTheme> newThemes = {};
      int colorIndex = 0;
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final branchName = (data['name'] ?? '').toString();
        
        if (branchName.isNotEmpty) {
          // Assign color from palette (cycle through if more branches than colors)
          final baseColor = _branchColorPalette[colorIndex % _branchColorPalette.length];
          
          // Create light background color (lighter version of base color with opacity)
          final lightBg = Color.fromRGBO(
            baseColor.red,
            baseColor.green,
            baseColor.blue,
            0.1,
          );
          
          // Create gradient (base color to lighter version)
          final lighterColor = Color.fromRGBO(
            (baseColor.red + 255) ~/ 2,
            (baseColor.green + 255) ~/ 2,
            (baseColor.blue + 255) ~/ 2,
            1.0,
          );
          
          newThemes[branchName] = BranchTheme(
            color: baseColor,
            lightBg: lightBg,
            gradient: [baseColor, lighterColor],
          );
          
          colorIndex++;
        }
      }
      
      setState(() {
        _branchThemes.clear();
        _branchThemes.addAll(newThemes);
      });
    }, onError: (e) {
      debugPrint('Error listening to branches: $e');
    });
  }
  
  void _startBookingsListener() {
    final ownerUid = _ownerUid;
    if (ownerUid == null || ownerUid.isEmpty) {
      setState(() {
        _isLoadingBookings = false;
        _bookingsError = 'Missing owner UID';
      });
      return;
    }

    _bookingsSub?.cancel();
    _bookingRequestsSub?.cancel();
    setState(() {
      _isLoadingBookings = true;
      _bookingsError = null;
      _scheduleData = {};
      _allBookings.clear();
    });
    
    final List<Map<String, dynamic>> bookingsData = [];
    final List<Map<String, dynamic>> bookingRequestsData = [];
    final Set<String> seenIds = {};
    
    void mergeAndRebuild() {
      _allBookings.clear();
      seenIds.clear();
      
      // Add all bookings first
      for (final b in bookingsData) {
        final id = b['id']?.toString() ?? '';
        if (id.isNotEmpty && !seenIds.contains(id)) {
          seenIds.add(id);
          _allBookings.add(b);
        }
      }
      
      // Add booking requests that aren't duplicates
      for (final b in bookingRequestsData) {
        final id = b['id']?.toString() ?? '';
        if (id.isNotEmpty && !seenIds.contains(id)) {
          seenIds.add(id);
          _allBookings.add(b);
        }
      }
      
      _rebuildScheduleFromBookings();
    }

    _bookingsSub = FirebaseFirestore.instance
        .collection('bookings')
        .where('ownerUid', isEqualTo: ownerUid)
        .snapshots()
        .listen((snap) {
      bookingsData
        ..clear()
        ..addAll(snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }));
      mergeAndRebuild();
    }, onError: (e) {
      debugPrint('Error listening to bookings: $e');
      if (mounted) {
        setState(() {
          _isLoadingBookings = false;
          _bookingsError = e.toString();
        });
      }
    });
    
    // Also listen to bookingRequests (from booking engine)
    _bookingRequestsSub = FirebaseFirestore.instance
        .collection('bookingRequests')
        .where('ownerUid', isEqualTo: ownerUid)
        .snapshots()
        .listen((snap) {
      bookingRequestsData
        ..clear()
        ..addAll(snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }));
      mergeAndRebuild();
    }, onError: (e) {
      // Silently ignore errors for bookingRequests - may not be accessible
      debugPrint('Error listening to bookingRequests: $e');
    });
  }

  void _rebuildScheduleFromBookings() {
    final Map<int, DaySchedule> byDay = {};
    final bool isOwner = _currentUserRole == 'workshop_owner';
    final bool isBranchAdmin = _currentUserRole == 'branch_admin';
    final bool isStaff = _currentUserRole == 'staff';

    for (final data in _allBookings) {
      final statusRaw = (data['status'] ?? '').toString().toLowerCase();
      
      // Skip cancelled/rejected bookings for everyone
      if (statusRaw == 'cancelled' || 
          statusRaw == 'canceled' || 
          statusRaw == 'staffrejected') continue;
      
      // Staff: only see confirmed bookings assigned to them
      if (isStaff && statusRaw != 'confirmed') continue;
      
      // Owners and branch admins see all statuses (pending, confirmed, awaiting approval, etc.)

      final dateStr = (data['date'] ?? '').toString();
      if (dateStr.isEmpty) continue;

      DateTime date;
      try {
        date = DateTime.parse(dateStr);
      } catch (_) {
        continue;
      }

      // Match currently focused month
      if (date.year != _focusedMonth.year || date.month != _focusedMonth.month) {
        continue;
      }

      // Role-based inclusion
      if (!_shouldIncludeBookingForCurrentUser(data, date)) {
        continue;
      }

      final int dayKey = date.day;

      final branchName = (data['branchName'] ?? '').toString();
      final clientName = (data['client'] ?? data['customerName'] ?? 'Walk-in').toString();
      final clientPhone = (data['phone'] ?? data['customerPhone'] ?? '').toString();
      final clientEmail = (data['email'] ?? data['customerEmail'] ?? '').toString();
      final bookingId = (data['id'] ?? '').toString();
      final bookingCode = (data['bookingCode'] ?? '').toString();
      final pickupTime = (data['pickupTime'] ?? '').toString();
      final bookingNotes = (data['notes'] ?? data['note'] ?? '').toString();
      final bookingDuration = int.tryParse((data['duration'] ?? '0').toString()) ?? 0;
      final createdAtRaw = data['createdAt'];
      String createdAtStr = '';
      if (createdAtRaw is Timestamp) {
        createdAtStr = DateFormat('dd MMM yyyy, h:mm a').format(createdAtRaw.toDate());
      } else if (createdAtRaw is String && createdAtRaw.isNotEmpty) {
        createdAtStr = createdAtRaw;
      }

      // Parse tasks, task progress, and final submission
      final List<BookingTask> bookingTasks = [];
      final rawTasks = data['tasks'];
      if (rawTasks is List) {
        for (final t in rawTasks) {
          if (t is Map) {
            bookingTasks.add(BookingTask.fromMap(Map<String, dynamic>.from(t)));
          }
        }
      }
      final int bookingTaskProgress = (data['taskProgress'] as num?)?.toInt() ?? 0;
      final Map<String, dynamic>? bookingFinalSubmission = data['finalSubmission'] != null
          ? Map<String, dynamic>.from(data['finalSubmission'] as Map)
          : null;

      // Derive service name, price, and individual service details
      String serviceName = (data['serviceName'] ?? '').toString();
      double totalPrice = 0;
      List<ServiceDetail> serviceDetails = [];
      
      // Try to get price from top level first
      if (data['price'] != null) {
        totalPrice = double.tryParse(data['price'].toString()) ?? 0;
      } else if (data['totalPrice'] != null) {
        totalPrice = double.tryParse(data['totalPrice'].toString()) ?? 0;
      }
      
      // Format status properly (convert camelCase like "AwaitingStaffApproval" to "Awaiting Staff Approval")
      String bookingStatus = _formatStatus(statusRaw);
      final roomLabel = branchName.isNotEmpty ? branchName : 'Salon';
      final bookingTimeStr = (data['time'] ?? '').toString();

      // Helper to get icon for a service
      IconData getServiceIcon(String svcName) {
        final lower = svcName.toLowerCase();
        if (lower.contains('nail')) return FontAwesomeIcons.handSparkles;
        if (lower.contains('facial') || lower.contains('spa')) return FontAwesomeIcons.spa;
        if (lower.contains('massage')) return FontAwesomeIcons.spa;
        if (lower.contains('extension')) return FontAwesomeIcons.wandMagicSparkles;
        if (lower.contains('color') || lower.contains('colour')) return FontAwesomeIcons.paintbrush;
        if (lower.contains('cut') || lower.contains('trim')) return FontAwesomeIcons.scissors;
        if (lower.contains('wax')) return FontAwesomeIcons.star;
        return FontAwesomeIcons.scissors;
      }

      // Helper to format time
      String formatTime(String timeStr) {
        if (timeStr.isEmpty) return '';
        try {
          final t = DateFormat('HH:mm').parse(timeStr);
          return DateFormat('h:mm a').format(t);
        } catch (_) {
          return timeStr;
        }
      }

      // Helper to add appointment to schedule
      void addAppointmentToDay(Appointment appt) {
        final existing = byDay[dayKey];
        if (existing == null) {
          byDay[dayKey] = DaySchedule(
            branch: branchName.isNotEmpty ? branchName : null,
            items: [appt],
          );
        } else {
          final List<Appointment> items = List.of(existing.items)..add(appt);
          String? mergedBranch = existing.branch;
          if (mergedBranch == null && branchName.isNotEmpty) {
            mergedBranch = branchName;
          } else if (mergedBranch != null && branchName.isNotEmpty && branchName != mergedBranch) {
            mergedBranch = 'Multiple Branches';
          }
          byDay[dayKey] = DaySchedule(branch: mergedBranch, items: items, isOffDay: false);
        }
      }

      // Create SEPARATE appointment for EACH service
      if (data['services'] is List && (data['services'] as List).isNotEmpty) {
        final list = data['services'] as List;
        for (final svc in list) {
          if (svc is Map) {
            final svcName = (svc['name'] ?? 'Service').toString();
            final svcPrice = double.tryParse((svc['price'] ?? '0').toString()) ?? 0;
            final svcStaffName = (svc['staffName'] ?? '').toString();
            final svcStaffId = (svc['staffId'] ?? '').toString();
            final svcDuration = int.tryParse((svc['duration'] ?? '0').toString()) ?? 0;
            final svcTime = (svc['time'] ?? bookingTimeStr).toString();
            final svcApprovalStatus = (svc['approvalStatus'] ?? '').toString();
            
            // Determine status - use service approval status if booking is awaiting
            String displayStatus = bookingStatus;
            if (statusRaw.toLowerCase().contains('awaiting') || statusRaw.toLowerCase().contains('partially')) {
              if (svcApprovalStatus == 'accepted') {
                displayStatus = 'Confirmed';
              } else if (svcApprovalStatus == 'rejected') {
                displayStatus = 'Rejected';
              } else {
                displayStatus = 'Awaiting Approval';
              }
            }
            
            final serviceDetail = ServiceDetail(
              name: svcName,
              price: svcPrice,
              staffName: svcStaffName,
              staffId: svcStaffId,
              duration: svcDuration,
            );

            final appt = Appointment(
              time: formatTime(svcTime),
              client: clientName,
              service: '$svcName ${svcDuration > 0 ? '${svcDuration}min' : ''}',
              room: roomLabel,
              icon: getServiceIcon(svcName),
              staffId: svcStaffId.isNotEmpty ? svcStaffId : _extractStaffId(data),
              status: displayStatus,
              price: svcPrice,
              staffName: svcStaffName.isNotEmpty ? svcStaffName : (data['staffName'] ?? '').toString(),
              phone: clientPhone,
              email: clientEmail,
              bookingId: bookingId,
              services: [serviceDetail],
              branchName: branchName.isNotEmpty ? branchName : null,
              bookingCode: bookingCode,
              pickupTime: pickupTime,
              notes: bookingNotes,
              date: dateStr,
              totalDuration: svcDuration > 0 ? svcDuration : bookingDuration,
              createdAt: createdAtStr,
              tasks: bookingTasks,
              taskProgress: bookingTaskProgress,
              finalSubmission: bookingFinalSubmission,
            );

            addAppointmentToDay(appt);
          }
        }
      } else {
        // Legacy: single service booking without services array
        serviceName = (data['serviceName'] ?? 'Service').toString();
        if (serviceName.isEmpty) serviceName = 'Service';
        
        final staffName = (data['staffName'] ?? '').toString();
        
        if (totalPrice == 0) {
          final rawPrice = data['price'];
          if (rawPrice is num) {
            totalPrice = rawPrice.toDouble();
          } else {
            totalPrice = double.tryParse(rawPrice?.toString() ?? '0') ?? 0;
          }
        }

        final appt = Appointment(
          time: formatTime(bookingTimeStr),
          client: clientName,
          service: serviceName,
          room: roomLabel,
          icon: getServiceIcon(serviceName),
          staffId: _extractStaffId(data),
          status: bookingStatus,
          price: totalPrice,
          staffName: staffName,
          phone: clientPhone,
          email: clientEmail,
          bookingId: bookingId,
          services: [],
          branchName: branchName.isNotEmpty ? branchName : null,
          bookingCode: bookingCode,
          pickupTime: pickupTime,
          notes: bookingNotes,
          date: dateStr,
          totalDuration: bookingDuration,
          createdAt: createdAtStr,
          tasks: bookingTasks,
          taskProgress: bookingTaskProgress,
          finalSubmission: bookingFinalSubmission,
        );

        addAppointmentToDay(appt);
      }
    }

    if (!mounted) return;
    setState(() {
      _scheduleData = byDay;
      _isLoadingBookings = false;
    });
  }

  /// Converts camelCase/PascalCase status like "AwaitingStaffApproval" to "Awaiting Staff Approval"
  String _formatStatus(String raw) {
    if (raw.isEmpty) return 'Pending';
    
    // Insert space before each uppercase letter (except the first)
    final spaced = raw.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    
    // Capitalize first letter and return
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// Format status for display in UI - handles camelCase and provides short labels
  String _formatStatusDisplay(String status) {
    // Handle camelCase like "AwaitingStaffApproval" -> "Awaiting Staff Approval"
    String formatted = status.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    
    // Also handle fully lowercase versions
    final lower = formatted.toLowerCase();
    if (lower == 'awaitingstaffapproval' || lower.contains('awaiting')) {
      return 'Awaiting Approval';
    }
    if (lower.contains('partially')) {
      return 'Partial';
    }
    
    // Capitalize first letter of each word
    return formatted.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  bool _shouldIncludeBookingForCurrentUser(
      Map<String, dynamic> data, DateTime date) {
    final role = _currentUserRole;
    final uid = _currentUserId;
    final branchId = _branchId;

    // Salon owner: see all confirmed bookings for their salon
    if (role == 'workshop_owner') return true;

    final bookingBranchId = (data['branchId'] ?? '').toString();

    // Branch admin: see only their branch in calendar;
    // per-staff vs branch-wide is handled later in _buildAppointmentsList.
    if (role == 'branch_admin') {
      if (branchId != null &&
          branchId.isNotEmpty &&
          bookingBranchId.isNotEmpty &&
          bookingBranchId != branchId) {
        return false;
      }
      return true;
    }

    // Staff: only their own bookings
    if (uid == null || uid.isEmpty) return false;
    return _isBookingForStaff(data, uid);
  }

  bool _isBookingForStaff(Map<String, dynamic> data, String staffUid) {
    // Check top-level staffId
    final topLevelStaff = data['staffId'];
    if (topLevelStaff != null &&
        topLevelStaff.toString().isNotEmpty &&
        topLevelStaff.toString() == staffUid) {
      return true;
    }
    
    // Check top-level staffAuthUid (for staff created bookings)
    final topLevelStaffAuthUid = data['staffAuthUid'];
    if (topLevelStaffAuthUid != null &&
        topLevelStaffAuthUid.toString().isNotEmpty &&
        topLevelStaffAuthUid.toString() == staffUid) {
      return true;
    }

    // Check services array for multi-service bookings
    if (data['services'] is List) {
      final list = data['services'] as List;
      for (final item in list) {
        if (item is Map) {
          // Check staffId in service
          if (item['staffId'] != null) {
            final sid = item['staffId'].toString();
            if (sid.isNotEmpty && sid == staffUid) {
              return true;
            }
          }
          // Check staffAuthUid in service (for staff created bookings)
          if (item['staffAuthUid'] != null) {
            final authUid = item['staffAuthUid'].toString();
            if (authUid.isNotEmpty && authUid == staffUid) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  String _extractStaffId(Map<String, dynamic> data) {
    final topLevelStaff = data['staffId'];
    if (topLevelStaff != null && topLevelStaff.toString().isNotEmpty) {
      return topLevelStaff.toString();
    }
    if (data['services'] is List) {
      final list = data['services'] as List;
      for (final item in list) {
        if (item is Map && item['staffId'] != null) {
          final sid = item['staffId'].toString();
          if (sid.isNotEmpty) {
            return sid;
          }
        }
      }
    }
    return '';
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month + offset, 1);
    });
    _rebuildScheduleFromBookings();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole || _isLoadingBookings) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(color: AppConfig.primary),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildMonthSelector(),
          const SizedBox(height: 24),
          _buildSelectedDayHeader(),
          const SizedBox(height: 24),
          _buildAppointmentsList(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final bool isBranchAdmin = _currentUserRole == 'branch_admin';
    final bool isOwner = _currentUserRole == 'workshop_owner';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D), Color(0xFF1A1A1A)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A1A).withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.03),
              ),
            ),
          ),
          Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.15),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: const Center(
                      child: Icon(FontAwesomeIcons.calendarDays, size: 16, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOwner
                              ? 'Salon Schedule'
                              : (_isBranchView ? 'Branch Schedule' : 'My Schedule'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          DateFormat('MMMM yyyy').format(_focusedMonth),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isBranchAdmin && !isOwner) ...[
                const SizedBox(height: 14),
                _buildViewToggle(),
              ],
              if ((!_isBranchView || !isBranchAdmin) && _branchThemes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _branchThemes.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: entry.value.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return SizedBox(
      width: 300,
      child: AnimatedToggle(
        backgroundColor: AppConfig.card,
        values: const ['My Schedule', 'Branch Schedule'],
        selectedIndex: _isBranchView ? 1 : 0,
        onChanged: (index) => setState(() => _isBranchView = index == 1),
      ),
    );
  }

  // Removed manual toggle buttons as we use AnimatedToggle now


  Widget _buildMonthSelector() {
    final daysInMonth =
        DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDayOffset =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _softShadowDecoration(),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _changeMonth(-1),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(FontAwesomeIcons.chevronLeft,
                      size: 14, color: AppConfig.text),
                ),
              ),
              Column(
                children: [
                  Text(
                    DateFormat('MMMM yyyy').format(_focusedMonth),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppConfig.text),
                  ),
                  const Text(
                    'Select a date to view details',
                    style: TextStyle(fontSize: 12, color: AppConfig.muted),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _changeMonth(1),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(FontAwesomeIcons.chevronRight,
                      size: 14, color: AppConfig.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map((d) => SizedBox(
                      width: 35,
                      child: Text(d,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppConfig.muted)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: daysInMonth + firstDayOffset,
            itemBuilder: (context, index) {
              if (index < firstDayOffset) return const SizedBox();
              final day = index - firstDayOffset + 1;
              final currentDt =
                  DateTime(_focusedMonth.year, _focusedMonth.month, day);
              final today = DateTime.now();
              final todayStart = DateTime(today.year, today.month, today.day);
              final isPastDate = currentDt.isBefore(todayStart);
              final isSelected = _selectedDate.year == currentDt.year &&
                  _selectedDate.month == currentDt.month &&
                  _selectedDate.day == currentDt.day;
              final dayData = _scheduleData[day];
              List<Color> branchColors = []; // List of colors for different branches
              Color? primaryBranchColor; // Primary color for border/selection
              int userBookingCount = 0;
              if (dayData != null) {
                // Filter bookings for current user based on role
                final filteredItems = dayData.items.where((appt) {
                  if (_currentUserRole == 'workshop_owner') return true;
                  if (_currentUserRole == 'branch_admin' && _isBranchView) return true;
                  return _currentUserId != null && appt.staffId == _currentUserId;
                }).toList();
                
                userBookingCount = filteredItems.length;
                
                // Collect all unique branch colors for this day
                if (userBookingCount > 0 && filteredItems.isNotEmpty) {
                  final Set<String> uniqueBranches = {};
                  for (final appt in filteredItems) {
                    if (appt.branchName != null && appt.branchName!.isNotEmpty) {
                      uniqueBranches.add(appt.branchName!);
                    }
                  }
                  
                  // If no branch names in appointments, try dayData.branch
                  if (uniqueBranches.isEmpty && dayData.branch != null && dayData.branch != 'Multiple Branches') {
                    uniqueBranches.add(dayData.branch!);
                  }
                  
                  // Get colors for each unique branch
                  for (final branchName in uniqueBranches) {
                    final branchTheme = _branchThemes[branchName];
                    if (branchTheme != null) {
                      branchColors.add(branchTheme.color);
                    } else {
                      // Fallback to primary color if branch theme not found
                      branchColors.add(AppConfig.primary);
                    }
                  }
                  
                  // Set primary color (first branch or primary)
                  if (branchColors.isNotEmpty) {
                    primaryBranchColor = branchColors.first;
                  } else {
                    primaryBranchColor = AppConfig.primary;
                  }
                }
              }
              return GestureDetector(
                onTap: isPastDate ? null : () {
                  setState(() {
                    _selectedDate = currentDt;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: isSelected && !isPastDate
                        ? const Color(0xFF1A1A1A)
                        : isPastDate
                            ? Colors.grey.shade50
                            : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected && !isPastDate
                        ? Border.all(color: const Color(0xFF1A1A1A), width: 2)
                        : Border.all(color: Colors.grey.shade300),
                    boxShadow: isSelected && !isPastDate
                        ? [
                            BoxShadow(
                                color: const Color(0xFF1A1A1A).withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 5))
                          ]
                        : null,
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontWeight: isPastDate ? FontWeight.normal : FontWeight.w700,
                            fontSize: isSelected ? 16 : 14,
                            color: isPastDate
                                ? AppConfig.muted.withOpacity(0.4)
                                : isSelected
                                    ? Colors.white
                                    : (dayData?.isOffDay == true
                                        ? AppConfig.muted.withOpacity(0.5)
                                        : AppConfig.text),
                          ),
                        ),
                      ),
                      if (dayData?.isOffDay == true)
                        const Positioned(
                          bottom: 4,
                          left: 0,
                          right: 0,
                          child: Text('OFF',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: AppConfig.muted)),
                        ),
                      // Show booking count badge for days with multiple bookings (filtered by role)
                      if (dayData != null) Builder(
                        builder: (context) {
                          final filteredCount = dayData.items.where((appt) {
                            if (_currentUserRole == 'workshop_owner') return true;
                            if (_currentUserRole == 'branch_admin' && _isBranchView) return true;
                            return _currentUserId != null && appt.staffId == _currentUserId;
                          }).length;
                          if (filteredCount > 1) {
                            return Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: primaryBranchColor ?? AppConfig.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$filteredCount',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      // Show multiple colored dots for different branches
                      if (branchColors.isNotEmpty)
                        Positioned(
                          bottom: 6,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: branchColors.map((color) {
                                return Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        )
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDayHeader() {
    final dayInt = _selectedDate.day;
    final data =
        _scheduleData[dayInt]; // Schedule generated from live bookings
    final bool isOwner = _currentUserRole == 'workshop_owner';
    
    List<Color> gradient = [Colors.grey.shade400, Colors.grey.shade300];
    String branchName = "No Schedule";
    int bookingCount = 0;
    double dayRevenue = 0;
    
    if (data != null) {
      // Filter items based on role & view mode (same logic as _buildAppointmentsList)
      final filteredItems = data.items.where((appt) {
        if (_currentUserRole == 'workshop_owner') return true;
        if (_currentUserRole == 'branch_admin' && _isBranchView) return true;
        // Staff or branch admin (My Schedule): only their own appointments
        return _currentUserId != null && appt.staffId == _currentUserId;
      }).toList();
      
      bookingCount = filteredItems.length;
      
      if (data.isOffDay) {
        branchName = "Day Off";
        gradient = [Colors.grey.shade400, Colors.grey.shade300];
      } else if (filteredItems.isNotEmpty) {
        // Get unique branch names from filtered appointments
        final branchNames = filteredItems
            .where((appt) => appt.branchName != null && appt.branchName!.isNotEmpty)
            .map((appt) => appt.branchName!)
            .toSet()
            .toList();
        
        if (branchNames.length == 1) {
          // Single branch - show branch name and use its color
          branchName = "${branchNames.first} Branch";
          final theme = _resolveBranchTheme(branchNames.first);
          gradient = theme.gradient;
        } else if (branchNames.length > 1) {
          // Multiple branches - show "Multiple Branches" but use first branch's color
          branchName = "Multiple Branches";
          final theme = _resolveBranchTheme(branchNames.first);
          gradient = theme.gradient;
        } else {
          // No branch info - use default
          branchName = "Salon";
          gradient = [AppConfig.primary, AppConfig.accent];
        }
      } else {
        // No bookings but not an off day
        branchName = "No Bookings";
        gradient = [Colors.grey.shade400, Colors.grey.shade300];
      }
      
      // Calculate day's total revenue for filtered items (only completed bookings)
      for (final appt in filteredItems) {
        // Only count completed bookings for revenue
        final status = (appt.status ?? '').toString().toLowerCase();
        if (status == 'completed') {
          dayRevenue += appt.price;
        }
      }
    }
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE, MMMM d').format(_selectedDate),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(FontAwesomeIcons.locationDot,
                        size: 12, color: Colors.white70),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        branchName,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // Show booking count and revenue for owners
                if (isOwner && bookingCount > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FontAwesomeIcons.calendarCheck,
                                size: 10, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              '$bookingCount booking${bookingCount > 1 ? 's' : ''}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      if (dayRevenue > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(FontAwesomeIcons.dollarSign,
                                  size: 10, color: Colors.white),
                              const SizedBox(width: 2),
                              Text(
                                'AU\$${dayRevenue.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: bookingCount > 0
                  ? Text(
                      '$bookingCount',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(FontAwesomeIcons.calendarDay,
                      color: Colors.white, size: 24),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAppointmentsList() {
    final dayInt = _selectedDate.day;
    final data = _scheduleData[dayInt];
    if (data == null || (data.items.isEmpty && !data.isOffDay)) {
      return _emptyState(
          FontAwesomeIcons.calendarXmark, "No appointments scheduled.");
    }
    if (data.isOffDay) {
      return _emptyState(FontAwesomeIcons.mugHot, "Enjoy your day off!");
    }

    // Filter items based on role & view mode
    final filteredItems = data.items.where((appt) {
      // Salon owner: always see full salon schedule
      if (_currentUserRole == 'workshop_owner') {
        return true;
      }

      // Branch admin: in branch view see all, otherwise personal
      if (_currentUserRole == 'branch_admin' && _isBranchView) {
        return true; 
      }

      // Staff / default: only "my" appointments
      return _currentUserId != null && appt.staffId == _currentUserId;
    }).toList();

    if (filteredItems.isEmpty) {
       return _emptyState(
          FontAwesomeIcons.calendarXmark, "No appointments for you today.");
    }

    final bool isOwner = _currentUserRole == 'workshop_owner';
    final bool isBranchAdmin = _currentUserRole == 'branch_admin';
    final bool isStaff = _currentUserRole == 'staff';
    
    // Sort by time
    filteredItems.sort((a, b) => a.time.compareTo(b.time));
    
    // For staff: always show time slots view
    // For branch admin: My Schedule = time slots, Branch Schedule = booking list
    if (isStaff || (isBranchAdmin && !_isBranchView)) {
      return _buildTimeSlotView(filteredItems, data.branch, isBranchView: false);
    }

    return Column(
      children: filteredItems.map((appt) {
        // Use the appointment's specific branch name for its color
        final theme = _resolveBranchTheme(appt.branchName);
        
        // Dynamic status colors
        Color statusBgColor;
        Color statusTextColor;
        Color statusBorderColor;
        
        final statusLower = appt.status.toLowerCase();
        if (statusLower == 'pending' || statusLower.contains('awaiting') || statusLower.contains('partially')) {
          statusBgColor = Colors.amber.shade50;
          statusTextColor = Colors.amber.shade700;
          statusBorderColor = Colors.amber.shade200;
        } else if (statusLower == 'confirmed') {
          statusBgColor = Colors.green.shade50;
          statusTextColor = Colors.green.shade700;
          statusBorderColor = Colors.green.shade100;
        } else if (statusLower == 'completed') {
          statusBgColor = Colors.blue.shade50;
          statusTextColor = Colors.blue.shade700;
          statusBorderColor = Colors.blue.shade100;
        } else {
          statusBgColor = Colors.grey.shade50;
          statusTextColor = Colors.grey.shade700;
          statusBorderColor = Colors.grey.shade700;
        }
        
        return GestureDetector(
          onTap: () => _showBookingDetailsSheet(context, appt, theme, statusBgColor, statusTextColor, statusBorderColor),
          child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppConfig.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: -5,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                // Main content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: theme.gradient),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                    color: theme.color.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4))
                              ],
                            ),
                            child: Center(
                                child:
                                    Icon(appt.icon, color: Colors.white, size: 20)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appt.service,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppConfig.text),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (appt.branchName != null && appt.branchName!.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: theme.lightBg,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          appt.branchName!.toUpperCase(),
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: theme.color),
                                        ),
                                      ),
                                    if (appt.price > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'AU\$${appt.price.toStringAsFixed(0)}',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green.shade700),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusBgColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: statusBorderColor),
                              ),
                              child: Text(
                                _formatStatusDisplay(appt.status),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: statusTextColor),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          )
                        ],
                      ),
                      
                      // Client info section (expanded for owner and branch admin in branch view)
                      if (isOwner || (isBranchAdmin && _isBranchView)) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppConfig.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        appt.client.isNotEmpty 
                                            ? appt.client[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppConfig.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          appt.client,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppConfig.text,
                                          ),
                                        ),
                                        if (appt.phone.isNotEmpty || appt.email.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              appt.phone.isNotEmpty 
                                                  ? appt.phone 
                                                  : appt.email,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppConfig.muted,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (appt.phone.isNotEmpty)
                                    Container(
                                      width: 32,
                                      height: 32,
                                      margin: const EdgeInsets.only(left: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        FontAwesomeIcons.phone,
                                        size: 12,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                ],
                              ),
                              // Service-wise breakdown for all bookings with services
                              if (appt.services.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(FontAwesomeIcons.listCheck, 
                                              size: 12, color: theme.color),
                                          const SizedBox(width: 6),
                                          Text(
                                            appt.services.length == 1 
                                                ? 'Service Details' 
                                                : 'Services (${appt.services.length})',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: theme.color,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ...appt.services.map((svc) => Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(colors: theme.gradient),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Center(
                                                child: Icon(FontAwesomeIcons.scissors, 
                                                    color: Colors.white, size: 12),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    svc.name,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppConfig.text,
                                                    ),
                                                  ),
                                                  if (svc.staffName.isNotEmpty)
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 2),
                                                      child: Row(
                                                        children: [
                                                          Icon(FontAwesomeIcons.user, 
                                                              size: 10, color: AppConfig.muted),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            svc.staffName,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: AppConfig.muted,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  if (svc.staffName.isEmpty)
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 2),
                                                      child: Row(
                                                        children: [
                                                          Icon(FontAwesomeIcons.userSlash, 
                                                              size: 10, color: Colors.orange),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            'Unassigned',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Colors.orange.shade700,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  'AU\$${svc.price.toStringAsFixed(0)}',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green.shade700,
                                                  ),
                                                ),
                                                if (svc.duration > 0)
                                                  Text(
                                                    '${svc.duration} min',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: AppConfig.muted,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      )),
                                    ],
                                  ),
                                ),
                              ] else if (appt.staffName.isNotEmpty) ...[
                                // Fallback for bookings without services array - just show staff
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        FontAwesomeIcons.userCheck,
                                        size: 11,
                                        color: theme.color,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        appt.staffName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppConfig.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Bottom info bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppConfig.border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _infoItem(FontAwesomeIcons.clock, appt.time, theme.color),
                      // Show staff member who is assigned
                      if (appt.staffName.isNotEmpty)
                        _infoItem(FontAwesomeIcons.scissors, appt.staffName, theme.color)
                      else
                        _infoItem(FontAwesomeIcons.userSlash, 'Unassigned', Colors.orange),
                      _infoItem(FontAwesomeIcons.locationDot, appt.room, theme.color),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
        );
      }).toList(),
    );
  }

  // Helper to parse time string (handles both "14:00" and "2:00 PM" formats)
  int _parseTimeToMinutes(String timeStr) {
    if (timeStr.isEmpty) return 0;
    
    // Try parsing as 12-hour format first (e.g., "2:00 PM")
    try {
      final t = DateFormat('h:mm a').parse(timeStr);
      return t.hour * 60 + t.minute;
    } catch (_) {}
    
    // Try parsing as 24-hour format (e.g., "14:00")
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      }
    } catch (_) {}
    
    return 0;
  }

  int _getAppointmentDurationMinutes(Appointment appt) {
    if (appt.services.isNotEmpty) {
      final d = appt.services.first.duration;
      if (d > 0) return d;
    }
    if (appt.totalDuration > 0) return appt.totalDuration;
    return 60;
  }

  /// Returns appointments that overlap with the given slot (slot in [start, end)).
  List<Appointment> _getOverlappingAppointmentsAtSlot(List<Appointment> appointments, int slotMinutes) {
    final overlapping = <Appointment>[];
    for (final appt in appointments) {
      final startMinutes = _parseTimeToMinutes(appt.time);
      final durationMinutes = _getAppointmentDurationMinutes(appt);
      final endMinutes = startMinutes + durationMinutes;
      if (startMinutes <= slotMinutes && slotMinutes < endMinutes) {
        overlapping.add(appt);
      }
    }
    overlapping.sort((a, b) => _parseTimeToMinutes(a.time).compareTo(_parseTimeToMinutes(b.time)));
    return overlapping;
  }
  
  Widget _buildTimeSlotView(List<Appointment> appointments, String? branchName, {bool isBranchView = false}) {
    // Use first appointment's branch color for header, or fallback to day's branch
    final firstApptBranch = appointments.isNotEmpty ? appointments.first.branchName : null;
    final theme = _resolveBranchTheme(firstApptBranch ?? branchName);
    
    // Generate time slots from 9 AM to 6 PM (in minutes from midnight) - 15 min intervals
    final List<int> timeSlotMinutes = [];
    for (int hour = 9; hour <= 18; hour++) {
      timeSlotMinutes.add(hour * 60); // :00
      if (hour < 18) {
        timeSlotMinutes.add(hour * 60 + 15); // :15
        timeSlotMinutes.add(hour * 60 + 30); // :30
        timeSlotMinutes.add(hour * 60 + 45); // :45
      }
    }
    
    // For each slot, find all overlapping appointments (dynamic column splitting)
    
    return Container(
      decoration: BoxDecoration(
        color: AppConfig.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: theme.gradient),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isBranchView ? FontAwesomeIcons.building : FontAwesomeIcons.clock, 
                  color: Colors.white, 
                  size: 18
                ),
                const SizedBox(width: 10),
                Text(
                  isBranchView ? 'Branch Schedule' : 'My Daily Schedule',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${appointments.length} booking${appointments.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Time slots - each slot shows all overlapping appointments side-by-side
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: timeSlotMinutes.length,
            itemBuilder: (context, index) {
              final slotMinutes = timeSlotMinutes[index];
              final slotHour = slotMinutes ~/ 60;
              final slotMinute = slotMinutes % 60;
              final timeSlotStr = '${slotHour.toString().padLeft(2, '0')}:${slotMinute.toString().padLeft(2, '0')}';
              final overlapping = _getOverlappingAppointmentsAtSlot(appointments, slotMinutes);
              final isHourMark = slotMinute == 0;
              
              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isHourMark ? Colors.grey.shade300 : Colors.grey.shade200,
                      width: isHourMark ? 1 : 0.5,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time column
                    Container(
                      width: 60,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isHourMark ? Colors.grey.shade50 : Colors.transparent,
                        border: const Border(
                          right: BorderSide(color: AppConfig.border, width: 1),
                        ),
                      ),
                      child: Text(
                        timeSlotStr,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isHourMark ? FontWeight.w600 : FontWeight.normal,
                          color: isHourMark ? AppConfig.text : AppConfig.muted,
                        ),
                      ),
                    ),
                    // Appointment slot - dynamic column splitting for overlaps
                    Expanded(
                      child: overlapping.isEmpty
                          ? Container(
                              height: 44,
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.grey.shade700,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Available',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),
                            )
                          : overlapping.length > 4
                              ? _buildOverflowSlot(overlapping)
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: overlapping.asMap().entries.map((entry) {
                                    final i = entry.key;
                                    final appt = entry.value;
                                    final n = overlapping.length;
                                    return Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          left: i == 0 ? 4 : 2,
                                          right: i == n - 1 ? 4 : 2,
                                          top: 4,
                                          bottom: 4,
                                        ),
                                        child: _buildTimeSlotAppointmentCompact(
                                          appt,
                                          _resolveBranchTheme(appt.branchName),
                                          slotMinutes: slotMinutes,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildTimeSlotAppointment(Appointment appt, BranchTheme theme, {double? fixedHeight}) {
    // Calculate height based on duration - minimum 52 pixels per slot (15-min intervals)
    double slotHeight;
    if (fixedHeight != null) {
      slotHeight = fixedHeight;
    } else {
      int durationMinutes = 60;
      if (appt.services.isNotEmpty) {
        durationMinutes = appt.services.first.duration;
        if (durationMinutes <= 0) durationMinutes = 60;
      }
      slotHeight = math.max((durationMinutes / 15) * 52.0, 52.0);
    }
    
    // Status colors
    Color statusColor;
    Color statusBgColor;
    Color statusTextColor;
    Color statusBorderColor;
    final statusLower = appt.status.toLowerCase();
    if (statusLower == 'confirmed') {
      statusColor = Colors.green;
      statusBgColor = Colors.green.shade50;
      statusTextColor = Colors.green.shade700;
      statusBorderColor = Colors.green.shade100;
    } else if (statusLower == 'pending' || statusLower.contains('awaiting') || statusLower.contains('partially')) {
      statusColor = Colors.amber;
      statusBgColor = Colors.amber.shade50;
      statusTextColor = Colors.amber.shade700;
      statusBorderColor = Colors.amber.shade200;
    } else if (statusLower == 'completed') {
      statusColor = Colors.blue;
      statusBgColor = Colors.blue.shade50;
      statusTextColor = Colors.blue.shade700;
      statusBorderColor = Colors.blue.shade100;
    } else {
      statusColor = Colors.grey;
      statusBgColor = Colors.grey.shade50;
      statusTextColor = Colors.grey.shade700;
      statusBorderColor = Colors.grey.shade200;
    }
    
    return GestureDetector(
      onTap: () => _showBookingDetailsSheet(context, appt, theme, statusBgColor, statusTextColor, statusBorderColor),
      child: Container(
      height: slotHeight,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.lightBg, theme.color.withOpacity(0.15)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: theme.color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: theme.gradient),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(appt.icon, color: Colors.white, size: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appt.service,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppConfig.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  appt.client,
                  style: TextStyle(fontSize: 10, color: AppConfig.muted),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Price
          if (appt.price > 0)
            Text(
              'AU\$${appt.price.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
          const SizedBox(width: 6),
          // Status dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  /// Compact card for overlapping slots - 52px height, tooltip on hover for readability
  Widget _buildTimeSlotAppointmentCompact(Appointment appt, BranchTheme theme, {required int slotMinutes}) {
    final statusLower = appt.status.toLowerCase();
    Color statusBgColor;
    Color statusTextColor;
    Color statusBorderColor;
    if (statusLower == 'confirmed') {
      statusBgColor = Colors.green.shade50;
      statusTextColor = Colors.green.shade700;
      statusBorderColor = Colors.green.shade100;
    } else if (statusLower == 'pending' || statusLower.contains('awaiting') || statusLower.contains('partially')) {
      statusBgColor = Colors.amber.shade50;
      statusTextColor = Colors.amber.shade700;
      statusBorderColor = Colors.amber.shade200;
    } else if (statusLower == 'completed') {
      statusBgColor = Colors.blue.shade50;
      statusTextColor = Colors.blue.shade700;
      statusBorderColor = Colors.blue.shade100;
    } else {
      statusBgColor = Colors.grey.shade50;
      statusTextColor = Colors.grey.shade700;
      statusBorderColor = Colors.grey.shade200;
    }
    final tooltipMsg = '${appt.service} - ${appt.client}${appt.price > 0 ? ' (AU\$${appt.price.toStringAsFixed(0)})' : ''}\nTap for full details';
    return Tooltip(
      message: tooltipMsg,
      preferBelow: false,
      child: GestureDetector(
        onTap: () => _showBookingDetailsSheet(context, appt, theme, statusBgColor, statusTextColor, statusBorderColor),
        child: _buildTimeSlotAppointment(appt, theme, fixedHeight: 52.0),
      ),
    );
  }

  /// When >4 overlaps, show a "+X more" pill that opens a modal
  Widget _buildOverflowSlot(List<Appointment> overlapping) {
    return GestureDetector(
      onTap: () => _showOverflowBookingsModal(context, overlapping),
      child: Container(
        height: 52,
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FontAwesomeIcons.layerGroup, size: 16, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            Text(
              '+${overlapping.length} bookings',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade800),
            ),
          ],
        ),
      ),
    );
  }

  void _showOverflowBookingsModal(BuildContext context, List<Appointment> overlapping) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${overlapping.length} overlapping bookings',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: overlapping.length,
                itemBuilder: (_, i) {
                  final appt = overlapping[i];
                  final theme = _resolveBranchTheme(appt.branchName);
                  final statusLower = appt.status.toLowerCase();
                  Color statusBgColor = Colors.grey.shade50;
                  Color statusTextColor = Colors.grey.shade700;
                  Color statusBorderColor = Colors.grey.shade200;
                  if (statusLower == 'confirmed') {
                    statusBgColor = Colors.green.shade50;
                    statusTextColor = Colors.green.shade700;
                    statusBorderColor = Colors.green.shade100;
                  } else if (statusLower == 'pending' || statusLower.contains('awaiting') || statusLower.contains('partially')) {
                    statusBgColor = Colors.amber.shade50;
                    statusTextColor = Colors.amber.shade700;
                    statusBorderColor = Colors.amber.shade200;
                  } else if (statusLower == 'completed') {
                    statusBgColor = Colors.blue.shade50;
                    statusTextColor = Colors.blue.shade700;
                    statusBorderColor = Colors.blue.shade100;
                  }
                  return ListTile(
                    title: Text(appt.service),
                    subtitle: Text('${appt.client} • ${appt.time}'),
                    trailing: appt.price > 0 ? Text('AU\$${appt.price.toStringAsFixed(0)}') : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showBookingDetailsSheet(context, appt, theme, statusBgColor, statusTextColor, statusBorderColor);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppConfig.muted.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(color: AppConfig.muted)),
          ],
        ),
      ),
    );
  }

  void _showBookingDetailsSheet(
    BuildContext context,
    Appointment appt,
    BranchTheme theme,
    Color statusBgColor,
    Color statusTextColor,
    Color statusBorderColor,
  ) {
    // Format the date for display
    String formattedDate = appt.date;
    try {
      final parsed = DateTime.parse(appt.date);
      formattedDate = DateFormat('EEE, dd MMM yyyy').format(parsed);
    } catch (_) {}

    // Format pickup time
    String formattedPickup = '';
    if (appt.pickupTime.isNotEmpty) {
      try {
        final t = DateFormat('HH:mm').parse(appt.pickupTime);
        formattedPickup = DateFormat('h:mm a').format(t);
      } catch (_) {
        formattedPickup = appt.pickupTime;
      }
    }

    // Calculate total duration from services
    int totalDuration = appt.totalDuration;
    if (totalDuration == 0 && appt.services.isNotEmpty) {
      totalDuration = appt.services.fold(0, (sum, svc) => sum + svc.duration);
    }

    // Calculate total price from services
    double totalPrice = appt.price;
    if (appt.services.length > 1) {
      totalPrice = appt.services.fold(0.0, (sum, svc) => sum + svc.price);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  children: [
                    // Header: service name + status
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: theme.gradient),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: theme.color.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(appt.icon, color: Colors.white, size: 22),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appt.service,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppConfig.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusBgColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: statusBorderColor),
                                ),
                                child: Text(
                                  _formatStatusDisplay(appt.status),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: statusTextColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Booking code
                    if (appt.bookingCode.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.lightBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.color.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(FontAwesomeIcons.hashtag, size: 14, color: theme.color),
                            const SizedBox(width: 10),
                            Text(
                              'Booking Code',
                              style: TextStyle(fontSize: 12, color: AppConfig.muted),
                            ),
                            const Spacer(),
                            Text(
                              appt.bookingCode,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: theme.color,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Date, time, duration row
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _detailRow(FontAwesomeIcons.calendarDay, 'Date', formattedDate, theme.color),
                          Divider(color: Colors.grey.shade200, height: 20),
                          _detailRow(FontAwesomeIcons.clock, 'Time', appt.time, theme.color),
                          if (formattedPickup.isNotEmpty) ...[
                            Divider(color: Colors.grey.shade200, height: 20),
                            _detailRow(FontAwesomeIcons.truckPickup, 'Pick-up Time', formattedPickup, theme.color),
                          ],
                          if (totalDuration > 0) ...[
                            Divider(color: Colors.grey.shade200, height: 20),
                            _detailRow(FontAwesomeIcons.hourglassHalf, 'Duration', '$totalDuration min', theme.color),
                          ],
                          Divider(color: Colors.grey.shade200, height: 20),
                          _detailRow(FontAwesomeIcons.locationDot, 'Branch', appt.room, theme.color),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Client details
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(FontAwesomeIcons.userLarge, size: 13, color: theme.color),
                              const SizedBox(width: 8),
                              const Text(
                                'Customer Details',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppConfig.text,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: theme.color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    appt.client.isNotEmpty ? appt.client[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: theme.color,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      appt.client,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppConfig.text,
                                      ),
                                    ),
                                    if (appt.phone.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Row(
                                          children: [
                                            Icon(FontAwesomeIcons.phone, size: 10, color: AppConfig.muted),
                                            const SizedBox(width: 6),
                                            Text(appt.phone, style: TextStyle(fontSize: 12, color: AppConfig.muted)),
                                          ],
                                        ),
                                      ),
                                    if (appt.email.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Row(
                                          children: [
                                            Icon(FontAwesomeIcons.envelope, size: 10, color: AppConfig.muted),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(appt.email, style: TextStyle(fontSize: 12, color: AppConfig.muted), overflow: TextOverflow.ellipsis),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Staff & Services
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(FontAwesomeIcons.scissors, size: 13, color: theme.color),
                              const SizedBox(width: 8),
                              Text(
                                appt.services.length > 1 ? 'Services (${appt.services.length})' : 'Service Details',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppConfig.text,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (appt.services.isNotEmpty)
                            ...appt.services.map((svc) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: theme.gradient),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Center(
                                      child: Icon(FontAwesomeIcons.scissors, color: Colors.white, size: 14),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          svc.name,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppConfig.text,
                                          ),
                                        ),
                                        if (svc.staffName.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Row(
                                              children: [
                                                Icon(FontAwesomeIcons.user, size: 10, color: AppConfig.muted),
                                                const SizedBox(width: 5),
                                                Text(svc.staffName, style: TextStyle(fontSize: 12, color: AppConfig.muted)),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (svc.price > 0)
                                        Text(
                                          'AU\$${svc.price.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      if (svc.duration > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            '${svc.duration} min',
                                            style: TextStyle(fontSize: 11, color: AppConfig.muted),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ))
                          else ...[
                            // Fallback for legacy bookings without services array
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: theme.gradient),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Icon(appt.icon, color: Colors.white, size: 14),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(appt.service, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppConfig.text)),
                                      if (appt.staffName.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Row(
                                            children: [
                                              Icon(FontAwesomeIcons.user, size: 10, color: AppConfig.muted),
                                              const SizedBox(width: 5),
                                              Text(appt.staffName, style: TextStyle(fontSize: 12, color: AppConfig.muted)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (appt.price > 0)
                                  Text(
                                    'AU\$${appt.price.toStringAsFixed(0)}',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Total price
                    if (totalPrice > 0 && appt.services.length > 1) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(FontAwesomeIcons.receipt, size: 14, color: Colors.green.shade700),
                                const SizedBox(width: 10),
                                Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                              ],
                            ),
                            Text(
                              'AU\$${totalPrice.toStringAsFixed(0)}',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.green.shade700),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ─── Task Progress Section ─────────────────────
                    if (appt.tasks.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildTaskProgressSection(appt, theme),
                    ],

                    // Notes
                    if (appt.notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(FontAwesomeIcons.noteSticky, size: 13, color: Colors.amber.shade700),
                                const SizedBox(width: 8),
                                Text('Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.amber.shade700)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              appt.notes,
                              style: TextStyle(fontSize: 13, color: Colors.amber.shade900, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Created at
                    if (appt.createdAt.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Booked on ${appt.createdAt}',
                          style: TextStyle(fontSize: 11, color: AppConfig.muted),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskProgressSection(Appointment appt, BranchTheme theme) {
    final doneCount = appt.tasks.where((t) => t.done).length;
    final totalCount = appt.tasks.length;
    final pct = appt.taskProgress > 0 ? appt.taskProgress : (totalCount > 0 ? ((doneCount / totalCount) * 100).round() : 0);
    final isComplete = pct == 100;

    // Colors based on progress
    final Color progressColor = isComplete
        ? const Color(0xFF10B981) // emerald
        : pct > 50
            ? const Color(0xFFF59E0B) // amber
            : const Color(0xFF3B82F6); // blue
    final Color progressBg = isComplete
        ? const Color(0xFFD1FAE5)
        : pct > 50
            ? const Color(0xFFFEF3C7)
            : const Color(0xFFDBEAFE);
    final Color cardBg = isComplete
        ? const Color(0xFFF0FDF4) // emerald-50
        : const Color(0xFFFAFAFA); // neutral-50

    return StatefulBuilder(
      builder: (context, setLocalState) {
        // Track expand state locally
        return _TaskProgressWidget(
          appt: appt,
          theme: theme,
          doneCount: doneCount,
          totalCount: totalCount,
          pct: pct,
          isComplete: isComplete,
          progressColor: progressColor,
          progressBg: progressBg,
          cardBg: cardBg,
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Icon(icon, size: 13, color: iconColor)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(fontSize: 12, color: AppConfig.muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppConfig.text),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(fontSize: 13, color: AppConfig.muted)),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppConfig.muted)),
      ],
    );
  }

  Widget _iconButton(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppConfig.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: Icon(icon, size: 16, color: AppConfig.text)),
    );
  }

  BoxDecoration _softShadowDecoration() {
    return BoxDecoration(
      color: AppConfig.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 25,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  BranchTheme _resolveBranchTheme(String? branchName) {
    // First check dynamic branch themes from database
    if (branchName != null && _branchThemes.containsKey(branchName)) {
      return _branchThemes[branchName]!;
    }
    // Fallback to hardcoded branches if not found in database
    if (branchName != null && AppConfig.branches.containsKey(branchName)) {
      return AppConfig.branches[branchName]!;
    }
    // Fallback theme if branch is unknown or represents multiple branches
    return BranchTheme(
      color: AppConfig.primary,
      lightBg: AppConfig.background,
      gradient: const [AppConfig.primary, AppConfig.accent],
    );
  }
}

// ─── Task Progress Widget (Stateful for expand/collapse) ─────────────
class _TaskProgressWidget extends StatefulWidget {
  final Appointment appt;
  final BranchTheme theme;
  final int doneCount;
  final int totalCount;
  final int pct;
  final bool isComplete;
  final Color progressColor;
  final Color progressBg;
  final Color cardBg;

  const _TaskProgressWidget({
    required this.appt,
    required this.theme,
    required this.doneCount,
    required this.totalCount,
    required this.pct,
    required this.isComplete,
    required this.progressColor,
    required this.progressBg,
    required this.cardBg,
  });

  @override
  State<_TaskProgressWidget> createState() => _TaskProgressWidgetState();
}

class _TaskProgressWidgetState extends State<_TaskProgressWidget>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appt = widget.appt;
    final pct = widget.pct;
    final isComplete = widget.isComplete;
    final doneCount = widget.doneCount;
    final totalCount = widget.totalCount;
    final progressColor = widget.progressColor;
    final progressBg = widget.progressBg;
    final theme = widget.theme;

    return Column(
      children: [
        // ─── Creative Progress Card ──────────────────────
        GestureDetector(
          onTap: _toggle,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isComplete
                    ? [const Color(0xFFF0FDF4), const Color(0xFFECFDF5), const Color(0xFFF0FDFA)]
                    : [const Color(0xFFFAFAFA), Colors.white, const Color(0xFFFAFAFA)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isComplete
                    ? const Color(0xFF10B981).withOpacity(0.3)
                    : Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isComplete ? const Color(0xFF10B981) : Colors.black).withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header row
                Row(
                  children: [
                    // Icon badge
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isComplete ? const Color(0xFF10B981) : const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: (isComplete ? const Color(0xFF10B981) : const Color(0xFF1A1A1A))
                                .withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          isComplete ? FontAwesomeIcons.checkDouble : FontAwesomeIcons.listCheck,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title & subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Service Progress',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppConfig.text,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            isComplete
                                ? 'All tasks completed'
                                : '${totalCount - doneCount} task${totalCount - doneCount != 1 ? "s" : ""} remaining',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppConfig.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Circular percentage indicator
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CustomPaint(
                        painter: _CircularProgressPainter(
                          progress: pct / 100.0,
                          progressColor: progressColor,
                          bgColor: progressBg,
                          strokeWidth: 3.5,
                        ),
                        child: Center(
                          child: Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isComplete ? const Color(0xFF059669) : const Color(0xFF374151),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Chevron
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        FontAwesomeIcons.chevronDown,
                        size: 11,
                        color: AppConfig.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Segmented progress bar
                Row(
                  children: List.generate(totalCount, (i) {
                    final task = appt.tasks[i];
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i < totalCount - 1 ? 3 : 0),
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: task.done
                              ? LinearGradient(
                                  colors: isComplete
                                      ? [const Color(0xFF34D399), const Color(0xFF10B981)]
                                      : [const Color(0xFFFBBF24), const Color(0xFFF59E0B)],
                                )
                              : null,
                          color: task.done ? null : Colors.grey.shade200,
                          boxShadow: task.done
                              ? [
                                  BoxShadow(
                                    color: progressColor.withOpacity(0.25),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  )
                                ]
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),

                // Bottom labels
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$doneCount',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isComplete ? const Color(0xFF059669) : AppConfig.text,
                            ),
                          ),
                          TextSpan(
                            text: '/$totalCount tasks',
                            style: TextStyle(fontSize: 11, color: AppConfig.muted),
                          ),
                        ],
                      ),
                    ),
                    if (isComplete)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FontAwesomeIcons.star, size: 9, color: const Color(0xFF059669)),
                            const SizedBox(width: 4),
                            const Text(
                              'Complete',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        'Tap to view details',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppConfig.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ─── Expanded Task List ──────────────────────
        SizeTransition(
          sizeFactor: _expandAnimation,
          child: Column(
            children: [
              const SizedBox(height: 10),
              ...List.generate(appt.tasks.length, (tIdx) {
                final task = appt.tasks[tIdx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: task.done ? const Color(0xFFF0FDF4) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: task.done
                          ? const Color(0xFF10B981).withOpacity(0.25)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Checkbox circle
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: task.done ? const Color(0xFF10B981) : Colors.grey.shade200,
                          shape: BoxShape.circle,
                          boxShadow: task.done
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: Center(
                          child: task.done
                              ? const Icon(FontAwesomeIcons.check, size: 10, color: Colors.white)
                              : Text(
                                  '${tIdx + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppConfig.muted,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Task content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    task.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: task.done ? const Color(0xFF065F46) : AppConfig.text,
                                    ),
                                  ),
                                ),
                                if (task.done)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Done',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF059669),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (task.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                task.description,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppConfig.muted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            if (task.serviceName.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Icon(FontAwesomeIcons.wrench, size: 9, color: AppConfig.muted),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      task.serviceName,
                                      style: TextStyle(fontSize: 10, color: AppConfig.muted),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            // Staff note
                            if (task.staffNote.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFDBEAFE)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(FontAwesomeIcons.comment, size: 10, color: const Color(0xFF3B82F6)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            task.staffNote,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF1D4ED8), height: 1.3),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (task.completedByStaffName.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '— ${task.completedByStaffName}',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF60A5FA)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // Final Submission
              if (appt.finalSubmission != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6366F1),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(FontAwesomeIcons.flagCheckered, size: 10, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Final Submission',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4338CA),
                            ),
                          ),
                          const Spacer(),
                          if ((appt.finalSubmission!['submittedByStaffName'] ?? '').toString().isNotEmpty)
                            Text(
                              'by ${appt.finalSubmission!['submittedByStaffName']}',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF818CF8)),
                            ),
                        ],
                      ),
                      if ((appt.finalSubmission!['description'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          appt.finalSubmission!['description'].toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF312E81),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Circular Progress Painter ──────────────────────────────────
class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color progressColor;
  final Color bgColor;
  final double strokeWidth;

  _CircularProgressPainter({
    required this.progress,
    required this.progressColor,
    required this.bgColor,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor;
  }
}
