import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'appointment_details_page.dart';

class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}

class OtherStaffAppointmentsPage extends StatefulWidget {
  final String branchId;
  final String ownerUid;

  const OtherStaffAppointmentsPage({
    super.key,
    required this.branchId,
    required this.ownerUid,
  });

  @override
  State<OtherStaffAppointmentsPage> createState() => _OtherStaffAppointmentsPageState();
}

class _OtherStaffAppointmentsPageState extends State<OtherStaffAppointmentsPage> {
  List<Map<String, dynamic>> _appointments = [];
  bool _isLoading = true;
  String _selectedFilter = 'today'; // 'today', 'upcoming', 'all'

  @override
  void initState() {
    super.initState();
    _listenToAppointments();
  }

  void _listenToAppointments() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final currentUserId = user.uid;

    // Listen to bookings for this branch
    FirebaseFirestore.instance
        .collection('bookings')
        .where('ownerUid', isEqualTo: widget.ownerUid)
        .where('branchId', isEqualTo: widget.branchId)
        .snapshots()
        .listen((snap) {
      final List<Map<String, dynamic>> appointments = [];
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      for (final doc in snap.docs) {
        final data = doc.data();
        final date = data['date']?.toString() ?? '';
        final status = data['status']?.toString() ?? 'pending';
        final client = data['client']?.toString() ?? data['clientName']?.toString() ?? 'Client';
        final bookingTime = data['time']?.toString() ?? data['startTime']?.toString() ?? '';

        // Check if this booking is assigned to current user - if so, skip it
        bool isMyAppointment = false;
        
        // Check top-level staffId
        final staffId = data['staffId']?.toString();
        final staffAuthUid = data['staffAuthUid']?.toString();
        if (staffId == currentUserId || staffAuthUid == currentUserId) {
          isMyAppointment = true;
        }

        // Check services array for multi-service bookings
        if (!isMyAppointment && data['services'] is List && (data['services'] as List).isNotEmpty) {
          for (final service in (data['services'] as List)) {
            if (service is Map) {
              final serviceStaffId = service['staffId']?.toString();
              final serviceStaffAuthUid = service['staffAuthUid']?.toString();
              if (serviceStaffId == currentUserId || serviceStaffAuthUid == currentUserId) {
                isMyAppointment = true;
                break;
              }
            }
          }
        }

        // Skip if this is the current user's appointment
        if (isMyAppointment) {
          continue;
        }

        // Process appointments assigned to other staff
        if (data['services'] is List && (data['services'] as List).isNotEmpty) {
          // Multi-service booking - create entry for each service assigned to other staff
          for (final service in (data['services'] as List)) {
            if (service is Map) {
              final serviceStaffId = service['staffId']?.toString();
              final serviceStaffAuthUid = service['staffAuthUid']?.toString();
              
              // Skip if assigned to current user
              if (serviceStaffId == currentUserId || serviceStaffAuthUid == currentUserId) {
                continue;
              }

              final serviceName = service['name']?.toString() ?? service['serviceName']?.toString() ?? 'Service';
              final duration = service['duration']?.toString() ?? '';
              final serviceTime = service['time']?.toString() ?? bookingTime;
              final approvalStatus = service['approvalStatus']?.toString();
              final completionStatus = service['completionStatus']?.toString()?.toLowerCase() ?? '';
              final staffName = service['staffName']?.toString() ?? 
                               data['staffName']?.toString() ?? 'Unassigned';
              
              // Determine display status - prioritize service completion status
              String displayStatus = status;
              if (completionStatus == 'completed') {
                displayStatus = 'completed';
              } else if (status.toLowerCase().contains('awaiting') || status.toLowerCase().contains('partially')) {
                displayStatus = approvalStatus == 'accepted' ? 'confirmed' : 
                                approvalStatus == 'rejected' ? 'rejected' : 'pending';
              }
              
              appointments.add({
                'id': doc.id,
                'serviceId': service['id']?.toString() ?? '',
                'serviceName': serviceName,
                'duration': duration,
                'time': serviceTime,
                'date': date,
                'status': displayStatus,
                'bookingStatus': status,
                'approvalStatus': approvalStatus,
                'completionStatus': completionStatus,
                'client': client,
                'staffName': staffName,
                'data': data,
                'isToday': date == todayStr,
                'isFuture': date.compareTo(todayStr) > 0,
              });
            }
          }
        } else {
          // Legacy: Single-service booking assigned to other staff
          final serviceName = data['serviceName']?.toString() ?? data['service']?.toString() ?? 'Service';
          final duration = data['duration']?.toString() ?? '';
          final staffName = data['staffName']?.toString() ?? 'Unassigned';

          appointments.add({
            'id': doc.id,
            'serviceName': serviceName,
            'duration': duration,
            'time': bookingTime,
            'date': date,
            'status': status,
            'client': client,
            'staffName': staffName,
            'data': data,
            'isToday': date == todayStr,
            'isFuture': date.compareTo(todayStr) > 0,
          });
        }
      }

      // Sort by date and time
      appointments.sort((a, b) {
        final dateCompare = (a['date'] ?? '').compareTo(b['date'] ?? '');
        if (dateCompare != 0) return dateCompare;
        return (a['time'] ?? '').compareTo(b['time'] ?? '');
      });

      if (!mounted) return;
      setState(() {
        _appointments = appointments;
        _isLoading = false;
      });
    }, onError: (e) {
      debugPrint('Error fetching other staff appointments: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  List<Map<String, dynamic>> get _filteredAppointments {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    // Filter to only show confirmed appointments (exclude pending)
    final confirmedAppointments = _appointments.where((a) {
      final status = (a['status']?.toString() ?? '').toLowerCase();
      return status == 'confirmed' || status == 'completed';
    }).toList();
    
    switch (_selectedFilter) {
      case 'today':
        return confirmedAppointments.where((a) => a['isToday'] == true).toList();
      case 'upcoming':
        // Show confirmed bookings that are in future days (not today)
        return confirmedAppointments.where((a) {
          final date = a['date']?.toString() ?? '';
          return date.compareTo(todayStr) > 0;
        }).toList();
      case 'all':
      default:
        return confirmedAppointments;
    }
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
      [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)],
      [const Color(0xFF1A1A1A), const Color(0xFF111111)],
      [const Color(0xFF333333), const Color(0xFF1A1A1A)],
      [const Color(0xFF60A5FA), const Color(0xFF3B82F6)],
      [const Color(0xFF34D399), const Color(0xFF10B981)],
      [const Color(0xFFF59E0B), const Color(0xFFD97706)],
    ];
    return colorSets[index % colorSets.length];
  }

