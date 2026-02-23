import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/audit_log_service.dart';
import 'branch_location_picker_page.dart';

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
// MODELS
// ============================================================================

class BranchModel {
  final String id;
  final String name;
  final String address;
  final String? phone;
  final String? email;
  final String status;
  final int? bookingLimitPerDay;
  final Map<String, dynamic>? hours;
  final List<String> serviceIds;
  final List<String> staffIds;
  final String? adminStaffId;
  final String timezone; // IANA timezone string
  // Location data for geofenced check-in
  final double? locationLatitude;
  final double? locationLongitude;
  final String? locationAddress;
  final String? locationPlaceId;
  final int allowedCheckInRadius;

  BranchModel({
    required this.id,
    required this.name,
    required this.address,
    this.phone,
    this.email,
    required this.status,
    this.bookingLimitPerDay,
    this.hours,
    this.serviceIds = const [],
    this.staffIds = const [],
    this.adminStaffId,
    this.timezone = 'Australia/Sydney',
    this.locationLatitude,
    this.locationLongitude,
    this.locationAddress,
    this.locationPlaceId,
    this.allowedCheckInRadius = 100,
  });

  bool get hasLocation => locationLatitude != null && locationLongitude != null;

  factory BranchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final location = data['location'] as Map<String, dynamic>?;
    return BranchModel(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      phone: data['phone'],
      email: data['email'],
      status: data['status'] ?? 'Active',
      bookingLimitPerDay: data['bookingLimitPerDay'],
      hours: data['hours'] as Map<String, dynamic>?,
      serviceIds: List<String>.from(data['serviceIds'] ?? []),
      staffIds: List<String>.from(data['staffIds'] ?? []),
      adminStaffId: data['adminStaffId'],
      timezone: data['timezone'] ?? 'Australia/Sydney',
      locationLatitude: location?['latitude']?.toDouble(),
      locationLongitude: location?['longitude']?.toDouble(),
      locationAddress: location?['formattedAddress'],
      locationPlaceId: location?['placeId'],
      allowedCheckInRadius: data['allowedCheckInRadius'] ?? 100,
    );
  }
}

/// Timezone options matching admin panel
const List<Map<String, String>> kTimezones = [
  // Australia
  {'value': 'Australia/Sydney', 'label': '🇦🇺 Sydney (NSW) - AEST/AEDT'},
  {'value': 'Australia/Melbourne', 'label': '🇦🇺 Melbourne (VIC) - AEST/AEDT'},
  {'value': 'Australia/Brisbane', 'label': '🇦🇺 Brisbane (QLD) - AEST'},
  {'value': 'Australia/Perth', 'label': '🇦🇺 Perth (WA) - AWST'},
  {'value': 'Australia/Adelaide', 'label': '🇦🇺 Adelaide (SA) - ACST/ACDT'},
  {'value': 'Australia/Darwin', 'label': '🇦🇺 Darwin (NT) - ACST'},
  {'value': 'Australia/Hobart', 'label': '🇦🇺 Hobart (TAS) - AEST/AEDT'},
  {'value': 'Australia/Canberra', 'label': '🇦🇺 Canberra (ACT) - AEST/AEDT'},
  {'value': 'Australia/Lord_Howe', 'label': '🇦🇺 Lord Howe Island - LHST/LHDT'},
  {'value': 'Australia/Broken_Hill', 'label': '🇦🇺 Broken Hill (NSW) - ACST/ACDT'},
  // Other countries
  {'value': 'Pacific/Auckland', 'label': '🇳🇿 Auckland (New Zealand)'},
  {'value': 'Asia/Singapore', 'label': '🇸🇬 Singapore'},
  {'value': 'Asia/Hong_Kong', 'label': '🇭🇰 Hong Kong'},
  {'value': 'Asia/Tokyo', 'label': '🇯🇵 Tokyo (Japan)'},
  {'value': 'Asia/Colombo', 'label': '🇱🇰 Colombo (Sri Lanka)'},
  {'value': 'Asia/Dubai', 'label': '🇦🇪 Dubai (UAE)'},
  {'value': 'Europe/London', 'label': '🇬🇧 London (UK)'},
  {'value': 'America/New_York', 'label': '🇺🇸 New York (US Eastern)'},
  {'value': 'America/Los_Angeles', 'label': '🇺🇸 Los Angeles (US Pacific)'},
];

class ServiceOption {
  final String id;
  final String name;

  ServiceOption({required this.id, required this.name});
}

class StaffOption {
  final String id;
  final String name;
  final String? role;
  final String? status;
  final String? avatar;
  final String? email;
  final Map<String, dynamic>? weeklySchedule;

  StaffOption({
    required this.id,
    required this.name,
    this.role,
    this.status,
    this.avatar,
    this.email,
    this.weeklySchedule,
  });
}

// ============================================================================
// BRANCHES PAGE
// ============================================================================

class BranchesPage extends StatefulWidget {
  const BranchesPage({super.key});

