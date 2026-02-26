import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'task_details_page.dart';
import 'completed_appointment_preview_page.dart';
import '../utils/timezone_helper.dart';

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
  static const green = Color(0xFF22C55E); // Matching Tailwind green-500
  static const yellow = Color(0xFFEAB308); // Matching Tailwind yellow-500
}

class AppointmentDetailsPage extends StatefulWidget {
  final Map<String, dynamic>? appointmentData;
  
  const AppointmentDetailsPage({super.key, this.appointmentData});

  @override
  State<AppointmentDetailsPage> createState() => _AppointmentDetailsPageState();
}

class _AppointmentDetailsPageState extends State<AppointmentDetailsPage> with TickerProviderStateMixin {
  // Animation Controller for Fade-in effects
  late AnimationController _fadeController;
  final List<Animation<double>> _fadeAnimations = [];

  // Data state
  Map<String, dynamic>? _customerData;
  Map<String, dynamic>? _bookingData;
  int _staffPoints = 0;
  bool _isLoading = true;
  String? _customerNotes;
  String _customerPhone = '';
  
  // Real-time updates
  StreamSubscription<DocumentSnapshot>? _bookingSubscription;
  bool _isServiceCompleted = false;
  bool _isCancelled = false;
  String? _currentServiceId;
  bool _isMyAppointment = false; // Track if appointment belongs to current user

