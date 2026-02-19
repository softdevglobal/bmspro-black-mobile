import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/staff_check_in_service.dart';
import '../services/permission_service.dart';

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

class StaffCheckInPage extends StatefulWidget {
  const StaffCheckInPage({super.key});

  @override
  State<StaffCheckInPage> createState() => _StaffCheckInPageState();
}

class _StaffCheckInPageState extends State<StaffCheckInPage> {
  bool _isLoading = true;
  bool _isCheckingIn = false;
  bool _isCheckingOut = false;
  bool _isGettingLocation = false;
  
  Position? _currentPosition;
  StaffCheckInRecord? _activeCheckIn;
  List<BranchForCheckIn> _branches = [];
  BranchForCheckIn? _selectedBranch;
  String? _errorMessage;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load active check-in and branches in parallel
      final results = await Future.wait([
        StaffCheckInService.getActiveCheckIn(),
        StaffCheckInService.getBranchesForCheckIn(),
      ]);

      setState(() {
        _activeCheckIn = results[0] as StaffCheckInRecord?;
        _branches = results[1] as List<BranchForCheckIn>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load data. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
      _locationError = null;
    });

    try {
      // Check if location services are enabled
      final serviceEnabled = await LocationService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services are disabled. Please enable them in settings.';
          _isGettingLocation = false;
        });
        return;
      }

      // Check current permission status first
      final currentPermission = await Geolocator.checkPermission();
      
      // If permission not granted, show custom dialog then request
      if (currentPermission == LocationPermission.denied) {
        if (!mounted) return;
        final granted = await PermissionService().requestLocationPermissionWithDialog(context);
        if (!granted) {
          setState(() {
            _locationError = 'Location permission denied. Please grant permission to check in.';
            _isGettingLocation = false;
          });
          return;
        }
      } else if (currentPermission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Location permission permanently denied. Please enable it in app settings.';
          _isGettingLocation = false;
        });
        return;
      }

      // Get current position
      final position = await LocationService.getCurrentLocation();
      if (position == null) {
        setState(() {
          _locationError = 'Could not get your location. Please try again.';
          _isGettingLocation = false;
        });
        return;
      }

      setState(() {
        _currentPosition = position;
        _isGettingLocation = false;
      });
    } catch (e) {
      setState(() {
        _locationError = 'Error getting location: $e';
        _isGettingLocation = false;
      });
    }
  }

  Future<void> _checkIn() async {
    if (_selectedBranch == null) {
      _showSnackBar('Please select a branch', isError: true);
      return;
    }

    if (_currentPosition == null) {
      _showSnackBar('Please get your current location first', isError: true);
      return;
    }

    setState(() => _isCheckingIn = true);

    final result = await StaffCheckInService.checkIn(
      branchId: _selectedBranch!.id,
      staffLatitude: _currentPosition!.latitude,
      staffLongitude: _currentPosition!.longitude,
    );

    setState(() => _isCheckingIn = false);

    if (result.success) {
      _showSnackBar(result.message);
      // Automatically return to dashboard after successful check-in
      Navigator.pop(context, true);
    } else {
      _showSnackBar(result.message, isError: true);
    }
  }

  Future<void> _checkOut() async {
    if (_activeCheckIn == null) return;

    setState(() => _isCheckingOut = true);

    final result = await StaffCheckInService.checkOut(_activeCheckIn!.id!);

    setState(() => _isCheckingOut = false);

    if (result.success) {
      _showSnackBar('${result.message}. Hours worked: ${result.hoursWorked}');
      _loadData();
    } else {
      _showSnackBar(result.message, isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? FontAwesomeIcons.circleExclamation : FontAwesomeIcons.circleCheck,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _getDistanceToBranch(BranchForCheckIn branch) {
    if (_currentPosition == null || !branch.hasLocation) {
      return 'Unknown';
    }
    final distance = LocationService.calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      branch.latitude!,
      branch.longitude!,
    );
    return LocationService.formatDistance(distance);
  }

  bool _isWithinBranchRadius(BranchForCheckIn branch) {
    if (_currentPosition == null || !branch.hasLocation) {
      return false;
    }
    return LocationService.isWithinRadius(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      branch.latitude!,
      branch.longitude!,
      branch.allowedRadius,
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
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D), Color(0xFF1A1A1A)]),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: const Color(0xFF1A1A1A).withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 8))],
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
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))),
                          child: const Center(child: Icon(FontAwesomeIcons.arrowLeft, size: 14, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Check In / Out', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
                            Text('Manage your attendance', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _loadData,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.08))),
                          child: const Center(child: Icon(FontAwesomeIcons.arrowRotateRight, size: 14, color: Colors.white)),
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _errorMessage != null
                      ? _buildErrorState()
                      : _activeCheckIn != null
                          ? _buildActiveCheckInView()
                          : _buildCheckInView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(FontAwesomeIcons.triangleExclamation, color: Colors.red.shade600, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(FontAwesomeIcons.arrowRotateRight, size: 14),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCheckInView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Active Check-in Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF34D399)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(FontAwesomeIcons.check, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Currently Checked In',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _activeCheckIn!.branchName,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FontAwesomeIcons.clock, color: Colors.white, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'Since ${_formatTime(_activeCheckIn!.checkInTime)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Check-in Details
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Check-in Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetailRow('Branch', _activeCheckIn!.branchName, FontAwesomeIcons.building),
                const Divider(height: 24),
                _buildDetailRow('Check-in Time', _formatTime(_activeCheckIn!.checkInTime), FontAwesomeIcons.clock),
                const Divider(height: 24),
                _buildDetailRow(
                  'Distance from Branch',
                  LocationService.formatDistance(_activeCheckIn!.distanceFromBranch),
                  FontAwesomeIcons.locationDot,
                ),
                const Divider(height: 24),
                _buildDetailRow(
                  'Status',
                  _activeCheckIn!.isWithinRadius ? 'Within Radius ✓' : 'Outside Radius',
                  FontAwesomeIcons.circleCheck,
                  valueColor: _activeCheckIn!.isWithinRadius ? Colors.green : Colors.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Check Out Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isCheckingOut ? null : _checkOut,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade500,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isCheckingOut
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Checking Out...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(FontAwesomeIcons.rightFromBracket, size: 16),
                        SizedBox(width: 12),
                        Text('Check Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(FontAwesomeIcons.mapLocationDot, color: Colors.white, size: 32),
                const SizedBox(height: 12),
                const Text(
                  'Location-Based Check In',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You must be at your branch location to check in',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Step 1: Get Location
          _buildStepCard(
            step: 1,
            title: 'Get Your Location',
            subtitle: _currentPosition != null
                ? 'Location captured ✓'
                : 'Tap the button to capture your GPS location',
            isCompleted: _currentPosition != null,
            child: Column(
              children: [
                if (_locationError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(FontAwesomeIcons.circleExclamation, color: Colors.red.shade600, size: 14),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _locationError!,
                            style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(FontAwesomeIcons.gear, size: 14),
                          color: Colors.red.shade600,
                          onPressed: () => LocationService.openAppSettings(),
                          tooltip: 'Open Settings',
                        ),
                      ],
                    ),
                  ),
                if (_currentPosition != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(FontAwesomeIcons.locationDot, color: Colors.green.shade600, size: 14),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                            style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isGettingLocation ? null : _getCurrentLocation,
                    icon: _isGettingLocation
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Icon(_currentPosition != null ? FontAwesomeIcons.arrowRotateRight : FontAwesomeIcons.crosshairs, size: 14),
                    label: Text(_isGettingLocation
                        ? 'Getting Location...'
                        : _currentPosition != null
                            ? 'Refresh Location'
                            : 'Get My Location'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentPosition != null ? Colors.green.shade600 : AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Step 2: Select Branch
          _buildStepCard(
            step: 2,
            title: 'Select Branch',
            subtitle: _selectedBranch != null
                ? 'Selected: ${_selectedBranch!.name}'
                : 'Choose the branch you are checking into',
            isCompleted: _selectedBranch != null,
            child: _branches.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(FontAwesomeIcons.circleInfo, color: Colors.amber, size: 14),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No branches with location configured. Please contact your administrator.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: _branches.map((branch) {
                      final isSelected = _selectedBranch?.id == branch.id;
                      final distance = _getDistanceToBranch(branch);
                      final isWithinRadius = _isWithinBranchRadius(branch);

                      return GestureDetector(
                        onTap: () => setState(() => _selectedBranch = branch),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : Colors.grey.shade200,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isSelected
                                        ? [AppColors.primary, AppColors.accent]
                                        : [Colors.grey.shade200, Colors.grey.shade300],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  FontAwesomeIcons.building,
                                  color: isSelected ? Colors.white : Colors.grey.shade600,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      branch.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected ? AppColors.primary : AppColors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          FontAwesomeIcons.locationDot,
                                          size: 10,
                                          color: isWithinRadius ? Colors.green : Colors.orange,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$distance away',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isWithinRadius ? Colors.green : Colors.orange,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (isWithinRadius) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'Within Range',
                                              style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(FontAwesomeIcons.circleCheck, color: AppColors.primary, size: 20),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 24),

          // Check In Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_isCheckingIn || _currentPosition == null || _selectedBranch == null)
                  ? null
                  : _checkIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isCheckingIn
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Checking In...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(FontAwesomeIcons.rightToBracket, size: 16),
                        SizedBox(width: 12),
                        Text('Check In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // Note
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(FontAwesomeIcons.circleInfo, color: Colors.blue.shade700, size: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your location will be recorded for attendance verification. Make sure you are at your assigned branch.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({
    required int step,
    required String title,
    required String subtitle,
    required bool isCompleted,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.green : AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(FontAwesomeIcons.check, color: Colors.white, size: 12)
                      : Text(
                          '$step',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.text),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: isCompleted ? Colors.green : AppColors.muted),
                    ),
                  ],
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

  Widget _buildDetailRow(String label, String value, IconData icon, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.muted),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.text,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