  @override
  State<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends State<BranchesPage> {
  String? _ownerUid;
  String? _userRole;
  String? _userBranchId; // For branch admins - their assigned branch
  List<BranchModel> _branches = [];
  List<ServiceOption> _services = [];
  List<StaffOption> _staff = [];
  bool _loading = true;

  bool get _isBranchAdmin => _userRole == 'branch_admin';
  bool get _canEdit => _userRole == 'workshop_owner';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String role = (userDoc.data()?['role'] ?? '').toString();
      // role is already normalized (staff, branch_admin, workshop_owner)
      _userRole = role;
      String ownerUid = user.uid;
      String? userBranchId;

      if (role == 'branch_admin') {
        ownerUid = userDoc.data()?['ownerUid'] ?? user.uid;
        userBranchId = userDoc.data()?['branchId'];
      }

      _ownerUid = ownerUid;
      _userBranchId = userBranchId;

      // Subscribe to branches
      FirebaseFirestore.instance
          .collection('branches')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          List<BranchModel> allBranches = snapshot.docs
              .map((doc) => BranchModel.fromFirestore(doc))
              .toList();
          
          // For branch admins, only show their assigned branch
          if (_isBranchAdmin && _userBranchId != null) {
            allBranches = allBranches.where((b) => b.id == _userBranchId).toList();
          }
          
          setState(() {
            _branches = allBranches;
          });
        }
      });

      // Subscribe to services
      FirebaseFirestore.instance
          .collection('services')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _services = snapshot.docs.map((doc) {
              final data = doc.data();
              return ServiceOption(
                id: doc.id,
                name: data['name'] ?? '',
              );
            }).toList();
          });
        }
      });

      // Subscribe to staff
      FirebaseFirestore.instance
          .collection('users')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _staff = snapshot.docs
                .where((doc) {
                  final role = doc.data()['role'] ?? '';
                  return role == 'staff' || role == 'branch_admin';
                })
                .map((doc) {
                  final data = doc.data();
                  return StaffOption(
                    id: doc.id,
                    name: data['displayName'] ?? data['name'] ?? '',
                    role: data['staffRole'],
                    status: data['status'],
                    avatar: data['avatar'],
                    email: data['email'],
                    weeklySchedule: data['weeklySchedule'] as Map<String, dynamic>?,
                  );
                })
                .toList();
          });
        }
      });

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() => _loading = false);
    }
  }

  void _showAddBranchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BranchFormSheet(
        ownerUid: _ownerUid!,
        services: _services,
        staff: _staff,
        branches: _branches,
        onSuccess: () {
          Navigator.pop(context);
          _showToast('Branch added successfully!');
        },
        onError: (msg) => _showToast(msg),
      ),
    );
  }

  void _showEditBranchSheet(BranchModel branch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BranchFormSheet(
        ownerUid: _ownerUid!,
        branch: branch,
        services: _services,
        staff: _staff,
        branches: _branches,
        onSuccess: () {
          Navigator.pop(context);
          _showToast('Branch updated successfully!');
        },
        onError: (msg) => _showToast(msg),
      ),
    );
  }

  void _showBranchPreview(BranchModel branch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BranchPreviewSheet(
        branch: branch,
        services: _services,
        staff: _staff,
        canEdit: _canEdit,
        onEdit: () {
          Navigator.pop(context);
          _showEditBranchSheet(branch);
        },
      ),
    );
  }

  void _confirmDelete(BranchModel branch) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(FontAwesomeIcons.triangleExclamation,
                  color: Colors.red.shade600, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Delete Branch?', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${branch.name}"? This action cannot be undone.',
          style: const TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteBranch(branch);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBranch(BranchModel branch) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      
      // Get branch data to check for admin
      final branchDoc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branch.id)
          .get();
      final branchData = branchDoc.data();
      final adminStaffId = branchData?['adminStaffId'] as String?;

      // Demote branch admin to regular staff before deleting branch
      if (adminStaffId != null && adminStaffId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(adminStaffId)
              .update({
            'role': 'staff',
            'systemRole': 'staff',
            'branchId': FieldValue.delete(),
            'branchName': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          debugPrint('Demoted branch admin $adminStaffId to regular staff');
        } catch (e) {
          debugPrint('Error demoting branch admin: $e');
          // Continue with deletion even if demotion fails
        }
      }

      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
        final userName = userData?['displayName'] ?? userData?['name'] ?? user.email ?? 'Unknown';
        final userRole = userData?['role'] ?? 'unknown';

        await FirebaseFirestore.instance
            .collection('branches')
            .doc(branch.id)
            .delete();

        // Create audit log
        await AuditLogService.logBranchDeleted(
          ownerUid: _ownerUid!,
          branchId: branch.id,
          branchName: branch.name,
          performedBy: user.uid,
          performedByName: userName,
          performedByRole: userRole,
        );
      } else {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(branch.id)
            .delete();
      }

      _showToast('Branch deleted');
    } catch (e) {
      debugPrint('Error deleting branch: $e');
      _showToast('Failed to delete branch');
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(FontAwesomeIcons.circleCheck, color: Colors.white, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                          child: const Center(
                            child: Icon(FontAwesomeIcons.arrowLeft, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isBranchAdmin ? 'My Branch' : 'Branches',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
                            ),
                            Text(
                              '${_branches.length} location${_branches.length == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                            ),
                          ],
                        ),
                      ),
                      if (_canEdit && _ownerUid != null)
                        GestureDetector(
                          onTap: _showAddBranchSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FontAwesomeIcons.plus, color: Colors.white, size: 12),
                                SizedBox(width: 6),
                                Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                              ],
                            ),
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
                : _branches.isEmpty
                    ? _buildEmptyState()
                    : _buildBranchesList(),
          ),
          ],
        ),
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
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF34D399)],
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Icon(FontAwesomeIcons.building, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 24),
          Text(
            _isBranchAdmin ? 'No Branch Assigned' : 'No Branches Yet',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isBranchAdmin 
                ? 'Contact your salon owner for branch assignment'
                : 'Add your first branch location',
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          if (_canEdit) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddBranchSheet,
              icon: const Icon(FontAwesomeIcons.plus, size: 14),
              label: const Text('Add Branch'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBranchesList() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _branches.length,
        itemBuilder: (context, index) {
          final branch = _branches[index];
          return _buildBranchCard(branch);
        },
      ),
    );
  }

  Widget _buildBranchCard(BranchModel branch) {
    final isOpen = _isBranchOpen(branch.hours);
    final statusColor = _getStatusColor(branch.status);
    
    // Calculate staff count based on weeklySchedule
    final staffCount = _staff.where((s) {
      final schedule = s.weeklySchedule;
      if (schedule == null) return false;
      return schedule.values.any((day) {
        if (day is Map) {
          return day['branchId'] == branch.id;
        }
        return false;
      });
    }).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with gradient
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF10B981).withOpacity(0.1),
                  const Color(0xFF34D399).withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF34D399)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(FontAwesomeIcons.building, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              branch.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  branch.status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(FontAwesomeIcons.locationDot, size: 11, color: Colors.grey.shade500),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              branch.address,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Info Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Stats Row
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        FontAwesomeIcons.clock,
                        isOpen ? 'Open Now' : 'Closed',
                        isOpen ? Colors.green : Colors.red,
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        FontAwesomeIcons.scissors,
                        '${branch.serviceIds.length} Services',
                        const Color(0xFF8B5CF6),
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        FontAwesomeIcons.users,
                        '$staffCount Staff',
                        const Color(0xFF3B82F6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Timezone Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FontAwesomeIcons.globe, size: 11, color: const Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Text(
                        _getTimezoneShortLabel(branch.timezone),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showBranchPreview(branch),
                        icon: const Icon(FontAwesomeIcons.eye, size: 12),
                        label: const Text('View'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    // Only show Edit and Delete for salon owners
                    if (_canEdit) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showEditBranchSheet(branch),
                          icon: const Icon(FontAwesomeIcons.penToSquare, size: 12),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF3B82F6),
                            side: BorderSide(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 44,
                        child: OutlinedButton(
                          onPressed: () => _confirmDelete(branch),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade400,
                            side: BorderSide(color: Colors.red.shade200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Icon(FontAwesomeIcons.trash, size: 12, color: Colors.red.shade400),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  bool _isBranchOpen(Map<String, dynamic>? hours) {
    if (hours == null) return false;
    final now = DateTime.now();
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final today = dayNames[now.weekday - 1];
    final todayHours = hours[today];
    if (todayHours == null || todayHours['closed'] == true) return false;
    
    final openTime = todayHours['open'] as String?;
    final closeTime = todayHours['close'] as String?;
    if (openTime == null || closeTime == null) return false;

    final openParts = openTime.split(':');
    final closeParts = closeTime.split(':');
    final openMinutes = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
    final closeMinutes = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
    final nowMinutes = now.hour * 60 + now.minute;

    return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green;
      case 'Pending':
        return Colors.orange;
      case 'Closed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getTimezoneShortLabel(String timezone) {
    final tz = kTimezones.firstWhere(
      (t) => t['value'] == timezone,
      orElse: () => {'value': timezone, 'label': timezone},
    );
    String label = tz['label'] ?? timezone;
    // Extract city name
    if (label.contains('🇦🇺')) {
      // Australian timezone - extract city name
      final match = RegExp(r'🇦🇺\s+(\w+)').firstMatch(label);
      if (match != null) return match.group(1)!;
    }
    // For other timezones, extract the main part
    if (label.contains(' (')) {
      label = label.split(' (').first;
    }
    // Remove any emoji
    label = label.replaceAll(RegExp(r'[^\x00-\x7F]+'), '').trim();
    return label.isEmpty ? timezone.split('/').last.replaceAll('_', ' ') : label;
  }
}

// ============================================================================
// BRANCH FORM SHEET (ADD/EDIT)
// ============================================================================

class _BranchFormSheet extends StatefulWidget {
  final String ownerUid;
  final BranchModel? branch;
  final List<ServiceOption> services;
  final List<StaffOption> staff;
  final List<BranchModel> branches;
  final VoidCallback onSuccess;
  final Function(String) onError;

  const _BranchFormSheet({
    required this.ownerUid,
    this.branch,
    required this.services,
    required this.staff,
    required this.branches,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<_BranchFormSheet> createState() => _BranchFormSheetState();
}

class _BranchFormSheetState extends State<_BranchFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _bookingLimitController;

  bool _saving = false;
  late String _status;
  late Map<String, Map<String, dynamic>> _hours;
  String? _selectedAdminStaffId;
  
  // Timezone
  late String _timezone;
  
  // Location data
  double? _locationLatitude;
  double? _locationLongitude;
  String? _locationAddress;
  int _allowedCheckInRadius = 50;

  @override
  void initState() {
    super.initState();
    final branch = widget.branch;
    _nameController = TextEditingController(text: branch?.name ?? '');
    _addressController = TextEditingController(text: branch?.address ?? '');
    _phoneController = TextEditingController(text: branch?.phone ?? '');
    _bookingLimitController = TextEditingController(text: branch?.bookingLimitPerDay?.toString() ?? '');
    _status = branch?.status ?? 'Active';
    _selectedAdminStaffId = branch?.adminStaffId;
    
    // Initialize timezone
    _timezone = branch?.timezone ?? 'Australia/Sydney';
    
    // Initialize location data
    _locationLatitude = branch?.locationLatitude;
    _locationLongitude = branch?.locationLongitude;
    _locationAddress = branch?.locationAddress;
    _allowedCheckInRadius = branch?.allowedCheckInRadius ?? 50;

    // Initialize hours
    _hours = {
      'Monday': {'open': '09:00', 'close': '17:00', 'closed': false},
      'Tuesday': {'open': '09:00', 'close': '17:00', 'closed': false},
      'Wednesday': {'open': '09:00', 'close': '17:00', 'closed': false},
      'Thursday': {'open': '09:00', 'close': '17:00', 'closed': false},
      'Friday': {'open': '09:00', 'close': '17:00', 'closed': false},
      'Saturday': {'open': '10:00', 'close': '16:00', 'closed': false},
      'Sunday': {'open': '10:00', 'close': '16:00', 'closed': true},
    };

    if (branch?.hours != null) {
      branch!.hours!.forEach((day, value) {
        if (value is Map) {
          _hours[day] = Map<String, dynamic>.from(value);
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _bookingLimitController.dispose();
    super.dispose();
  }

  Future<void> _saveBranch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      // Get admin staff email - required for branch email
      String? adminEmail;
      String? managerName;
      if (_selectedAdminStaffId != null && _selectedAdminStaffId!.isNotEmpty) {
        try {
          final adminStaff = widget.staff.firstWhere(
            (s) => s.id == _selectedAdminStaffId,
          );
          adminEmail = adminStaff.email;
          managerName = adminStaff.name;
        } catch (e) {
          debugPrint('Admin staff not found: $e');
        }
      }

      // For new branches, email must come from branch admin
      if (widget.branch == null && (adminEmail == null || adminEmail.isEmpty)) {
        widget.onError('Branch Admin must have an email address');
        setState(() => _saving = false);
        return;
      }

      final data = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': adminEmail ?? widget.branch?.email ?? '',
        'bookingLimitPerDay': int.tryParse(_bookingLimitController.text),
        'status': _status,
        'timezone': _timezone,
        'hours': _hours,
        'serviceIds': [],
        'adminStaffId': _selectedAdminStaffId ?? null,
        'manager': managerName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // Add location data if set
      if (_locationLatitude != null && _locationLongitude != null) {
        data['location'] = {
          'latitude': _locationLatitude,
          'longitude': _locationLongitude,
          'formattedAddress': _locationAddress,
          'allowedCheckInRadius': _allowedCheckInRadius,
        };
      }

      final user = FirebaseAuth.instance.currentUser;
      final userDoc = user != null 
          ? await FirebaseFirestore.instance.collection('users').doc(user.uid).get()
          : null;
      final userData = userDoc?.data();
      final userName = userData?['displayName'] ?? userData?['name'] ?? user?.email ?? 'Unknown';
      final userRole = userData?['role'] ?? 'unknown';

      if (widget.branch == null) {
        // Create new branch
        data['ownerUid'] = widget.ownerUid;
        data['createdAt'] = FieldValue.serverTimestamp();
        data['staffIds'] = [];

        final docRef = await FirebaseFirestore.instance.collection('branches').add(data);
        final branchId = docRef.id;

        // If admin was assigned, call API to promote staff and send email
        if (_selectedAdminStaffId != null && _selectedAdminStaffId!.isNotEmpty) {
          try {
            final ownerToken = await user!.getIdToken();
            final branchHours = data['hours'] as Map<String, dynamic>?;
            
            final apiResponse = await http.post(
              Uri.parse('https://black.bmspros.com.au/api/branches/assign-admin'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $ownerToken',
              },
              body: json.encode({
                'branchId': branchId,
                'adminStaffId': _selectedAdminStaffId,
                'branchName': data['name'].toString(),
                'branchHours': branchHours,
              }),
            );

            if (apiResponse.statusCode != 200) {
              debugPrint('Failed to assign branch admin via API: ${apiResponse.body}');
            } else {
              debugPrint('Branch admin assigned and email sent successfully');
            }
          } catch (e) {
            debugPrint('Error calling branch admin assignment API: $e');
          }
        }

        // Create audit log
        if (user != null) {
          await AuditLogService.logBranchCreated(
            ownerUid: widget.ownerUid,
            branchId: branchId,
            branchName: data['name'].toString(),
            address: data['address'].toString(),
            performedBy: user.uid,
            performedByName: userName,
            performedByRole: userRole,
          );

          // Log admin assignment if admin was selected
          if (_selectedAdminStaffId != null && _selectedAdminStaffId!.isNotEmpty) {
            try {
              final adminStaff = widget.staff.firstWhere((s) => s.id == _selectedAdminStaffId);
                await AuditLogService.logBranchAdminAssigned(
                  ownerUid: widget.ownerUid,
                  branchId: branchId,
                  branchName: data['name'].toString(),
                  adminId: _selectedAdminStaffId!,
                  adminName: adminStaff.name,
                  performedBy: user.uid,
                  performedByName: userName,
                  performedByRole: userRole,
                );
            } catch (e) {
              debugPrint('Failed to log admin assignment: $e');
            }
          }
        }
      } else {
        // Update existing branch
        final branchId = widget.branch!.id;
        final changes = <String>[];
        
        if (widget.branch!.name != data['name']) {
          changes.add('Name: ${widget.branch!.name} → ${data['name']}');
        }
        if (widget.branch!.address != data['address']) {
          changes.add('Address updated');
        }
        if (widget.branch!.phone != data['phone']) {
          changes.add('Phone updated');
        }
        if (widget.branch!.status != data['status']) {
          changes.add('Status: ${widget.branch!.status} → ${data['status']}');
        }
        if (widget.branch!.adminStaffId != _selectedAdminStaffId) {
          if (_selectedAdminStaffId != null && _selectedAdminStaffId!.isNotEmpty) {
            try {
              final adminStaff = widget.staff.firstWhere((s) => s.id == _selectedAdminStaffId);
              changes.add('Admin: ${adminStaff.name}');
            } catch (e) {
              changes.add('Admin updated');
            }
          } else {
            changes.add('Admin removed');
          }
        }

        // If admin changed, call API to promote staff and send email
        if (widget.branch!.adminStaffId != _selectedAdminStaffId && 
            _selectedAdminStaffId != null && 
            _selectedAdminStaffId!.isNotEmpty) {
          try {
            final ownerToken = await user!.getIdToken();
            final branchHours = data['hours'] as Map<String, dynamic>?;
            
            final apiResponse = await http.post(
              Uri.parse('https://black.bmspros.com.au/api/branches/assign-admin'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $ownerToken',
              },
              body: json.encode({
                'branchId': branchId,
                'adminStaffId': _selectedAdminStaffId,
                'branchName': data['name'].toString(),
                'branchHours': branchHours,
              }),
            );

            if (apiResponse.statusCode != 200) {
              debugPrint('Failed to assign branch admin via API: ${apiResponse.body}');
              // Continue with direct update if API fails
            } else {
              debugPrint('Branch admin assigned and email sent successfully');
            }
          } catch (e) {
            debugPrint('Error calling branch admin assignment API: $e');
            // Continue with direct update if API fails
          }
        }

        await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .update(data);

        // Create audit log
        if (user != null) {
          await AuditLogService.logBranchUpdated(
            ownerUid: widget.ownerUid,
            branchId: branchId,
            branchName: data['name'].toString(),
            performedBy: user.uid,
            performedByName: userName,
            performedByRole: userRole,
            changes: changes.isNotEmpty ? changes.join(', ') : null,
          );

          // Log admin assignment change if changed
          if (widget.branch!.adminStaffId != _selectedAdminStaffId) {
            if (_selectedAdminStaffId != null && _selectedAdminStaffId!.isNotEmpty) {
              try {
                final adminStaff = widget.staff.firstWhere((s) => s.id == _selectedAdminStaffId);
                await AuditLogService.logBranchAdminAssigned(
                  ownerUid: widget.ownerUid,
                  branchId: branchId,
                  branchName: data['name'].toString(),
                  adminId: _selectedAdminStaffId!,
                  adminName: adminStaff.name,
                  performedBy: user.uid,
                  performedByName: userName,
                  performedByRole: userRole,
                );
              } catch (e) {
                debugPrint('Failed to log admin assignment: $e');
              }
            }
          }
        }
      }

      widget.onSuccess();
    } catch (e) {
      debugPrint('Error saving branch: $e');
      widget.onError('Failed to save branch');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.branch != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF34D399)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isEditing ? FontAwesomeIcons.penToSquare : FontAwesomeIcons.building,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEditing ? 'Edit Branch' : 'Add Branch',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          // Form
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Basic Info
                  _buildSectionCard(
                    title: 'Basic Information',
                    icon: FontAwesomeIcons.building,
                    iconColor: const Color(0xFF10B981),
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration('Branch Name', 'e.g. Melbourne Branch'),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        decoration: _inputDecoration('Address', 'Full address'),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              FontAwesomeIcons.circleInfo,
                              size: 12,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This will automatically fill from the Staff Check-in Location below',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              decoration: _inputDecoration('Phone', '(03) 1234 5678'),
                              keyboardType: TextInputType.phone,
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _bookingLimitController,
                              decoration: _inputDecoration('Booking Limit / Day', '10'),
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v != null && v.isNotEmpty) {
                                  final limit = int.tryParse(v);
                                  if (limit == null || limit <= 0) {
                                    return 'Must be a positive number';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Timezone Selector
                      DropdownButtonFormField<String>(
                        value: _timezone,
                        decoration: InputDecoration(
                          labelText: 'Time Zone',
                          hintText: 'Select timezone',
                          prefixIcon: const Icon(
                            FontAwesomeIcons.globe,
                            size: 16,
                            color: Color(0xFF10B981),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        isExpanded: true,
                        items: kTimezones.map((tz) {
                          return DropdownMenuItem<String>(
                            value: tz['value'],
                            child: Text(
                              tz['label']!,
                              style: const TextStyle(fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _timezone = value);
                          }
                        },
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              FontAwesomeIcons.circleInfo,
                              size: 12,
                              color: const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'All booking times will be shown in this timezone',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Contact & Admin Section
                  _buildSectionCard(
                    title: 'Contact & Admin',
                    icon: FontAwesomeIcons.addressBook,
                    iconColor: const Color(0xFF8B5CF6),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF8B5CF6).withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  FontAwesomeIcons.userShield,
                                  size: 14,
                                  color: const Color(0xFF8B5CF6),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Assign Branch Admin',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String?>(
                              value: _selectedAdminStaffId,
                              decoration: _inputDecoration('Branch Admin', 'Select staff member'),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('-- No Admin Assigned --'),
                                ),
                                ...widget.staff.map((staff) {
                                  // Check if this staff is already a branch admin
                                  String? branchName;
                                  try {
                                    final adminBranch = widget.branches.firstWhere(
                                      (b) => b.adminStaffId == staff.id && 
                                             (widget.branch == null || b.id != widget.branch!.id),
                                    );
                                    branchName = adminBranch.name;
                                  } catch (e) {
                                    // Staff is not a branch admin of any other branch
                                    branchName = null;
                                  }
                                  
                                  return DropdownMenuItem<String?>(
                                    value: staff.id,
                                    child: Text(
                                      branchName != null 
                                          ? '${staff.name} ($branchName)'
                                          : staff.name,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  );
                                }),
                              ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedAdminStaffId = value;
                                  });
                                },
                                validator: (v) {
                                  // Branch admin is required when creating a new branch
                                  if (widget.branch == null && (v == null || v.isEmpty)) {
                                    return 'Branch Admin is required';
                                  }
                                  return null;
                                },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'User role will become Branch Admin',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Status
                  _buildSectionCard(
                    title: 'Status',
                    icon: FontAwesomeIcons.toggleOn,
                    iconColor: _getStatusColor(_status),
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: ['Active', 'Pending', 'Closed'].map((status) {
                          final isSelected = _status == status;
                          final color = _getStatusColor(status);
                          return GestureDetector(
                            onTap: () => setState(() => _status = status),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? color.withOpacity(0.1) : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected ? color : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isSelected ? color : Colors.grey.shade300,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? color : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Operating Hours
                  _buildSectionCard(
                    title: 'Operating Hours',
                    icon: FontAwesomeIcons.clock,
                    iconColor: const Color(0xFF8B5CF6),
                    children: [
                      ..._hours.keys.map((day) => _buildHoursRow(day)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Check-in Location
                  _buildSectionCard(
                    title: 'Check-in Location',
                    icon: FontAwesomeIcons.locationDot,
                    iconColor: const Color(0xFFEF4444),
                    children: [
                      if (_locationLatitude != null && _locationLongitude != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(FontAwesomeIcons.mapPin, 
                                  color: Colors.green.shade700, size: 14),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _locationAddress ?? 'Location set',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green.shade700,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Radius: ${_allowedCheckInRadius}m',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(FontAwesomeIcons.triangleExclamation, 
                                color: Colors.amber.shade700, size: 16),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'No location set. Staff check-in will not be geofenced.',
                                  style: TextStyle(fontSize: 12, color: AppColors.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push<BranchLocationData>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BranchLocationPickerPage(
                                  branchId: widget.branch?.id, // Null for new branches
                                  branchName: _nameController.text.isNotEmpty 
                                      ? _nameController.text 
                                      : (widget.branch?.name ?? 'New Branch'),
                                  initialLatitude: _locationLatitude,
                                  initialLongitude: _locationLongitude,
                                  initialRadius: _allowedCheckInRadius,
                                  initialAddress: _locationAddress,
                                ),
                              ),
                            );
                            if (result != null && mounted) {
                              setState(() {
                                _locationLatitude = result.latitude;
                                _locationLongitude = result.longitude;
                                _locationAddress = result.formattedAddress;
                                _allowedCheckInRadius = result.allowedRadius;
                              });
                            }
                          },
                          icon: Icon(
                            _locationLatitude != null 
                                ? FontAwesomeIcons.penToSquare 
                                : FontAwesomeIcons.locationDot,
                            size: 14,
                          ),
                          label: Text(
                            _locationLatitude != null ? 'Edit Location' : 'Set Location',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Save Button
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveBranch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Saving...', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ],
                      )
                    : Text(
                        isEditing ? 'Save Changes' : 'Add Branch',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildHoursRow(String day) {
    final dayHours = _hours[day]!;
    final isClosed = dayHours['closed'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              day.substring(0, 3),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isClosed ? Colors.grey.shade400 : AppColors.text,
              ),
            ),
          ),
          Expanded(
            child: isClosed
                ? Text('Closed', style: TextStyle(fontSize: 13, color: Colors.grey.shade400))
                : Row(
                    children: [
                      _buildTimeDropdown(day, 'open'),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('-', style: TextStyle(color: AppColors.muted)),
                      ),
                      _buildTimeDropdown(day, 'close'),
                    ],
                  ),
          ),
          Switch(
            value: !isClosed,
            onChanged: (v) {
              setState(() {
                _hours[day]!['closed'] = !v;
              });
            },
            activeColor: const Color(0xFF10B981),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeDropdown(String day, String type) {
    final times = List.generate(24, (i) {
      final h = i.toString().padLeft(2, '0');
      return ['$h:00', '$h:30'];
    }).expand((e) => e).toList();

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _hours[day]![type] as String,
        icon: const Icon(FontAwesomeIcons.chevronDown, size: 10),
        style: const TextStyle(fontSize: 13, color: AppColors.text),
        items: times.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _hours[day]![type] = v;
            });
          }
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green;
      case 'Pending':
        return Colors.orange;
      case 'Closed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

// ============================================================================
// BRANCH PREVIEW SHEET
// ============================================================================

class _BranchPreviewSheet extends StatefulWidget {
  final BranchModel branch;
  final List<ServiceOption> services;
  final List<StaffOption> staff;
  final bool canEdit;
  final VoidCallback onEdit;

  const _BranchPreviewSheet({
    required this.branch,
    required this.services,
    required this.staff,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  State<_BranchPreviewSheet> createState() => _BranchPreviewSheetState();
}

class _BranchPreviewSheetState extends State<_BranchPreviewSheet> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    final branchServices = widget.services.where((s) => widget.branch.serviceIds.contains(s.id)).toList();
    
    // Filter staff who work at this branch based on their weeklySchedule
    final branchStaff = widget.staff.where((s) {
      final schedule = s.weeklySchedule;
      if (schedule == null) return false;
      // Check if any day in their schedule is for this branch
      return schedule.values.any((day) {
        if (day is Map) {
          return day['branchId'] == widget.branch.id;
        }
        return false;
      });
    }).toList();
    
    // Filter staff for selected date
    final filteredStaff = _selectedDate == null
        ? branchStaff
        : branchStaff.where((s) {
            final schedule = s.weeklySchedule;
            if (schedule == null) return false;
            final dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
            final dayName = dayNames[_selectedDate!.weekday % 7];
            final daySchedule = schedule[dayName];
            if (daySchedule is Map) {
              return daySchedule['branchId'] == widget.branch.id;
            }
            return false;
          }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF34D399)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(FontAwesomeIcons.building, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Branch Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Basic Info
                _buildSectionCard(
                  title: 'Basic Information',
                  icon: FontAwesomeIcons.building,
                  iconColor: const Color(0xFF10B981),
                  child: Column(
                    children: [
                      _buildDetailRow('Name', widget.branch.name),
                      const Divider(height: 20),
                      _buildDetailRow('Address', widget.branch.address),
                      if (widget.branch.phone != null && widget.branch.phone!.isNotEmpty) ...[
                        const Divider(height: 20),
                        _buildDetailRow('Phone', widget.branch.phone!),
                      ],
                      if (widget.branch.email != null && widget.branch.email!.isNotEmpty) ...[
                        const Divider(height: 20),
                        _buildDetailRow('Email', widget.branch.email!),
                      ],
                      if (widget.branch.bookingLimitPerDay != null) ...[
                        const Divider(height: 20),
                        _buildDetailRow('Booking Limit / Day', '${widget.branch.bookingLimitPerDay} bookings'),
                      ],
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Status', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(widget.branch.status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.branch.status,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _getStatusColor(widget.branch.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(FontAwesomeIcons.globe, size: 12, color: AppColors.muted),
                              const SizedBox(width: 6),
                              const Text('Time Zone', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getTimezoneLabel(widget.branch.timezone),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Location for Check-in (read-only in preview)
                _buildSectionCard(
                  title: 'Check-in Location',
                  icon: FontAwesomeIcons.locationDot,
                  iconColor: const Color(0xFFEF4444),
                  child: widget.branch.hasLocation
                      ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(FontAwesomeIcons.mapPin, 
                                  color: Colors.green.shade700, size: 14),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.branch.locationAddress ?? 'Location set',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green.shade700,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Radius: ${widget.branch.allowedCheckInRadius}m',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(FontAwesomeIcons.triangleExclamation, 
                                color: Colors.amber.shade700, size: 16),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'No location set. Edit branch to set check-in location.',
                                  style: TextStyle(fontSize: 12, color: AppColors.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 16),

                // Operating Hours
                _buildSectionCard(
                  title: 'Operating Hours',
                  icon: FontAwesomeIcons.clock,
                  iconColor: const Color(0xFF8B5CF6),
                  child: _buildHoursDisplay(),
                ),
                const SizedBox(height: 16),

                // Services
                _buildSectionCard(
                  title: 'Services (${branchServices.length})',
                  icon: FontAwesomeIcons.scissors,
                  iconColor: const Color(0xFF1A1A1A),
                  child: branchServices.isEmpty
                      ? const Text('No services assigned', style: TextStyle(color: AppColors.muted))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: branchServices.map((s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              s.name,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1A1A1A),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )).toList(),
                        ),
                ),
                const SizedBox(height: 16),

                // Staff with Calendar
                _buildSectionCard(
                  title: 'Staff (${branchStaff.length})',
                  icon: FontAwesomeIcons.users,
                  iconColor: const Color(0xFF3B82F6),
                  child: branchStaff.isEmpty
                      ? const Text('No staff assigned', style: TextStyle(color: AppColors.muted))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Calendar for selecting day
                            _buildStaffCalendar(branchStaff),
                            const SizedBox(height: 16),
                            
                            // Selected date info
                            if (_selectedDate != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF3B82F6).withOpacity(0.1),
                                      const Color(0xFF3B82F6).withOpacity(0.05),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(FontAwesomeIcons.calendarDay, size: 14, color: Color(0xFF3B82F6)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${_getDayName(_selectedDate!.weekday)}, ${_selectedDate!.day} ${_getMonthName(_selectedDate!.month)} ${_selectedDate!.year}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF3B82F6),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${filteredStaff.length} staff working',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => setState(() => _selectedDate = null),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.close, size: 14, color: AppColors.muted),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            
                            // Legend
                            Row(
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text('Working Day', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade300,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text('Off Day', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            
                            // Staff list - filtered by selected date
                            if (filteredStaff.isEmpty && _selectedDate != null)
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Icon(FontAwesomeIcons.userSlash, size: 32, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No staff working on this day',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tap another date or clear selection',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              // Staff list - show admin first
                              ...filteredStaff
                                  .where((s) => s.id == widget.branch.adminStaffId)
                                  .map((s) => _buildStaffWithDays(s, widget.branch.id, isAdmin: true))
                                  .toList(),
                              ...filteredStaff
                                  .where((s) => s.id != widget.branch.adminStaffId)
                                  .map((s) => _buildStaffWithDays(s, widget.branch.id, isAdmin: false))
                                  .toList(),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          // Bottom Button
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: widget.canEdit
                  ? ElevatedButton.icon(
                      onPressed: widget.onEdit,
                      icon: const Icon(FontAwesomeIcons.penToSquare, size: 14),
                      label: const Text('Edit Branch', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: AppColors.text,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('Close', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // Calendar widget for staff schedule
  Widget _buildStaffCalendar(List<StaffOption> branchStaff) {
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startingWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0
    final today = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Month header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF3B82F6).withOpacity(0.1),
                  const Color(0xFF3B82F6).withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
                    });
                  },
                  icon: const Icon(FontAwesomeIcons.chevronLeft, size: 14),
                  color: const Color(0xFF3B82F6),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                Text(
                  '${_getMonthName(_focusedMonth.month)} ${_focusedMonth.year}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3B82F6),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                    });
                  },
                  icon: const Icon(FontAwesomeIcons.chevronRight, size: 14),
                  color: const Color(0xFF3B82F6),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
          
          // Day headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                  .map((day) => Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: day == 'Sun' || day == 'Sat'
                                  ? Colors.red.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          
          // Calendar grid
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              children: List.generate(6, (weekIndex) {
                return Row(
                  children: List.generate(7, (dayIndex) {
                    final dayNumber = weekIndex * 7 + dayIndex - startingWeekday + 1;
                    if (dayNumber < 1 || dayNumber > daysInMonth) {
                      return Expanded(child: Container(height: 40));
                    }
                    
                    final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayNumber);
                    final isSelected = _selectedDate != null &&
                        _selectedDate!.year == date.year &&
                        _selectedDate!.month == date.month &&
                        _selectedDate!.day == date.day;
                    final isToday = date.year == today.year &&
                        date.month == today.month &&
                        date.day == today.day;
                    
                    // Count staff working on this day
                    final dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
                    final dayName = dayNames[date.weekday % 7];
                    final staffWorkingCount = branchStaff.where((s) {
                      final schedule = s.weeklySchedule;
                      if (schedule == null) return false;
                      final daySchedule = schedule[dayName];
                      if (daySchedule is Map) {
                        return daySchedule['branchId'] == widget.branch.id;
                      }
                      return false;
                    }).length;
                    
                    final hasStaff = staffWorkingCount > 0;
                    
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedDate = null;
                            } else {
                              _selectedDate = date;
                            }
                          });
                        },
                        child: Container(
                          height: 40,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF3B82F6)
                                : isToday
                                    ? const Color(0xFF3B82F6).withOpacity(0.1)
                                    : hasStaff
                                        ? const Color(0xFF10B981).withOpacity(0.1)
                                        : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday && !isSelected
                                ? Border.all(color: const Color(0xFF3B82F6), width: 1.5)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$dayNumber',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected || isToday
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : dayIndex == 0 || dayIndex == 6
                                          ? Colors.red.shade400
                                          : AppColors.text,
                                ),
                              ),
                              if (hasStaff && !isSelected)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  width: 4,
                                  height: 4,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (isSelected && hasStaff)
                                Text(
                                  '$staffWorkingCount',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
          
          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Staff working', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ],
                ),
                const SizedBox(width: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Today', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  String _getDayName(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[weekday - 1];
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildHoursDisplay() {
    if (widget.branch.hours == null) {
      return const Text('No hours configured', style: TextStyle(color: AppColors.muted));
    }

    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      children: List.generate(days.length, (index) {
        final day = days[index];
        final dayHours = widget.branch.hours![day];
        final isClosed = dayHours == null || dayHours['closed'] == true;
        final open = dayHours?['open'] ?? '';
        final close = dayHours?['close'] ?? '';

        return Container(
          margin: EdgeInsets.only(bottom: index < 6 ? 8 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isClosed ? Colors.grey.shade100 : const Color(0xFF8B5CF6).withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  shortDays[index],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isClosed ? Colors.grey.shade400 : const Color(0xFF8B5CF6),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  isClosed ? 'Closed' : '$open - $close',
                  style: TextStyle(
                    fontSize: 13,
                    color: isClosed ? Colors.grey.shade400 : AppColors.text,
                  ),
                ),
              ),
              Icon(
                isClosed ? FontAwesomeIcons.circleMinus : FontAwesomeIcons.circleCheck,
                size: 14,
                color: isClosed ? Colors.grey.shade300 : Colors.green,
              ),
            ],
          ),
        );
      }),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green;
      case 'Pending':
        return Colors.orange;
      case 'Closed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getTimezoneLabel(String timezone) {
    final tz = kTimezones.firstWhere(
      (t) => t['value'] == timezone,
      orElse: () => {'value': timezone, 'label': timezone},
    );
    // Return shortened label (remove emoji and extra info)
    String label = tz['label'] ?? timezone;
    // Extract just the city/region name
    if (label.contains(' - ')) {
      label = label.split(' - ').first;
    }
    // Remove emoji if present
    if (label.contains('🇦🇺') || label.contains('🇳🇿') || label.contains('🇸🇬') ||
        label.contains('🇭🇰') || label.contains('🇯🇵') || label.contains('🇱🇰') ||
        label.contains('🇦🇪') || label.contains('🇬🇧') || label.contains('🇺🇸')) {
      label = label.replaceAll(RegExp(r'[^\x00-\x7F]+'), '').trim();
    }
    return label.isEmpty ? timezone : label;
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Widget _buildStaffWithDays(StaffOption staff, String branchId, {bool isAdmin = false}) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final schedule = staff.weeklySchedule ?? {};
    
    // Get days this staff works at THIS branch
    final workingDays = days.where((day) {
      final daySchedule = schedule[day];
      if (daySchedule is Map) {
        return daySchedule['branchId'] == branchId;
      }
      return false;
    }).toList();

    final statusColor = staff.status == 'Active'
        ? const Color(0xFF10B981)
        : staff.status == 'Suspended'
            ? Colors.red
            : Colors.grey;

    // Admin highlight colors
    const adminGradient = [Color(0xFF8B5CF6), Color(0xFFA855F7)];
    final adminBorderColor = const Color(0xFF8B5CF6).withOpacity(0.4);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAdmin ? const Color(0xFF8B5CF6).withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAdmin ? adminBorderColor : Colors.grey.shade200,
          width: isAdmin ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isAdmin 
                ? const Color(0xFF8B5CF6).withOpacity(0.1)
                : Colors.black.withOpacity(0.03),
            blurRadius: isAdmin ? 12 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Admin badge
          if (isAdmin)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: adminGradient),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(FontAwesomeIcons.crown, size: 12, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Branch Admin',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          // Staff info row
          Row(
            children: [
              // Avatar with crown for admin
              Stack(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isAdmin 
                            ? adminGradient 
                            : const [Color(0xFFFCE7F3), Color(0xFFE9D5FF)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: staff.avatar != null && staff.avatar!.startsWith('http')
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              staff.avatar!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  _getInitials(staff.name),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isAdmin ? Colors.white : const Color(0xFF1A1A1A),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              _getInitials(staff.name),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isAdmin ? Colors.white : const Color(0xFF1A1A1A),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Name & role
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isAdmin ? FontWeight.w700 : FontWeight.w600,
                        color: isAdmin ? const Color(0xFF8B5CF6) : AppColors.text,
                      ),
                    ),
                    if (staff.role != null)
                      Text(
                        staff.role!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              // Status & days count
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (staff.status != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        staff.status!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${workingDays.length} day${workingDays.length != 1 ? 's' : ''}/week',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Day pills
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(days.length, (index) {
              final day = days[index];
              final isWorking = workingDays.contains(day);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isWorking
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isWorking
                        ? const Color(0xFF10B981).withOpacity(0.3)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Text(
                  shortDays[index],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isWorking
                        ? const Color(0xFF10B981)
                        : Colors.grey.shade400,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