  String _formatTime(String time) {
    if (time.isEmpty) return '';
    if (time.toUpperCase().contains('AM') || time.toUpperCase().contains('PM')) {
      return time;
    }
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

  String _formatDate(String date) {
    if (date.isEmpty) return '';
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        return '${months[month - 1]} $day';
      }
    } catch (_) {}
    return date;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return const Color(0xFF10B981);
      case 'completed':
        return const Color(0xFF3B82F6);
      case 'cancelled':
      case 'rejected':
        return const Color(0xFFEF4444);
      case 'awaiting':
      case 'awaitingstaffapproval':
      case 'pending':
      default:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildFilterTabs(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _filteredAppointments.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredAppointments.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final appt = _filteredAppointments[index];
                            return _buildAppointmentTile(appt, index);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(color: AppColors.background),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(FontAwesomeIcons.chevronLeft,
                size: 18, color: AppColors.text),
          ),
          Expanded(
            child: Center(
              child: Column(
                children: [
                  const Text(
                    'Other Staff Appointments',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text),
                  ),
                  Text(
                    '${_filteredAppointments.length} appointments',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip('Today', 'today'),
          const SizedBox(width: 8),
          _buildFilterChip('Upcoming', 'upcoming'),
          const SizedBox(width: 8),
          _buildFilterChip('All', 'all'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(colors: [AppColors.primary, AppColors.accent])
              : null,
          color: isSelected ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? null : Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.muted,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FontAwesomeIcons.calendarXmark,
            size: 48,
            color: AppColors.muted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedFilter == 'today'
                ? 'No appointments today'
                : _selectedFilter == 'upcoming'
                    ? 'No upcoming appointments'
                    : 'No appointments found',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Other staff appointments will appear here',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.muted.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentTile(Map<String, dynamic> appt, int index) {
    final serviceName = appt['serviceName'] ?? 'Service';
    final duration = appt['duration'];
    final time = appt['time'] ?? '';
    final date = appt['date'] ?? '';
    final status = appt['status'] ?? 'pending';
    final client = appt['client'] ?? '';
    final staffName = appt['staffName'] ?? 'Unassigned';
    final isToday = appt['isToday'] == true;

    final displayTitle = duration != null && duration.isNotEmpty
        ? '$serviceName ${duration}min'
        : serviceName;

    final icon = _getServiceIcon(serviceName);
    final colors = _getServiceColors(index);
    final statusColor = _getStatusColor(status);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AppointmentDetailsPage(appointmentData: appt),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              blurRadius: 25,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(FontAwesomeIcons.clock, size: 10, color: AppColors.muted),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(time),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      if (!isToday && date.isNotEmpty) ...[
                        const Text(' • ', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        Text(
                          _formatDate(date),
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                  if (staffName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(FontAwesomeIcons.user, size: 10, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            staffName,
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Icon(FontAwesomeIcons.chevronRight,
                    size: 12, color: AppColors.muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
