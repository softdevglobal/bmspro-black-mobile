import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_screen.dart' as profile_screen;

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
}

class AdminDashboard extends StatefulWidget {
  final String role;
  final String? branchName;

  const AdminDashboard({
    super.key,
    required this.role,
    this.branchName,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _loadingMetrics = true;

  double _totalRevenue = 0;
  int _bookingCount = 0;
  double _avgTicketValue = 0;
  double _staffUtilization = 0; // 0–1
  double _clientRetention = 0; // 0–1

  // Revenue chart data (last 7 days)
  List<Map<String, dynamic>> _revenueByDay = [];

  // Service breakdown data
  List<Map<String, dynamic>> _serviceBreakdown = [];

  // Top performers data
  List<Map<String, dynamic>> _topPerformers = [];

  @override
  void initState() {
    super.initState();
    _loadOwnerAnalytics();
  }

  Future<void> _loadOwnerAnalytics() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => _loadingMetrics = false);
        return;
      }

      final qs = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerUid', isEqualTo: user.uid)
          .get();

      double totalRevenue = 0;
      int bookingCount = 0;
      final Set<String> staffIds = {};
      final Map<String, int> clientVisits = {};

      // For revenue by day chart (last 30 days)
      final Map<String, double> revenueByDate = {};
      final now = DateTime.now();
      // Initialize last 7 days with 0
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        revenueByDate[dateKey] = 0;
      }

      // For service breakdown
      final Map<String, double> serviceRevenue = {};

      // For staff performance
      final Map<String, Map<String, dynamic>> staffPerformance = {};

      for (final doc in qs.docs) {
        final data = doc.data();

        // Only completed bookings count for revenue (not confirmed or cancelled)
        final status =
            (data['status'] ?? '').toString().toLowerCase().trim();
        if (status != 'completed') continue;

        bookingCount++;

        // Price
        double price = 0;
        final rawPrice = data['price'];
        if (rawPrice is num) {
          price = rawPrice.toDouble();
        } else if (rawPrice is String) {
          price = double.tryParse(rawPrice) ?? 0;
        }

        // If price not set, derive from services list if present
        if (price == 0 && data['services'] is List) {
          final list = data['services'] as List;
          for (final item in list) {
            if (item is Map && item['price'] != null) {
              final p = item['price'];
              if (p is num) {
                price += p.toDouble();
              } else if (p is String) {
                price += double.tryParse(p) ?? 0;
              }
            }
          }
        }

        totalRevenue += price;

        // Revenue by date (for chart)
        final bookingDate = (data['date'] ?? '').toString();
        if (bookingDate.isNotEmpty && revenueByDate.containsKey(bookingDate)) {
          revenueByDate[bookingDate] = (revenueByDate[bookingDate] ?? 0) + price;
        }

        // Service breakdown
        if (data['services'] is List) {
          for (final item in (data['services'] as List)) {
            if (item is Map) {
              final serviceName = (item['name'] ?? 'Other').toString();
              double servicePrice = 0;
              if (item['price'] is num) {
                servicePrice = (item['price'] as num).toDouble();
              } else if (item['price'] is String) {
                servicePrice = double.tryParse(item['price']) ?? 0;
              }
              serviceRevenue[serviceName] = (serviceRevenue[serviceName] ?? 0) + servicePrice;

              // Staff performance from services list
              final staffId = (item['staffId'] ?? '').toString();
              final staffName = (item['staffName'] ?? '').toString();
              if (staffId.isNotEmpty && staffName.isNotEmpty && 
                  !staffName.toLowerCase().contains('any')) {
                if (!staffPerformance.containsKey(staffId)) {
                  staffPerformance[staffId] = {
                    'name': staffName,
                    'revenue': 0.0,
                    'services': 0,
                  };
                }
                staffPerformance[staffId]!['revenue'] = 
                    (staffPerformance[staffId]!['revenue'] as double) + servicePrice;
                staffPerformance[staffId]!['services'] = 
                    (staffPerformance[staffId]!['services'] as int) + 1;
              }
            }
          }
        } else {
          // Legacy booking without services array
          final serviceName = (data['serviceName'] ?? 'Other').toString();
          serviceRevenue[serviceName] = (serviceRevenue[serviceName] ?? 0) + price;
          
          // Staff performance from top-level fields
          final staffId = (data['staffId'] ?? '').toString();
          final staffName = (data['staffName'] ?? '').toString();
          if (staffId.isNotEmpty && staffName.isNotEmpty && 
              !staffName.toLowerCase().contains('any')) {
            if (!staffPerformance.containsKey(staffId)) {
              staffPerformance[staffId] = {
                'name': staffName,
                'revenue': 0.0,
                'services': 0,
              };
            }
            staffPerformance[staffId]!['revenue'] = 
                (staffPerformance[staffId]!['revenue'] as double) + price;
            staffPerformance[staffId]!['services'] = 
                (staffPerformance[staffId]!['services'] as int) + 1;
          }
        }

        // Staff IDs for utilization
        final topStaff = data['staffId'];
        if (topStaff != null && topStaff.toString().isNotEmpty) {
          staffIds.add(topStaff.toString());
        }
        if (data['services'] is List) {
          for (final item in (data['services'] as List)) {
            if (item is Map && item['staffId'] != null) {
              final sid = item['staffId'].toString();
              if (sid.isNotEmpty) staffIds.add(sid);
            }
          }
        }

        // Client visits for retention
        final clientKeySource = data['customerUid'] ??
            data['clientEmail'] ??
            data['clientPhone'] ??
            data['client'];
        final clientKey = (clientKeySource ?? '').toString().trim();
        if (clientKey.isNotEmpty) {
          clientVisits[clientKey] = (clientVisits[clientKey] ?? 0) + 1;
        }
      }

      double avgTicket = 0;
      if (bookingCount > 0) {
        avgTicket = totalRevenue / bookingCount;
      }

      double utilization = 0;
      if (staffIds.isNotEmpty && bookingCount > 0) {
        // Simple heuristic: assume 40 ideal bookings per staff member
        final capacity = staffIds.length * 40;
        utilization = (bookingCount / capacity).clamp(0.0, 1.0);
      }

      double retention = 0;
      if (clientVisits.isNotEmpty) {
        final totalClients = clientVisits.length;
        final returningClients =
            clientVisits.values.where((visits) => visits > 1).length;
        retention = (returningClients / totalClients).clamp(0.0, 1.0);
      }

      // Process revenue by day for chart
      final List<Map<String, dynamic>> revenueList = [];
      final sortedDates = revenueByDate.keys.toList()..sort();
      for (final date in sortedDates) {
        revenueList.add({
          'date': date,
          'revenue': revenueByDate[date] ?? 0,
        });
      }

      // Process service breakdown for pie chart
      final List<Map<String, dynamic>> serviceList = [];
      final totalServiceRevenue = serviceRevenue.values.fold(0.0, (a, b) => a + b);
      if (totalServiceRevenue > 0) {
        final sortedServices = serviceRevenue.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final entry in sortedServices.take(5)) {
          serviceList.add({
            'name': entry.key,
            'revenue': entry.value,
            'percentage': (entry.value / totalServiceRevenue * 100).round(),
          });
        }
      }

      // Process top performers
      final List<Map<String, dynamic>> performerList = staffPerformance.entries
          .map((e) => {
                'id': e.key,
                'name': e.value['name'],
                'revenue': e.value['revenue'],
                'services': e.value['services'],
              })
          .toList()
        ..sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));

      if (!mounted) return;
      setState(() {
        _totalRevenue = totalRevenue;
        _bookingCount = bookingCount;
        _avgTicketValue = avgTicket;
        _staffUtilization = utilization;
        _clientRetention = retention;
        _revenueByDay = revenueList;
        _serviceBreakdown = serviceList;
        _topPerformers = performerList.take(5).toList();
        _loadingMetrics = false;
      });
    } catch (e) {
      debugPrint('Error loading owner analytics: $e');
      if (!mounted) return;
      setState(() {
        _loadingMetrics = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.fromLTRB(16, 16, 16, 80), // Bottom padding for nav bar
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 24),
            _buildKpiSection(),
            const SizedBox(height: 24),
            _buildRevenueChartSection(),
            const SizedBox(height: 24),
            _buildServiceBreakdownSection(),
            const SizedBox(height: 24),
            _buildStaffPerformanceSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    String adminLabel = 'Admin';
    final role = widget.role;
    if (role == 'workshop_owner') {
      adminLabel = 'Workshop Owner';
    } else if (role == 'branch_admin') {
      if (widget.branchName != null && widget.branchName!.isNotEmpty) {
        adminLabel = '${widget.branchName} Admin';
      } else {
        adminLabel = 'Branch Admin';
      }
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
          // Profile button for workshop owners
          if (role == 'workshop_owner') ...[
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
          ],
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
          // Role pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    size: 12, color: Colors.white.withOpacity(0.8)),
                const SizedBox(width: 6),
                Text(
                  adminLabel,
                  style: TextStyle(
                    fontSize: 11,
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

  Widget _buildKpiSection() {
    final totalRevenueLabel =
        _loadingMetrics ? '—' : '\$${_totalRevenue.toStringAsFixed(0)}';
    final staffUtilPercent = _loadingMetrics
        ? '—'
        : '${(_staffUtilization * 100).toStringAsFixed(0)}%';
    final clientRetentionPercent = _loadingMetrics
        ? '—'
        : '${(_clientRetention * 100).toStringAsFixed(0)}%';
    final avgTicketLabel =
        _loadingMetrics ? '—' : '\$${_avgTicketValue.toStringAsFixed(0)}';
    final bookingCountLabel = _loadingMetrics ? '—' : '$_bookingCount';
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                title: 'Total Revenue',
                value: totalRevenueLabel,
                icon: FontAwesomeIcons.dollarSign,
                iconColor: AppColors.green,
                iconBg: AppColors.green.withOpacity(0.1),
                trend: '$_bookingCount bookings',
                trendUp: true,
                trendColor: AppColors.green,
                isPill: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                title: 'Staff Utilization',
                value: staffUtilPercent,
                icon: FontAwesomeIcons.users,
                iconColor: AppColors.blue,
                iconBg: AppColors.blue.withOpacity(0.1),
                progressBarValue:
                    _loadingMetrics ? 0.0 : _staffUtilization,
                progressBarColor: AppColors.blue,
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
                value: clientRetentionPercent,
                icon: FontAwesomeIcons.heart,
                iconColor: AppColors.purple,
                iconBg: AppColors.purple.withOpacity(0.1),
                progressBarValue:
                    _loadingMetrics ? 0.0 : _clientRetention,
                progressBarColor: AppColors.purple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                title: 'Avg Ticket Value',
                value: avgTicketLabel,
                icon: FontAwesomeIcons.receipt,
                iconColor: AppColors.primary,
                iconBg: AppColors.primary.withOpacity(0.1),
                trend: 'per booking',
                trendUp: true,
                trendColor: AppColors.primary,
                isPill: true,
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
    double? progressBarValue,
    Color? progressBarColor,
    bool isPill = false,
  }) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color muted = Theme.of(context).colorScheme.onBackground.withOpacity(0.6);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(icon, color: iconColor, size: 15),
                ),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: trendColor?.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    children: [
                      if (!isPill && trendUp == true) ...[
                        Icon(FontAwesomeIcons.arrowUp, size: 10, color: trendColor),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        trend,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: trendColor,
                        ),
                      ),
                    ],
                  ),
                ),
              if (progressBarValue != null)
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: progressBarColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (progressBarValue == null)
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
          if (progressBarValue != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progressBarValue,
                backgroundColor: Colors.grey.shade200,
                color: progressBarColor,
                minHeight: 6,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChartSection() {
    // Generate chart spots from real data
    List<FlSpot> spots = [];
    double maxRevenue = 0;
    
    if (_revenueByDay.isNotEmpty) {
      for (int i = 0; i < _revenueByDay.length; i++) {
        final revenue = (_revenueByDay[i]['revenue'] as num).toDouble();
        spots.add(FlSpot(i.toDouble(), revenue / 100)); // Scale down for display
        if (revenue > maxRevenue) maxRevenue = revenue;
      }
    } else {
      // Default empty state
      for (int i = 0; i < 7; i++) {
        spots.add(FlSpot(i.toDouble(), 0));
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
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
              Text(
                'Revenue Trends',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              Text(
                'Last 7 Days',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_loadingMetrics)
            const SizedBox(
              height: 250,
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (maxRevenue == 0)
            SizedBox(
              height: 250,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.show_chart, size: 48, color: AppColors.muted.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    Text(
                      'No revenue data yet',
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < _revenueByDay.length) {
                            final date = _revenueByDay[index]['date'] as String;
                            // Show only day number
                            final parts = date.split('-');
                            if (parts.length == 3) {
                              final day = int.tryParse(parts[2]) ?? 0;
                              final month = int.tryParse(parts[1]) ?? 0;
                              const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                                             'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  index == 0 || index == 6 
                                      ? '${months[month]} $day' 
                                      : '$day',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                                ),
                              );
                            }
                          }
                          return const Text('');
                        },
                        interval: 1,
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final index = spot.spotIndex;
                          if (index >= 0 && index < _revenueByDay.length) {
                            final revenue = _revenueByDay[index]['revenue'] as num;
                            return LineTooltipItem(
                              '\$${revenue.toStringAsFixed(0)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }
                          return null;
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: AppColors.primary,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: AppColors.primary,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primary.withOpacity(0.1),
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
    // Colors for pie chart sections
    const List<Color> pieColors = [
      AppColors.primary,
      AppColors.primaryDark,
      Color(0xFF333333),
      Color(0xFF555555),
      Color(0xFFFBCFE8),
    ];

    // Generate pie chart sections from real data
    List<PieChartSectionData> sections = [];
    List<Widget> legends = [];

    if (_serviceBreakdown.isNotEmpty) {
      for (int i = 0; i < _serviceBreakdown.length && i < 5; i++) {
        final service = _serviceBreakdown[i];
        final name = service['name'] as String;
        final percentage = service['percentage'] as int;
        final color = pieColors[i % pieColors.length];

        sections.add(PieChartSectionData(
          color: color,
          value: percentage.toDouble(),
          title: '',
          radius: 50,
        ));

        // Truncate long service names
        String displayName = name.length > 15 ? '${name.substring(0, 12)}...' : name;
        legends.add(_buildLegendItem(color, '$displayName ($percentage%)'));
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Revenue by Service',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 24),
          if (_loadingMetrics)
            const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_serviceBreakdown.isEmpty)
            SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pie_chart_outline, size: 48, color: AppColors.muted.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    Text(
                      'No service data yet',
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: sections,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: legends,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontSize: 10, color: AppColors.muted),
          ),
        ],
      ),
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
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
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
              Text(
                'Top Performers',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              if (_topPerformers.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_topPerformers.length} staff',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.green,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingMetrics)
            const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_topPerformers.isEmpty)
            SizedBox(
              height: 150,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline, size: 48, color: AppColors.muted.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    Text(
                      'No staff performance data yet',
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Complete bookings to see staff rankings',
                      style: TextStyle(color: AppColors.muted.withOpacity(0.7), fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(
              _topPerformers.length,
              (index) {
                final performer = _topPerformers[index];
                final name = performer['name'] as String;
                final revenue = (performer['revenue'] as num).toDouble();
                final services = performer['services'] as int;
                
                return _buildStaffItem(
                  name,
                  '$services services',
                  revenue.toStringAsFixed(0),
                  index + 1, // Rank
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStaffItem(String name, String subtitle, String revenue, int rank) {
    // Colors for rank badges
    Color rankColor;
    Color rankBgColor;
    IconData? rankIcon;
    
    switch (rank) {
      case 1:
        rankColor = const Color(0xFFD97706);
        rankBgColor = const Color(0xFFFEF3C7);
        rankIcon = FontAwesomeIcons.crown;
        break;
      case 2:
        rankColor = const Color(0xFF6B7280);
        rankBgColor = const Color(0xFFF3F4F6);
        break;
      case 3:
        rankColor = const Color(0xFFB45309);
        rankBgColor = const Color(0xFFFED7AA);
        break;
      default:
        rankColor = AppColors.muted;
        rankBgColor = Colors.grey.shade100;
    }

    // Get initials from name
    String initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final nameParts = name.split(' ');
    if (nameParts.length > 1 && nameParts[1].isNotEmpty) {
      initials = '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rankBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: rank == 1 && rankIcon != null
                  ? Icon(rankIcon, size: 12, color: rankColor)
                  : Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: rankColor,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          // Revenue
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '\$$revenue',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

