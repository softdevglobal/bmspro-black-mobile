import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

class CompletedAppointmentPreviewPage extends StatefulWidget {
  final Map<String, dynamic>? appointmentData;
  final Map<String, dynamic>? bookingData;
  final String? serviceId;

  const CompletedAppointmentPreviewPage({
    super.key,
    this.appointmentData,
    this.bookingData,
    this.serviceId,
  });

  @override
  State<CompletedAppointmentPreviewPage> createState() =>
      _CompletedAppointmentPreviewPageState();
}

class _CompletedAppointmentPreviewPageState
    extends State<CompletedAppointmentPreviewPage> {
  bool _downloading = false;

  Future<void> _downloadJobReport() async {
    final bookingId = widget.bookingData?['id'] ??
        widget.appointmentData?['id'] ??
        widget.appointmentData?['bookingId'];
    if (bookingId == null) {
      _showSnackbar('Booking ID not found');
      return;
    }

    setState(() => _downloading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');
      final token = await user.getIdToken();

      final apiUrl = 'https://black.bmspros.com.au/api/bookings/$bookingId/pdf';
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to download PDF');
      }

      final dir = await getApplicationDocumentsDirectory();
      final bookingCode =
          widget.bookingData?['bookingCode'] ?? bookingId.toString().substring(0, 8);
      final file = File('${dir.path}/Job-Report-$bookingCode.pdf');
      await file.writeAsBytes(response.bodyBytes);

      if (!mounted) return;
      _showSnackbar('Job report saved successfully!', isSuccess: true);

      // Try to open the file
      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('PDF download error: $e');
      if (mounted) {
        _showSnackbar('Failed to download report. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showSnackbar(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? AppColors.green : Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    if (widget.bookingData != null && widget.bookingData!['services'] is List && widget.serviceId != null) {
      for (final service in (widget.bookingData!['services'] as List)) {
        if (service is Map && service['id']?.toString() == widget.serviceId) {
          serviceData = Map<String, dynamic>.from(service);
          break;
        }
      }
    }

    final serviceName = serviceData?['name']?.toString() ??
        widget.appointmentData?['serviceName']?.toString() ??
        widget.bookingData?['serviceName']?.toString() ??
        'Service';
    final duration = serviceData?['duration']?.toString() ??
        widget.appointmentData?['duration']?.toString() ??
        widget.bookingData?['duration']?.toString() ??
        '';
    final time = serviceData?['time']?.toString() ??
        widget.appointmentData?['time']?.toString() ??
        widget.bookingData?['time']?.toString() ??
        '';
    final date = widget.appointmentData?['date']?.toString() ??
        widget.bookingData?['date']?.toString() ??
        '';
    final clientName = widget.bookingData?['client']?.toString() ??
        widget.bookingData?['clientName']?.toString() ??
        widget.appointmentData?['client']?.toString() ??
        'Customer';
    final branchName = widget.bookingData?['branchName']?.toString() ?? 'Location';
    final completedAt = serviceData?['completedAt'] ?? widget.bookingData?['completedAt'];
    final completedByStaffName = serviceData?['completedByStaffName'] ??
        widget.bookingData?['completedByStaffName'] ??
        'Staff';
    final price = serviceData?['price'] ?? widget.bookingData?['price'];

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
                                    if (widget.bookingData?['clientEmail'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.bookingData!['clientEmail'].toString(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                    if (widget.bookingData?['vehicleNumber'] != null &&
                                        widget.bookingData!['vehicleNumber'].toString().trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Vehicle: ${widget.bookingData!['vehicleNumber']}',
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
                    const SizedBox(height: 24),

                    // Download Job Report Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _downloading ? null : _downloadJobReport,
                        icon: _downloading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(FontAwesomeIcons.filePdf, size: 16),
                        label: Text(
                          _downloading ? 'Generating Report...' : 'Download Job Report',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                          disabledForegroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                          shadowColor: AppColors.primary.withOpacity(0.3),
                        ),
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
                    const Text('Completed Appointment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
                    Text('Service summary & details', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                  ],
                ),
              ),
            ],
          ),
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

