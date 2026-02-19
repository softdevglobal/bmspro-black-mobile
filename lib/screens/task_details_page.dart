import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

// --- 1. Theme & Colors ---
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
}

class TaskDetailsPage extends StatefulWidget {
  final Map<String, dynamic>? appointmentData;
  
  const TaskDetailsPage({super.key, this.appointmentData});

  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _TaskDetailsPageState extends State<TaskDetailsPage> with TickerProviderStateMixin {
  // API Base URL - Update this to your admin panel URL
  static const String _apiBaseUrl = 'https://black.bmspros.com.au';
  
  // --- Stopwatch State ---
  Timer? _stopwatchTimer;
  int _elapsedSeconds = 0;
  bool _isStopwatchRunning = false;
  DateTime? _appointmentStartTime;

  // --- Task State ---
  bool _isNotesExpanded = false;
  bool _isFinishing = false;
  bool _isLoading = true;

  // Appointment Data
  Map<String, dynamic>? _bookingData;
  Map<String, dynamic>? _customerData;
  String _serviceName = 'Service';
  String _duration = '60';
  String _appointmentTime = '';
  String _location = 'Salon';
  String _customerName = 'Customer';
  String _serviceType = '';
  String _customerNotes = 'No special notes available.';
  
  // Multi-service tracking
  List<Map<String, dynamic>> _assignedServices = [];
  String? _currentServiceId; // For multi-service bookings, the service being worked on


  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // 2. Setup Pulse Animation for Finish Button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadAppointmentData();
  }

  Future<void> _loadAppointmentData() async {
    if (widget.appointmentData == null) {
      setState(() => _isLoading = false);
      _startStopwatch();
      return;
    }

    try {
      _bookingData = widget.appointmentData!['data'] as Map<String, dynamic>?;
      final bookingId = widget.appointmentData!['id'] as String?;
      
      // Load full booking data if we have an ID
      if (bookingId != null && _bookingData == null) {
        final bookingDoc = await FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .get();
        if (bookingDoc.exists) {
          _bookingData = bookingDoc.data();
        }
      }

      // Extract service information
      _serviceName = widget.appointmentData?['serviceName']?.toString() ?? 
                    _bookingData?['serviceName']?.toString() ?? 
                    'Service';
      _duration = widget.appointmentData?['duration']?.toString() ?? 
                 _bookingData?['duration']?.toString() ?? 
                 '60';
      
      // Extract time and location
      final time = widget.appointmentData?['time']?.toString() ?? 
                  _bookingData?['time']?.toString() ?? 
                  _bookingData?['startTime']?.toString() ?? '';
      _appointmentTime = _formatTime(time);
      
      _location = _bookingData?['branchName']?.toString() ?? 
                 _bookingData?['room']?.toString() ?? 
                 _bookingData?['location']?.toString() ?? 
                 'Salon';

      // Extract customer information
      _customerName = _bookingData?['client']?.toString() ?? 
                     _bookingData?['clientName']?.toString() ?? 
                     widget.appointmentData?['client']?.toString() ?? 
                     'Customer';
      
      // Try to get service type from services array or use service name
      // Also identify services assigned to this staff member
      final user = FirebaseAuth.instance.currentUser;
      if (_bookingData?['services'] is List && (_bookingData!['services'] as List).isNotEmpty) {
        final services = _bookingData!['services'] as List;
        final firstService = services.first;
        if (firstService is Map) {
          _serviceType = firstService['name']?.toString() ?? _serviceName;
        }
        
        // Find services assigned to current staff
        if (user != null) {
          _assignedServices = services
            .where((s) => s is Map && (s['staffId'] == user.uid || s['staffAuthUid'] == user.uid))
            .map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s as Map))
            .toList();
          
          // If we found assigned services, find the FIRST UNCOMPLETED one
          if (_assignedServices.isNotEmpty) {
            // Find the first service that is NOT completed
            final nextUncompletedService = _assignedServices.firstWhere(
              (s) => (s['completionStatus'] ?? '').toString().toLowerCase() != 'completed',
              orElse: () => _assignedServices.first, // Fallback to first if all completed
            );
            
            _serviceName = nextUncompletedService['name']?.toString() ?? _serviceName;
            _currentServiceId = nextUncompletedService['id']?.toString();
            _duration = nextUncompletedService['duration']?.toString() ?? _duration;
            
            // Also update the appointment time to show this service's time
            final serviceTime = nextUncompletedService['time']?.toString();
            if (serviceTime != null && serviceTime.isNotEmpty) {
              _appointmentTime = _formatTime(serviceTime);
            }
            
            debugPrint('Selected service to complete: $_serviceName (ID: $_currentServiceId)');
          }
        }
      } else {
        _serviceType = _serviceName;
      }

