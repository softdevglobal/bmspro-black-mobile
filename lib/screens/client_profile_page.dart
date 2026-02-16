import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'clients_screen.dart';

// --- 1. Theme & Colors (Matching HTML/Tailwind) ---
class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF5F5F5);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF9E9E9E);
  static const border = Color(0xFFE0E0E0);
  static const green = Color(0xFF10B981);
  static const yellow = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const redLight = Color(0xFFFEE2E2);
  static const blueLight = Color(0xFFF0F9FF);
  static const greenLight = Color(0xFFF0FDF4);
}

class ClientProfilePage extends StatefulWidget {
  final Client client;

  const ClientProfilePage({super.key, required this.client});

  @override
  State<ClientProfilePage> createState() => _ClientProfilePageState();
}

class _ClientProfilePageState extends State<ClientProfilePage> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  final List<Animation<double>> _fadeAnimations = [];

  // Booking history
  bool _loadingHistory = false;
  List<_ClientBooking> _history = [];

  @override
  void initState() {
    super.initState();
    // 1. Fade-in Staggered Animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
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
    // 2. Allergy Alert Pulse Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _loadHistory();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      setState(() {
        _loadingHistory = true;
      });
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loadingHistory = false;
          _history = [];
        });
        return;
      }
      final client = widget.client;
      final db = FirebaseFirestore.instance;
      final ownerUid = user.uid;

      // Load all bookings for this owner and filter client matches in memory
      final qs = await db
          .collection('bookings')
          .where('ownerUid', isEqualTo: ownerUid)
          .get();

      final List<_ClientBooking> list = [];

      for (final doc in qs.docs) {
        final data = doc.data();

        final name = (data['client'] ?? '').toString().trim();
        final email = (data['clientEmail'] ?? '').toString().trim();
        final phone = (data['clientPhone'] ?? '').toString().trim();

        final bool matchesEmail =
            client.email.isNotEmpty && email.isNotEmpty && email == client.email;
        final bool matchesPhone =
            client.phone.isNotEmpty && phone.isNotEmpty && phone == client.phone;
        final bool matchesName =
            !matchesEmail &&
            !matchesPhone &&
            client.name.isNotEmpty &&
            name.isNotEmpty &&
            name.toLowerCase() == client.name.toLowerCase();

        if (!matchesEmail && !matchesPhone && !matchesName) continue;

        final id = doc.id;

        final serviceNameRaw = (data['serviceName'] ?? '').toString();
        String serviceName = serviceNameRaw;
        if (serviceName.isEmpty && data['services'] is List) {
          final listServices = data['services'] as List;
          if (listServices.isNotEmpty && listServices.first is Map) {
            serviceName =
                ((listServices.first as Map)['name'] ?? 'Service').toString();
          }
        }
        if (serviceName.isEmpty) serviceName = 'Service';

        final staffNameRaw = (data['staffName'] ?? '').toString();
        String staffName = staffNameRaw;
        if (staffName.isEmpty && data['services'] is List) {
          final listServices = data['services'] as List;
          if (listServices.isNotEmpty && listServices.first is Map) {
            staffName = ((listServices.first as Map)['staffName'] ?? '').toString();
          }
        }

        final date = (data['date'] ?? '').toString();
        final time = (data['time'] ?? '').toString();
        String dateTimeLabel = date;
        DateTime? sortDate;
        try {
          if (date.isNotEmpty) {
            sortDate = DateTime.parse(date);
          }
        } catch (_) {}
        if (date.isNotEmpty && time.isNotEmpty) {
          dateTimeLabel = '$date at $time';
        }

        final durationMinutes = data['duration'];
        String durationLabel = '';
        if (durationMinutes is num && durationMinutes > 0) {
          durationLabel = '${durationMinutes.toInt()} min';
        }

        final rawPrice = data['price'];
        double priceValue = 0;
        if (rawPrice is num) {
          priceValue = rawPrice.toDouble();
        } else if (rawPrice != null) {
          priceValue = double.tryParse(rawPrice.toString()) ?? 0;
        }
        final priceLabel =
            priceValue > 0 ? '\$${priceValue.toStringAsFixed(0)}' : '\$0';

        String status =
            (data['status'] ?? 'pending').toString().toLowerCase();
        if (status == 'canceled') status = 'cancelled';

        list.add(
          _ClientBooking(
            id: id,
            serviceName: serviceName,
            staffName: staffName.isNotEmpty ? staffName : 'Any staff',
            dateTimeLabel: dateTimeLabel,
            sortDate: sortDate,
            durationLabel: durationLabel,
            statusLabel: status,
            priceLabel: priceLabel,
          ),
        );
      }

      list
        ..sort((a, b) {
          final ad = a.sortDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.sortDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        });

      if (!mounted) return;
      setState(() {
        _history = list;
        _loadingHistory = false;
      });
    } catch (e) {
      debugPrint('Error loading client history: $e');
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _history = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;

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
                    _buildFadeWrapper(0, _buildClientHeaderCard()),
                    const SizedBox(height: 24),
                    _buildFadeWrapper(1, _buildAllergyAlert()),
                    const SizedBox(height: 24),
                    _buildFadeWrapper(2, _buildFormulasSection()),
                    const SizedBox(height: 24),
                    _buildFadeWrapper(3, _buildHistorySection()),
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

  // --- Animation Helper ---
  Widget _buildFadeWrapper(int index, Widget child) {
    return FadeTransition(
      opacity: _fadeAnimations[index],
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(_fadeAnimations[index]),
        child: child,
      ),
    );
  }

  // --- Header ---
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
                'Client Profile',
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

  // --- Client Header Card ---
  Widget _buildClientHeaderCard() {
    final client = widget.client;

    final name = client.name;
    final phone = client.phone.isNotEmpty ? client.phone : 'Not provided';
    final email = client.email.isNotEmpty ? client.email : 'Not provided';
    final initials = _getInitials(name);

    String statusLabel = 'Active Client';
    Color statusColor = AppColors.green;
    if (client.type == 'new') {
      statusLabel = 'New Client';
      statusColor = const Color(0xFF0EA5E9);
    } else if (client.type == 'vip') {
      statusLabel = 'VIP Client';
      statusColor = const Color(0xFFF59E0B);
    } else if (client.type == 'risk') {
      statusLabel = 'At Risk';
      statusColor = AppColors.red;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80, 
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: AppColors.primary.withOpacity(0.15),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
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
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _iconTextRow(FontAwesomeIcons.phone, phone),
                    const SizedBox(height: 2),
                    _iconTextRow(FontAwesomeIcons.envelope, email),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _GradientButton(
                  text: 'Book Appointment',
                  icon: FontAwesomeIcons.calendarPlus,
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 12),
              _SecondaryButton(icon: FontAwesomeIcons.penToSquare, onPressed: () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconTextRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }

  // --- Allergy Alert ---
  Widget _buildAllergyAlert() {
    final client = widget.client;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.redLight, Color(0xFFFECACA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color.lerp(AppColors.red, const Color(0xFFDC2626), _pulseController.value)!,
              width: 2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(FontAwesomeIcons.triangleExclamation, color: Color(0xFFDC2626), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Client Alerts & Notes',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF991B1B),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No specific allergies or warnings have been recorded for ${client.name}. '
                      'Use customer notes in the admin panel to capture important info like sensitivities or preferences.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB91C1C),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Formulas Section ---
  Widget _buildFormulasSection() {
    final client = widget.client;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notes & Preferences',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.blueLight, Color(0xFFE0F2FE)]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Client Notes',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(8)),
                      child: const Text(
                        'Overview',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  client.visits > 0
                      ? 'This client has visited ${client.visits} time${client.visits == 1 ? '' : 's'}. '
                        'Use your admin panel to record detailed formulas or service notes for future reference.'
                      : 'No visits recorded yet. Once this client has completed services, you can record formulas and notes here.',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.greenLight, Color(0xFFDCFCE7)]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.green.withOpacity(0.3)),
            ),
            child: const Text(
              'No specific service preferences have been saved yet. '
              'You can capture things like preferred pressure, temperature, or style notes in the dashboard.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- History Section ---
  Widget _buildHistorySection() {
    final client = widget.client;

    String visitsLabel = '${client.visits} booking${client.visits == 1 ? '' : 's'}';
    String lastVisitLabel = 'Never';
    if (client.lastVisit != null) {
      final d = client.lastVisit!;
      lastVisitLabel = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appointment History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Bookings',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      visitsLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Last Visit',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lastVisitLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingHistory)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            )
          else if (_history.isEmpty)
            const Text(
              'No previous bookings found for this client.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                height: 1.5,
              ),
            )
          else
            Column(
              children: _history
                  .map(
                    (h) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildHistoryItem(h),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(_ClientBooking booking) {
    final statusColor = () {
      switch (booking.statusLabel) {
        case 'confirmed':
          return const Color(0xFF16A34A);
        case 'completed':
          return const Color(0xFF1D4ED8);
        case 'cancelled':
          return const Color(0xFFB91C1C);
        default:
          return const Color(0xFF92400E);
      }
    }();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                booking.serviceName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  booking.statusLabel[0].toUpperCase() +
                      booking.statusLabel.substring(1),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            booking.dateTimeLabel,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'With ${booking.staffName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                ),
              ),
              if (booking.durationLabel.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  booking.durationLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            booking.priceLabel,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required String title, required String date, required String staff,
    required String duration, required String notes, String? products,
    bool hasPhotos = false, bool isLast = false
  }) {
    return Padding(
      padding: EdgeInsets.only(left: 24, bottom: isLast ? 0 : 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -30, top: 0,
            child: Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 4)],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                    Text(date, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Done by: $staff', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    const SizedBox(width: 16),
                    Text('Duration: $duration', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Notes: $notes', style: const TextStyle(fontSize: 12, color: AppColors.text)),
                if (products != null) ...[
                  const SizedBox(height: 4),
                  Text('Products used: $products', style: const TextStyle(fontSize: 12, color: AppColors.text)),
                ],
                if (hasPhotos) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                          child: const Center(child: Text('Before', style: TextStyle(fontSize: 10, color: AppColors.muted))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                          child: const Center(child: Text('After', style: TextStyle(fontSize: 10, color: AppColors.muted))),
                        ),
                      ),
                    ],
                  )
                ]
              ],
            ),
          )
        ],
      ),
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

class _ClientBooking {
  final String id;
  final String serviceName;
  final String staffName;
  final String dateTimeLabel;
  final DateTime? sortDate;
  final String durationLabel;
  final String statusLabel;
  final String priceLabel;

  _ClientBooking({
    required this.id,
    required this.serviceName,
    required this.staffName,
    required this.dateTimeLabel,
    required this.sortDate,
    required this.durationLabel,
    required this.statusLabel,
    required this.priceLabel,
  });
}

// --- Helper: Back Chevron to match other pages ---
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

// --- Helper Buttons ---
class _GradientButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onPressed;
  const _GradientButton({required this.text, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _SecondaryButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Icon(FontAwesomeIcons.penToSquare, color: AppColors.primary, size: 16),
          ),
        ),
      ),
    );
  }
}


