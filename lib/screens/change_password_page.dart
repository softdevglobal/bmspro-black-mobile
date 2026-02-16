import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../routes.dart';
import '../services/audit_log_service.dart';

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
  static const red = Color(0xFFEF4444);
  static const yellow = Color(0xFFF59E0B);
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage>
    with TickerProviderStateMixin {
  final TextEditingController _currentPassController = TextEditingController();
  final TextEditingController _newPassController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isUpdating = false;

  bool _hasLength = false;
  bool _hasUpper = false;
  bool _hasLower = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;
  bool _passwordsMatch = false;

  late AnimationController _entranceController;
  late AnimationController _ledBorderController;
  late AnimationController _lockPulseController;

  final List<Animation<Offset>> _slideAnimations = [];
  final List<Animation<double>> _fadeAnimations = [];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    for (int i = 0; i < 4; i++) {
      final double start = 0.1 + (i * 0.1);
      final double end = start + 0.4;
      _slideAnimations.add(Tween<Offset>(begin: const Offset(-0.1, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: _entranceController, curve: Interval(start, end, curve: Curves.easeOut)),
      ));
      _fadeAnimations.add(Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _entranceController, curve: Interval(start, end, curve: Curves.easeOut)),
      ));
    }
    _ledBorderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _lockPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _entranceController.forward();
  }

  @override
  void dispose() {
    _currentPassController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    _entranceController.dispose();
    _ledBorderController.dispose();
    _lockPulseController.dispose();
    super.dispose();
  }

  void _validatePassword(String value) {
    setState(() {
      _hasLength = value.length >= 8;
      _hasUpper = value.contains(RegExp(r'[A-Z]'));
      _hasLower = value.contains(RegExp(r'[a-z]'));
      _hasNumber = value.contains(RegExp(r'[0-9]'));
      _hasSpecial = value.contains(RegExp(r'[!@#$%^&*]'));
      _checkMatch(_confirmPassController.text);
    });
  }

  void _checkMatch(String value) {
    setState(() {
      _passwordsMatch = value.isNotEmpty && value == _newPassController.text;
    });
  }

  bool get _isFormValid {
    return _hasLength &&
        _hasUpper &&
        _hasLower &&
        _hasNumber &&
        _hasSpecial &&
        _passwordsMatch &&
        _currentPassController.text.isNotEmpty;
  }

  int get _strengthScore {
    int score = 0;
    if (_hasLength) score++;
    if (_hasUpper) score++;
    if (_hasLower) score++;
    if (_hasNumber) score++;
    if (_hasSpecial) score++;
    return score;
  }

  Color get _strengthColor {
    if (_strengthScore <= 2) return AppColors.red;
    if (_strengthScore <= 4) return AppColors.yellow;
    return AppColors.green;
  }

  String get _strengthText {
    if (_newPassController.text.isEmpty) return '';
    if (_strengthScore <= 2) return 'Weak';
    if (_strengthScore <= 4) return 'Medium';
    return 'Strong';
  }

  Future<void> _handleUpdate() async {
    if (!_isFormValid || _isUpdating) return;

    final currentPassword = _currentPassController.text.trim();
    final newPassword = _newPassController.text.trim();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No authenticated user. Please log in again.')),
        );
      }
      return;
    }

    // Basic guard: avoid updating to the same password
    if (currentPassword == newPassword) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New password must be different from current password.')),
        );
      }
      return;
    }

    setState(() => _isUpdating = true);

    try {
      // 1. Re-authenticate with current password
      final email = user.email;
      if (email == null || email.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-email',
          message: 'Unable to verify user email for password change.',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // 2. Update password
      await user.updatePassword(newPassword);

      // 3. Log password change to audit log
      try {
        // Get user document to find ownerUid, name, and role
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          String ownerUid = user.uid;
          final role = (userData['role'] ?? '').toString();
          
          // Determine ownerUid based on role
          if (role == 'workshop_owner') {
            ownerUid = user.uid;
          } else if (userData['ownerUid'] != null && userData['ownerUid'].toString().isNotEmpty) {
            ownerUid = userData['ownerUid'].toString();
          }

          final userName = (userData['displayName'] ?? userData['name'] ?? email ?? 'User').toString();
          
          // Create audit log entry
          await AuditLogService.logPasswordChanged(
            ownerUid: ownerUid,
            userId: user.uid,
            userName: userName,
            performedByRole: role.isNotEmpty ? role : null,
          );
        }
      } catch (auditError) {
        // Don't fail password change if audit log fails
        debugPrint('Failed to create password change audit log: $auditError');
      }

      if (!mounted) return;
      setState(() => _isUpdating = false);
      _showSuccessModal();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);

      String message = 'Failed to update password.';
      if (e.code == 'wrong-password') {
        message = 'The current password you entered is incorrect.';
      } else if (e.code == 'weak-password') {
        message = 'The new password is too weak. Please choose a stronger password.';
      } else if (e.code == 'requires-recent-login') {
        message = 'Please log in again and then try changing your password.';
      } else if (e.code == 'missing-email') {
        message = e.message ?? message;
      } else if (e.message != null && e.message!.isNotEmpty) {
        message = e.message!;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    }
  }

  void _showSuccessModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SuccessModal(),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildHeroSection(),
                    const SizedBox(height: 24),
                    _buildFormSection(),
                    const SizedBox(height: 24),
                    _buildRequirementsSection(),
                    const SizedBox(height: 24),
                    _buildUpdateButton(),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(color: AppColors.background),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              FontAwesomeIcons.chevronLeft,
              size: 18,
              color: AppColors.text,
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Change Password',
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

  Widget _buildHeroSection() {
    return AnimatedBuilder(
      animation: _ledBorderController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: SweepGradient(
              transform: GradientRotation(_ledBorderController.value * 2 * math.pi),
              colors: const [
                AppColors.primary,
                AppColors.accent,
                Colors.amber,
                AppColors.accent,
                AppColors.primary,
              ],
            ),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withOpacity(0.1),
                  AppColors.accent.withOpacity(0.05),
                ],
              ),
              color: Colors.white.withOpacity(0.9),
            ),
            child: Column(
              children: [
                ScaleTransition(
                  scale: Tween<double>(begin: 1.0, end: 1.1).animate(
                    CurvedAnimation(parent: _lockPulseController, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary,
                          blurRadius: 20,
                          spreadRadius: -5,
                          offset: Offset(0, 10),
                        )
                      ],
                    ),
                    child: const Center(
                      child: Icon(FontAwesomeIcons.shieldHalved, color: Colors.white, size: 32),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Secure Your Account',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create a strong password to protect your data',
                  style: TextStyle(fontSize: 14, color: AppColors.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildAnimatedField(
            0,
            label: 'Current Password',
            controller: _currentPassController,
            obscure: _obscureCurrent,
            onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
          ),
          const SizedBox(height: 20),
          _buildAnimatedField(
            1,
            label: 'New Password',
            controller: _newPassController,
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
            onChanged: _validatePassword,
          ),
          if (_newPassController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildStrengthIndicator(),
          ],
          const SizedBox(height: 20),
          _buildAnimatedField(
            2,
            label: 'Confirm New Password',
            controller: _confirmPassController,
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            onChanged: _checkMatch,
          ),
          if (_confirmPassController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildMatchIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimatedField(
    int index, {
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    Function(String)? onChanged,
  }) {
    return FadeTransition(
      opacity: _fadeAnimations[index],
      child: SlideTransition(
        position: _slideAnimations[index],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              obscureText: obscure,
              onChanged: onChanged,
              style: const TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Enter $label',
                hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscure ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  onPressed: onToggle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrengthIndicator() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Password Strength', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            Text(_strengthText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _strengthColor)),
          ],
        ),
        const SizedBox(height: 4),
        Stack(
          children: [
            Container(
              height: 4,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2)),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              width: MediaQuery.of(context).size.width * (_strengthScore / 5) * 0.8,
              decoration: BoxDecoration(color: _strengthColor, borderRadius: BorderRadius.circular(2)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMatchIndicator() {
    return Row(
      children: [
        Icon(
          _passwordsMatch ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circleXmark,
          size: 14,
          color: _passwordsMatch ? AppColors.green : AppColors.red,
        ),
        const SizedBox(width: 6),
        Text(
          _passwordsMatch ? 'Passwords match' : 'Passwords do not match',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _passwordsMatch ? AppColors.green : AppColors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildRequirementsSection() {
    return FadeTransition(
      opacity: _fadeAnimations[3],
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.purple.shade50],
          ),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(FontAwesomeIcons.circleInfo, color: AppColors.primary, size: 16),
                SizedBox(width: 8),
                Text('Password Requirements', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text)),
              ],
            ),
            const SizedBox(height: 12),
            _buildRequirementItem('At least 8 characters', _hasLength),
            _buildRequirementItem('One uppercase letter', _hasUpper),
            _buildRequirementItem('One lowercase letter', _hasLower),
            _buildRequirementItem('One number', _hasNumber),
            _buildRequirementItem('One special character (!@#\$%^&*)', _hasSpecial),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirementItem(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            met ? FontAwesomeIcons.solidCircleCheck : FontAwesomeIcons.circle,
            size: 12,
            color: met ? AppColors.green : Colors.grey.shade300,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: met ? AppColors.green : AppColors.muted,
              fontWeight: met ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: _isFormValid
            ? const LinearGradient(colors: [AppColors.primary, AppColors.accent])
            : null,
        color: _isFormValid ? null : Colors.grey.shade300,
        boxShadow: _isFormValid
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                )
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isFormValid && !_isUpdating ? _handleUpdate : null,
          borderRadius: BorderRadius.circular(30),
          child: Center(
            child: _isUpdating
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Updating...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        FontAwesomeIcons.lock,
                        color: _isFormValid ? Colors.white : Colors.grey.shade500,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Update Password',
                        style: TextStyle(
                          color: _isFormValid ? Colors.white : Colors.grey.shade500,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class SuccessModal extends StatelessWidget {
  const SuccessModal({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 10)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF4ADE80), Color(0xFF16A34A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(child: Icon(FontAwesomeIcons.check, color: Colors.white, size: 32)),
                  ),
                  const Text('Password Updated!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.text)),
                  const SizedBox(height: 8),
                  const Text(
                    'Your password has been changed successfully. You will be logged out for security.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            AppRoutes.login,
                            (route) => false,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: const Text('Got it', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


