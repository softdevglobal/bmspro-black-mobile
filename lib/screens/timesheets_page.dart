import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/staff_check_in_service.dart';

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

// ============================================================================
// DATA MODELS
// ============================================================================

class StaffMember {
  final String id;
  final String name;
  final String? role;
  final String? branchName;
  final String? systemRole;
  final String? authUid;
  final String? uid;

  StaffMember({
    required this.id,
    required this.name,
    this.role,
    this.branchName,
    this.systemRole,
    this.authUid,
    this.uid,
  });

  factory StaffMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    String? rawSystemRole = data['role'];
    return StaffMember(
      id: doc.id,
      name: data['displayName'] ?? data['name'] ?? 'Unknown',
      role: data['staffRole'] ?? rawSystemRole,
      branchName: data['branchName'],
      systemRole: rawSystemRole,
      authUid: data['authUid'] ?? data['uid'] ?? doc.id,
      uid: data['uid'] ?? data['authUid'] ?? doc.id,
    );
  }
}


class DayWorkHours {
  final DateTime date;
  final List<StaffCheckInRecord> checkIns;
  final int totalHours;
  final int totalMinutes;

  DayWorkHours({
    required this.date,
    required this.checkIns,
    required this.totalHours,
    required this.totalMinutes,
  });
}

class StaffWorkSummary {
  final String staffId;
  final String staffName;
  final String? staffRole;
  final String? branchName;
  final String? systemRole;
  final List<DayWorkHours> days;
  final int totalHours;
  final int totalMinutes;

  StaffWorkSummary({
    required this.staffId,
    required this.staffName,
    this.staffRole,
    this.branchName,
    this.systemRole,
    required this.days,
    required this.totalHours,
    required this.totalMinutes,
  });
}

// ============================================================================
// TIMESHEETS PAGE
// ============================================================================

class TimesheetsPage extends StatefulWidget {
  const TimesheetsPage({super.key});

  @override
  State<TimesheetsPage> createState() => _TimesheetsPageState();
}

class _TimesheetsPageState extends State<TimesheetsPage> {
  String? _ownerUid;
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();
  List<StaffMember> _staffMembers = [];
  List<StaffWorkSummary> _workSummaries = [];
  