      // Get customer notes
      _customerNotes = _bookingData?['customerNotes']?.toString() ?? 
                      _bookingData?['notes']?.toString() ?? 
                      'No special notes available.';

      // Try to find customer in customers collection for additional info
      // (user is already defined above on line 141)
      if (user != null) {
        final ownerUid = user.uid;
        final customerEmail = _bookingData?['email']?.toString() ?? 
                             _bookingData?['clientEmail']?.toString() ?? '';
        final customerPhone = _bookingData?['phone']?.toString() ?? 
                             _bookingData?['clientPhone']?.toString() ?? '';
        
        QuerySnapshot? customerSnap;
        if (customerEmail.isNotEmpty) {
          customerSnap = await FirebaseFirestore.instance
              .collection('customers')
              .where('ownerUid', isEqualTo: ownerUid)
              .where('email', isEqualTo: customerEmail)
              .limit(1)
              .get();
        }
        if ((customerSnap == null || customerSnap.docs.isEmpty) && customerPhone.isNotEmpty) {
          customerSnap = await FirebaseFirestore.instance
              .collection('customers')
              .where('ownerUid', isEqualTo: ownerUid)
              .where('phone', isEqualTo: customerPhone)
              .limit(1)
              .get();
        }
        
        if (customerSnap != null && customerSnap.docs.isNotEmpty) {
          _customerData = customerSnap.docs.first.data() as Map<String, dynamic>;
          // Use customer notes from customer profile if available
          final customerNotesFromProfile = _customerData?['notes']?.toString() ?? 
                                           _customerData?['customerNotes']?.toString() ?? '';
          if (customerNotesFromProfile.isNotEmpty) {
            _customerNotes = customerNotesFromProfile;
          }
        }
      }