  // Task management state
  List<Map<String, dynamic>> _tasks = [];
  int _taskProgress = 0;
  Map<String, dynamic>? _finalSubmission;
  bool _isUpdatingTask = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // Staggered animations for sections (5 sections: customer, info, tasks, points, actions)
    for (int i = 0; i < 5; i++) {
      final start = i * 0.1;
      final end = start + 0.4;
      _fadeAnimations.add(
        CurvedAnimation(
          parent: _fadeController,
          curve: Interval(start, end > 1.0 ? 1.0 : end, curve: Curves.easeOut),
        ),
      );
    }
    _fadeController.forward();
    _loadAppointmentData();
    _setupRealtimeListener();
  }

  void _setupRealtimeListener() {
    final bookingId = widget.appointmentData?['id'] as String?;
    if (bookingId == null) return;

    _bookingSubscription = FirebaseFirestore.instance
        .collection('bookings')
        .doc(bookingId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;
      
      final data = snapshot.data() as Map<String, dynamic>;
      final user = FirebaseAuth.instance.currentUser;
      
      // Get the serviceId from appointment data (for multi-service bookings)
      final serviceId = widget.appointmentData?['serviceId']?.toString();
      _currentServiceId = serviceId;
      
      // Check if appointment belongs to current user
      bool isMyAppointment = false;
      
      // Check completion and cancellation status
      bool isCompleted = false;
      final bookingStatus = (data['status']?.toString().toLowerCase() ?? '');
      final isCancelled = bookingStatus == 'cancelled' || bookingStatus == 'canceled';
      
      if (data['services'] is List && serviceId != null && serviceId.isNotEmpty) {
        // Multi-service booking - check specific service completion status
        for (final service in (data['services'] as List)) {
          if (service is Map && service['id']?.toString() == serviceId) {
            final staffId = service['staffId']?.toString();
            final staffAuthUid = service['staffAuthUid']?.toString();
            if (staffId == user?.uid || staffAuthUid == user?.uid) {
              isMyAppointment = true;
            }
            final completionStatus = service['completionStatus']?.toString()?.toLowerCase() ?? '';
            isCompleted = completionStatus == 'completed';
            break;
          }
        }
      } else if (data['services'] is List && (data['services'] as List).isNotEmpty) {
        // Multi-service booking but no specific serviceId - check if staff's service is completed
        for (final service in (data['services'] as List)) {
          if (service is Map) {
            final staffId = service['staffId']?.toString();
            final staffAuthUid = service['staffAuthUid']?.toString();
            if (staffId == user?.uid || staffAuthUid == user?.uid) {
              isMyAppointment = true;
              final completionStatus = service['completionStatus']?.toString()?.toLowerCase() ?? '';
              isCompleted = completionStatus == 'completed';
              break;
            }
          }
        }
      } else {
        // Single service booking - check booking-level status and assignment
        final staffId = data['staffId']?.toString();
        final staffAuthUid = data['staffAuthUid']?.toString();
        if (staffId == user?.uid || staffAuthUid == user?.uid) {
          isMyAppointment = true;
        }
        final status = data['status']?.toString()?.toLowerCase() ?? '';
        isCompleted = status == 'completed';
      }
      
      // Parse tasks from booking data
      final rawTasks = data['tasks'];
      List<Map<String, dynamic>> parsedTasks = [];
      if (rawTasks is List) {
        parsedTasks = rawTasks.map<Map<String, dynamic>>((t) => Map<String, dynamic>.from(t as Map)).toList();
      }
      final taskProg = (data['taskProgress'] as num?)?.toInt() ?? 0;
      final finalSub = data['finalSubmission'] != null
          ? Map<String, dynamic>.from(data['finalSubmission'] as Map)
          : null;

      // Update booking data and completion/cancellation status
      setState(() {
        _bookingData = data;
        _isServiceCompleted = isCompleted;
        _isCancelled = isCancelled;
        _isMyAppointment = isMyAppointment;
        _tasks = parsedTasks;
        _taskProgress = taskProg;
        _finalSubmission = finalSub;
      });
    });
  }

  Future<void> _loadAppointmentData() async {
    if (widget.appointmentData == null) {
      setState(() => _isLoading = false);
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
      
      // Check if appointment belongs to current user (initial check)
      final user = FirebaseAuth.instance.currentUser;
      bool isMyAppointment = false;
      
      if (_bookingData != null && user != null) {
        final serviceId = widget.appointmentData?['serviceId']?.toString();
        
        if (_bookingData!['services'] is List && serviceId != null && serviceId.isNotEmpty) {
          // Multi-service booking - check specific service
          for (final service in (_bookingData!['services'] as List)) {
            if (service is Map && service['id']?.toString() == serviceId) {
              final staffId = service['staffId']?.toString();
              final staffAuthUid = service['staffAuthUid']?.toString();
              if (staffId == user.uid || staffAuthUid == user.uid) {
                isMyAppointment = true;
                break;
              }
            }
          }
        } else if (_bookingData!['services'] is List && (_bookingData!['services'] as List).isNotEmpty) {
          // Multi-service booking - check if any service belongs to user
          for (final service in (_bookingData!['services'] as List)) {
            if (service is Map) {
              final staffId = service['staffId']?.toString();
              final staffAuthUid = service['staffAuthUid']?.toString();
              if (staffId == user.uid || staffAuthUid == user.uid) {
                isMyAppointment = true;
                break;
              }
            }
          }
        } else {
          // Single service booking - check booking-level assignment
          final staffId = _bookingData!['staffId']?.toString();
          final staffAuthUid = _bookingData!['staffAuthUid']?.toString();
          if (staffId == user.uid || staffAuthUid == user.uid) {
            isMyAppointment = true;
          }
        }
      }
      
      // Set the appointment ownership flag
      _isMyAppointment = isMyAppointment;

      // Extract customer info from booking
      final clientName = _bookingData?['client']?.toString() ?? 
                        _bookingData?['clientName']?.toString() ?? 
                        widget.appointmentData!['client']?.toString() ?? 
                        'Customer';
      final clientEmail = _bookingData?['email']?.toString() ?? 
                         _bookingData?['clientEmail']?.toString() ?? '';
      final clientPhone = _bookingData?['phone']?.toString() ?? 
                         _bookingData?['clientPhone']?.toString() ?? '';
      _customerPhone = clientPhone;
      
      // Try to find customer in customers collection
      if (user != null) {
        final ownerUid = user.uid;
        // Try to find customer by email or phone
        QuerySnapshot? customerSnap;
        if (clientEmail.isNotEmpty) {
          customerSnap = await FirebaseFirestore.instance
              .collection('customers')
              .where('ownerUid', isEqualTo: ownerUid)
              .where('email', isEqualTo: clientEmail)
              .limit(1)
              .get();
        }
        if ((customerSnap == null || customerSnap.docs.isEmpty) && clientPhone.isNotEmpty) {
          customerSnap = await FirebaseFirestore.instance
              .collection('customers')
              .where('ownerUid', isEqualTo: ownerUid)
              .where('phone', isEqualTo: clientPhone)
              .limit(1)
              .get();
        }
        
        if (customerSnap != null && customerSnap.docs.isNotEmpty) {
          _customerData = customerSnap.docs.first.data() as Map<String, dynamic>;
          // Use phone from customer data if available, otherwise use booking phone
          final customerPhone = _customerData?['phone']?.toString() ?? '';
          if (customerPhone.isNotEmpty) {
            _customerPhone = customerPhone;
          }
        } else {
          // Create customer data from booking
          _customerData = {
            'name': clientName,
            'email': clientEmail,
            'phone': clientPhone,
            'visits': 0,
          };
        }

        // Load staff points
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          _staffPoints = (userData?['staffPoints'] ?? 0) as int;
        }
      }

      // Get customer notes from booking - check multiple possible field names
      // Try to get notes from the booking data
      String? notesValue;
      
      // Debug: Print all booking data keys to see what's available
      if (_bookingData != null) {
        debugPrint('Booking data keys: ${_bookingData!.keys.toList()}');
        debugPrint('Booking data notes field: ${_bookingData!['notes']}');
      }
      
      // Check various possible field names for notes (in order of likelihood)
      if (_bookingData != null) {
        // Primary field name used in walk_in_booking_page.dart
        final rawNotes = _bookingData!['notes'];
        if (rawNotes != null) {
          notesValue = rawNotes.toString().trim();
          debugPrint('Found notes in "notes" field: $notesValue');
        }
        
        // Fallback to other possible field names
        if (notesValue == null || notesValue.isEmpty) {
          notesValue = _bookingData!['customerNotes']?.toString()?.trim();
          if (notesValue != null && notesValue.isNotEmpty) {
            debugPrint('Found notes in "customerNotes" field: $notesValue');
          }
        }
        if (notesValue == null || notesValue.isEmpty) {
          notesValue = _bookingData!['bookingNotes']?.toString()?.trim();
        }
        if (notesValue == null || notesValue.isEmpty) {
          notesValue = _bookingData!['additionalNotes']?.toString()?.trim();
        }
        if (notesValue == null || notesValue.isEmpty) {
          notesValue = _bookingData!['specialNotes']?.toString()?.trim();
        }
        if (notesValue == null || notesValue.isEmpty) {
          notesValue = _bookingData!['clientNotes']?.toString()?.trim();
        }
      }
      
      // Also check in the appointment data directly (in case it's passed but not in bookingData)
      if ((notesValue == null || notesValue.isEmpty) && widget.appointmentData != null) {
        final apptNotes = widget.appointmentData!['notes']?.toString()?.trim();
        if (apptNotes != null && apptNotes.isNotEmpty) {
          notesValue = apptNotes;
          debugPrint('Found notes in appointment data: $notesValue');
        }
      }
      
      // Also check in services array if it exists
      if ((notesValue == null || notesValue.isEmpty) && 
          _bookingData != null && 
          _bookingData!['services'] is List) {
        final services = _bookingData!['services'] as List;
        for (final service in services) {
          if (service is Map) {
            final serviceNotes = service['notes']?.toString()?.trim();
            if (serviceNotes != null && serviceNotes.isNotEmpty) {
              notesValue = serviceNotes;
              debugPrint('Found notes in services array: $notesValue');
              break;
            }
          }
        }
      }
      
      // Set the notes value - only show default message if truly no notes found
      if (notesValue != null && notesValue.isNotEmpty && notesValue != 'null') {
        _customerNotes = notesValue;
        debugPrint('Final customer notes set: ${_customerNotes}');
      } else {
        _customerNotes = 'No customer notes available.';
        debugPrint('No customer notes found in booking');
      }

    } catch (e) {
      debugPrint('Error loading appointment data: $e');
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _bookingSubscription?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _contactCustomer() async {
    if (_customerPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number available for this customer.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Clean the phone number (remove spaces, dashes, parentheses, plus signs, etc.)
    // Keep only digits and + sign at the beginning
    String cleanPhone = _customerPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // Ensure phone number starts with + or has digits
    if (cleanPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid phone number format.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    debugPrint('Attempting to call: $cleanPhone');
    
    // Create tel: URL
    final Uri phoneUri = Uri.parse('tel:$cleanPhone');
    
    try {
      // Use externalApplication mode to force opening the phone dialer
      final launched = await launchUrl(
        phoneUri,
        mode: LaunchMode.externalApplication,
      );
      
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open phone dialer. Please check if a dialer app is installed.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error launching phone: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening dialer: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
                  _buildFadeWrapper(0, _buildCustomerCard()),
                  const SizedBox(height: 24),
                  _buildFadeWrapper(1, _buildAppointmentInfo()),
                  const SizedBox(height: 24),
                  if (_tasks.isNotEmpty) ...[
                    _buildFadeWrapper(2, _buildTaskSection()),
                    const SizedBox(height: 24),
                  ],
                  _buildFadeWrapper(3, _buildActionButtons()),
                  const SizedBox(height: 40), // Bottom padding
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildFadeWrapper(int index, Widget child) {
    return FadeTransition(
      opacity: _fadeAnimations[index],
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(_fadeAnimations[index]),
        child: child,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
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
                      'Appointment Details',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
                    ),
                    Text(
                      'View & manage booking',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
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

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String _getLoyaltyStatus(int visits) {
    if (visits >= 10) return 'Platinum';
    if (visits >= 5) return 'Gold';
    if (visits >= 2) return 'Silver';
    return 'New';
  }

  Widget _buildCustomerCard() {
    final customerName = _customerData?['name']?.toString() ?? 
                        _bookingData?['client']?.toString() ?? 
                        _bookingData?['clientName']?.toString() ?? 
                        widget.appointmentData?['client']?.toString() ?? 
                        'Customer';
    final customerEmail = _customerData?['email']?.toString() ?? 
                         _bookingData?['email']?.toString() ?? 
                         _bookingData?['clientEmail']?.toString() ?? '';
    final customerPhone = _customerData?['phone']?.toString() ?? 
                         _bookingData?['phone']?.toString() ?? 
                         _bookingData?['clientPhone']?.toString() ?? '';
    final vehicleNumber = _bookingData?['vehicleNumber']?.toString() ?? '';
    final visits = (_customerData?['visits'] ?? 0) as int;
    final loyaltyStatus = _getLoyaltyStatus(visits);
    final initials = _getInitials(customerName);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64, 
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 8))],
                  color: AppColors.primary.withOpacity(0.15),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text),
                    ),
                    if (customerPhone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        customerPhone,
                        style: const TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    ],
                    if (vehicleNumber.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Vehicle: $vehicleNumber',
                        style: const TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Loyalty: $loyaltyStatus',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text),
                        ),
                        const SizedBox(width: 8),
                        const Icon(FontAwesomeIcons.solidStar, size: 14, color: AppColors.yellow),
                      ],
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

  String _calculateEndTime(String startTime, int durationMinutes) {
    if (startTime.isEmpty) return '';
    try {
      final parts = startTime.split(':');
      if (parts.length >= 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1]);
        
        final startDateTime = DateTime(2000, 1, 1, hour, minute);
        final endDateTime = startDateTime.add(Duration(minutes: durationMinutes));
        
        final endHour = endDateTime.hour;
        final endMinute = endDateTime.minute;
        final period = endHour >= 12 ? 'PM' : 'AM';
        int displayHour = endHour > 12 ? endHour - 12 : (endHour == 0 ? 12 : endHour);
        
        return '$displayHour:${endMinute.toString().padLeft(2, '0')} $period';
      }
    } catch (_) {}
    return '';
  }

  Widget _buildAppointmentInfo() {
    final serviceName = widget.appointmentData?['serviceName']?.toString() ?? 
                       _bookingData?['serviceName']?.toString() ?? 
                       'Service';
    final duration = widget.appointmentData?['duration']?.toString() ?? 
                    _bookingData?['duration']?.toString() ?? '';
    final time = widget.appointmentData?['time']?.toString() ?? 
                _bookingData?['time']?.toString() ?? 
                _bookingData?['startTime']?.toString() ?? '';
    final date = widget.appointmentData?['date']?.toString() ?? 
                _bookingData?['date']?.toString() ?? '';
    final location = _bookingData?['branchName']?.toString() ?? 
                    _bookingData?['room']?.toString() ?? 
                    _bookingData?['location']?.toString() ?? 
                    'Salon';

    final durationInt = int.tryParse(duration) ?? 60;
    final formattedStartTime = _formatTime(time);
    final formattedEndTime = _calculateEndTime(time, durationInt);
    final timeRange = formattedEndTime.isNotEmpty 
        ? '$formattedStartTime → $formattedEndTime'
        : formattedStartTime;
    
    final serviceDisplay = duration.isNotEmpty 
        ? '$serviceName – ${duration}min'
        : serviceName;

    IconData serviceIcon = FontAwesomeIcons.spa;
    final serviceLower = serviceName.toLowerCase();
    if (serviceLower.contains('nail') || serviceLower.contains('manicure') || serviceLower.contains('pedicure')) {
      serviceIcon = FontAwesomeIcons.handSparkles;
    } else if (serviceLower.contains('facial') || serviceLower.contains('face')) {
      serviceIcon = FontAwesomeIcons.leaf;
    } else if (serviceLower.contains('hair') || serviceLower.contains('cut') || serviceLower.contains('style')) {
      serviceIcon = FontAwesomeIcons.scissors;
    } else if (serviceLower.contains('wax') || serviceLower.contains('threading')) {
      serviceIcon = FontAwesomeIcons.feather;
    } else if (serviceLower.contains('makeup') || serviceLower.contains('beauty')) {
      serviceIcon = FontAwesomeIcons.wandMagicSparkles;
    } else if (serviceLower.contains('color') || serviceLower.contains('colour')) {
      serviceIcon = FontAwesomeIcons.paintbrush;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Appointment Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 16),
          _infoRow(serviceIcon, [Colors.purple.shade400, Colors.purple.shade600], serviceDisplay, 'SERVICE'),
          const SizedBox(height: 16),
          _infoRow(FontAwesomeIcons.clock, [Colors.blue.shade400, Colors.blue.shade600], timeRange.isNotEmpty ? timeRange : 'Time TBD', 'TIME'),
          const SizedBox(height: 16),
          _infoRow(FontAwesomeIcons.doorOpen, [Colors.green.shade400, Colors.green.shade600], location, 'LOCATION'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, List<Color> colors, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Icon(icon, color: Colors.white, size: 14)),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ],
    );
  }

  Widget _buildPointsRewards() {
    final formattedPoints = _staffPoints.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration().copyWith(border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          const Align(alignment: Alignment.centerLeft, child: Text('Points & Rewards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text))),
          const SizedBox(height: 16),
          Text(
            '$formattedPoints pts',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
          const Text('Staff Point Balance', style: TextStyle(fontSize: 14, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _buildNotes() {
    // Get notes and ensure they're displayed properly
    final notes = _customerNotes ?? 'No customer notes available.';
    final displayNotes = (notes.isEmpty || 
                         notes == 'No customer notes available.' || 
                         notes.trim().isEmpty) 
        ? 'No customer notes available.' 
        : notes.trim();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Customer Notes:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
                const SizedBox(height: 8),
                Text(
                  displayNotes,
                  style: const TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Task Management Section ─────────────────────────────────────────────
  Widget _buildTaskSection() {
    final completedCount = _tasks.where((t) => t['done'] == true).length;
    final totalCount = _tasks.length;
    final progress = totalCount > 0 ? (completedCount / totalCount) : 0.0;
    final allDone = completedCount == totalCount && totalCount > 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: allDone
                        ? [Colors.green.shade400, Colors.green.shade600]
                        : [Colors.amber.shade400, Colors.amber.shade600],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    allDone ? FontAwesomeIcons.clipboardCheck : FontAwesomeIcons.clipboardList,
                    color: Colors.white, size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Task Progress', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text('$completedCount of $totalCount tasks completed', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              // Progress percentage
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: allDone ? Colors.green.shade50 : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: allDone ? Colors.green.shade200 : Colors.amber.shade200),
                ),
                child: Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold,
                    color: allDone ? Colors.green.shade700 : Colors.amber.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                allDone ? Colors.green.shade500 : Colors.amber.shade500,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Task list
          ..._tasks.asMap().entries.map((entry) {
            final idx = entry.key;
            final task = entry.value;
            final isDone = task['done'] == true;
            return _buildTaskItem(task, idx, isDone);
          }),

          // Final submission section
          if (allDone && _finalSubmission == null && _isMyAppointment) ...[
            const SizedBox(height: 16),
            _buildFinalSubmissionForm(),
          ],
          if (_finalSubmission != null) ...[
            const SizedBox(height: 16),
            _buildFinalSubmissionView(),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskItem(Map<String, dynamic> task, int index, bool isDone) {
    final taskName = task['name']?.toString() ?? 'Task ${index + 1}';
    final taskDesc = task['description']?.toString() ?? '';
    final staffNote = task['staffNote']?.toString() ?? '';
    final imageUrl = task['imageUrl']?.toString() ?? '';
    final serviceName = task['serviceName']?.toString() ?? '';
    final completedBy = task['completedByStaffName']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDone ? Colors.green.shade50.withOpacity(0.5) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone ? Colors.green.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox / number
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: isDone ? Colors.green.shade500 : Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '${index + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taskName,
                      style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600,
                        color: isDone ? Colors.green.shade700 : AppColors.text,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (taskDesc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(taskDesc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                    if (serviceName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(FontAwesomeIcons.wandMagicSparkles, size: 10, color: Colors.purple.shade400),
                          const SizedBox(width: 4),
                          Text(serviceName, style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (isDone)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Done', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                ),
            ],
          ),

          // Staff note
          if (staffNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(FontAwesomeIcons.commentDots, size: 10, color: Colors.blue.shade600),
                      const SizedBox(width: 6),
                      Text('Staff Note', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(staffNote, style: TextStyle(fontSize: 12, color: Colors.blue.shade800)),
                  if (completedBy.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('— $completedBy', style: TextStyle(fontSize: 10, color: Colors.blue.shade500)),
                  ],
                ],
              ),
            ),
          ],

          // Task image
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                ),
              ),
            ),
          ],

          // Action button for assigned staff (mark as done)
          if (!isDone && _isMyAppointment) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUpdatingTask ? null : () => _showTaskCompletionDialog(task),
                icon: _isUpdatingTask
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(FontAwesomeIcons.check, size: 14),
                label: const Text('Mark as Done', style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showTaskCompletionDialog(Map<String, dynamic> task) async {
    final noteController = TextEditingController();
    File? selectedImage;
    String? uploadedImageUrl;
    bool isUploading = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Complete: ${task['name'] ?? 'Task'}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
                    ),
                    if ((task['description'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task['description'].toString(),
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Photo capture (optional)
                    Row(
                      children: [
                        const Text('Photo ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                        Text('(optional)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: isUploading ? null : () async {
                        final source = await showDialog<ImageSource>(
                          context: ctx,
                          builder: (c) => AlertDialog(
                            title: const Text('Select Image Source'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.camera_alt),
                                  title: const Text('Camera'),
                                  onTap: () => Navigator.pop(c, ImageSource.camera),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.photo_library),
                                  title: const Text('Gallery'),
                                  onTap: () => Navigator.pop(c, ImageSource.gallery),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (source == null) return;
                        final picked = await _imagePicker.pickImage(source: source, imageQuality: 70, maxWidth: 1200);
                        if (picked != null) {
                          setSheetState(() {
                            selectedImage = File(picked.path);
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: selectedImage != null ? 200 : 80,
                        decoration: BoxDecoration(
                          color: selectedImage != null ? Colors.grey.shade100 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selectedImage != null ? Colors.green.shade300 : Colors.grey.shade300,
                          ),
                        ),
                        child: selectedImage != null
                            ? Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.file(selectedImage!, width: double.infinity, height: 200, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: 8, right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade600,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check_circle, color: Colors.white, size: 12),
                                          SizedBox(width: 4),
                                          Text('Photo selected', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8, right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(FontAwesomeIcons.camera, color: Colors.white, size: 10),
                                          SizedBox(width: 4),
                                          Text('Tap to change', style: TextStyle(color: Colors.white, fontSize: 10)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(FontAwesomeIcons.camera, color: Colors.grey.shade400, size: 20),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Tap to add a photo',
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    const Text('Description', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Describe the work done...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: isUploading ? null : () async {
                          // Upload image only if one was selected
                          if (selectedImage != null) {
                            setSheetState(() {
                              isUploading = true;
                            });
                            uploadedImageUrl = await _uploadTaskImage(selectedImage!);
                            if (uploadedImageUrl == null || uploadedImageUrl!.isEmpty) {
                              setSheetState(() {
                                isUploading = false;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Failed to upload photo. Please try again.'),
                                    backgroundColor: Colors.red.shade600,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                              return;
                            }
                          }
                          Navigator.pop(ctx, {
                            'note': noteController.text.trim(),
                            'imageUrl': uploadedImageUrl ?? '',
                          });
                        },
                        icon: isUploading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(FontAwesomeIcons.check, size: 16),
                        label: Text(
                          isUploading ? 'Uploading Photo...' : 'Complete Task',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isUploading ? Colors.grey.shade400 : Colors.green.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                ),
              ),
            );
          },
        );
      },
    ).then((result) {
      if (result != null && result is Map) {
        _completeTask(task, result['note'] ?? '', result['imageUrl'] ?? '');
      }
    });
  }

  Future<String?> _uploadTaskImage(File imageFile) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final bookingId = widget.appointmentData?['id'] as String? ?? 'unknown';
      final fileName = 'task_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('bookings/$bookingId/tasks/$fileName');
      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading task image: $e');
      return null;
    }
  }

  Future<void> _completeTask(Map<String, dynamic> task, String staffNote, String imageUrl) async {
    final bookingId = widget.appointmentData?['id'] as String?;
    if (bookingId == null) return;

    setState(() => _isUpdatingTask = true);

    try {
      final taskId = task['id']?.toString() ?? '';
      
      // Update the task directly in Firestore
      final bookingRef = FirebaseFirestore.instance.collection('bookings').doc(bookingId);
      final bookingSnap = await bookingRef.get();
      if (!bookingSnap.exists) return;

      final data = bookingSnap.data()!;
      final tasks = List<Map<String, dynamic>>.from(
        (data['tasks'] as List? ?? []).map((t) => Map<String, dynamic>.from(t as Map)),
      );

      final user = FirebaseAuth.instance.currentUser;
      final taskIndex = tasks.indexWhere((t) => t['id'] == taskId);
      if (taskIndex == -1) return;

      tasks[taskIndex] = {
        ...tasks[taskIndex],
        'done': true,
        'imageUrl': imageUrl.isNotEmpty ? imageUrl : (tasks[taskIndex]['imageUrl'] ?? ''),
        'staffNote': staffNote.isNotEmpty ? staffNote : (tasks[taskIndex]['staffNote'] ?? ''),
        'completedAt': DateTime.now().toIso8601String(),
        'completedByStaffUid': user?.uid ?? '',
        'completedByStaffName': user?.displayName ?? 'Staff',
      };

      final total = tasks.length;
      final completed = tasks.where((t) => t['done'] == true).length;
      final taskProgress = total > 0 ? ((completed / total) * 100).round() : 0;

      await bookingRef.update({
        'tasks': tasks,
        'taskProgress': taskProgress,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Task "${task['name']}" completed!'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error completing task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete task: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingTask = false);
    }
  }

  Widget _buildFinalSubmissionForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.flagCheckered, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Final Submission', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'All tasks completed! Submit your final report.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isUpdatingTask ? null : _showFinalSubmissionDialog,
              icon: const Icon(FontAwesomeIcons.paperPlane, size: 14),
              label: const Text('Submit Final Report', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalSubmissionView() {
    final desc = _finalSubmission?['description']?.toString() ?? '';
    final imgUrl = _finalSubmission?['imageUrl']?.toString() ?? '';
    final submittedBy = _finalSubmission?['submittedByStaffName']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Icon(FontAwesomeIcons.flagCheckered, size: 12, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              const Text('Final Submission', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text)),
              const Spacer(),
              if (submittedBy.isNotEmpty)
                Text('by $submittedBy', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(desc, style: const TextStyle(fontSize: 13, color: AppColors.text, height: 1.5)),
          ],
          if (imgUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imgUrl,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 60,
                  color: Colors.grey.shade200,
                  child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showFinalSubmissionDialog() async {
    final descController = TextEditingController();
    File? selectedImage;
    String? uploadedImageUrl;
    bool isUploading = false;
    bool showImageError = false;
    bool showDescError = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Final Submission', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text)),
                    const SizedBox(height: 4),
                    Text('Provide an overall summary and final photo.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 20),

                    // Final photo (REQUIRED)
                    Row(
                      children: [
                        const Text('Final Photo ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                        Text('(required)', style: TextStyle(fontSize: 12, color: showImageError ? Colors.red : Colors.orange.shade700, fontWeight: showImageError ? FontWeight.bold : FontWeight.normal)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: isUploading ? null : () async {
                        final source = await showDialog<ImageSource>(
                          context: ctx,
                          builder: (c) => AlertDialog(
                            title: const Text('Select Image Source'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.camera_alt),
                                  title: const Text('Camera'),
                                  onTap: () => Navigator.pop(c, ImageSource.camera),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.photo_library),
                                  title: const Text('Gallery'),
                                  onTap: () => Navigator.pop(c, ImageSource.gallery),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (source == null) return;
                        final picked = await _imagePicker.pickImage(source: source, imageQuality: 70, maxWidth: 1200);
                        if (picked != null) {
                          setSheetState(() {
                            selectedImage = File(picked.path);
                            showImageError = false;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: selectedImage != null ? 200 : 120,
                        decoration: BoxDecoration(
                          color: selectedImage != null ? Colors.grey.shade100 : (showImageError ? Colors.red.shade50 : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: showImageError ? Colors.red.shade400 : (selectedImage != null ? Colors.grey.shade600 : Colors.grey.shade300),
                            width: showImageError ? 2 : 1,
                          ),
                        ),
                        child: selectedImage != null
                            ? Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.file(selectedImage!, width: double.infinity, height: 200, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: 8, right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check_circle, color: Colors.white, size: 12),
                                          SizedBox(width: 4),
                                          Text('Photo selected', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8, right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(FontAwesomeIcons.camera, color: Colors.white, size: 10),
                                          SizedBox(width: 4),
                                          Text('Tap to change', style: TextStyle(color: Colors.white, fontSize: 10)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(FontAwesomeIcons.camera, color: showImageError ? Colors.red.shade400 : Colors.grey.shade400, size: 28),
                                  const SizedBox(height: 8),
                                  Text(
                                    showImageError ? 'Final photo is required!' : 'Tap to capture final photo',
                                    style: TextStyle(
                                      color: showImageError ? Colors.red.shade600 : Colors.grey.shade500,
                                      fontSize: 13,
                                      fontWeight: showImageError ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description (REQUIRED)
                    Row(
                      children: [
                        const Text('Description ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                        Text('(required)', style: TextStyle(fontSize: 12, color: showDescError ? Colors.red : Colors.orange.shade700, fontWeight: showDescError ? FontWeight.bold : FontWeight.normal)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      maxLines: 4,
                      onChanged: (_) {
                        if (showDescError) setSheetState(() => showDescError = false);
                      },
                      decoration: InputDecoration(
                        hintText: 'Overall description of work completed...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        filled: true,
                        fillColor: showDescError ? Colors.red.shade50 : Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: showDescError ? Colors.red.shade400 : Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: showDescError ? Colors.red.shade400 : Colors.grey.shade300, width: showDescError ? 2 : 1)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                        errorText: showDescError ? 'Please provide a description' : null,
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: isUploading ? null : () async {
                          bool hasError = false;
                          if (selectedImage == null) {
                            showImageError = true;
                            hasError = true;
                          }
                          if (descController.text.trim().isEmpty) {
                            showDescError = true;
                            hasError = true;
                          }
                          if (hasError) {
                            setSheetState(() {});
                            return;
                          }

                          setSheetState(() {
                            isUploading = true;
                          });
                          uploadedImageUrl = await _uploadTaskImage(selectedImage!);
                          if (uploadedImageUrl == null || uploadedImageUrl!.isEmpty) {
                            setSheetState(() {
                              isUploading = false;
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Failed to upload photo. Please try again.'),
                                  backgroundColor: Colors.red.shade600,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                            return;
                          }
                          Navigator.pop(ctx, {
                            'description': descController.text.trim(),
                            'imageUrl': uploadedImageUrl ?? '',
                          });
                        },
                        icon: isUploading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(FontAwesomeIcons.paperPlane, size: 14),
                        label: Text(
                          isUploading ? 'Uploading...' : 'Submit Report',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isUploading ? Colors.grey.shade400 : AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                ),
              ),
            );
          },
        );
      },
    ).then((result) async {
      if (result != null && result is Map) {
        await _submitFinalReport(result['description'] ?? '', result['imageUrl'] ?? '');
      }
    });
  }

  Future<void> _submitFinalReport(String description, String imageUrl) async {
    final bookingId = widget.appointmentData?['id'] as String?;
    if (bookingId == null) return;

    setState(() => _isUpdatingTask = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final finalSubmission = {
        'description': description,
        'imageUrl': imageUrl,
        'submittedAt': DateTime.now().toIso8601String(),
        'submittedByStaffUid': user?.uid ?? '',
        'submittedByStaffName': user?.displayName ?? 'Staff',
      };

      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'finalSubmission': finalSubmission,
        'taskProgress': 100,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Auto-complete the booking via the service-complete API
      // This handles: status → Completed, customer notification, email, activity log
      bool bookingCompleted = false;
      try {
        final token = await user?.getIdToken();
        if (token != null) {
          const apiBaseUrl = 'https://black.bmspros.com.au';
          final Map<String, dynamic> requestBody = {};
          if (_currentServiceId != null && _currentServiceId!.isNotEmpty) {
            requestBody['serviceId'] = _currentServiceId;
          }
          final response = await http.post(
            Uri.parse('$apiBaseUrl/api/bookings/$bookingId/service-complete'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(requestBody),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final responseData = jsonDecode(response.body);
            bookingCompleted = responseData['bookingCompleted'] ?? false;
            debugPrint('✅ Service-complete API succeeded: ${responseData['message']}');
          } else {
            debugPrint('⚠️ Service-complete API returned ${response.statusCode}: ${response.body}');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Service-complete API call failed (final submission saved): $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bookingCompleted
                ? 'Report submitted & booking marked as completed!'
                : 'Final report submitted successfully!'),
            backgroundColor: bookingCompleted ? Colors.green.shade600 : AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error submitting final report: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit report: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingTask = false);
    }
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        if (_isCancelled) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(FontAwesomeIcons.ban, color: Color(0xFFEF4444), size: 20),
                SizedBox(width: 12),
                Text(
                  'Booking Cancelled',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ] else if (_isServiceCompleted) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.green.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(FontAwesomeIcons.circleCheck, color: AppColors.green, size: 20),
                SizedBox(width: 12),
                Text(
                  'Service Completed',
                  style: TextStyle(
                    color: AppColors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CompletedAppointmentPreviewPage(
                      appointmentData: widget.appointmentData,
                      bookingData: _bookingData,
                      serviceId: _currentServiceId,
                    ),
                  ),
                );
              },
              icon: const Icon(FontAwesomeIcons.eye, size: 16, color: AppColors.primary),
              label: const Text('View Details', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _customerPhone.isNotEmpty ? _contactCustomer : null,
            icon: const Icon(FontAwesomeIcons.phone, size: 16, color: AppColors.primary),
            label: const Text('Contact Customer', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
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

// Back chevron used in headers to match other pages
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

// --- Helper: Gradient Button ---
class _GradientButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onPressed;
  const _GradientButton({required this.text, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

