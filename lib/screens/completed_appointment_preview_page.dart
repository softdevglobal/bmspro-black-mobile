import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

// --- Theme & Colors ---
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

class CompletedAppointmentPreviewPage extends StatelessWidget {
  final Map<String, dynamic>? appointmentData;
  final Map<String, dynamic>? bookingData;
  final String? serviceId;

  const CompletedAppointmentPreviewPage({
    super.key,
    this.appointmentData,
    this.bookingData,
    this.serviceId,
  });

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

  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      DateTime? dateTime;
      if (timestamp is String) {
        dateTime = DateTime.tryParse(timestamp);
      } else if (timestamp.runtimeType.toString().contains('Timestamp')) {
        dateTime = (timestamp as dynamic).toDate();
      }
      if (dateTime != null) {
        return DateFormat('MMM d, yyyy h:mm a').format(dateTime);
      }
    } catch (_) {}
    return timestamp.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Get service details
    Map<String, dynamic>? serviceData;
    if (bookingData != null && bookingData!['services'] is List && serviceId != null) {
      for (final service in (bookingData!['services'] as List)) {
        if (service is Map && service['id']?.toString() == serviceId) {
          serviceData = Map<String, dynamic>.from(service);
          break;
        }
      }
    }

    final serviceName = serviceData?['name']?.toString() ??
        appointmentData?['serviceName']?.toString() ??
        bookingData?['serviceName']?.toString() ??
        'Service';
    final duration = serviceData?['duration']?.toString() ??
        appointmentData?['duration']?.toString() ??
        bookingData?['duration']?.toString() ??
        '';
    final time = serviceData?['time']?.toString() ??
        appointmentData?['time']?.toString() ??
        bookingData?['time']?.toString() ??
        '';
    final date = appointmentData?['date']?.toString() ??
        bookingData?['date']?.toString() ??
        '';
    final clientName = bookingData?['client']?.toString() ??
        bookingData?['clientName']?.toString() ??
        appointmentData?['client']?.toString() ??
        'Customer';
    final branchName = bookingData?['branchName']?.toString() ?? 'Location';
    final completedAt = serviceData?['completedAt'] ?? bookingData?['completedAt'];
    final completedByStaffName = serviceData?['completedByStaffName'] ??
        bookingData?['completedByStaffName'] ??
        'Staff';
    final price = serviceData?['price'] ?? bookingData?['price'];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Completion Status Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.green.withOpacity(0.1),
                            AppColors.green.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.green.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: const Center(
                              child: Icon(
                                FontAwesomeIcons.circleCheck,
                                color: AppColors.green,
                                size: 32,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Service Completed',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Completed at ${_formatDateTime(completedAt)}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.muted,
                            ),
                          ),
                          if (completedByStaffName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'by $completedByStaffName',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Service Info Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: _cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Service Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _infoRow(
                            FontAwesomeIcons.scissors,
                            [Colors.purple.shade400, Colors.purple.shade600],
                            duration.isNotEmpty ? '$serviceName – ${duration}min' : serviceName,
                            'SERVICE',
                          ),
                          const SizedBox(height: 16),
                          _infoRow(
                            FontAwesomeIcons.clock,
                            [Colors.blue.shade400, Colors.blue.shade600],
                            time.isNotEmpty ? _formatTime(time) : 'Time N/A',
                            'TIME',
                          ),
                          const SizedBox(height: 16),
                          _infoRow(
                            FontAwesomeIcons.calendarDay,
                            [Colors.orange.shade400, Colors.orange.shade600],
                            date.isNotEmpty ? date : 'Date N/A',
                            'DATE',
                          ),
                          const SizedBox(height: 16),
                          _infoRow(
                            FontAwesomeIcons.doorOpen,
                            [Colors.green.shade400, Colors.green.shade600],
                            branchName,
                            'LOCATION',
                          ),
                          if (price != null) ...[
                            const SizedBox(height: 16),
                            _infoRow(
                              FontAwesomeIcons.dollarSign,
                              [Colors.teal.shade400, Colors.teal.shade600],
                              '\$${price.toString()}',
                              'PRICE',
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Customer Info Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: _cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Customer',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppColors.primary.withOpacity(0.15),
                                ),
                                child: Center(
                                  child: Text(
                                    clientName.isNotEmpty ? clientName[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      clientName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.text,
                                      ),
                                    ),
                                    if (bookingData?['clientEmail'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        bookingData!['clientEmail'].toString(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
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
            child: const Icon(FontAwesomeIcons.chevronLeft, size: 18, color: AppColors.text),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Completed Appointment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, List<Color> colors, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
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

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withOpacity(0.08),
          blurRadius: 25,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

