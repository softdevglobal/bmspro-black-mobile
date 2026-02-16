import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/animated_toggle.dart';
import '../services/staff_check_in_service.dart';

// Data class for weekly hours
class WeeklyHoursData {
  final DateTime weekStart; // Monday of the week
  final DateTime weekEnd; // Sunday of the week
  final int totalSeconds;
  final Map<String, int> dailyHours; // Day name -> seconds

  WeeklyHoursData({
    required this.weekStart,
    required this.weekEnd,
    required this.totalSeconds,
    required this.dailyHours,
  });

  String get weekLabel {
    final startFormat = DateFormat('MMM d');
    final endFormat = DateFormat('MMM d, yyyy');
    if (weekStart.year == weekEnd.year && weekStart.month == weekEnd.month) {
      return '${startFormat.format(weekStart)} - ${endFormat.format(weekEnd)}';
    }
    return '${startFormat.format(weekStart)} - ${endFormat.format(weekEnd)}';
  }

  String get shortLabel {
    final now = DateTime.now();
    final weekStartOnly = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final nowStartOnly = DateTime(now.year, now.month, now.day);
    final daysDiff = nowStartOnly.difference(weekStartOnly).inDays;
    
    if (daysDiff < 7) {
      return 'This Week';
    } else if (daysDiff < 14) {
      return 'Last Week';
    } else {
      final weekNum = (daysDiff ~/ 7);
      return '$weekNum weeks ago';
    }
  }
}

