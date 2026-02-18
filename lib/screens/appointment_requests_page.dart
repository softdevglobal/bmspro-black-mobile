import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const green = Color(0xFF22C55E);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const cyan = Color(0xFF06B6D4);
}

/// Represents a service within a booking that needs staff approval
class ServiceRequest {
  final String bookingId;
  final String serviceId;
  final String serviceName;
  final String? duration;
  final String? time;
  final String? staffId;
  final String? staffName;
  final String client;
  final String? clientPhone;
  final String date;
  final String? branchName;
  final double? price;
  final String? notes;
  final String? bookingCode;
  final String approvalStatus; // pending, accepted, rejected
  final String? rejectionReason;
  final Map<String, dynamic> rawData;
  final bool isMultiServiceBooking;
  final int totalServices;
  final int acceptedServices;
  final int rejectedServices;
  final List<Map<String, dynamic>> tasks;

  ServiceRequest({
    required this.bookingId,
    required this.serviceId,
    required this.serviceName,
    this.duration,
    this.time,
    this.staffId,
    this.staffName,
    required this.client,
    this.clientPhone,
    required this.date,
    this.branchName,
    this.price,
    this.notes,
    this.bookingCode,
    required this.approvalStatus,
    this.rejectionReason,
    required this.rawData,
    required this.isMultiServiceBooking,
    required this.totalServices,
    required this.acceptedServices,
    required this.rejectedServices,
    this.tasks = const [],
  });
}

class AppointmentRequestsPage extends StatefulWidget {
  const AppointmentRequestsPage({super.key});

  @override
  State<AppointmentRequestsPage> createState() => _AppointmentRequestsPageState();
}

class _AppointmentRequestsPageState extends State<AppointmentRequestsPage> {
  List<ServiceRequest> _pendingRequests = [];
  bool _isLoading = true;
  String? _ownerUid;
  String? _userRole;
  String? _userBranchId;

  @override
  void initState() {
    super.initState();
    _fetchPendingRequests();
  }

