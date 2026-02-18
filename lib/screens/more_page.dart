import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'services_page.dart';
import 'staff_management_page.dart';
import 'attendance_page.dart';
import 'timesheets_page.dart';
import 'branches_page.dart';
import 'salon_settings_page.dart';
import 'audit_logs_page.dart';
import 'subscription_page.dart';
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
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}

class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  String? _userRole;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
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
          setState(() {
            String? rawRole = doc.data()?['role'] as String?;
            // role is already normalized (staff, branch_admin, workshop_owner)
            _userRole = rawRole;
            _isLoading = false;
          });
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching role: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isBranchAdmin => _userRole == 'branch_admin';
  bool get _isWorkshopOwner => _userRole == 'workshop_owner';

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header
            const Text(
              'More',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _isBranchAdmin ? 'Manage your branch' : 'Manage your salon settings',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.muted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Services Section - Available for all roles
            _buildMenuCard(
              context,
              icon: FontAwesomeIcons.scissors,
              title: 'Services',
              subtitle: _isBranchAdmin ? 'View available services' : 'Manage your salon services',
              gradientColors: [const Color(0xFF1A1A1A), const Color(0xFF333333)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ServicesPage()),
                );
              },
            ),
            const SizedBox(height: 16),

            // Staff Section (Expandable) - Only for salon owners
            if (_isWorkshopOwner) ...[
              _buildExpandableMenuCard(
                context,
                icon: FontAwesomeIcons.users,
                title: 'Staff',
                subtitle: 'Manage staff and attendance',
                gradientColors: [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)],
                children: [
                  _buildSubMenuItem(
                    context,
                    icon: FontAwesomeIcons.userGear,
                    title: 'Staff Management',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StaffManagementPage()),
                      );
                    },
                  ),
                  _buildSubMenuItem(
                    context,
                    icon: FontAwesomeIcons.clipboardUser,
                    title: 'Attendance & GPS',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AttendancePage()),
                      );
                    },
                  ),
                  _buildSubMenuItem(
                    context,
                    icon: FontAwesomeIcons.clock,
                    title: 'Timesheets',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TimesheetsPage()),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Branches Section - Available for all roles (branch admins see their branch)
            _buildMenuCard(
              context,
              icon: FontAwesomeIcons.building,
              title: _isBranchAdmin ? 'My Branch' : 'Branches',
              subtitle: _isBranchAdmin ? 'View your branch details' : 'Manage your salon locations',
              gradientColors: [const Color(0xFF10B981), const Color(0xFF34D399)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BranchesPage()),
                );
              },
            ),

            // Summary Section - For branch admins
            if (_isBranchAdmin) ...[
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                icon: FontAwesomeIcons.chartPie,
                title: 'Summary',
                subtitle: 'View your performance & branch reports',
                gradientColors: [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BranchAdminSummaryPage()),
                  );
                },
              ),
            ],

            // Summary Section - Only for salon owners
            if (_isWorkshopOwner) ...[
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                icon: FontAwesomeIcons.chartPie,
                title: 'Summary',
                subtitle: 'View your performance & reports',
                gradientColors: [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MySummaryPage()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                icon: FontAwesomeIcons.clipboardList,
                title: 'Audit Logs',
                subtitle: 'Track all system activities & changes',
                gradientColors: [const Color(0xFF475569), const Color(0xFF64748B)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuditLogsPage()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                icon: FontAwesomeIcons.crown,
                title: 'My Subscription',
                subtitle: 'View your plan details',
                gradientColors: [const Color(0xFF8B5CF6), const Color(0xFFC4B5FD)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SubscriptionPage()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                context,
                icon: FontAwesomeIcons.gear,
                title: 'Salon Settings',
                subtitle: 'Business profile, logo & terms',
                gradientColors: [const Color(0xFF6366F1), const Color(0xFF818CF8)],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SalonSettingsPage()),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors[0].withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    FontAwesomeIcons.chevronRight,
                    color: AppColors.muted,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
          leading: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: gradientColors[0].withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.muted,
            ),
          ),
          iconColor: AppColors.muted,
          collapsedIconColor: AppColors.muted,
          children: children,
        ),
      ),
    );
  }

  Widget _buildSubMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E8E8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(icon, color: AppColors.text, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
              ),
              Icon(
                FontAwesomeIcons.chevronRight,
                color: AppColors.muted,
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// OTHER SUB-PAGES
// ============================================================================

class MySummaryPage extends StatefulWidget {
  const MySummaryPage({super.key});

  @override
  State<MySummaryPage> createState() => _MySummaryPageState();
}

class _MySummaryPageState extends State<MySummaryPage> {
  int _selectedTab = 0; // 0 = Day, 1 = Week, 2 = Month
  bool _loading = true;
  String? _ownerUid;
  
  // Summary data
  int _completedServices = 0;
  double _revenue = 0;
  int _totalBookings = 0;
  String _rating = '—';
  int _pendingBookings = 0;
  double _averageBookingValue = 0;
  List<double> _weeklyRevenue = []; // For month view chart

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (mounted && userDoc.exists) {
        final userData = userDoc.data();
        setState(() {
          _ownerUid = userData?['ownerUid']?.toString() ?? user.uid;
        });
        _loadSummaryData();
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSummaryData() async {
    if (_ownerUid == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      // Determine date range based on selected tab
      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate;
      
      if (_selectedTab == 0) {
        // Today
        startDate = DateTime(now.year, now.month, now.day, 0, 0, 0);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (_selectedTab == 1) {
        // Current week (Monday to Sunday)
        final weekStart = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(weekStart.year, weekStart.month, weekStart.day, 0, 0, 0);
        endDate = startDate.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      } else {
        // Current month
        startDate = DateTime(now.year, now.month, 1, 0, 0, 0);
        endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      }

      // Query bookings for the owner
      final bookingsQuery = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerUid', isEqualTo: _ownerUid)
          .get();

      int completedServices = 0;
      double revenue = 0;
      int totalBookings = 0;
      double totalRating = 0;
      int ratingCount = 0;
      int pendingBookings = 0;
      double totalBookingValue = 0;
      List<double> weeklyRevenue = []; // For month view: 4 weeks of revenue

      for (final doc in bookingsQuery.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        
        // Parse booking date
        DateTime? bookingDate;
        try {
          if (data['date'] is Timestamp) {
            bookingDate = (data['date'] as Timestamp).toDate();
          } else if (data['dateTimeUtc'] is Timestamp) {
            bookingDate = (data['dateTimeUtc'] as Timestamp).toDate();
          } else if (data['dateTimeUtc'] != null && data['dateTimeUtc'].toString().isNotEmpty) {
            try {
              bookingDate = DateTime.parse(data['dateTimeUtc'].toString());
            } catch (e) {
              // Fall through
            }
          }
          
          if (bookingDate == null) {
            final bookingDateStr = (data['date'] ?? '').toString();
            if (bookingDateStr.isNotEmpty) {
              final parts = bookingDateStr.split('-');
              if (parts.length == 3) {
                bookingDate = DateTime(
                  int.parse(parts[0]),
                  int.parse(parts[1]),
                  int.parse(parts[2]),
                );
              } else {
                bookingDate = DateTime.parse(bookingDateStr);
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing booking date: $e');
          continue;
        }

        if (bookingDate == null) continue;
        
        // Check if booking is within date range
        final bookingDateOnly = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);
        final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
        final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
        
        final compareStart = bookingDateOnly.compareTo(startDateOnly);
        final compareEnd = bookingDateOnly.compareTo(endDateOnly);
        final isInRange = compareStart >= 0 && compareEnd <= 0;
        
        if (!isInRange) continue;

        totalBookings++;
        final bookingPrice = _getPrice(data['price']);
        totalBookingValue += bookingPrice;
        
        // Only count completed bookings for revenue (not confirmed or cancelled)
        if (status == 'completed') {
          completedServices++;
          revenue += bookingPrice;
          
          // Get rating if available
          if (data['rating'] != null) {
            final ratingValue = _getPrice(data['rating']);
            if (ratingValue > 0) {
              totalRating += ratingValue;
              ratingCount++;
            }
          }
        } else if (status == 'pending' || status.contains('awaiting')) {
          pendingBookings++;
        }
        
        // For month view: calculate weekly revenue (4 weeks of the month)
        if (_selectedTab == 2 && bookingDate != null && isInRange) {
          // Calculate which week of the month (1-4)
          final dayOfMonth = bookingDate.day;
          int weekOfMonth = ((dayOfMonth - 1) ~/ 7);
          if (weekOfMonth > 3) weekOfMonth = 3; // Cap at week 4
          
          // Ensure list has enough elements
          while (weeklyRevenue.length <= weekOfMonth) {
            weeklyRevenue.add(0.0);
          }
          
          // Only count completed bookings for revenue
          if (status == 'completed') {
            weeklyRevenue[weekOfMonth] += bookingPrice;
          }
        }
      }

      // Calculate average rating - default to 4.8 if there are completed services, otherwise show —
      final avgRating = ratingCount > 0 
          ? (totalRating / ratingCount).toStringAsFixed(1)
          : (completedServices > 0 ? '4.8' : '—');
      
      // Calculate average booking value
      final avgBookingValue = totalBookings > 0 ? (totalBookingValue / totalBookings) : 0.0;
      
      // Ensure weeklyRevenue has 4 weeks
      while (weeklyRevenue.length < 4) {
        weeklyRevenue.add(0.0);
      }

      if (mounted) {
        setState(() {
          _completedServices = completedServices;
          _revenue = revenue;
          _totalBookings = totalBookings;
          _rating = avgRating;
          _pendingBookings = pendingBookings;
          _averageBookingValue = avgBookingValue;
          _weeklyRevenue = weeklyRevenue;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading summary data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  double _getPrice(dynamic price) {
    if (price == null) return 0;
    if (price is num) return price.toDouble();
    if (price is String) return double.tryParse(price) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(FontAwesomeIcons.arrowLeft, size: 18, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Tab Selector
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                      ),
                      child: Row(
                        children: [
                          _buildTabButton('Day', 0),
                          _buildTabButton('Week', 1),
                          _buildTabButton('Month', 2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Summary Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF333333)]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: const Color(0xFF1A1A1A).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedTab == 0 ? 'Daily Summary' : _selectedTab == 1 ? 'Week Summary' : 'Month Summary',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(_getDateString(), style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Stats Grid - 4 cards matching the original design
                    Row(
                      children: [
                        Expanded(child: _buildStatCard(FontAwesomeIcons.calendarCheck, '$_totalBookings', 'Total Bookings')),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(FontAwesomeIcons.circleCheck, '$_completedServices', 'Tasks Completed')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildStatCard(FontAwesomeIcons.dollarSign, '\$${_revenue.toStringAsFixed(0)}', 'Total Revenue')),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(FontAwesomeIcons.star, _rating, 'Rating')),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Additional Stats Row
                    Row(
                      children: [
                        Expanded(child: _buildStatCard(FontAwesomeIcons.clock, '$_pendingBookings', 'Pending', const Color(0xFFF59E0B))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(FontAwesomeIcons.chartLine, '\$${_averageBookingValue.toStringAsFixed(0)}', 'Avg Booking', const Color(0xFF8B5CF6))),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Revenue Chart (for Month view)
                    if (_selectedTab == 2) ...[
                      _buildRevenueChart(),
                      const SizedBox(height: 20),
                    ],
                    // Performance Insights
                    _buildPerformanceInsights(),
                    const SizedBox(height: 20),
                    // Notes
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                          const SizedBox(height: 8),
                          Text(
                            _completedServices > 0
                                ? 'Great work today! 🌸'
                                : 'Start completing services to see your performance stats here.',
                            style: const TextStyle(fontSize: 14, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = index;
            _loading = true;
          });
          _loadSummaryData();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1A1A1A) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppColors.muted)),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label, [Color? iconColor]) {
    final color = iconColor ?? const Color(0xFFE0E0E0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Icon(icon, color: color, size: 20)),
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.text)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    if (_weeklyRevenue.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Find max revenue for scaling
    double maxRevenue = 0;
    for (final rev in _weeklyRevenue) {
      if (rev > maxRevenue) maxRevenue = rev;
    }
    if (maxRevenue < 100) maxRevenue = 100; // Minimum scale
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  FontAwesomeIcons.chartLine,
                  color: Color(0xFF1A1A1A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Monthly Revenue Breakdown',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: maxRevenue,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => const Color(0xFF1A1A1A),
                    tooltipRoundedRadius: 8,
                    tooltipPadding: const EdgeInsets.all(8),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '\$${_weeklyRevenue[group.x.toInt()].toStringAsFixed(0)}',
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
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 && value.toInt() < 4) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'Week ${value.toInt() + 1}',
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
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const Text('');
                        return Text(
                          '\$${value.toInt()}',
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
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: AppColors.border.withOpacity(0.3),
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(4, (index) {
                  final revenue = _weeklyRevenue[index];
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: revenue,
                        color: index % 2 == 0 
                            ? const Color(0xFF1A1A1A) 
                            : const Color(0xFF333333),
                        width: 20,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxRevenue,
                          color: AppColors.border.withOpacity(0.1),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceInsights() {
    final completionRate = _totalBookings > 0 
        ? ((_completedServices / _totalBookings) * 100).toStringAsFixed(0)
        : '0';
    
    String insightText = '';
    String insightEmoji = '📊';
    
    if (_totalBookings == 0) {
      insightText = 'No bookings yet. Start accepting bookings to see insights here.';
    } else if (_completedServices == 0) {
      insightText = 'You have $_totalBookings bookings but none completed yet. Focus on completing services!';
      insightEmoji = '⚠️';
    } else if (double.parse(completionRate) >= 80) {
      insightText = 'Excellent! Your completion rate is ${completionRate}%. Keep up the great work! 🎉';
      insightEmoji = '🌟';
    } else if (double.parse(completionRate) >= 60) {
      insightText = 'Good progress! Your completion rate is ${completionRate}%. You can improve by completing more bookings.';
      insightEmoji = '📈';
    } else {
      insightText = 'Your completion rate is ${completionRate}%. Focus on completing pending bookings to improve performance.';
      insightEmoji = '💡';
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A1A).withOpacity(0.1),
            const Color(0xFF333333).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1A1A1A).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  insightEmoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Performance Insights',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInsightItem('Completion Rate', '$completionRate%', const Color(0xFF10B981)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInsightItem('Total Revenue', '\$${_revenue.toStringAsFixed(0)}', const Color(0xFF8B5CF6)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            insightText,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.text,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _getDateString() {
    final now = DateTime.now();
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    
    if (_selectedTab == 0) {
      // Day
      return '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
    } else if (_selectedTab == 1) {
      // Week
      final weekStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      return '${DateFormat('d').format(weekStart)} → ${DateFormat('d MMM yyyy').format(weekEnd)}';
    } else {
      // Month
      return DateFormat('MMMM yyyy').format(now);
    }
  }
}

// ============================================================================
// BRANCH ADMIN SUMMARY PAGE
// ============================================================================

class BranchAdminSummaryPage extends StatefulWidget {
  const BranchAdminSummaryPage({super.key});

  @override
  State<BranchAdminSummaryPage> createState() => _BranchAdminSummaryPageState();
}

class _BranchAdminSummaryPageState extends State<BranchAdminSummaryPage> {
  bool _showBranchSummary = false; // false = My Summary, true = Branch Summary
  bool _loading = true;
  String? _currentUserName;

  // My Summary data
  int _myCompletedServices = 0;
  double _myRevenue = 0;
  int _myTotalBookings = 0;
  Map<String, int> _dailyWorkingHours = {}; // Day-wise working hours in seconds (current week)
  int _totalWeeklyHours = 0; // Total weekly hours in seconds (current week)
  
  // 4 weeks of data
  List<WeeklyHoursData> _weeklyHoursData = []; // 4 weeks: [current, week-1, week-2, week-3]
  int _selectedWeekIndex = 0; // 0 = current week, 1 = last week, etc.

  // Branch Summary data
  double _branchRevenue = 0;
  int _branchBookings = 0;
  int _branchStaffCount = 0;
  int _branchCompletedBookings = 0;
  int _branchPendingBookings = 0;
  String _branchName = 'My Branch';

  @override
  void initState() {
    super.initState();
    _loadSummaryData();
  }

  Future<void> _loadSummaryData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      // Get user document to find branchId and ownerUid
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        setState(() => _loading = false);
        return;
      }

      final userData = userDoc.data()!;
      final branchId = (userData['branchId'] ?? '').toString();
      final ownerUid = (userData['ownerUid'] ?? '').toString();
      _currentUserName = userData['displayName'] ?? userData['name'] ?? 'Staff';
      
      debugPrint('Branch Admin Summary - branchId: $branchId, ownerUid: $ownerUid');
      
      // Get branch name from branches collection
      String branchNameForMatching = '';
      if (branchId.isNotEmpty) {
        final branchDoc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .get();
        if (branchDoc.exists) {
          _branchName = (branchDoc.data()?['name'] ?? 'My Branch').toString();
          branchNameForMatching = _branchName.toLowerCase();
          debugPrint('Branch name from DB: $_branchName');
        }
      }
      
      // Also check user document for branchName as fallback
      if (_branchName == 'My Branch') {
        _branchName = (userData['branchName'] ?? 'My Branch').toString();
        branchNameForMatching = _branchName.toLowerCase();
      }

      // Load ALL bookings for the owner (ALL TIME - no date filtering)
      // This calculates total completed revenue across all time, not just recent bookings
      final allBookingsQuery = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerUid', isEqualTo: ownerUid)
          .get();
      
      debugPrint('Total bookings for owner (all time): ${allBookingsQuery.docs.length}');
      debugPrint('Current user UID: ${user.uid}');

      // Initialize counters for MY SUMMARY (all-time totals)
      int myCompleted = 0;
      double myRevenue = 0; // All-time completed revenue
      int myTotal = 0;

      // Load Branch Summary
      double branchRevenue = 0;
      int branchBookings = 0;
      int branchCompleted = 0;
      int branchPending = 0;

      for (final doc in allBookingsQuery.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        final bookingBranchId = (data['branchId'] ?? '').toString();
        
        // ============== MY SUMMARY ==============
        // Check if this booking is assigned to me (staff/branch admin)
        bool isMyBooking = false;
        
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
          myTotal++;
          debugPrint('Found my booking ${doc.id}: status=$status, hasServices=${data['services'] is List}');
          
          // For multi-service bookings, check individual service completion status
          if (data['services'] is List && (data['services'] as List).isNotEmpty) {
            // Count each completed service separately
            int servicesInThisBooking = 0;
            for (final service in (data['services'] as List)) {
              if (service is Map) {
                final svcStaffId = service['staffId']?.toString();
                final svcStaffAuthUid = service['staffAuthUid']?.toString();
                // Check if this service is assigned to me
                if (svcStaffId == user.uid || svcStaffAuthUid == user.uid) {
                  final completionStatus = (service['completionStatus'] ?? '').toString().toLowerCase();
                  debugPrint('  Service assigned to me: completionStatus=$completionStatus, bookingStatus=$status');
                  // Count service if:
                  // 1. Service has completionStatus = 'completed', OR
                  // 2. Booking status is 'completed' (fallback for bookings where service completionStatus wasn't set)
                  if (completionStatus == 'completed' || status == 'completed') {
                    servicesInThisBooking++;
                    final servicePrice = _getPrice(service['price']);
                    myRevenue += servicePrice;
                    debugPrint('    Completed service: price=$servicePrice');
                  }
                }
              }
            }
            myCompleted += servicesInThisBooking;
            if (servicesInThisBooking > 0) {
              debugPrint('  Booking ${doc.id}: Added $servicesInThisBooking completed services');
            } else if (status == 'completed') {
              // Fallback: If booking is assigned to me and status is completed, 
              // but no services were found with completionStatus, count it as 1 completed service
              // This handles cases where services array exists but completionStatus wasn't set at service level
              final bookingPrice = _getPrice(data['price']);
              myCompleted++;
              myRevenue += bookingPrice;
              debugPrint('  Booking ${doc.id}: Fallback - counted as 1 completed service (booking status=completed), price=$bookingPrice');
            }
          } else {
            // Single service booking - check both booking status and completionStatus
            // A booking can be "confirmed" but the service might have completionStatus = "completed"
            final bookingCompletionStatus = (data['completionStatus'] ?? '').toString().toLowerCase();
            final isCompleted = status == 'completed' || bookingCompletionStatus == 'completed';
            
            if (isCompleted) {
              // Double-check it's assigned to me (should already be true from isMyBooking check)
              if (data['staffId'] == user.uid || data['staffAuthUid'] == user.uid) {
                final bookingPrice = _getPrice(data['price']);
                // Count even if price is 0, as long as it's completed
                myCompleted++;
                myRevenue += bookingPrice;
                debugPrint('  Single service booking ${doc.id}: completed (status=$status, completionStatus=$bookingCompletionStatus), price=$bookingPrice');
              }
            }
          }
        }
        
        // ============== BRANCH SUMMARY ==============
        // Match by branchId OR by branchName (some bookings might use name)
        final bookingBranchName = (data['branchName'] ?? '').toString().toLowerCase();
        final isBranchMatch = bookingBranchId == branchId || 
                              (branchNameForMatching.isNotEmpty && bookingBranchName == branchNameForMatching);
        
        if (isBranchMatch) {
          branchBookings++;
          
          // Count by status
          if (status == 'completed') {
            branchCompleted++;
          } else if (status == 'pending' || 
                     status.contains('awaiting') || 
                     status.contains('partially')) {
            branchPending++;
          }
          
          // Revenue for completed bookings only (not confirmed or cancelled)
          if (status == 'completed') {
            // Get price from top-level field first
            double bookingPrice = _getPrice(data['price']);
            
            // If price not set or is 0, derive from services list if present
            if (bookingPrice == 0 && data['services'] is List) {
              final servicesList = data['services'] as List;
              for (final item in servicesList) {
                if (item is Map && item['price'] != null) {
                  bookingPrice += _getPrice(item['price']);
                }
              }
            }
            
            branchRevenue += bookingPrice;
          }
        }
      }
      
      debugPrint('Branch $branchId: bookings=$branchBookings, completed=$branchCompleted, pending=$branchPending, revenue=$branchRevenue');

      // Count branch staff - get from branch document's staffIds array
      int staffCount = 0;
      
      // The branch document has staffIds array with all assigned staff
      if (branchId.isNotEmpty) {
        final branchDoc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .get();
        
        if (branchDoc.exists) {
          final branchData = branchDoc.data();
          final staffIds = branchData?['staffIds'];
          if (staffIds is List) {
            staffCount = staffIds.length;
            debugPrint('Staff from branch staffIds: $staffCount');
          }
        }
      }
      
      // If no staffIds in branch, count staff who have this branch in their schedule
      if (staffCount == 0) {
        final usersQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('ownerUid', isEqualTo: ownerUid)
            .get();
        
        for (final doc in usersQuery.docs) {
          final data = doc.data();
          final role = (data['role'] ?? '').toString().toLowerCase();
          
          if (role != 'staff' && role != 'branch_admin') continue;
          
          // Check if user's branchId matches
          final userBranchId = (data['branchId'] ?? '').toString();
          if (userBranchId == branchId) {
            staffCount++;
            continue;
          }
          
          // Check weeklySchedule for branch assignment
          final schedule = data['weeklySchedule'];
          if (schedule is Map) {
            for (final daySchedule in schedule.values) {
              if (daySchedule is Map) {
                final scheduleBranchId = daySchedule['branchId']?.toString();
                if (scheduleBranchId == branchId) {
                  staffCount++;
                  break;
                }
              }
            }
          }
        }
      }
      
      debugPrint('Final staff count for branch $branchId: $staffCount');

      // Calculate weekly working hours (day-wise)
      await _calculateWeeklyWorkingHours(user.uid);

      debugPrint('MY SUMMARY RESULTS:');
      debugPrint('  Completed Services: $myCompleted');
      debugPrint('  Revenue: $myRevenue');
      debugPrint('  Total Bookings: $myTotal');
      debugPrint('BRANCH SUMMARY RESULTS:');
      debugPrint('  Revenue: $branchRevenue');
      debugPrint('  Bookings: $branchBookings');
      debugPrint('  Staff Count: $staffCount');
      
      if (!mounted) return;
      setState(() {
        _myCompletedServices = myCompleted;
        _myRevenue = myRevenue;
        _myTotalBookings = myTotal;
        _branchRevenue = branchRevenue;
        _branchBookings = branchBookings;
        _branchStaffCount = staffCount;
        _branchCompletedBookings = branchCompleted;
        _branchPendingBookings = branchPending;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading summary data: $e');
      if (mounted) setState(() => _loading = false);
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
      
      // Also try querying without field filter to see all records (for debugging)
      if (checkInsQuery.docs.isEmpty) {
        debugPrint('No check-ins found with staffId/staffAuthUid, checking all records...');
        final allCheckIns = await FirebaseFirestore.instance
            .collection('staff_check_ins')
            .limit(10)
            .get();
        debugPrint('Sample check-in records (first 10):');
        for (final doc in allCheckIns.docs) {
          final data = doc.data();
          debugPrint('  Check-in ${doc.id}: staffId=${data['staffId']}, staffAuthUid=${data['staffAuthUid']}, staffName=${data['staffName']}');
        }
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
          debugPrint('Weekly hours data calculated: ${weeklyData.length} weeks');
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
      // Even on error, create empty 4 weeks structure so UI can still show the section
      final List<WeeklyHoursData> emptyWeeklyData = [];
      final now = DateTime.now();
      for (int weekOffset = 0; weekOffset < 4; weekOffset++) {
        final weekStartDate = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1 + (weekOffset * 7)));
        final weekEndDate = weekStartDate.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
        emptyWeeklyData.add(WeeklyHoursData(
          weekStart: weekStartDate,
          weekEnd: weekEndDate,
          totalSeconds: 0,
          dailyHours: {
            'Monday': 0,
            'Tuesday': 0,
            'Wednesday': 0,
            'Thursday': 0,
            'Friday': 0,
            'Saturday': 0,
            'Sunday': 0,
          },
        ));
      }
      
      if (mounted) {
        setState(() {
          _weeklyHoursData = emptyWeeklyData;
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

  Widget _buildWeeksOverview() {
    if (_weeklyHoursData.isEmpty) {
      return const SizedBox.shrink();
    }
    
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(FontAwesomeIcons.arrowLeft, size: 18, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Summary',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Toggle Switch
                    _buildToggle(),
                    const SizedBox(height: 24),
                    // Content based on toggle
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _showBranchSummary
                          ? _buildBranchSummary()
                          : _buildMySummary(),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildToggle() {
    return AnimatedToggle(
      backgroundColor: Colors.white,
      values: const ['My Summary', 'Branch Summary'],
      selectedIndex: _showBranchSummary ? 1 : 0,
      onChanged: (index) => setState(() => _showBranchSummary = index == 1),
    );
  }

  Widget _buildMySummary() {
    return Column(
      key: const ValueKey('my_summary'),
      children: [
        // Header Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A1A), Color(0xFF333333)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A1A1A).withOpacity(0.3),
                blurRadius: 20,
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      FontAwesomeIcons.userCheck,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'My Performance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _getDateString(),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Stats Grid
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.circleCheck,
                '$_myCompletedServices',
                'Services Done',
                const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.dollarSign,
                '\$${_myRevenue.toStringAsFixed(0)}',
                'Revenue Generated',
                const Color(0xFF8B5CF6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.calendarCheck,
                '$_myTotalBookings',
                'Total Bookings',
                const Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.star,
                _myCompletedServices > 0 ? '4.8' : '—',
                'Rating',
                const Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Weekly Working Hours Section
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
              ),
            ],
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
              if (_currentUserName != null)               const SizedBox(height: 4),
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
              // 4 Weeks Overview - Always show if we have data
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
        ),
        const SizedBox(height: 20),
        // Tips Section
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      FontAwesomeIcons.lightbulb,
                      color: Color(0xFFF59E0B),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Performance Tip',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _myCompletedServices > 0
                    ? 'Great work! You\'ve completed $_myCompletedServices services. Keep up the excellent performance! 🌟'
                    : 'Start completing services to see your performance stats here.',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBranchSummary() {
    return Column(
      key: const ValueKey('branch_summary'),
      children: [
        // Header Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF34D399)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withOpacity(0.3),
                blurRadius: 20,
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      FontAwesomeIcons.building,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _branchName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Branch Overview',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Stats Grid
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.dollarSign,
                '\$${_branchRevenue.toStringAsFixed(0)}',
                'Total Revenue',
                const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.calendarDays,
                '$_branchBookings',
                'Total Bookings',
                const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.users,
                '$_branchStaffCount',
                'Staff Members',
                const Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.circleCheck,
                '$_branchCompletedBookings',
                'Completed',
                const Color(0xFF10B981),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.clock,
                '$_branchPendingBookings',
                'Pending',
                const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                FontAwesomeIcons.chartLine,
                _branchBookings > 0
                    ? '${((_branchCompletedBookings / _branchBookings) * 100).toStringAsFixed(0)}%'
                    : '—',
                'Completion Rate',
                const Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Branch Info Section
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      FontAwesomeIcons.chartPie,
                      color: Color(0xFF3B82F6),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Branch Insights',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _branchBookings > 0
                    ? 'Your branch has processed $_branchBookings bookings with $_branchStaffCount active staff members. '
                      '${_branchCompletedBookings > 0 ? "Keep up the great work! 💪" : "Focus on completing pending bookings."}'
                    : 'No bookings yet for this branch. Start accepting bookings to see insights here.',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(icon, color: color, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  String _getDateString() {
    // Show "All Time" since we're displaying all-time summary data, not just today's data
    return 'All Time';
  }
}