class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _selectedTab = 'day'; // 'day', 'week', 'month'
  
  // Role & Toggle state
  String? _currentUserRole;
  String? _currentUserName;
  bool _isBranchView = false; // false = My Summary, true = Branch Summary
  bool _isLoadingRole = true;
  Map<String, int> _dailyWorkingHours = {}; // Day-wise working hours in seconds (current week)
  int _totalWeeklyHours = 0; // Total weekly hours in seconds (current week)
  
  // 4 weeks of data
  List<WeeklyHoursData> _weeklyHoursData = []; // 4 weeks: [current, week-1, week-2, week-3]
  int _selectedWeekIndex = 0; // 0 = current week, 1 = last week, etc.

  // Real data for summary
  int _completedServices = 0;
  double _revenue = 0;
  int _totalBookings = 0;
  String _rating = '—';
  bool _isLoadingData = true;
  String? _ownerUid;
  int _currentTabWorkingHours = 0; // Working hours for current tab (day/week/month)

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
    _loadWeeklyWorkingHours();
    _loadSummaryData();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (mounted && doc.exists) {
          final userData = doc.data();
          setState(() {
            _currentUserRole = userData?['role'];
            _currentUserName = userData?['displayName'] ?? userData?['name'] ?? 'Staff';
            _ownerUid = userData?['ownerUid']?.toString() ?? user.uid;
            _isLoadingRole = false;
          });
          // Reload summary data when role is fetched
          if (_ownerUid != null) {
            _loadSummaryData();
          }
        }
      } else {
         if (mounted) setState(() => _isLoadingRole = false);
      }
    } catch (e) {
      debugPrint('Error fetching role: $e');
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  Future<void> _loadWeeklyWorkingHours() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _calculateWeeklyWorkingHours(user.uid);
      }
    } catch (e) {
      debugPrint('Error loading weekly working hours: $e');
    }
  }

  // Calculate working hours for a specific date range
  Future<int> _calculateWorkingHoursForRange(DateTime startDate, DateTime endDate, String userId) async {
    try {
      // Query all check-ins for the user
      QuerySnapshot checkInsQuery;
      try {
        checkInsQuery = await FirebaseFirestore.instance
            .collection('staff_check_ins')
            .where('staffId', isEqualTo: userId)
            .get();
      } catch (e) {
        checkInsQuery = await FirebaseFirestore.instance
            .collection('staff_check_ins')
            .where('staffAuthUid', isEqualTo: userId)
            .get();
      }

      int totalSeconds = 0;
      final startMs = startDate.millisecondsSinceEpoch;
      final endMs = endDate.millisecondsSinceEpoch;

      for (final doc in checkInsQuery.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final docStaffId = data['staffId']?.toString();
          final docStaffAuthUid = data['staffAuthUid']?.toString();
          if (docStaffId != userId && docStaffAuthUid != userId) {
            continue;
          }

          final checkIn = StaffCheckInRecord.fromFirestore(doc);
          final checkInTimeMs = checkIn.checkInTime.millisecondsSinceEpoch;

          // Check if check-in falls within the date range
          if (checkInTimeMs >= startMs && checkInTimeMs <= endMs) {
            totalSeconds += checkIn.workingSeconds;
          }
        } catch (e) {
          debugPrint('Error processing check-in ${doc.id}: $e');
          continue;
        }
      }

      return totalSeconds;
    } catch (e) {
      debugPrint('Error calculating working hours for range: $e');
      return 0;
    }
  }

  Future<void> _loadSummaryData() async {
    if (_ownerUid == null || _currentUserRole == null) return;
    
    setState(() => _isLoadingData = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoadingData = false);
        return;
      }

      // Determine date range based on selected tab
      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate;
      
      if (_selectedTab == 'day') {
        // Today
        startDate = DateTime(now.year, now.month, now.day, 0, 0, 0);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        debugPrint('Day view - Date range: ${startDate.toString()} to ${endDate.toString()}');
      } else if (_selectedTab == 'week') {
        // Current week (Monday to Sunday)
        final weekStart = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(weekStart.year, weekStart.month, weekStart.day, 0, 0, 0);
        endDate = startDate.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
        debugPrint('Week view - Date range: ${startDate.toString()} to ${endDate.toString()}');
      } else {
        // Current month
        startDate = DateTime(now.year, now.month, 1, 0, 0, 0);
        endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        debugPrint('Month view - Date range: ${startDate.toString()} to ${endDate.toString()}');
      }

      // Query bookings for the date range
      final bookingsQuery = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerUid', isEqualTo: _ownerUid)
          .get();

      int completedServices = 0;
      double revenue = 0;
      int totalBookings = 0;
      int completedBookings = 0;

      int bookingsChecked = 0;
      int bookingsInRange = 0;
      
      for (final doc in bookingsQuery.docs) {
        bookingsChecked++;
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        
        // Parse booking date - handle multiple formats
        DateTime? bookingDate;
        try {
          // First, try to get date as Timestamp (Firestore format)
          if (data['date'] is Timestamp) {
            final timestamp = data['date'] as Timestamp;
            bookingDate = timestamp.toDate();
          } else if (data['dateTimeUtc'] is Timestamp) {
            // Try dateTimeUtc field if available (Timestamp)
            final timestamp = data['dateTimeUtc'] as Timestamp;
            bookingDate = timestamp.toDate();
          } else if (data['dateTimeUtc'] != null && data['dateTimeUtc'].toString().isNotEmpty) {
            // Try dateTimeUtc as string (ISO format)
            try {
              bookingDate = DateTime.parse(data['dateTimeUtc'].toString());
            } catch (e) {
              // Fall through to date field
            }
          }
          
          // If still no date, try parsing date field as string
          if (bookingDate == null) {
            final bookingDateStr = (data['date'] ?? '').toString();
            if (bookingDateStr.isNotEmpty) {
              // Try parsing as YYYY-MM-DD format
              final parts = bookingDateStr.split('-');
              if (parts.length == 3) {
                bookingDate = DateTime(
                  int.parse(parts[0]),
                  int.parse(parts[1]),
                  int.parse(parts[2]),
                );
              } else {
                // Try parsing as ISO format or other formats
                bookingDate = DateTime.parse(bookingDateStr);
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing booking date from doc ${doc.id}: $e');
          continue; // Skip bookings with invalid date
        }

        // Check if booking is within date range
        if (bookingDate == null) {
          continue; // Skip bookings without valid date
        }
        
        // Normalize dates to compare only date part (ignore time)
        final bookingDateOnly = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);
        final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
        final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
        
        // Inclusive date range check: bookingDate >= startDate && bookingDate <= endDate
        // Use compareTo for reliable date comparison
        final compareStart = bookingDateOnly.compareTo(startDateOnly);
        final compareEnd = bookingDateOnly.compareTo(endDateOnly);
        final isInRange = compareStart >= 0 && compareEnd <= 0;
        
        if (!isInRange) {
          continue; // Skip bookings outside date range
        }
        
        bookingsInRange++;

        // Check if this booking is assigned to current user (for staff)
        bool isMyBooking = false;

        if (_currentUserRole == 'staff' || _currentUserRole == 'branch_admin') {
          // Check top-level staffId
          if (data['staffId'] == user.uid || data['staffAuthUid'] == user.uid) {
            isMyBooking = true;
          }

          // Check services array for multi-service bookings
          if (data['services'] is List) {
            for (final service in (data['services'] as List)) {
              if (service is Map) {
                final svcStaffId = service['staffId']?.toString();
                final svcStaffAuthUid = service['staffAuthUid']?.toString();
                if (svcStaffId == user.uid || svcStaffAuthUid == user.uid) {
                  isMyBooking = true;
                  break;
                }
              }
            }
          }

          if (isMyBooking) {
            totalBookings++;
            
            // Check for completed services in multi-service bookings
            if (data['services'] is List && (data['services'] as List).isNotEmpty) {
              for (final service in (data['services'] as List)) {
                if (service is Map) {
                  final svcStaffId = service['staffId']?.toString();
                  final svcStaffAuthUid = service['staffAuthUid']?.toString();
                  if (svcStaffId == user.uid || svcStaffAuthUid == user.uid) {
                    final completionStatus = (service['completionStatus'] ?? '').toString().toLowerCase();
                    if (completionStatus == 'completed') {
                      completedServices++;
                      revenue += _getPrice(service['price']);
                    }
                  }
                }
              }
            } else if (status == 'completed') {
              // Single service booking - check booking status is completed
              // Only count if assigned to me
              if (data['staffId'] == user.uid || data['staffAuthUid'] == user.uid) {
                final bookingPrice = _getPrice(data['price']);
                if (bookingPrice > 0) {
                  completedServices++;
                  revenue += bookingPrice;
                }
              }
            }
          }
        } else {
          // For owners/admins, count all bookings
          totalBookings++;
          // Only count completed bookings for revenue (not confirmed or cancelled)
          if (status == 'completed') {
            completedBookings++;
            completedServices++;
            revenue += _getPrice(data['price']);
          }
        }
      }

      // Calculate rating (default to 4.8 if there are completed services, otherwise show —)
      final rating = completedServices > 0 ? '4.8' : '—';

      // Calculate working hours for the current tab's date range
      final workingHours = await _calculateWorkingHoursForRange(startDate, endDate, user.uid);
      debugPrint('${_selectedTab.toUpperCase()} view - Date range: ${DateFormat('yyyy-MM-dd').format(startDate)} to ${DateFormat('yyyy-MM-dd').format(endDate)}');
      debugPrint('${_selectedTab.toUpperCase()} view - Checked $bookingsChecked bookings, $bookingsInRange in range');
      debugPrint('${_selectedTab.toUpperCase()} view - Working hours: ${_formatDuration(workingHours)}, Services: $completedServices, Revenue: \$${revenue.toStringAsFixed(0)}');

      if (mounted) {
        setState(() {
          _completedServices = completedServices;
          _revenue = revenue;
          _totalBookings = totalBookings;
          _rating = rating;
          _currentTabWorkingHours = workingHours;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading summary data: $e');
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  double _getPrice(dynamic price) {
    if (price == null) return 0;
    if (price is num) return price.toDouble();
    if (price is String) return double.tryParse(price) ?? 0;
    return 0;
  }

  Future<void> _calculateWeeklyWorkingHours(String userId) async {
    try {
      final now = DateTime.now();
      
      // Query ALL check-ins for this user (like admin panel does - no date filter in query)
      // This avoids index requirements and ensures we get all data
      // Try both staffId and staffAuthUid to handle different record formats
      QuerySnapshot checkInsQuery;
      try {
        checkInsQuery = await FirebaseFirestore.instance
            .collection('staff_check_ins')
            .where('staffId', isEqualTo: userId)
            .get();
        debugPrint('Total check-ins found for user (staffId): ${checkInsQuery.docs.length}');
      } catch (e) {
        // Fallback to staffAuthUid if staffId query fails
        debugPrint('staffId query failed, trying staffAuthUid: $e');
        checkInsQuery = await FirebaseFirestore.instance
            .collection('staff_check_ins')
            .where('staffAuthUid', isEqualTo: userId)
            .get();
        debugPrint('Total check-ins found for user (staffAuthUid): ${checkInsQuery.docs.length}');
      }

      // Initialize weekly data structures
      final List<WeeklyHoursData> weeklyData = [];
      
      for (int weekOffset = 0; weekOffset < 4; weekOffset++) {
        // Calculate week start (Monday at 00:00:00) and end (Sunday at 23:59:59)
        final weekStartDate = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1 + (weekOffset * 7)));
        final weekStart = DateTime(weekStartDate.year, weekStartDate.month, weekStartDate.day, 0, 0, 0);
        final weekEndDate = weekStart.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

        // Initialize day-wise map for this week
        final dailyHours = <String, int>{
          'Monday': 0,
          'Tuesday': 0,
          'Wednesday': 0,
          'Thursday': 0,
          'Friday': 0,
          'Saturday': 0,
          'Sunday': 0,
        };

        int totalSeconds = 0;

        // Filter check-ins for this specific week (in memory, like admin panel)
        for (final doc in checkInsQuery.docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            
            // Verify this check-in belongs to the user (double-check)
            final docStaffId = data['staffId']?.toString();
            final docStaffAuthUid = data['staffAuthUid']?.toString();
            if (docStaffId != userId && docStaffAuthUid != userId) {
              continue; // Skip if not for this user
            }
            
            final checkIn = StaffCheckInRecord.fromFirestore(doc);
            final checkInDate = checkIn.checkInTime;
            
            // Check if this check-in falls within this week
            // Use same logic as admin panel - compare timestamps
            final checkInTimeMs = checkInDate.millisecondsSinceEpoch;
            final weekStartMs = weekStart.millisecondsSinceEpoch;
            final weekEndMs = weekEndDate.millisecondsSinceEpoch;
            
            if (checkInTimeMs >= weekStartMs && checkInTimeMs <= weekEndMs) {
              final dayName = _getDayName(checkInDate.weekday);
              
              // Calculate working seconds for this check-in
              final workingSeconds = checkIn.workingSeconds;
              debugPrint('Week $weekOffset - ${checkInDate.toString()}: $workingSeconds seconds (${_formatDuration(workingSeconds)}) - Staff: ${checkIn.staffName}');
              
              dailyHours[dayName] = (dailyHours[dayName] ?? 0) + workingSeconds;
              totalSeconds += workingSeconds;
            }
          } catch (e) {
            debugPrint('Error processing check-in ${doc.id}: $e');
            continue;
          }
        }

        debugPrint('Week $weekOffset total: ${_formatDuration(totalSeconds)}');
        
        weeklyData.add(WeeklyHoursData(
          weekStart: weekStart,
          weekEnd: weekEndDate,
          totalSeconds: totalSeconds,
          dailyHours: dailyHours,
        ));
      }

      if (mounted) {
        setState(() {
          _weeklyHoursData = weeklyData;
          // Set current week data for backward compatibility
          if (weeklyData.isNotEmpty) {
            _dailyWorkingHours = weeklyData[0].dailyHours;
            _totalWeeklyHours = weeklyData[0].totalSeconds;
          } else {
            _dailyWorkingHours = {
              'Monday': 0,
              'Tuesday': 0,
              'Wednesday': 0,
              'Thursday': 0,
              'Friday': 0,
              'Saturday': 0,
              'Sunday': 0,
            };
            _totalWeeklyHours = 0;
          }
        });
      }
    } catch (e) {
      debugPrint('Error calculating weekly working hours: $e');
      if (mounted) {
        setState(() {
          _weeklyHoursData = [];
          _dailyWorkingHours = {
            'Monday': 0,
            'Tuesday': 0,
            'Wednesday': 0,
            'Thursday': 0,
            'Friday': 0,
            'Saturday': 0,
            'Sunday': 0,
          };
          _totalWeeklyHours = 0;
        });
      }
    }
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return 'Monday';
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '0m';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isBranchAdmin = _currentUserRole == 'branch_admin';

    return SafeArea(
      child: Container(
        color: AppColors.background,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: Column(
                        children: [
                          Text(
                            _isBranchView ? 'Branch Summary' : 'My Summary',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          if (isBranchAdmin) ...[
                            const SizedBox(height: 12),
                            _buildViewToggle(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _buildTabs(),
                  const SizedBox(height: 24),
                  Container(
                    color: AppColors.background,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.05, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _buildCurrentView(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewToggle() {
    return SizedBox(
      width: 300,
      child: AnimatedToggle(
        backgroundColor: Colors.white,
        values: const ['My Summary', 'Branch Summary'],
        selectedIndex: _isBranchView ? 1 : 0,
        onChanged: (index) {
          setState(() => _isBranchView = index == 1);
          // Reload data when view changes
          _loadSummaryData();
        },
      ),
    );
  }

  // Removed manual toggle buttons


  Widget _iconButton(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: Icon(icon, size: 16, color: AppColors.text)),
    );
  }

  Widget _buildTabs() {
    final tabs = ['day', 'week', 'month'];
    return AnimatedToggle(
      backgroundColor: Colors.white,
      values: const ['Day', 'Week', 'Month'],
      selectedIndex: tabs.indexOf(_selectedTab),
      onChanged: (index) {
        setState(() {
          _selectedTab = tabs[index];
          // Reset data when tab changes to avoid showing stale data
          _completedServices = 0;
          _revenue = 0;
          _currentTabWorkingHours = 0;
          _isLoadingData = true;
        });
        // Reload data when tab changes
        _loadSummaryData();
      },
    );
  }

  // Removed manual tab buttons


  Widget _buildCurrentView() {
    switch (_selectedTab) {
      case 'day':
        return _buildDayView();
      case 'week':
        return _buildWeekView();
      case 'month':
        return _buildMonthView();
      default:
        return _buildDayView();
    }
  }

  Widget _buildDayView() {
    // Real data - use working hours calculated for today
    final hours = _formatDuration(_currentTabWorkingHours);
    
    // Real data from bookings
    final tasks = _isLoadingData ? '—' : '$_completedServices';
    final tips = _isLoadingData ? '—' : '\$${_revenue.toStringAsFixed(0)}';
    final rating = _isLoadingData ? '—' : _rating;

    // Format date for header
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(now);

    return Column(
      key: const ValueKey('day'),
      children: [
        _buildSummaryHeader('Daily Summary', dateStr),
        const SizedBox(height: 24),
        _isLoadingData
            ? const Center(child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: AppColors.primary),
              ))
            : _buildKpiGrid([
                _KpiData(FontAwesomeIcons.clock, hours, 'Hours Worked'),
                _KpiData(FontAwesomeIcons.circleCheck, tasks, 'Services Done'),
                _KpiData(FontAwesomeIcons.dollarSign, tips, 'Revenue Generated'),
                _KpiData(FontAwesomeIcons.star, rating, 'Rating'),
              ]),
        const SizedBox(height: 24),
        if (!_isBranchView && (_currentUserRole == 'staff' || _currentUserRole == 'branch_admin')) ...[
          _buildWeeklyWorkingHoursCard(),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildWeekView() {
    // Real data - use working hours calculated for current week
    final totalHours = _formatDuration(_currentTabWorkingHours);
    
    // Real data from bookings
    final tasks = _isLoadingData ? '—' : '$_completedServices';
    final tips = _isLoadingData ? '—' : '\$${_revenue.toStringAsFixed(0)}';
    final rating = _isLoadingData ? '—' : _rating;

    // Format date range for header
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final dateStr = '${DateFormat('d').format(weekStart)} → ${DateFormat('d MMM yyyy').format(weekEnd)}';

    return Column(
      key: const ValueKey('week'),
      children: [
        _buildSummaryHeader('Week Summary', dateStr),
        const SizedBox(height: 24),
        _isLoadingData
            ? const Center(child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: AppColors.primary),
              ))
            : _buildKpiGrid([
                _KpiData(FontAwesomeIcons.clock, totalHours, 'Total Hours'),
                _KpiData(FontAwesomeIcons.listCheck, tasks, 'Services Done'),
                _KpiData(FontAwesomeIcons.dollarSign, tips, 'Revenue Generated'),
                _KpiData(FontAwesomeIcons.star, rating, 'Avg Rating'),
              ]),
        const SizedBox(height: 24),
        if (!_isBranchView && (_currentUserRole == 'staff' || _currentUserRole == 'branch_admin')) ...[
          _buildWeeklyWorkingHoursCard(),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildMonthView() {
    // Real data - use working hours calculated for current month
    final totalHours = _formatDuration(_currentTabWorkingHours);
    
    // Real data from bookings
    final tasks = _isLoadingData ? '—' : '$_completedServices';
    final tips = _isLoadingData ? '—' : '\$${_revenue.toStringAsFixed(0)}';
    final rating = _isLoadingData ? '—' : _rating;

    // Format month for header
    final now = DateTime.now();
    final dateStr = DateFormat('MMMM yyyy').format(now);

    return Column(
      key: const ValueKey('month'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSummaryHeader('Month Summary', dateStr),
        const SizedBox(height: 24),
        _isLoadingData
            ? const Center(child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: AppColors.primary),
              ))
            : _buildKpiGrid([
                _KpiData(FontAwesomeIcons.clock, totalHours, 'Total Hours'),
                _KpiData(FontAwesomeIcons.listCheck, tasks, 'Services Done'),
                _KpiData(FontAwesomeIcons.dollarSign, tips, 'Revenue Generated'),
                _KpiData(FontAwesomeIcons.star, rating, 'Avg Rating'),
              ]),
        const SizedBox(height: 24),
        _buildChartContainer('Weekly Breakdown', _buildMonthChart()),
        const SizedBox(height: 40), // Extra padding at bottom to prevent cutoff
      ],
    );
  }

  Widget _buildSummaryHeader(String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.accent],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(List<_KpiData> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _buildKpiCard(items[index]);
      },
    );
  }

  Widget _buildKpiCard(_KpiData data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Center(child: Icon(data.icon, color: Colors.white, size: 18)),
          ),
          Text(
            data.value,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyWorkingHoursCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  FontAwesomeIcons.clock,
                  color: Color(0xFF3B82F6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Weekly Working Hours',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_currentUserName != null)
            Text(
              _currentUserName!,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          if (_currentUserName != null) const SizedBox(height: 4),
          Text(
            _weeklyHoursData.isNotEmpty && _selectedWeekIndex < _weeklyHoursData.length
                ? _formatDuration(_weeklyHoursData[_selectedWeekIndex].totalSeconds)
                : _formatDuration(_totalWeeklyHours),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _weeklyHoursData.isNotEmpty && _selectedWeekIndex < _weeklyHoursData.length
                ? _weeklyHoursData[_selectedWeekIndex].shortLabel
                : 'This Week',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 24),
          // 4 Weeks Overview
          if (_weeklyHoursData.isNotEmpty) ...[
            _buildWeeksOverview(),
            const SizedBox(height: 24),
          ],
          // Bar Chart (Current Week)
          SizedBox(
            height: 200,
            child: _buildWeeklyHoursChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeksOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Last 4 Weeks',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_weeklyHoursData.length, (index) {
          final weekData = _weeklyHoursData[index];
          final isCurrentWeek = index == 0;
          final isSelected = _selectedWeekIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedWeekIndex = index;
                // Update current week data for chart
                _dailyWorkingHours = weekData.dailyHours;
                _totalWeeklyHours = weekData.totalSeconds;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF3B82F6).withOpacity(0.1)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF3B82F6).withOpacity(0.3)
                      : AppColors.border.withOpacity(0.5),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            weekData.shortLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? const Color(0xFF3B82F6)
                                  : AppColors.text,
                            ),
                          ),
                          if (isCurrentWeek) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Current',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          if (isSelected && !isCurrentWeek) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Selected',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        weekData.weekLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatDuration(weekData.totalSeconds),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          );
        }),
      ],
    );
  }

  Widget _buildWeeklyHoursChart() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    
    // Use selected week's data if available, otherwise use current week data
    final Map<String, int> chartData = _weeklyHoursData.isNotEmpty && _selectedWeekIndex < _weeklyHoursData.length
        ? _weeklyHoursData[_selectedWeekIndex].dailyHours
        : _dailyWorkingHours;
    
    // Find max hours for scaling
    double maxHours = 0;
    for (final dayName in dayNames) {
      final seconds = chartData[dayName] ?? 0;
      final hours = seconds / 3600.0;
      if (hours > maxHours) maxHours = hours;
    }
    // Set minimum max to 8 hours for better visualization
    if (maxHours < 8) maxHours = 8;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxHours,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => const Color(0xFF3B82F6),
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final dayName = dayNames[group.x.toInt()];
              final seconds = chartData[dayName] ?? 0;
              return BarTooltipItem(
                _formatDuration(seconds),
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < days.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      days[value.toInt()],
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == meta.max) return const Text('');
                return Text(
                  '${value.toInt()}h',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: AppColors.border.withOpacity(0.3),
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(7, (index) {
          final dayName = dayNames[index];
          final seconds = chartData[dayName] ?? 0;
          final hours = seconds / 3600.0;
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: hours,
                color: const Color(0xFF3B82F6),
                width: 20,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxHours,
                  color: AppColors.border.withOpacity(0.1),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildNotesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notes',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text)),
          SizedBox(height: 8),
          Text('Great work today! 🌸',
              style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _buildDownloadBtn(String text) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.25),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(FontAwesomeIcons.download,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartContainer(String title, Widget chart) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text)),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 280,
              maxHeight: 320,
            ),
            child: SizedBox(
              height: 280,
              child: chart,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekChart() {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                if (value.toInt() >= 0 && value.toInt() < days.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(days[value.toInt()],
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.muted)),
                  );
                }
                return const Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          _makeGroupData(0, 7, AppColors.primary),
          _makeGroupData(1, 6, AppColors.accent),
          _makeGroupData(2, 5.5, AppColors.primary),
          _makeGroupData(3, 8, AppColors.accent),
          _makeGroupData(4, 5, AppColors.primary),
          _makeGroupData(5, 6.5, AppColors.accent),
          _makeGroupData(6, 0, Colors.grey.shade200),
        ],
      ),
    );
  }

  Widget _buildMonthChart() {
    // Use real data from _weeklyHoursData
    // Convert total seconds to hours for each week
    final weekHours = <double>[];
    for (int i = 0; i < 4; i++) {
      if (i < _weeklyHoursData.length) {
        weekHours.add(_weeklyHoursData[i].totalSeconds / 3600.0);
      } else {
        weekHours.add(0.0);
      }
    }
    
    // Find max hours for scaling
    double maxHours = 0;
    for (final hours in weekHours) {
      if (hours > maxHours) maxHours = hours;
    }
    // Set minimum max to 8 hours for better visualization
    if (maxHours < 8) maxHours = 8;
    
    return BarChart(
      BarChartData(
        maxY: maxHours,
        gridData: const FlGridData(
          show: false,
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == meta.max) return const Text('');
                return Text(
                  '${value.toInt()}h',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < 4) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('Week ${value.toInt() + 1}',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.muted)),
                  );
                }
                return const Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => AppColors.primary,
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final hours = weekHours[group.x.toInt()];
              return BarTooltipItem(
                '${hours.toStringAsFixed(1)}h',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(4, (index) {
          final hours = weekHours[index];
          final color = index % 2 == 0 ? AppColors.primary : AppColors.accent;
          return _makeGroupData(index, hours, color);
        }),
      ),
    );
  }

  BarChartGroupData _makeGroupData(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 16,
          borderRadius: BorderRadius.circular(4),
          backDrawRodData: BackgroundBarChartRodData(
            show: false,
          ),
        ),
      ],
    );
  }
}

class _KpiData {
  final IconData icon;
  final String value;
  final String label;
  _KpiData(this.icon, this.value, this.label);
}