  // Filter states
  String _searchQuery = '';
  String _selectedRole = 'all';
  String _selectedBranch = 'all';
  double _minHours = 0.0;
  String _sortBy = 'hours';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    try {
      // Get owner UID
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      final role = userDoc.data()?['role'] ?? '';
      String ownerUid = user.uid;
      
      if (role == 'branch_admin') {
        ownerUid = userDoc.data()?['ownerUid'] ?? user.uid;
      }

      _ownerUid = ownerUid;

      // Subscribe to staff members
      FirebaseFirestore.instance
          .collection('users')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _staffMembers = snapshot.docs
                .where((doc) {
                  final role = doc.data()['role'] ?? '';
                  return role == 'staff' || role == 'branch_admin';
                })
                .map((doc) => StaffMember.fromFirestore(doc))
                .toList();
          });
          _fetchWorkHours();
        }
      });

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() => _loading = false);
    }
  }

  void _fetchWorkHours() async {
    if (_ownerUid == null || _staffMembers.isEmpty) {
      setState(() => _workSummaries = []);
      return;
    }

    try {
      final weekRange = _getWeekRange(_selectedDate);
      
      // Query all check-ins for the owner
      final checkInsQuery = await FirebaseFirestore.instance
          .collection('staff_check_ins')
          .where('ownerUid', isEqualTo: _ownerUid)
          .get();

      // Filter check-ins by week range
      final allCheckIns = checkInsQuery.docs
          .map((doc) => StaffCheckInRecord.fromFirestore(doc))
          .where((checkIn) {
            final checkInTime = checkIn.checkInTime;
            return checkInTime.isAfter(weekRange['start']!) &&
                   checkInTime.isBefore(weekRange['end']!.add(const Duration(seconds: 1)));
          })
          .toList();

      // Create staff ID map
      final staffByIdMap = <String, StaffMember>{};
      for (final staff in _staffMembers) {
        staffByIdMap[staff.id] = staff;
        if (staff.authUid != null) staffByIdMap[staff.authUid!] = staff;
        if (staff.uid != null && staff.uid != staff.authUid) {
          staffByIdMap[staff.uid!] = staff;
        }
      }

      // Group check-ins by staff
      final checkInsByStaff = <String, List<StaffCheckInRecord>>{};
      for (final checkIn in allCheckIns) {
        final staff = staffByIdMap[checkIn.staffId] ??
            _staffMembers.firstWhere(
              (s) => s.name.toLowerCase() == checkIn.staffName.toLowerCase(),
              orElse: () => StaffMember(id: checkIn.staffId, name: checkIn.staffName),
            );
        
        if (!checkInsByStaff.containsKey(staff.id)) {
          checkInsByStaff[staff.id] = [];
        }
        checkInsByStaff[staff.id]!.add(checkIn);
      }

      // Create summaries for all staff
      final summaries = <StaffWorkSummary>[];
      for (final staff in _staffMembers) {
        final checkIns = checkInsByStaff[staff.id] ?? [];
        final days = _calculateDaysWorkHours(checkIns, weekRange);
        final totals = _calculateTotalHours(days);
        
        summaries.add(StaffWorkSummary(
          staffId: staff.id,
          staffName: staff.name,
          staffRole: staff.role,
          branchName: staff.branchName,
          systemRole: staff.systemRole,
          days: days,
          totalHours: totals['hours']!,
          totalMinutes: totals['minutes']!,
        ));
      }

      // Sort by total hours (descending)
      summaries.sort((a, b) {
        final aTotal = a.totalHours * 60 + a.totalMinutes;
        final bTotal = b.totalHours * 60 + b.totalMinutes;
        return bTotal.compareTo(aTotal);
      });

      if (mounted) {
        setState(() => _workSummaries = summaries);
      }
    } catch (e) {
      debugPrint('Error fetching work hours: $e');
      if (mounted) {
        setState(() => _workSummaries = []);
      }
    }
  }

  Map<String, DateTime> _getWeekRange(DateTime date) {
    // Get Monday of the week (weekday 1 = Monday)
    final day = date.weekday;
    final diff = date.day - day + 1; // Adjust to get Monday
    final monday = DateTime(date.year, date.month, diff);
    final sunday = monday.add(const Duration(days: 6));
    
    return {
      'start': DateTime(monday.year, monday.month, monday.day, 0, 0, 0),
      'end': DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59),
    };
  }

  bool _isCurrentWeek(Map<String, DateTime> weekRange) {
    final now = DateTime.now();
    final currentWeekRange = _getWeekRange(now);
    return weekRange['start']!.year == currentWeekRange['start']!.year &&
           weekRange['start']!.month == currentWeekRange['start']!.month &&
           weekRange['start']!.day == currentWeekRange['start']!.day;
  }

  List<DayWorkHours> _calculateDaysWorkHours(
    List<StaffCheckInRecord> checkIns,
    Map<String, DateTime> weekRange,
  ) {
    final days = <DayWorkHours>[];
    final monday = weekRange['start']!;
    
    for (int i = 0; i < 7; i++) {
      final date = DateTime(monday.year, monday.month, monday.day + i);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      
      final dayCheckIns = checkIns.where((checkIn) {
        final checkInDate = DateFormat('yyyy-MM-dd').format(checkIn.checkInTime);
        return checkInDate == dateKey;
      }).toList();
      
      int dayHours = 0;
      int dayMinutes = 0;
      
      for (final checkIn in dayCheckIns) {
        final duration = _calculateDuration(
          checkIn.checkInTime,
          checkIn.checkOutTime,
          checkIn.breakPeriods,
        );
        dayHours += duration['hours']!;
        dayMinutes += duration['minutes']!;
      }
      
      if (dayMinutes >= 60) {
        dayHours += dayMinutes ~/ 60;
        dayMinutes = dayMinutes % 60;
      }
      
      days.add(DayWorkHours(
        date: date,
        checkIns: dayCheckIns,
        totalHours: dayHours,
        totalMinutes: dayMinutes,
      ));
    }
    
    return days;
  }

  Map<String, int> _calculateDuration(
    DateTime checkIn,
    DateTime? checkOut,
    List<BreakPeriod> breakPeriods,
  ) {
    final end = checkOut ?? DateTime.now();
    final totalDiff = end.difference(checkIn);
    
    // Calculate total break time
    int totalBreakMs = 0;
    for (final breakPeriod in breakPeriods) {
      if (breakPeriod.startTime != null) {
        final breakEnd = breakPeriod.endTime ?? DateTime.now();
        totalBreakMs += breakEnd.difference(breakPeriod.startTime!).inMilliseconds;
      }
    }
    
    // Subtract break time
    final workingMs = totalDiff.inMilliseconds - totalBreakMs;
    final hours = (workingMs / (1000 * 60 * 60)).floor();
    final minutes = ((workingMs % (1000 * 60 * 60)) / (1000 * 60)).floor();
    
    return {
      'hours': hours > 0 ? hours : 0,
      'minutes': minutes > 0 ? minutes : 0,
    };
  }

  Map<String, int> _calculateTotalHours(List<DayWorkHours> days) {
    int totalHours = 0;
    int totalMinutes = 0;
    
    for (final day in days) {
      totalHours += day.totalHours;
      totalMinutes += day.totalMinutes;
    }
    
    if (totalMinutes >= 60) {
      totalHours += totalMinutes ~/ 60;
      totalMinutes = totalMinutes % 60;
    }
    
    return {'hours': totalHours, 'minutes': totalMinutes};
  }

  String _formatDuration(int hours, int minutes) {
    if (hours == 0 && minutes == 0) return '0m';
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEE, d MMM').format(date);
  }

  String _formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date);
  }

  List<StaffWorkSummary> get _filteredSummaries {
    var filtered = List<StaffWorkSummary>.from(_workSummaries);

    // Filter by search query
    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((s) => s.staffName.toLowerCase().contains(query)).toList();
    }

    // Filter by role
    if (_selectedRole != 'all') {
      filtered = filtered.where((s) {
        if (_selectedRole == 'Branch Admin') {
          return s.systemRole == 'branch_admin';
        }
        return s.staffRole == _selectedRole;
      }).toList();
    }

    // Filter by branch
    if (_selectedBranch != 'all') {
      filtered = filtered.where((s) => s.branchName == _selectedBranch).toList();
    }

    // Filter by minimum hours
    if (_minHours > 0) {
      filtered = filtered.where((s) {
        final totalMinutes = s.totalHours * 60 + s.totalMinutes;
        final minMinutes = _minHours * 60;
        return totalMinutes >= minMinutes;
      }).toList();
    }

    // Sort
    if (_sortBy == 'name') {
      filtered.sort((a, b) => a.staffName.compareTo(b.staffName));
    } else {
      filtered.sort((a, b) {
        final aTotal = a.totalHours * 60 + a.totalMinutes;
        final bTotal = b.totalHours * 60 + b.totalMinutes;
        return bTotal.compareTo(aTotal);
      });
    }

    return filtered;
  }

  List<String> get _uniqueRoles {
    final roles = <String>{};
    for (final s in _workSummaries) {
      if (s.staffRole != null) roles.add(s.staffRole!);
      if (s.systemRole == 'branch_admin') roles.add('Branch Admin');
    }
    return roles.toList()..sort();
  }

  List<String> get _uniqueBranches {
    final branches = <String>{};
    for (final s in _workSummaries) {
      if (s.branchName != null && s.branchName!.trim().isNotEmpty) {
        branches.add(s.branchName!.trim());
      }
    }
    return branches.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final weekRange = _getWeekRange(_selectedDate);
    final weekDays = List.generate(7, (i) {
      final monday = weekRange['start']!;
      return DateTime(monday.year, monday.month, monday.day + i);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ═══════════ CREATIVE HERO HEADER ═══════════
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D), Color(0xFF1A1A1A)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF1A1A1A).withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(top: -20, right: -20, child: Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.03)))),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: const Center(child: Icon(FontAwesomeIcons.arrowLeft, size: 14, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Timesheets',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
                            ),
                            Text(
                              'Staff work hours overview',
                              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildWeekNavigation(weekRange),
                          _buildFilters(),
                          _buildSummaryStats(),
                          _filteredSummaries.isEmpty
                              ? SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.4,
                                  child: _buildEmptyState(),
                                )
                              : _buildTimesheetTable(weekDays),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekNavigation(Map<String, DateTime> weekRange) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF333333), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                  });
                  _fetchWorkHours();
                },
                icon: const Icon(FontAwesomeIcons.chevronLeft, color: Colors.white, size: 16),
              ),
              Text(
                '${_formatDate(weekRange['start']!)} - ${_formatDate(weekRange['end']!)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 7));
                  });
                  _fetchWorkHours();
                },
                icon: const Icon(FontAwesomeIcons.chevronRight, color: Colors.white, size: 16),
              ),
            ],
          ),
          if (_isCurrentWeek(weekRange))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime.now();
                  });
                  _fetchWorkHours();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('This Week'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.filter, color: AppColors.primary, size: 14),
              const SizedBox(width: 6),
              const Text(
                'Quick Filters',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Search
          TextField(
            decoration: InputDecoration(
              hintText: 'Search staff name...',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(FontAwesomeIcons.magnifyingGlass, size: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Role Filter
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedRole,
                  isDense: true,
                  style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  menuMaxHeight: 300,
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: SizedBox(
                        height: 32,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('All Roles', style: const TextStyle(fontSize: 13, color: AppColors.text), overflow: TextOverflow.visible),
                        ),
                      ),
                    ),
                    ..._uniqueRoles.map((role) => DropdownMenuItem(
                      value: role,
                      child: SizedBox(
                        height: 32,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(role, style: const TextStyle(fontSize: 13, color: AppColors.text), overflow: TextOverflow.visible),
                        ),
                      ),
                    )),
                  ],
                  onChanged: (value) => setState(() => _selectedRole = value ?? 'all'),
                ),
              ),
              const SizedBox(width: 6),
              // Branch Filter
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedBranch,
                  isDense: true,
                  style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  menuMaxHeight: 300,
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: SizedBox(
                        height: 32,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('All Branches', style: const TextStyle(fontSize: 13, color: AppColors.text), overflow: TextOverflow.visible),
                        ),
                      ),
                    ),
                    ..._uniqueBranches.map((branch) => DropdownMenuItem(
                      value: branch,
                      child: SizedBox(
                        height: 32,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(branch, style: const TextStyle(fontSize: 13, color: AppColors.text), overflow: TextOverflow.visible),
                        ),
                      ),
                    )),
                  ],
                  onChanged: (value) => setState(() => _selectedBranch = value ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Min Hours
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Min hours',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    prefixIcon: const Icon(FontAwesomeIcons.clock, size: 12, color: AppColors.muted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() => _minHours = double.tryParse(value) ?? 0.0);
                  },
                ),
              ),
              const SizedBox(width: 6),
              // Sort By
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _sortBy,
                  isDense: true,
                  style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  menuMaxHeight: 300,
                  items: const [
                    DropdownMenuItem(
                      value: 'hours',
                      child: Text('Sort by Hours', style: TextStyle(fontSize: 13, color: AppColors.text), overflow: TextOverflow.visible),
                    ),
                    DropdownMenuItem(
                      value: 'name',
                      child: Text('Sort by Name', style: TextStyle(fontSize: 13, color: AppColors.text), overflow: TextOverflow.visible),
                    ),
                  ],
                  onChanged: (value) => setState(() => _sortBy = value ?? 'hours'),
                ),
              ),
            ],
          ),
          if (_searchQuery.isNotEmpty || _selectedRole != 'all' || _selectedBranch != 'all' || _minHours > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _selectedRole = 'all';
                    _selectedBranch = 'all';
                    _minHours = 0.0;
                  });
                },
                icon: const Icon(FontAwesomeIcons.xmark, size: 11),
                label: const Text('Clear Filters', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryStats() {
    final filtered = _filteredSummaries;
    final totalHours = filtered.fold<int>(0, (sum, s) => sum + s.totalHours);
    final totalMinutes = filtered.fold<int>(0, (sum, s) => sum + s.totalMinutes);
    
    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Staff Members',
              '${filtered.length}',
              _workSummaries.length != filtered.length ? ' / ${_workSummaries.length}' : '',
              AppColors.primary,
              FontAwesomeIcons.users,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Total Hours',
              _formatDuration(totalHours, totalMinutes),
              '',
              const Color(0xFF10B981),
              FontAwesomeIcons.clock,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String suffix, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              children: [
                TextSpan(text: value),
                if (suffix.isNotEmpty)
                  TextSpan(
                    text: suffix,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Icon(FontAwesomeIcons.clock, color: AppColors.primary, size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Timesheet Data',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _workSummaries.isEmpty
                ? 'No timesheet data for this week'
                : 'No staff members match the current filters',
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
          if (_searchQuery.isNotEmpty || _selectedRole != 'all' || _selectedBranch != 'all' || _minHours > 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _selectedRole = 'all';
                    _selectedBranch = 'all';
                    _minHours = 0.0;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Clear Filters'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimesheetTable(List<DateTime> weekDays) {
    return Column(
      children: _filteredSummaries.map((summary) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _buildStaffTimesheetCard(summary, weekDays),
        );
      }).toList(),
    );
  }

  Widget _buildStaffTimesheetCard(StaffWorkSummary summary, List<DateTime> weekDays) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Staff Header
          Container(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary.withOpacity(0.8), AppColors.accent.withOpacity(0.6)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(summary.staffName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Staff Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.staffName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (summary.systemRole == 'branch_admin')
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Admin',
                                style: TextStyle(fontSize: 9, color: Colors.purple, fontWeight: FontWeight.bold),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              summary.systemRole == 'branch_admin'
                                  ? 'Branch Admin'
                                  : summary.staffRole ?? 'Staff',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                      if (summary.branchName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            summary.branchName!,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ),
                    ],
                  ),
                ),
                // Total Hours
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDuration(summary.totalHours, summary.totalMinutes),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const Text(
                      'Total',
                      style: TextStyle(fontSize: 10, color: AppColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Weekly Breakdown
          Container(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: weekDays.asMap().entries.map((entry) {
                final dayIndex = entry.key;
                final day = entry.value;
                final dayData = summary.days[dayIndex];
                final hasData = dayData.checkIns.isNotEmpty;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hasData ? AppColors.primary.withOpacity(0.05) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hasData ? AppColors.primary.withOpacity(0.2) : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Day Name
                      SizedBox(
                        width: 70,
                        child: Text(
                          _formatDate(day),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: hasData ? AppColors.primary : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Day Details
                      Expanded(
                        child: hasData
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...dayData.checkIns.map((checkIn) {
                                    final duration = _calculateDuration(
                                      checkIn.checkInTime,
                                      checkIn.checkOutTime,
                                      checkIn.breakPeriods,
                                    );
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${_formatTime(checkIn.checkInTime)} - ${checkIn.checkOutTime != null ? _formatTime(checkIn.checkOutTime!) : 'Active'}',
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                          ),
                                          Text(
                                            _formatDuration(duration['hours']!, duration['minutes']!),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  if (dayData.checkIns.length > 1)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Day Total: ${_formatDuration(dayData.totalHours, dayData.totalMinutes)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            : const Text(
                                '-',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}

