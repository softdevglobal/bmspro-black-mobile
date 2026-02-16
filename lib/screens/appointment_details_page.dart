import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'task_details_page.dart';
import 'completed_appointment_preview_page.dart';
import '../utils/timezone_helper.dart';

// --- 1. Theme & Colors ---
class AppColors {
  static const primary = Color(0xFFFF2D8F);
  static const primaryDark = Color(0xFFD81F75);
  static const accent = Color(0xFFFF6FB5);
  static const background = Color(0xFFFFF5FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF9E9E9E);
  static const border = Color(0xFFF2D2E9);
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
  String? _currentServiceId;
  bool _isMyAppointment = false; // Track if appointment belongs to current user

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // Staggered animations for sections (removed checklist and notes, so 4 sections now)
    for (int i = 0; i < 4; i++) {
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
      
      // Check completion status
      bool isCompleted = false;
      
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
      
      // Update booking data and completion status
      setState(() {
        _bookingData = data;
        _isServiceCompleted = isCompleted;
        _isMyAppointment = isMyAppointment;
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
                    _buildFadeWrapper(2, _buildPointsRewards()),
                    const SizedBox(height: 24),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(color: AppColors.background),
      child: Row(
        children: const [
          _BackChevron(),
          Expanded(
            child: Center(
              child: Text(
                'Appointment Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
            ),
          ),
          SizedBox(width: 24),
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

  Widget _buildActionButtons() {
    return Column(
      children: [
        if (_isServiceCompleted) ...[
          // Show completed badge and view details button for completed services
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
        ] else ...[
          // Show Start Appointment button only if it's the current user's appointment
          if (_isMyAppointment)
            _GradientButton(
              text: 'Start Appointment',
              icon: FontAwesomeIcons.play,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TaskDetailsPage(appointmentData: widget.appointmentData),
                  ),
                );
              },
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