  Future<void> _fetchPendingRequests() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get user document to find ownerUid, role, and branchId
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        _ownerUid = data['ownerUid']?.toString() ?? user.uid;
        String rawRole = (data['role'] ?? '').toString();
        // role is already normalized (staff, branch_admin, workshop_owner)
        _userRole = rawRole;
        _userBranchId = data['branchId']?.toString();
      } else {
        _ownerUid = user.uid;
        _userRole = null;
        _userBranchId = null;
      }

      _listenToPendingRequests();
    } catch (e) {
      debugPrint('Error fetching user: $e');
      setState(() => _isLoading = false);
    }
  }

  void _listenToPendingRequests() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _ownerUid == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Listen to bookings with AwaitingStaffApproval or PartiallyApproved status for this owner
    debugPrint('=== FETCHING BOOKINGS ===');
    debugPrint('Current user UID: ${user.uid}');
    debugPrint('Owner UID: $_ownerUid');
    debugPrint('User Role: $_userRole');
    debugPrint('User Branch ID: $_userBranchId');
    
    // Build query with constraints - branch admin should only see bookings for their branch
    Query query = FirebaseFirestore.instance
        .collection('bookings')
        .where('ownerUid', isEqualTo: _ownerUid)
        .where('status', whereIn: ['AwaitingStaffApproval', 'PartiallyApproved']);
    
    // Branch admin should only see bookings for their branch (matching admin panel logic)
    if (_userRole == 'branch_admin' && _userBranchId != null && _userBranchId!.isNotEmpty) {
      query = query.where('branchId', isEqualTo: _userBranchId);
      debugPrint('Added branchId filter: $_userBranchId');
    }
    
    query.snapshots().listen((snap) {
      debugPrint('Found ${snap.docs.length} bookings with pending/partial status');
      final List<ServiceRequest> requests = [];

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final bookingId = doc.id;
        debugPrint('--- Booking: ${data['bookingCode']} (status: ${data['status']}) ---');

        // Check if this is a multi-service booking
        // Parse tasks from booking data
        final List<Map<String, dynamic>> bookingTasks = [];
        if (data['tasks'] is List) {
          for (final t in data['tasks'] as List) {
            if (t is Map) {
              bookingTasks.add(Map<String, dynamic>.from(t));
            }
          }
        }

        if (data['services'] is List && (data['services'] as List).isNotEmpty) {
          final services = data['services'] as List;
          
          // Count service statuses
          int totalServices = services.length;
          int acceptedServices = 0;
          int rejectedServices = 0;
          
          for (final service in services) {
            if (service is Map) {
              final status = service['approvalStatus']?.toString() ?? 'pending';
              if (status == 'accepted') acceptedServices++;
              if (status == 'rejected') rejectedServices++;
            }
          }

          // For each service assigned to this staff member with pending status
          for (final service in services) {
            if (service is Map) {
              final serviceStaffId = service['staffId']?.toString();
              final serviceStaffAuthUid = service['staffAuthUid']?.toString(); // Alternative field
              final approvalStatus = service['approvalStatus']?.toString() ?? 'pending';
              
              // Debug logging
              debugPrint('=== SERVICE CHECK ===');
              debugPrint('Service: ${service['name']}');
              debugPrint('serviceStaffId: $serviceStaffId');
              debugPrint('serviceStaffAuthUid: $serviceStaffAuthUid');
              debugPrint('user.uid: ${user.uid}');
              debugPrint('approvalStatus: $approvalStatus');
              debugPrint('Match staffId: ${serviceStaffId == user.uid}');
              debugPrint('Match authUid: ${serviceStaffAuthUid == user.uid}');
              
              // Only show pending services assigned to this staff
              // Check both staffId and staffAuthUid for compatibility
              final isAssignedToMe = serviceStaffId == user.uid || serviceStaffAuthUid == user.uid;
              debugPrint('isAssignedToMe: $isAssignedToMe');
              debugPrint('=====================');
              
              if (isAssignedToMe && approvalStatus == 'pending') {
                requests.add(ServiceRequest(
                  bookingId: bookingId,
                  serviceId: service['id']?.toString() ?? '',
                  serviceName: service['name']?.toString() ?? service['serviceName']?.toString() ?? 'Service',
                  duration: service['duration']?.toString(),
                  time: service['time']?.toString() ?? data['time']?.toString(),
                  staffId: serviceStaffId,
                  staffName: service['staffName']?.toString(),
                  client: data['client']?.toString() ?? data['clientName']?.toString() ?? 'Client',
                  clientPhone: data['clientPhone']?.toString(),
                  date: data['date']?.toString() ?? '',
                  branchName: data['branchName']?.toString(),
                  price: (service['price'] ?? data['price'])?.toDouble(),
                  notes: data['notes']?.toString(),
                  bookingCode: data['bookingCode']?.toString(),
                  approvalStatus: approvalStatus,
                  rejectionReason: service['rejectionReason']?.toString(),
                  rawData: data,
                  isMultiServiceBooking: true,
                  totalServices: totalServices,
                  acceptedServices: acceptedServices,
                  rejectedServices: rejectedServices,
                  tasks: bookingTasks,
                ));
              }
            }
          }
        } else {
          // Single service booking - check if assigned to current staff
          // Check both staffId and staffAuthUid for compatibility
          final bookingStaffId = data['staffId']?.toString();
          final bookingStaffAuthUid = data['staffAuthUid']?.toString();
          final isAssignedToMe = bookingStaffId == user.uid || bookingStaffAuthUid == user.uid;
          if (isAssignedToMe) {
            requests.add(ServiceRequest(
              bookingId: bookingId,
              serviceId: data['serviceId']?.toString() ?? '',
              serviceName: data['serviceName']?.toString() ?? data['service']?.toString() ?? 'Service',
              duration: data['duration']?.toString(),
              time: data['time']?.toString() ?? data['startTime']?.toString(),
              staffId: data['staffId']?.toString(),
              staffName: data['staffName']?.toString(),
              client: data['client']?.toString() ?? data['clientName']?.toString() ?? 'Client',
              clientPhone: data['clientPhone']?.toString(),
              date: data['date']?.toString() ?? '',
              branchName: data['branchName']?.toString(),
              price: data['price']?.toDouble(),
              notes: data['notes']?.toString(),
              bookingCode: data['bookingCode']?.toString(),
              approvalStatus: 'pending',
              rejectionReason: null,
              rawData: data,
              isMultiServiceBooking: false,
              totalServices: 1,
              acceptedServices: 0,
              rejectedServices: 0,
              tasks: bookingTasks,
            ));
          }
        }
      }

      // Sort by date and time
      requests.sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return (a.time ?? '').compareTo(b.time ?? '');
      });

      if (!mounted) return;
      setState(() {
        _pendingRequests = requests;
        _isLoading = false;
      });
    }, onError: (e) {
      debugPrint('Error fetching pending requests: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  String _formatTime(String? time) {
    if (time == null || time.isEmpty) return '';
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

  Future<void> _handleAccept(ServiceRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(FontAwesomeIcons.circleCheck, color: AppColors.green, size: 24),
            SizedBox(width: 12),
            Text('Accept Service'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accept "${request.serviceName}" for ${request.client}?'),
            const SizedBox(height: 8),
            Text(
              '${_formatDate(request.date)} at ${_formatTime(request.time)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            if (request.isMultiServiceBooking) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(FontAwesomeIcons.layerGroup, size: 16, color: AppColors.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Multi-service booking (${request.acceptedServices}/${request.totalServices} already accepted)',
                        style: const TextStyle(fontSize: 12, color: AppColors.cyan),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Tasks to complete section
            if (request.tasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(FontAwesomeIcons.clipboardList, size: 14, color: Color(0xFFEA580C)),
                        const SizedBox(width: 8),
                        Text(
                          'Tasks to Complete (${request.tasks.length})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFEA580C)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...request.tasks.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final task = entry.value;
                      final taskName = task['name']?.toString() ?? 'Task ${idx + 1}';
                      final taskDesc = task['description']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 20, height: 20,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFED7AA),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFEA580C))),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(taskName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF78350F))),
                                  if (taskDesc.isNotEmpty)
                                    Text(taskDesc, style: const TextStyle(fontSize: 10, color: Color(0xFF92400E))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    const Text(
                      'You must complete all tasks with photos after accepting.',
                      style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Color(0xFFB45309)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(FontAwesomeIcons.bell, size: 16, color: AppColors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request.isMultiServiceBooking && request.acceptedServices + 1 < request.totalServices
                        ? 'Waiting for other staff to respond before customer is notified.'
                        : 'The customer will be notified that their booking is confirmed.',
                      style: const TextStyle(fontSize: 12, color: AppColors.green),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Accept', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      _showLoadingDialog('Accepting service...');

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();

      // Call the staff-response API with serviceId for multi-service bookings
      final apiUrl = '${_getApiBaseUrl()}/api/bookings/${request.bookingId}/staff-response';
      debugPrint('Calling API: $apiUrl');
      
      final body = request.isMultiServiceBooking
        ? {'action': 'accept', 'serviceId': request.serviceId}
        : {'action': 'accept'};
      
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final message = json['message']?.toString() ?? 'Service accepted!';
        _showSuccessSnackbar(message);
      } else {
        String errorMsg = 'Failed to accept (${response.statusCode})';
        try {
          if (response.body.isNotEmpty) {
            final decoded = jsonDecode(response.body);
            errorMsg = decoded['error']?.toString() ?? errorMsg;
          }
        } catch (_) {
          errorMsg = 'Server error: ${response.statusCode}';
        }
        _showErrorSnackbar(errorMsg);
      }
    } catch (e) {
      debugPrint('Accept error: $e');
      Navigator.pop(context); // Close loading dialog
      _showErrorSnackbar('Network error. Please try again.');
    }
  }

  Future<void> _handleReject(ServiceRequest request) async {
    final reasonController = TextEditingController();
    
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(FontAwesomeIcons.circleXmark, color: AppColors.red, size: 24),
            SizedBox(width: 12),
            Text('Reject Service'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reject "${request.serviceName}" for ${request.client}?'),
            const SizedBox(height: 8),
            Text(
              '${_formatDate(request.date)} at ${_formatTime(request.time)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            if (request.isMultiServiceBooking) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(FontAwesomeIcons.layerGroup, size: 16, color: AppColors.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Only this service will be rejected. Other services remain unaffected.',
                        style: const TextStyle(fontSize: 12, color: AppColors.cyan),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason for rejection *',
                hintText: 'Please provide a reason...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(FontAwesomeIcons.circleInfo, size: 16, color: AppColors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The admin will be notified to reassign this service to another staff member.',
                      style: TextStyle(fontSize: 12, color: AppColors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a reason for rejection'),
                    backgroundColor: AppColors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context, reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      _showLoadingDialog('Rejecting service...');

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();

      final apiUrl = '${_getApiBaseUrl()}/api/bookings/${request.bookingId}/staff-response';
      debugPrint('Calling API: $apiUrl');
      
      final body = request.isMultiServiceBooking
        ? {'action': 'reject', 'rejectionReason': result, 'serviceId': request.serviceId}
        : {'action': 'reject', 'rejectionReason': result};
      
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final message = json['message']?.toString() ?? 'Service rejected. Admin notified.';
        _showSuccessSnackbar(message);
      } else {
        String errorMsg = 'Failed to reject (${response.statusCode})';
        try {
          if (response.body.isNotEmpty) {
            final decoded = jsonDecode(response.body);
            errorMsg = decoded['error']?.toString() ?? errorMsg;
          }
        } catch (_) {
          errorMsg = 'Server error: ${response.statusCode}';
        }
        _showErrorSnackbar(errorMsg);
      }
    } catch (e) {
      debugPrint('Reject error: $e');
      Navigator.pop(context); // Close loading dialog
      _showErrorSnackbar('Network error. Please try again.');
    }
  }

  String _getApiBaseUrl() {
    return 'https://black.bmspros.com.au';
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(width: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(FontAwesomeIcons.circleCheck, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(FontAwesomeIcons.circleExclamation, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _pendingRequests.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: () async {
                            setState(() => _isLoading = true);
                            _fetchPendingRequests();
                          },
                          color: AppColors.primary,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _pendingRequests.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              return _buildRequestCard(_pendingRequests[index]);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                    'Service Requests',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text),
                  ),
                  Text(
                    '${_pendingRequests.length} pending',
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                FontAwesomeIcons.circleCheck,
                size: 40,
                color: AppColors.green,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'All Caught Up!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You have no pending service requests.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(ServiceRequest request) {
    return Container(
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
        children: [
          // Header with status badge
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.orange.withOpacity(0.1),
                  AppColors.primary.withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.orange, AppColors.primary],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Icon(FontAwesomeIcons.userClock,
                        color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.client,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.text,
                        ),
                      ),
                      if (request.clientPhone != null &&
                          request.clientPhone!.isNotEmpty)
                        Text(
                          request.clientPhone!,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FontAwesomeIcons.clock, size: 12, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Pending',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (request.isMultiServiceBooking) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                        ),
                        child: Text(
                          '${request.acceptedServices}/${request.totalServices} accepted',
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Service & Booking Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Service
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(FontAwesomeIcons.spa,
                            color: AppColors.primary, size: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.serviceName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: AppColors.text,
                            ),
                          ),
                          if (request.duration != null &&
                              request.duration!.isNotEmpty)
                            Text(
                              '${request.duration} minutes',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (request.price != null)
                      Text(
                        '\$${request.price!.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Date & Time
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        children: [
                          const Icon(FontAwesomeIcons.calendar,
                              size: 14, color: AppColors.muted),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(request.date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 1,
                        height: 20,
                        color: AppColors.border,
                      ),
                      Row(
                        children: [
                          const Icon(FontAwesomeIcons.clock,
                              size: 14, color: AppColors.muted),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(request.time),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Branch
                if (request.branchName != null &&
                    request.branchName!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(FontAwesomeIcons.locationDot,
                          size: 14, color: AppColors.muted),
                      const SizedBox(width: 8),
                      Text(
                        request.branchName!,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],

                // Notes
                if (request.notes != null &&
                    request.notes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(FontAwesomeIcons.noteSticky,
                            size: 14, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            request.notes!,
                            style: TextStyle(
                              color: Colors.amber.shade800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Tasks to do
                if (request.tasks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(FontAwesomeIcons.clipboardList, size: 14, color: Color(0xFFEA580C)),
                            const SizedBox(width: 8),
                            Text(
                              'Tasks (${request.tasks.length})',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFEA580C)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...request.tasks.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final task = entry.value;
                          final taskName = task['name']?.toString() ?? 'Task ${idx + 1}';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 18, height: 18,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFED7AA),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text('${idx + 1}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFEA580C))),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    taskName,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF78350F)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action Buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _handleReject(request),
                    icon: const Icon(FontAwesomeIcons.xmark, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleAccept(request),
                    icon: const Icon(FontAwesomeIcons.check, size: 16, color: Colors.white),
                    label: const Text('Accept', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