      // Calculate elapsed time if appointment has started
      final date = widget.appointmentData?['date']?.toString() ?? 
                  _bookingData?['date']?.toString() ?? '';
      if (date.isNotEmpty && time.isNotEmpty) {
        try {
          final dateTime = DateTime.parse(date);
          final timeParts = time.split(':');
          if (timeParts.length >= 2) {
            final hour = int.parse(timeParts[0]);
            final minute = int.parse(timeParts[1]);
            _appointmentStartTime = DateTime(
              dateTime.year,
              dateTime.month,
              dateTime.day,
              hour,
              minute,
            );
            
            // If appointment has started, calculate elapsed time
            final now = DateTime.now();
            if (now.isAfter(_appointmentStartTime!)) {
              _elapsedSeconds = now.difference(_appointmentStartTime!).inSeconds;
            }
          }
        } catch (_) {
          // If parsing fails, start from 0
        }
      }

    } catch (e) {
      debugPrint('Error loading task data: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
      // Auto-start stopwatch on load
      _startStopwatch();
    }
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

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // --- Stopwatch Logic ---
  void _startStopwatch() {
    if (_isStopwatchRunning) return;
    setState(() => _isStopwatchRunning = true);
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  void _stopStopwatch() {
    _stopwatchTimer?.cancel();
    setState(() => _isStopwatchRunning = false);
  }

  void _toggleStopwatch() {
    if (_isStopwatchRunning) {
      _stopStopwatch();
    } else {
      _startStopwatch();
    }
  }

  String _formatElapsedTime(int totalSeconds) {
    final hrs = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final mins = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$hrs:$mins:$secs";
  }


  void _handleFinish() async {
    // Stop timer on finish
    _stopStopwatch();
    setState(() => _isFinishing = true);
    
    final bookingId = widget.appointmentData?['id'] as String?;
    bool success = false;
    String message = "Task Completed Successfully!";
    bool bookingFullyCompleted = false;
    
    try {
      if (bookingId != null) {
        // Get Firebase auth token
        final user = FirebaseAuth.instance.currentUser;
        final token = await user?.getIdToken();
        
        if (token != null) {
          // Call the service-complete API endpoint
          final uri = Uri.parse('$_apiBaseUrl/api/bookings/$bookingId/service-complete');
          
          // Build request body
          final Map<String, dynamic> requestBody = {};
          
          // If this is a multi-service booking, specify which service to complete
          if (_currentServiceId != null && _assignedServices.length > 1) {
            requestBody['serviceId'] = _currentServiceId;
          }
          
          debugPrint('Calling service-complete API: $uri');
          
          final response = await http.post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(requestBody),
          );
          
          debugPrint('API Response status: ${response.statusCode}');
          debugPrint('API Response body: ${response.body}');
          
          // Check if response body is empty (API endpoint might not be deployed)
          if (response.body.isEmpty) {
            debugPrint('Empty response - API endpoint may not be deployed yet');
            throw Exception('API endpoint returned empty response. Please ensure the admin panel is deployed with the latest changes.');
          }
          
          // Check for 404 (endpoint not found)
          if (response.statusCode == 404) {
            debugPrint('API endpoint not found (404) - endpoint may not be deployed');
            throw Exception('API endpoint not found. Please deploy the admin panel with the new service-complete endpoint.');
          }
          
          final responseData = jsonDecode(response.body);
          
          if (response.statusCode == 200 && responseData['ok'] == true) {
            success = true;
            bookingFullyCompleted = responseData['bookingCompleted'] ?? false;
            
            // Customize message based on response
            if (bookingFullyCompleted) {
              message = responseData['message'] ?? "Booking completed! Customer has been notified.";
            } else {
              // Multi-service booking, not all services done yet
              final progress = responseData['progress'];
              if (progress != null) {
                message = "Service completed! (${progress['completed']}/${progress['total']} services done)";
              } else {
                message = responseData['message'] ?? "Service marked as completed!";
              }
            }
            
            // Also store elapsed time in Firestore (supplementary data)
            try {
              await FirebaseFirestore.instance
                  .collection('bookings')
                  .doc(bookingId)
                  .update({
                'durationElapsed': _elapsedSeconds,
              });
            } catch (e) {
              debugPrint('Note: Could not update elapsed time: $e');
            }
          } else {
            // API returned an error
            final errorMessage = responseData['error'] ?? 'Failed to complete service';
            debugPrint('API Error: $errorMessage');
            
            // Check if already completed - this is not really an error, just navigate back
            if (errorMessage.toString().toLowerCase().contains('already') && 
                errorMessage.toString().toLowerCase().contains('completed')) {
              success = true;
              message = "This service was already completed.";
              bookingFullyCompleted = true;
            } else {
              throw Exception(errorMessage);
            }
          }
        } else {
          // No auth token - fallback to direct Firestore update
          debugPrint('No auth token available, using fallback');
          await _fallbackDirectCompletion(bookingId);
          success = true;
          message = "Task Completed!";
        }
      } else {
        // No booking ID - just show success
        success = true;
      }
    } catch (e) {
      debugPrint('Error completing service: $e');
      
      // Check if this is an API deployment issue
      final errorString = e.toString();
      if (errorString.contains('empty response') || 
          errorString.contains('not found') || 
          errorString.contains('404') ||
          errorString.contains('FormatException')) {
        message = "Service completion API not available. Please ensure the admin panel is deployed with the latest changes.";
      } else if (errorString.contains('permission')) {
        message = "Permission denied. Please contact your administrator.";
      } else {
        message = "Error completing task: ${e.toString().split(':').last.trim()}";
      }
      
      // Note: Direct Firestore fallback removed as it requires admin privileges
      // The service-complete API must be deployed for this feature to work
    }
    
    if (mounted) {
      setState(() => _isFinishing = false);
      
      if (success) {
        Navigator.pop(context); // Go back to previous screen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  bookingFullyCompleted ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.check,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: AppColors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(FontAwesomeIcons.triangleExclamation, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// Fallback method to directly update Firestore if API call fails
  Future<void> _fallbackDirectCompletion(String bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'durationElapsed': _elapsedSeconds,
    };
    
    // Check if it's a multi-service booking
    if (_bookingData?['services'] is List && (_bookingData!['services'] as List).isNotEmpty) {
      // Update the specific service's completion status
      final services = List<Map<String, dynamic>>.from(
        (_bookingData!['services'] as List).map((s) => Map<String, dynamic>.from(s as Map))
      );
      
      bool allCompleted = true;
      for (int i = 0; i < services.length; i++) {
        final service = services[i];
        // Mark our assigned services as completed
        if (service['staffId'] == user?.uid || service['staffAuthUid'] == user?.uid) {
          if (_currentServiceId == null || service['id'].toString() == _currentServiceId) {
            services[i]['completionStatus'] = 'completed';
            services[i]['completedAt'] = DateTime.now().toIso8601String();
            services[i]['completedByStaffUid'] = user?.uid;
            services[i]['completedByStaffName'] = user?.displayName ?? 'Staff';
          }
        }
        // Check if this service is completed
        if (services[i]['completionStatus'] != 'completed') {
          allCompleted = false;
        }
      }
      
      updates['services'] = services;
      
      // If all services are completed, mark booking as completed
      if (allCompleted) {
        updates['status'] = 'Completed';
        updates['completedAt'] = FieldValue.serverTimestamp();
      }
    } else {
      // Single service booking - mark as completed directly
      updates['status'] = 'Completed';
      updates['completedAt'] = FieldValue.serverTimestamp();
      updates['completedByStaffUid'] = user?.uid;
      updates['completedByStaffName'] = user?.displayName ?? 'Staff';
    }
    
    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(bookingId)
        .update(updates);
  }

  // --- UI Construction ---
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildServiceHeader(),
                  const SizedBox(height: 24),
                  _buildCustomerInfo(),
                  const SizedBox(height: 24),
                  _buildFinishSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
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
                    const Text('Service Details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
                    Text('Task progress & completion', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getServiceIcon(String serviceName) {
    final serviceLower = serviceName.toLowerCase();
    if (serviceLower.contains('nail') || serviceLower.contains('manicure') || serviceLower.contains('pedicure')) {
      return FontAwesomeIcons.handSparkles;
    } else if (serviceLower.contains('facial') || serviceLower.contains('face')) {
      return FontAwesomeIcons.leaf;
    } else if (serviceLower.contains('hair') || serviceLower.contains('cut') || serviceLower.contains('style')) {
      return FontAwesomeIcons.scissors;
    } else if (serviceLower.contains('wax') || serviceLower.contains('threading')) {
      return FontAwesomeIcons.feather;
    } else if (serviceLower.contains('makeup') || serviceLower.contains('beauty')) {
      return FontAwesomeIcons.wandMagicSparkles;
    } else if (serviceLower.contains('color') || serviceLower.contains('colour')) {
      return FontAwesomeIcons.paintbrush;
    }
    return FontAwesomeIcons.spa;
  }

  Widget _buildServiceHeader() {
    final durationDisplay = '${_duration} Minutes Session';
    final serviceIcon = _getServiceIcon(_serviceName);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 25, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _serviceName,
                      style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      durationDisplay,
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                child: Center(child: Icon(serviceIcon, color: Colors.white, size: 24)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(FontAwesomeIcons.clock, color: Colors.white, size: 14),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _appointmentTime.isNotEmpty ? _appointmentTime : 'Time TBD',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(FontAwesomeIcons.doorOpen, color: Colors.white, size: 14),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _location,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // --- Stopwatch Component ---
              GestureDetector(
                onTap: _toggleStopwatch,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: _isStopwatchRunning ? Border.all(color: Colors.white.withOpacity(0.5)) : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isStopwatchRunning ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatElapsedTime(_elapsedSeconds),
                        style: GoogleFonts.robotoMono(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCustomerInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.circleUser, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text('Customer Information', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow('Name', _customerName),
          const SizedBox(height: 12),
          _infoRow('Service Type', _serviceType.isNotEmpty ? _serviceType : _serviceName),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border),
          InkWell(
            onTap: () => setState(() => _isNotesExpanded = !_isNotesExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Special Notes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.primary)),
                  Icon(_isNotesExpanded ? FontAwesomeIcons.chevronUp : FontAwesomeIcons.chevronDown, size: 14, color: AppColors.primary),
                ],
              ),
            ),
          ),
          if (_isNotesExpanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Text(
                _customerNotes,
                style: GoogleFonts.inter(fontSize: 14, height: 1.5, color: AppColors.text),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFinishSection() {
    // Check if this is a multi-service booking with multiple assigned services
    final isMultiServiceBooking = _assignedServices.length > 1;
    
    // Count completed vs pending services
    final completedServices = _assignedServices.where(
      (s) => (s['completionStatus'] ?? '').toString().toLowerCase() == 'completed'
    ).toList();
    final pendingServices = _assignedServices.where(
      (s) => (s['completionStatus'] ?? '').toString().toLowerCase() != 'completed'
    ).toList();
    
    // Check if all services are already completed
    final allServicesCompleted = pendingServices.isEmpty && completedServices.isNotEmpty;
    
    final buttonLabel = allServicesCompleted 
        ? 'All Services Completed' 
        : (isMultiServiceBooking ? 'Complete "$_serviceName"' : 'Complete Service');
    
    // Button is enabled if not all services are completed
    final bool canComplete = !allServicesCompleted;
    
    return Column(
      children: [
        // Show info about multi-service bookings
        if (isMultiServiceBooking) ...[
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: allServicesCompleted ? Colors.green.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: allServicesCompleted ? Colors.green.shade200 : Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      allServicesCompleted ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circleInfo, 
                      color: allServicesCompleted ? Colors.green.shade600 : Colors.blue.shade600, 
                      size: 16
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        allServicesCompleted 
                            ? 'All your services are completed!'
                            : 'This booking has ${_assignedServices.length} services assigned to you.',
                        style: GoogleFonts.inter(
                          fontSize: 13, 
                          fontWeight: FontWeight.w600,
                          color: allServicesCompleted ? Colors.green.shade700 : Colors.blue.shade700
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Show service completion status
                ..._assignedServices.map((service) {
                  final isCompleted = (service['completionStatus'] ?? '').toString().toLowerCase() == 'completed';
                  final serviceName = service['name']?.toString() ?? 'Service';
                  return Padding(
                    padding: const EdgeInsets.only(left: 28, bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          isCompleted ? FontAwesomeIcons.solidCircleCheck : FontAwesomeIcons.circle,
                          size: 12,
                          color: isCompleted ? Colors.green.shade600 : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            serviceName,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isCompleted ? Colors.green.shade700 : Colors.grey.shade600,
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (isCompleted)
                          Text(
                            'Done',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.green.shade600,
                              fontWeight: FontWeight.w600,
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
        
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: canComplete 
                  ? const LinearGradient(colors: [AppColors.primary, AppColors.accent]) 
                  : (allServicesCompleted 
                      ? LinearGradient(colors: [Colors.green.shade400, Colors.green.shade600])
                      : null),
              color: canComplete || allServicesCompleted ? null : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(16),
              boxShadow: canComplete 
                  ? [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)] 
                  : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (!_isFinishing && canComplete) ? _handleFinish : (allServicesCompleted ? () => Navigator.pop(context) : null),
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: _isFinishing
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              FontAwesomeIcons.circleCheck, 
                              color: canComplete || allServicesCompleted ? Colors.white : Colors.grey.shade500, 
                              size: 20
                            ),
                            const SizedBox(width: 12),
                            Text(
                              allServicesCompleted ? 'Go Back' : buttonLabel,
                              style: GoogleFonts.inter(
                                fontSize: 18, 
                                fontWeight: FontWeight.bold, 
                                color: canComplete || allServicesCompleted ? Colors.white : Colors.grey.shade500
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (allServicesCompleted)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(FontAwesomeIcons.circleCheck, size: 14, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Text(
                'All your assigned services are done!',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.green.shade600),
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(FontAwesomeIcons.check, size: 14, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                isMultiServiceBooking 
                    ? 'Tap to complete this service'
                    : 'Tap to complete service',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.green),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: BottomNavigationBar(
        backgroundColor: AppColors.card,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.muted,
        items: const [
          BottomNavigationBarItem(icon: Icon(FontAwesomeIcons.house), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(FontAwesomeIcons.calendar), label: 'Schedule'),
          BottomNavigationBarItem(icon: Icon(FontAwesomeIcons.users), label: 'Clients'),
          BottomNavigationBarItem(icon: Icon(FontAwesomeIcons.chartSimple), label: 'Reports'),
          BottomNavigationBarItem(icon: Icon(FontAwesomeIcons.gear), label: 'Settings'),
        ],
      ),
    );
  }

  // --- Helper Widgets ---
  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(color: AppColors.muted, fontSize: 14)),
        Text(value, style: GoogleFonts.inter(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 8))],
    );
  }
}

// Back chevron to match other pages
class _BackChevron extends StatelessWidget {
  const _BackChevron();
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: const Icon(FontAwesomeIcons.chevronLeft, size: 18, color: AppColors.text),
    );
  }
}


