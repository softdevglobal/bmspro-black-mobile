import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

class Branch {
  final String id;
  final String name;
  final double? latitude;
  final double? longitude;
  final double? allowedCheckInRadius;

  Branch({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
    this.allowedCheckInRadius,
  });
}

// ============================================================================
// ATTENDANCE & GPS PAGE
// ============================================================================

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  String? _ownerUid;
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();
  String _selectedBranchId = 'all';
  List<StaffCheckInRecord> _checkIns = [];
  List<Branch> _branches = [];
  String _activeView = 'list'; // 'map' or 'list'
  GoogleMapController? _mapController;
  
  // Stream subscriptions for cleanup
  dynamic _branchesSubscription;
  dynamic _checkInsSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _branchesSubscription?.cancel();
    _checkInsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    try {
      // Get owner UID - check staff collection first (like admin panel)
      String ownerUid = user.uid;
      
      // Try staff collection first
      final staffDoc = await FirebaseFirestore.instance
          .collection('staff')
          .doc(user.uid)
          .get();
      
      if (staffDoc.exists && staffDoc.data()?['ownerUid'] != null) {
        ownerUid = staffDoc.data()!['ownerUid'];
        debugPrint('Got ownerUid from staff: $ownerUid');
      } else {
        // Fall back to users collection
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        final role = userDoc.data()?['role'] ?? '';
        if (role == 'branch_admin' || role == 'staff') {
          ownerUid = userDoc.data()?['ownerUid'] ?? user.uid;
        }
        debugPrint('Got ownerUid from users: $ownerUid (role: $role)');
      }

      _ownerUid = ownerUid;
      debugPrint('Final ownerUid: $_ownerUid');

      // Subscribe to branches (real-time)
      _branchesSubscription = FirebaseFirestore.instance
          .collection('branches')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _branches = snapshot.docs.map((doc) {
              final data = doc.data();
              final location = data['location'];
              return Branch(
                id: doc.id,
                name: data['name'] ?? '',
                latitude: location?['latitude']?.toDouble(),
                longitude: location?['longitude']?.toDouble(),
                allowedCheckInRadius: (data['allowedCheckInRadius'] ?? 100).toDouble(),
              );
            }).toList();
          });
          debugPrint('Loaded ${_branches.length} branches');
        }
      }, onError: (e) {
        debugPrint('Error subscribing to branches: $e');
      });

      // Subscribe to check-ins (real-time)
      _subscribeToCheckIns();

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() => _loading = false);
    }
  }

  void _subscribeToCheckIns() {
    if (_ownerUid == null) return;

    // Cancel existing subscription
    _checkInsSubscription?.cancel();

    // Get start and end of selected date
    final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
    final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);

    debugPrint('Subscribing to check-ins for ownerUid: $_ownerUid');
    debugPrint('Date range: $startOfDay to $endOfDay');

    // Subscribe to check-ins for the owner (real-time like admin panel)
    _checkInsSubscription = FirebaseFirestore.instance
        .collection('staff_check_ins')
        .where('ownerUid', isEqualTo: _ownerUid)
        .snapshots()
        .listen((snapshot) {
      debugPrint('Received ${snapshot.docs.length} total check-ins from Firestore');
      
      // Filter by date in memory (like admin panel's timesheet approach)
      final allCheckIns = snapshot.docs
          .map((doc) {
            try {
              return StaffCheckInRecord.fromFirestore(doc);
            } catch (e) {
              debugPrint('Error parsing check-in ${doc.id}: $e');
              return null;
            }
          })
          .where((checkIn) => checkIn != null)
          .cast<StaffCheckInRecord>()
          .where((checkIn) {
            final checkInTime = checkIn.checkInTime;
            final isInRange = checkInTime.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
                   checkInTime.isBefore(endOfDay.add(const Duration(seconds: 1)));
            return isInRange;
          })
          .toList();
      
      // Sort by checkInTime descending (most recent first) - like admin panel
      allCheckIns.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

      debugPrint('Filtered to ${allCheckIns.length} check-ins for selected date');
      
      if (mounted) {
        setState(() => _checkIns = allCheckIns);
      }
    }, onError: (e) {
      debugPrint('Error subscribing to check-ins: $e');
      if (mounted) {
        setState(() => _checkIns = []);
      }
    });
  }
  
  // Called when date changes to re-subscribe with new date filter
  void _onDateChanged() {
    _subscribeToCheckIns();
  }

  List<StaffCheckInRecord> get _filteredCheckIns {
    if (_selectedBranchId == 'all') return _checkIns;
    return _checkIns.where((c) => c.branchId == _selectedBranchId).toList();
  }

  List<StaffCheckInRecord> get _activeCheckIns {
    return _filteredCheckIns.where((c) => c.status == 'checked_in').toList();
  }

  List<StaffCheckInRecord> get _completedCheckIns {
    return _filteredCheckIns.where((c) => c.status == 'checked_out' || c.status == 'auto_checked_out').toList();
  }

  List<StaffCheckInRecord> get _outsideRadiusCheckIns {
    return _filteredCheckIns.where((c) => !c.isWithinRadius).toList();
  }

  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)}m';
    }
    return '${(distanceInMeters / 1000).toStringAsFixed(2)}km';
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEEE, d MMMM yyyy').format(date);
  }

  String _formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date);
  }

  String _calculateDuration(StaffCheckInRecord checkIn) {
    final start = checkIn.checkInTime;
    final end = checkIn.checkOutTime ?? DateTime.now();
    final totalDiff = end.difference(start);
    
    // Calculate break time
    int totalBreakSeconds = 0;
    for (final breakPeriod in checkIn.breakPeriods) {
      if (breakPeriod.endTime != null) {
        totalBreakSeconds += breakPeriod.endTime!.difference(breakPeriod.startTime).inSeconds;
      } else {
        // Active break
        totalBreakSeconds += DateTime.now().difference(breakPeriod.startTime).inSeconds;
      }
    }
    
    final workingSeconds = totalDiff.inSeconds - totalBreakSeconds;
    final hours = workingSeconds ~/ 3600;
    final minutes = (workingSeconds % 60) ~/ 60;
    
    if (hours == 0 && minutes == 0) return '0m';
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
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
                              'Attendance & GPS',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
                            ),
                            Text(
                              'Track staff check-ins & locations',
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
                        _buildStatsCards(),
                        _buildDateNavigation(),
                        _buildViewToggle(),
                        _activeView == 'list' ? _buildListView() : _buildMapView(),
                        _buildBranchQuickView(),
                      ],
                    ),
                  ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Currently Active',
              '${_activeCheckIns.length}',
              Colors.blue,
              FontAwesomeIcons.clock,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Completed Today',
              '${_completedCheckIns.length}',
              Colors.green,
              FontAwesomeIcons.circleCheck,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Total Check-ins',
              '${_checkIns.length}',
              Colors.purple,
              FontAwesomeIcons.users,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Outside Radius',
              '${_outsideRadiusCheckIns.length}',
              Colors.red,
              FontAwesomeIcons.triangleExclamation,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
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
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDateNavigation() {
    final isToday = _selectedDate.year == DateTime.now().year &&
                    _selectedDate.month == DateTime.now().month &&
                    _selectedDate.day == DateTime.now().day;

    return Container(
      margin: const EdgeInsets.all(16),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                  });
                  _onDateChanged();
                },
                icon: const Icon(FontAwesomeIcons.chevronLeft, size: 16),
              ),
              Expanded(
                child: Text(
                  _formatDate(_selectedDate),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                  });
                  _onDateChanged();
                },
                icon: const Icon(FontAwesomeIcons.chevronRight, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Branch Filter
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedBranchId,
                  isDense: true,
                  style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    labelText: 'Branch',
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Branches', style: TextStyle(fontSize: 13, color: AppColors.text)),
                    ),
                    ..._branches.map((branch) => DropdownMenuItem(
                      value: branch.id,
                      child: Text(branch.name, style: const TextStyle(fontSize: 13, color: AppColors.text)),
                    )),
                  ],
                  onChanged: (value) => setState(() => _selectedBranchId = value ?? 'all'),
                ),
              ),
              const SizedBox(width: 8),
              // Today Button
              if (!isToday)
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedDate = DateTime.now();
                    });
                    _onDateChanged();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text('Today'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeView = 'map'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _activeView == 'map' ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      FontAwesomeIcons.map,
                      size: 14,
                      color: _activeView == 'map' ? AppColors.primary : AppColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Map',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _activeView == 'map' ? AppColors.primary : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeView = 'list'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _activeView == 'list' ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      FontAwesomeIcons.list,
                      size: 14,
                      color: _activeView == 'list' ? AppColors.primary : AppColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'List',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _activeView == 'list' ? AppColors.primary : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = {};

    // Add branch markers
    for (final branch in _branches) {
      if (branch.latitude != null && branch.longitude != null) {
        final position = LatLng(branch.latitude!, branch.longitude!);
        final activeStaffCount = _checkIns
            .where((c) => c.branchId == branch.id && c.status == 'checked_in')
            .length;
        
        // Branch marker
        markers.add(
          Marker(
            markerId: MarkerId('branch_${branch.id}'),
            position: position,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            infoWindow: InfoWindow(
              title: branch.name,
              snippet: '$activeStaffCount active • Radius: ${_formatDistance(branch.allowedCheckInRadius ?? 100)}',
            ),
          ),
        );
      }
    }

    // Add staff check-in markers
    for (final checkIn in _filteredCheckIns) {
      final isActive = checkIn.status == 'checked_in';
      final isOutsideRadius = !checkIn.isWithinRadius;
      
      // Determine marker color based on status
      double hue;
      if (isOutsideRadius) {
        hue = BitmapDescriptor.hueRed; // Red for outside radius
      } else if (isActive) {
        hue = BitmapDescriptor.hueGreen; // Green for active
      } else {
        hue = BitmapDescriptor.hueAzure; // Blue for completed
      }

      markers.add(
        Marker(
          markerId: MarkerId('staff_${checkIn.id}'),
          position: LatLng(checkIn.staffLatitude, checkIn.staffLongitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: checkIn.staffName,
            snippet: '${isActive ? "Active" : "Completed"} at ${checkIn.branchName}\n${_formatDistance(checkIn.distanceFromBranch)} from branch',
          ),
        ),
      );
    }

    return markers;
  }

  Set<Circle> _buildCircles() {
    final Set<Circle> circles = {};

    // Add branch check-in radius circles
    for (final branch in _branches) {
      if (branch.latitude != null && branch.longitude != null) {
        final position = LatLng(branch.latitude!, branch.longitude!);
        
        circles.add(
          Circle(
            circleId: CircleId('radius_${branch.id}'),
            center: position,
            radius: branch.allowedCheckInRadius ?? 100,
            strokeWidth: 2,
            strokeColor: AppColors.primary,
            fillColor: AppColors.primary.withOpacity(0.1),
          ),
        );
      }
    }

    return circles;
  }

  LatLng _getMapCenter() {
    // If viewing a specific branch, center on it
    if (_selectedBranchId != 'all') {
      final branch = _branches.firstWhere(
        (b) => b.id == _selectedBranchId,
        orElse: () => _branches.first,
      );
      if (branch.latitude != null && branch.longitude != null) {
        return LatLng(branch.latitude!, branch.longitude!);
      }
    }

    // If there are branches with locations, center on the first one
    final branchesWithLocation = _branches.where((b) => b.latitude != null && b.longitude != null);
    if (branchesWithLocation.isNotEmpty) {
      final branch = branchesWithLocation.first;
      return LatLng(branch.latitude!, branch.longitude!);
    }

    // Default center (Colombo, Sri Lanka)
    return const LatLng(6.9271, 79.8612);
  }

  Widget _buildMapView() {
    final branchesWithLocation = _branches.where((b) => b.latitude != null && b.longitude != null).toList();
    final markers = _buildMarkers();
    final circles = _buildCircles();
    
    if (branchesWithLocation.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        height: 400,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(FontAwesomeIcons.mapLocationDot, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No Branch Locations Set',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Set branch locations to view staff check-ins on the map',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Map
            SizedBox(
              height: 350,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _getMapCenter(),
                  zoom: 15,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                markers: markers,
                circles: circles,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
            // Map Legend
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildLegendItem(Colors.purple, 'Branch'),
                      _buildLegendItem(Colors.green, 'Active Staff'),
                      _buildLegendItem(Colors.blue, 'Completed'),
                      _buildLegendItem(Colors.red, 'Outside Radius'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 2),
                          color: AppColors.primary.withOpacity(0.1),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Check-in Radius',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Quick Branch Selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildBranchChip('all', 'All Branches'),
                    ...branchesWithLocation.map((branch) => 
                      _buildBranchChip(branch.id, branch.name),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _buildBranchChip(String branchId, String name) {
    final isSelected = _selectedBranchId == branchId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedBranchId = branchId);
          if (branchId != 'all') {
            final branch = _branches.firstWhere((b) => b.id == branchId);
            if (branch.latitude != null && branch.longitude != null) {
              _mapController?.animateCamera(
                CameraUpdate.newLatLngZoom(
                  LatLng(branch.latitude!, branch.longitude!),
                  17,
                ),
              );
            }
          } else {
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(_getMapCenter(), 13),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.grey.shade300,
            ),
          ),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListView() {
    if (_filteredCheckIns.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(FontAwesomeIcons.clipboardList, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No check-ins for this date',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Staff check-in records will appear here',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _filteredCheckIns.map((checkIn) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _buildCheckInCard(checkIn),
        );
      }).toList(),
    );
  }

  Widget _buildCheckInCard(StaffCheckInRecord checkIn) {
    final isActive = checkIn.status == 'checked_in';
    final isOutsideRadius = !checkIn.isWithinRadius;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOutsideRadius ? Colors.red.shade200 : Colors.grey.shade200,
          width: isOutsideRadius ? 2 : 1,
        ),
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
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isOutsideRadius ? Colors.red.shade50 : Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.shade100 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive ? Colors.green.shade300 : Colors.grey.shade300,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(checkIn.staffName),
                      style: TextStyle(
                        color: isActive ? Colors.green.shade700 : Colors.grey.shade700,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        checkIn.staffName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${checkIn.branchName} • ${checkIn.staffRole ?? 'Staff'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                // Status Badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.green.shade500 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isActive ? 'ACTIVE' : 'DONE',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isOutsideRadius)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FontAwesomeIcons.triangleExclamation, size: 10, color: Colors.red.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Location Alert',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                // Time Info
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoBox(
                        'Clock In',
                        _formatTime(checkIn.checkInTime),
                        Colors.green,
                        FontAwesomeIcons.signInAlt,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoBox(
                        'Clock Out',
                        checkIn.checkOutTime != null
                            ? _formatTime(checkIn.checkOutTime!)
                            : 'In Progress',
                        checkIn.checkOutTime != null ? Colors.red : Colors.blue,
                        FontAwesomeIcons.signOutAlt,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoBox(
                        'Duration',
                        _calculateDuration(checkIn),
                        AppColors.primary,
                        FontAwesomeIcons.clock,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // GPS Details
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isOutsideRadius ? Colors.red.shade50 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOutsideRadius ? Colors.red.shade200 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildGPSInfo(
                              'Distance',
                              _formatDistance(checkIn.distanceFromBranch),
                              checkIn.isWithinRadius ? Colors.green : Colors.red,
                            ),
                          ),
                          Expanded(
                            child: _buildGPSInfo(
                              'Status',
                              checkIn.isWithinRadius ? '✓ Within Range' : '✗ Outside Range',
                              checkIn.isWithinRadius ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildGPSInfo(
                              'Allowed Radius',
                              _formatDistance(checkIn.allowedRadius),
                              Colors.grey,
                            ),
                          ),
                          Expanded(
                            child: _buildGPSInfo(
                              'Coordinates',
                              '${checkIn.staffLatitude.toStringAsFixed(4)}, ${checkIn.staffLongitude.toStringAsFixed(4)}',
                              Colors.grey,
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
        ],
      ),
    );
  }

  Widget _buildInfoBox(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.8)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGPSInfo(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildBranchQuickView() {
    if (_branches.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FontAwesomeIcons.store, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Branches',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._branches.map((branch) {
            final activeCount = _checkIns
                .where((c) => c.branchId == branch.id && c.status == 'checked_in')
                .length;
            final isSelected = _selectedBranchId == branch.id;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.grey.shade200,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedBranchId = isSelected ? 'all' : branch.id;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: branch.latitude != null
                                ? Colors.green.shade100
                                : Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            FontAwesomeIcons.mapMarkerAlt,
                            size: 18,
                            color: branch.latitude != null
                                ? Colors.green.shade600
                                : Colors.amber.shade600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                branch.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                branch.latitude != null
                                    ? 'Radius: ${_formatDistance(branch.allowedCheckInRadius ?? 100)}'
                                    : 'No location set',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$activeCount',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text,
                              ),
                            ),
                            const Text(
                              'Active',
                              style: TextStyle(fontSize: 10, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
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
