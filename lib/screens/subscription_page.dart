import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF5F5F5);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF9E9E9E);
  static const border = Color(0xFFE0E0E0);
}

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  bool _loading = true;
  
  // Subscription data
  String _planName = '';
  String _planPrice = '';
  String _subscriptionStatus = '';
  DateTime? _trialEndDate;
  int _trialDays = 0;
  DateTime? _createdAt;
  String _billingCycle = 'Monthly';

  @override
  void initState() {
    super.initState();
    _loadSubscriptionData();
  }

  Future<void> _loadSubscriptionData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!snap.exists) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final data = snap.data()!;
      
      if (mounted) {
        setState(() {
          _planName = data['plan'] ?? '';
          _planPrice = data['price'] ?? '';
          _subscriptionStatus = data['subscriptionStatus'] ?? '';
          _trialDays = data['trialDays'] ?? 0;
          _billingCycle = data['billingCycle'] ?? 'Monthly';
          
          // Parse created at date first (needed for trial calculation)
          if (data['createdAt'] != null) {
            if (data['createdAt'] is Timestamp) {
              _createdAt = (data['createdAt'] as Timestamp).toDate();
            }
          }
          
          // Parse trial end date - try multiple field names (admin panel uses 'trial_end')
          DateTime? trialEnd;
          
          // Try trial_end field (this is what admin panel uses)
          if (data['trial_end'] != null) {
            if (data['trial_end'] is Timestamp) {
              trialEnd = (data['trial_end'] as Timestamp).toDate();
            } else if (data['trial_end'] is String) {
              trialEnd = DateTime.tryParse(data['trial_end']);
            }
            debugPrint('Found trial_end field: $trialEnd');
          }
          
          // Try trialEndDate field as fallback
          if (trialEnd == null && data['trialEndDate'] != null) {
            if (data['trialEndDate'] is Timestamp) {
              trialEnd = (data['trialEndDate'] as Timestamp).toDate();
            } else if (data['trialEndDate'] is String) {
              trialEnd = DateTime.tryParse(data['trialEndDate']);
            }
            debugPrint('Found trialEndDate field: $trialEnd');
          }
          
          // If no trial end date found, calculate from createdAt + trialDays
          if (trialEnd == null && _createdAt != null && _trialDays > 0) {
            trialEnd = _createdAt!.add(Duration(days: _trialDays));
            debugPrint('Calculated trial end date: $trialEnd from createdAt: $_createdAt + $_trialDays days');
          }
          
          _trialEndDate = trialEnd;
          debugPrint('Final trial end date: $_trialEndDate, Trial days: $_trialDays, Status: $_subscriptionStatus');
          
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading subscription data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Active';
      case 'trialing':
        return 'Free Trial';
      case 'pending':
        return 'Pending Payment';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Expired';
      default:
        return status.isNotEmpty ? status : 'Unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return const Color(0xFF10B981); // Green
      case 'trialing':
        return const Color(0xFF3B82F6); // Blue
      case 'pending':
        return const Color(0xFFF59E0B); // Orange
      case 'cancelled':
      case 'expired':
        return const Color(0xFFEF4444); // Red
      default:
        return AppColors.muted;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return FontAwesomeIcons.circleCheck;
      case 'trialing':
        return FontAwesomeIcons.gift;
      case 'pending':
        return FontAwesomeIcons.clock;
      case 'cancelled':
      case 'expired':
        return FontAwesomeIcons.circleXmark;
      default:
        return FontAwesomeIcons.circleQuestion;
    }
  }

  int _getTrialDaysRemaining() {
    if (_trialEndDate == null) {
      // If no trial end date but we have trialDays and createdAt, calculate remaining
      if (_trialDays > 0 && _createdAt != null) {
        final trialEnd = _createdAt!.add(Duration(days: _trialDays));
        final now = DateTime.now();
        final diff = trialEnd.difference(now).inDays;
        return diff > 0 ? diff + 1 : 0; // +1 to include current day
      }
      return 0;
    }
    final now = DateTime.now();
    // Calculate difference in days, adding 1 to include the current day
    final diff = _trialEndDate!.difference(now).inDays;
    return diff >= 0 ? diff + 1 : 0;
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
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPlanCard(),
                          const SizedBox(height: 20),
                          _buildSubscriptionDetails(),
                          const SizedBox(height: 20),
                          if (_subscriptionStatus.toLowerCase() == 'trialing')
                            _buildTrialInfo(),
                          if (_subscriptionStatus.toLowerCase() == 'trialing')
                            const SizedBox(height: 20),
                          _buildInfoCard(),
                          const SizedBox(height: 32),
                        ],
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
          const Expanded(
            child: Center(
              child: Text(
                'My Subscription',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text),
              ),
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildPlanCard() {
    final statusColor = _getStatusColor(_subscriptionStatus);
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      FontAwesomeIcons.crown,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Plan',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _planName.isNotEmpty ? _planName : 'No Plan',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStatusIcon(_subscriptionStatus),
                      color: statusColor,
                      size: 12,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getStatusLabel(_subscriptionStatus),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPlanStat(
                  label: 'Price',
                  value: _planPrice.isNotEmpty ? _planPrice : '-',
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withOpacity(0.3),
                ),
                _buildPlanStat(
                  label: 'Billing',
                  value: _billingCycle,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withOpacity(0.3),
                ),
                _buildPlanStat(
                  label: 'Since',
                  value: _createdAt != null 
                      ? DateFormat('MMM yyyy').format(_createdAt!)
                      : '-',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanStat({required String label, required String value}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionDetails() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(
                    FontAwesomeIcons.fileInvoice,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Subscription Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildDetailRow(
            icon: FontAwesomeIcons.tag,
            label: 'Plan Name',
            value: _planName.isNotEmpty ? _planName : 'Not set',
            iconColor: const Color(0xFF8B5CF6),
          ),
          const Divider(height: 24, color: AppColors.border),
          _buildDetailRow(
            icon: FontAwesomeIcons.dollarSign,
            label: 'Price',
            value: _planPrice.isNotEmpty ? _planPrice : 'Not set',
            iconColor: const Color(0xFF10B981),
          ),
          const Divider(height: 24, color: AppColors.border),
          _buildDetailRow(
            icon: FontAwesomeIcons.calendarDays,
            label: 'Billing Cycle',
            value: _billingCycle,
            iconColor: const Color(0xFF3B82F6),
          ),
          const Divider(height: 24, color: AppColors.border),
          _buildDetailRow(
            icon: FontAwesomeIcons.circleInfo,
            label: 'Status',
            value: _getStatusLabel(_subscriptionStatus),
            valueColor: _getStatusColor(_subscriptionStatus),
            iconColor: _getStatusColor(_subscriptionStatus),
          ),
          if (_createdAt != null) ...[
            const Divider(height: 24, color: AppColors.border),
            _buildDetailRow(
              icon: FontAwesomeIcons.clockRotateLeft,
              label: 'Member Since',
              value: DateFormat('MMMM d, yyyy').format(_createdAt!),
              iconColor: const Color(0xFFF59E0B),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(icon, color: iconColor, size: 14),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrialInfo() {
    final daysRemaining = _getTrialDaysRemaining();
    final isExpiringSoon = daysRemaining <= 3 && daysRemaining > 0;
    final isExpired = daysRemaining == 0 && _trialEndDate != null && _trialEndDate!.isBefore(DateTime.now());
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isExpired 
              ? [const Color(0xFFEF4444).withOpacity(0.1), const Color(0xFFFECACA)]
              : isExpiringSoon
                  ? [const Color(0xFFF59E0B).withOpacity(0.1), const Color(0xFFFEF3C7)]
                  : [const Color(0xFF3B82F6).withOpacity(0.1), const Color(0xFFDBEAFE)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpired 
              ? const Color(0xFFEF4444).withOpacity(0.3)
              : isExpiringSoon
                  ? const Color(0xFFF59E0B).withOpacity(0.3)
                  : const Color(0xFF3B82F6).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isExpired 
                      ? const Color(0xFFEF4444)
                      : isExpiringSoon
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isExpired 
                      ? FontAwesomeIcons.triangleExclamation
                      : FontAwesomeIcons.gift,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isExpired 
                          ? 'Trial Expired'
                          : 'Free Trial',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isExpired 
                            ? const Color(0xFFEF4444)
                            : isExpiringSoon
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF3B82F6),
                      ),
                    ),
                    Text(
                      isExpired 
                          ? 'Please subscribe to continue'
                          : '$daysRemaining days remaining',
                      style: TextStyle(
                        fontSize: 13,
                        color: isExpired 
                            ? const Color(0xFFEF4444).withOpacity(0.8)
                            : isExpiringSoon
                                ? const Color(0xFFF59E0B).withOpacity(0.8)
                                : const Color(0xFF3B82F6).withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_trialEndDate != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    FontAwesomeIcons.calendarCheck,
                    size: 14,
                    color: isExpired 
                        ? const Color(0xFFEF4444)
                        : isExpiringSoon
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF3B82F6),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isExpired 
                        ? 'Trial ended on ${DateFormat('MMMM d, yyyy').format(_trialEndDate!)}'
                        : 'Trial ends on ${DateFormat('MMMM d, yyyy').format(_trialEndDate!)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(
                    FontAwesomeIcons.lightbulb,
                    color: Color(0xFFF59E0B),
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Need Help?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'If you need to change your subscription plan or have any billing questions, please contact our support team. We\'re here to help!',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.muted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  FontAwesomeIcons.envelope,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'support@bmsproblack.com',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Contact',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
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
