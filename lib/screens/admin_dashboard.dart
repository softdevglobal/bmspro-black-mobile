import 'dart:async';
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

  // Weekly calendar data
  DateTime _calendarWeekStart = _getWeekStart(DateTime.now());
  final List<Map<String, dynamic>> _calendarBookings = [];
  StreamSubscription<QuerySnapshot>? _calendarBookingsSub;
  String _calendarBranchFilter = 'all';
  String _calendarStaffFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadOwnerAnalytics();
    _listenToCalendarBookings();
  }

  static DateTime _getWeekStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final diff = (d.weekday - DateTime.monday) % 7;
    return d.subtract(Duration(days: diff));
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

  Future<void> _listenToCalendarBookings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String ownerUid = user.uid;
    if (widget.role == 'branch_admin') {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final ownerFromUser = (userDoc.data()?['ownerUid'] ?? '').toString();
      if (ownerFromUser.isNotEmpty) ownerUid = ownerFromUser;
    }

    _calendarBookingsSub?.cancel();
    _calendarBookingsSub = FirebaseFirestore.instance
        .collection('bookings')
        .where('ownerUid', isEqualTo: ownerUid)
        .snapshots()
        .listen((snap) {
      final next = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = d.data();
        final status = (data['status'] ?? '').toString().toLowerCase().trim();
        if (status == 'canceled' || status == 'cancelled' || status == 'staffrejected') {
          continue;
        }

        final branchName = (data['branchName'] ?? '').toString();
        if (widget.role == 'branch_admin' &&
            widget.branchName != null &&
            widget.branchName!.isNotEmpty &&
            branchName.toLowerCase() != widget.branchName!.toLowerCase()) {
          continue;
        }

        final services = (data['services'] is List) ? (data['services'] as List) : const [];
        final dateKey = _normalizeDateKey(data['date']);
        if (dateKey.isEmpty) continue;

        if (services.isNotEmpty) {
          for (final item in services) {
            if (item is! Map) continue;
            final svc = Map<String, dynamic>.from(item);
            final serviceName =
                (svc['serviceName'] ?? svc['name'] ?? data['serviceName'] ?? 'Service').toString();
            next.add({
              'id': d.id,
              'bookingCode': (data['bookingCode'] ?? '').toString(),
              'date': dateKey,
              'time': (svc['time'] ?? data['time'] ?? '09:00').toString(),
              'pickupTime': (data['pickupTime'] ?? data['pickUpTime'] ?? '').toString(),
              'duration': _parseDuration(svc['duration'] ?? data['duration']),
              'client': (data['client'] ?? data['clientName'] ?? 'Customer').toString(),
              'serviceName': serviceName,
              'status': (svc['completionStatus'] ?? data['status'] ?? 'Pending').toString(),
              'price': _parsePrice(svc['price'] ?? data['price']),
              'staffName': _pickStaffName(data, svc),
              'branchName': branchName,
            });
          }
        } else {
          next.add({
            'id': d.id,
            'bookingCode': (data['bookingCode'] ?? '').toString(),
            'date': dateKey,
            'time': (data['time'] ?? '09:00').toString(),
            'pickupTime': (data['pickupTime'] ?? data['pickUpTime'] ?? '').toString(),
            'duration': _parseDuration(data['duration']),
            'client': (data['client'] ?? data['clientName'] ?? 'Customer').toString(),
            'serviceName': (data['serviceName'] ?? 'Service').toString(),
            'status': (data['status'] ?? 'Pending').toString(),
            'price': _parsePrice(data['price']),
            'staffName': _pickStaffName(data),
            'branchName': branchName,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _calendarBookings
          ..clear()
          ..addAll(next);
      });
    });
  }

  String _normalizeDateKey(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) {
      final v = raw.trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return v;
      if (RegExp(r'^\d{4}/\d{2}/\d{2}$').hasMatch(v)) return v.replaceAll('/', '-');
      if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(v)) {
        final p = v.split('/');
        return '${p[2]}-${p[1]}-${p[0]}';
      }
      final d = DateTime.tryParse(v);
      if (d != null) {
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
      return '';
    }
    if (raw is Timestamp) {
      final d = raw.toDate();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return '';
  }

  int _parseDuration(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 60;
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

  double _parsePrice(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  ({int hour, int minute}) _parseTime(String value) {
    if (value.isEmpty) return (hour: 9, minute: 0);
    final upper = value.toUpperCase();
    final numberPart = value.replaceAll(RegExp(r'\s*(AM|PM)', caseSensitive: false), '').trim();
    // Handle "0700" or "0930" (HHMM) format when no colon
    if (!numberPart.contains(':')) {
      final s = numberPart.replaceAll(RegExp(r'\D'), '');
      if (s.length >= 4) {
        final h = int.tryParse(s.substring(0, 2)) ?? 9;
        final m = int.tryParse(s.substring(2, 4)) ?? 0;
        return (hour: h, minute: m);
      }
    }
    final parts = numberPart.split(':');
    int h = int.tryParse(parts[0]) ?? 9;
    int m = parts.length > 1 ? int.tryParse(parts[1].replaceAll(RegExp(r'\D'), '')) ?? 0 : 0;

    final isPM = upper.contains('PM');
    final isAM = upper.contains('AM');
    if (isPM && h < 12) h += 12;
    if (isAM && h == 12) h = 0;
    return (hour: h, minute: m);
  }

  String _format12h(int hour, int minute) {
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

  /// Assign overlap columns to day bookings (waterfall layout) so overlapping blocks show side-by-side
  List<Map<String, dynamic>> _assignOverlapColumns(List<Map<String, dynamic>> dayBookings) {
    if (dayBookings.isEmpty) return [];
    final withMins = dayBookings.map((b) {
      final tm = _parseTime((b['time'] ?? '09:00').toString());
      final dur = (b['duration'] as int?) ?? 60;
      final startM = tm.hour * 60 + tm.minute;
      final endM = startM + dur;
      return {...b, '_startM': startM, '_endM': endM};
    }).toList();
    withMins.sort((a, b) {
      final cmp = (a['_startM'] as int).compareTo(b['_startM'] as int);
      if (cmp != 0) return cmp;
      return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });
    final active = <({int endM, int col})>[];
    for (final b in withMins) {
      final startM = b['_startM'] as int;
      active.removeWhere((a) => a.endM <= startM);
      active.sort((a, b) => a.endM.compareTo(b.endM));
      final usedCols = active.map((a) => a.col).toSet();
      int col = 0;
      while (usedCols.contains(col)) col++;
      b['_overlapCol'] = col;
      active.add((endM: b['_endM'] as int, col: col));
    }
    final maxCol = withMins.isEmpty
        ? 0
        : withMins.map((b) => b['_overlapCol'] as int).reduce((a, b) => a > b ? a : b);
    final n = maxCol + 1;
    for (final b in withMins) {
      b['_overlapCount'] = n;
    }
    return withMins;
  }

  Widget _buildCalendarSection() {
    const startHour = 7;
    const endHour = 19; // exclusive
    const slotHeight = 26.0;
    const timeColWidth = 34.0;
    final gridHeight = (endHour - startHour) * slotHeight;
    final weekDates = List.generate(7, (i) => _calendarWeekStart.add(Duration(days: i)));
    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final weekLabel =
        '${weekDates.first.day}/${weekDates.first.month} - ${weekDates.last.day}/${weekDates.last.month}';
    final weekSet = weekDates
        .map((d) =>
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}')
        .toSet();
    final branchOptions = _calendarBookings
        .map((b) => (b['branchName'] ?? '').toString())
        .where((b) => b.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final branchFilteredForStaff = _calendarBookings.where((b) {
      if (_calendarBranchFilter == 'all') return true;
      return (b['branchName'] ?? '').toString() == _calendarBranchFilter;
    }).toList();
    final staffOptions = branchFilteredForStaff
        .map((b) => (b['staffName'] ?? '').toString())
        .where((s) =>
            s.isNotEmpty &&
            !s.toLowerCase().contains('any') &&
            s.toLowerCase() != 'unassigned' &&
            s.toLowerCase() != 'not assigned')
        .toSet()
        .toList()
      ..sort();
    final branchFilterValid =
        _calendarBranchFilter == 'all' || branchOptions.contains(_calendarBranchFilter);
    final staffFilterValid =
        _calendarStaffFilter == 'all' || staffOptions.contains(_calendarStaffFilter);
    final weekBookings = _calendarBookings.where((b) {
      final date = (b['date'] ?? '').toString();
      if (!weekSet.contains(date)) return false;
      final branchName = (b['branchName'] ?? '').toString();
      final staffName = (b['staffName'] ?? '').toString();
      final branchOk = !branchFilterValid || _calendarBranchFilter == 'all' || branchName == _calendarBranchFilter;
      final staffOk = !staffFilterValid || _calendarStaffFilter == 'all' || staffName == _calendarStaffFilter;
      return branchOk && staffOk;
    }).toList();

    final statusColors = <String, (Color bg, Color border, Color text)>{
      'completed': (const Color(0xFFDCEAFE), const Color(0xFF93C5FD), const Color(0xFF1D4ED8)),
      'confirmed': (const Color(0xFFDCFCE7), const Color(0xFF86EFAC), const Color(0xFF166534)),
    };
    final fallbackColors = [
      (const Color(0xFFE0F2FE), const Color(0xFF7DD3FC), const Color(0xFF075985)),
      (const Color(0xFFFEF3C7), const Color(0xFFFCD34D), const Color(0xFF92400E)),
      (const Color(0xFFEDE9FE), const Color(0xFFC4B5FD), const Color(0xFF5B21B6)),
      (const Color(0xFFFCE7F3), const Color(0xFFF9A8D4), const Color(0xFF9D174D)),
    ];

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
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.08),
            blurRadius: 16,
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
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(FontAwesomeIcons.calendarWeek, size: 12, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Calendar',
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
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: branchFilterValid ? _calendarBranchFilter : 'all',
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      borderRadius: BorderRadius.circular(12),
                      style: const TextStyle(fontSize: 12, color: AppColors.text, fontWeight: FontWeight.w600),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All Branches')),
                        ...branchOptions.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                      ],
                      onChanged: (v) => setState(() => _calendarBranchFilter = v ?? 'all'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: staffFilterValid ? _calendarStaffFilter : 'all',
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 10),
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
                        Text(
                          ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1],
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isToday ? Colors.white70 : AppColors.muted,
                          ),
                        ),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isToday ? Colors.white : AppColors.text,
                          ),
                        ),
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
                      final lbl = hour == 12
                          ? '12 PM'
                          : hour > 12
                              ? '${hour - 12} PM'
                              : '$hour AM';
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
                  final dayBookings =
                      weekBookings.where((b) => (b['date'] ?? '') == key).toList();
                  final dayBookingsWithOverlap = _assignOverlapColumns(dayBookings);
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: key == todayKey ? const Color(0xFFFEFCE8) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          return Stack(
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
                              ...dayBookingsWithOverlap.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final bk = entry.value;
                                final overlapCol = bk['_overlapCol'] as int? ?? 0;
                                final overlapCount = bk['_overlapCount'] as int? ?? 1;
                                final blockWidth = overlapCount <= 1
                                    ? w - 3
                                    : (w - 3 - (overlapCount - 1) * 1) / overlapCount;
                                final left = 1.5 + overlapCol * (blockWidth + 1);
                                final tm = _parseTime((bk['time'] ?? '09:00').toString());
                                final dur = (bk['duration'] as int?) ?? 60;
                                final top = ((tm.hour - startHour) * slotHeight) +
                                    ((tm.minute / 60) * slotHeight);
                                if (top < 0 || top > gridHeight - 8) return const SizedBox.shrink();
                                final height = ((dur / 60) * slotHeight).clamp(22.0, 90.0);
                                final endMins = tm.hour * 60 + tm.minute + dur;
                                final endHour = endMins ~/ 60;
                                final endMin = endMins % 60;
                                final status = (bk['status'] ?? '').toString().toLowerCase();
                                final palette = statusColors[status] ?? fallbackColors[idx % fallbackColors.length];
                                final isCompact = overlapCount > 1 && blockWidth < 45;
                                return Positioned(
                                  top: top + 1,
                                  left: left,
                                  width: blockWidth,
                                  height: height,
                                  child: GestureDetector(
                                    onTap: () => _showCalendarBookingDetails(bk),
                                    child: Container(
                                      padding: EdgeInsets.fromLTRB(isCompact ? 2 : 4, 3, isCompact ? 2 : 4, 3),
                                      decoration: BoxDecoration(
                                        color: palette.$1,
                                        border: Border.all(color: palette.$2, width: 1.0),
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: palette.$2.withOpacity(0.18),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            (bk['client'] ?? 'Customer').toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: isCompact ? 7 : 8,
                                              fontWeight: FontWeight.w700,
                                              color: palette.$3,
                                            ),
                                          ),
                                          if (!isCompact)
                                            Text(
                                              (bk['serviceName'] ?? 'Service').toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 7,
                                                color: palette.$3.withOpacity(0.85),
                                              ),
                                            ),
                                          const Spacer(),
                                          Text(
                                            '${_format12h(tm.hour, tm.minute)} - ${_format12h(endHour, endMin)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: isCompact ? 6 : 7,
                                              fontWeight: FontWeight.w600,
                                              color: palette.$3.withOpacity(0.9),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
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
    final start = _parseTime((bk['time'] ?? '09:00').toString());
    final duration = (bk['duration'] as int?) ?? 60;
    final endTotalMins = start.hour * 60 + start.minute + duration;
    final endHour = endTotalMins ~/ 60;
    final endMin = endTotalMins % 60;
    final pickupRaw = (bk['pickupTime'] ?? '').toString().trim();
    final pickup = pickupRaw.isNotEmpty
        ? (() {
            final p = _parseTime(pickupRaw);
            return _format12h(p.hour, p.minute);
          })()
        : _format12h(endHour, endMin);
    final status = (bk['status'] ?? 'Pending').toString();
    final bookingCode = (bk['bookingCode'] ?? '').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        title: Row(
          children: [
            const Icon(FontAwesomeIcons.calendarDay, size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Booking Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (status.toLowerCase() == 'completed' || status.toLowerCase() == 'confirmed')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status.toLowerCase() == 'completed'
                      ? const Color(0xFFDBEAFE)
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: status.toLowerCase() == 'completed'
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF166534),
                  ),
                ),
              ),
          ],
        ),
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
            _detailRow(
              'Time',
              '${_format12h(start.hour, start.minute)} - ${_format12h(endHour, endMin)}',
            ),
            _detailRow('Pick-up Time', pickup),
            _detailRow('Duration', '$duration min'),
            _detailRow('Staff', (bk['staffName'] ?? 'Not assigned').toString()),
            _detailRow('Branch', (bk['branchName'] ?? 'No branch').toString()),
            _detailRow('Status', status),
            _detailRow('Price', '\$${(bk['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
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
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
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
  void dispose() {
    _calendarBookingsSub?.cancel();
    super.dispose();
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
            _buildCalendarSection(),
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
          // Decorative circles
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
          Positioned(
            bottom: -30,
            left: -10,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.02),
              ),
            ),
          ),
          Column(
            children: [
              Row(
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
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.15),
                                Colors.white.withOpacity(0.05),
                              ],
                            ),
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
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
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
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.12),
                          Colors.white.withOpacity(0.06),
                        ],
                      ),
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
                            size: 12, color: const Color(0xFFFFD700).withOpacity(0.9)),
                        const SizedBox(width: 6),
                        Text(
                          adminLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Revenue highlight row
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(FontAwesomeIcons.chartLine, size: 14, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Revenue',
                            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _loadingMetrics ? '—' : '\$${_totalRevenue.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_bookingCount} bookings',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF10B981).withOpacity(0.9),
                        ),
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
  }

  Widget _buildKpiSection() {
    final staffUtilPercent = _loadingMetrics
        ? '—'
        : '${(_staffUtilization * 100).toStringAsFixed(0)}%';
    final clientRetentionPercent = _loadingMetrics
        ? '—'
        : '${(_clientRetention * 100).toStringAsFixed(0)}%';
    final avgTicketLabel =
        _loadingMetrics ? '—' : '\$${_avgTicketValue.toStringAsFixed(0)}';
    final bookingCountLabel = _loadingMetrics ? '—' : '$_bookingCount';
    
    return SizedBox(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildKpiPill(
            icon: FontAwesomeIcons.calendarCheck,
            label: 'Bookings',
            value: bookingCountLabel,
            color: AppColors.green,
            bgColor: const Color(0xFFECFDF5),
          ),
          const SizedBox(width: 10),
          _buildKpiPill(
            icon: FontAwesomeIcons.users,
            label: 'Utilization',
            value: staffUtilPercent,
            color: AppColors.blue,
            bgColor: const Color(0xFFEFF6FF),
          ),
          const SizedBox(width: 10),
          _buildKpiPill(
            icon: FontAwesomeIcons.heart,
            label: 'Retention',
            value: clientRetentionPercent,
            color: AppColors.purple,
            bgColor: const Color(0xFFF5F3FF),
          ),
          const SizedBox(width: 10),
          _buildKpiPill(
            icon: FontAwesomeIcons.receipt,
            label: 'Avg Ticket',
            value: avgTicketLabel,
            color: const Color(0xFFF59E0B),
            bgColor: const Color(0xFFFFFBEB),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const Spacer(),
              Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5),
              ),
            ],
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  // KPI cards replaced by creative pills above

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

