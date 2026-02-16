import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}

class ForgotPasswordRequestPage extends StatefulWidget {
  const ForgotPasswordRequestPage({super.key});
  @override
  State<ForgotPasswordRequestPage> createState() => _ForgotPasswordRequestPageState();
}

class _ForgotPasswordRequestPageState extends State<ForgotPasswordRequestPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _sending = false;
  String? _error;

  static const String _apiBaseUrl = 'https://black.bmspros.com.au';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Email is required');
      return;
    }

    // Basic email validation
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/auth/forgot-password'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email.toLowerCase(),
        }),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      if (!mounted) return;

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        setState(() => _sending = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _ForgotPasswordCodePage(email: email),
          ),
        );
      } else {
        setState(() {
          _sending = false;
          _error = result['error']?.toString() ?? 'Failed to send code. Please try again.';
        });
      }
    } catch (e) {
      debugPrint('Error sending reset code: $e');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Network error. Please check your connection and try again.';
      });
    }
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
                child: Container(
                  padding: const EdgeInsets.all(20),
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Reset your password',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter the email associated with your account and we’ll send a 6‑digit code to reset your password.',
                        style: TextStyle(color: AppColors.muted, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                          errorText: _error,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _sending ? null : _sendCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: _sending
                                  ? const SizedBox(
                                      width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('Send Code',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
        children: const [
          _BackChevron(),
          Expanded(
            child: Center(
              child: Text(
                'Forgot Password',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
            ),
          ),
          SizedBox(width: 24),
        ],
      ),
    );
  }
}

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

class _ForgotPasswordCodePage extends StatefulWidget {
  final String email;
  const _ForgotPasswordCodePage({required this.email});
  @override
  State<_ForgotPasswordCodePage> createState() => _ForgotPasswordCodePageState();
}

class _ForgotPasswordCodePageState extends State<_ForgotPasswordCodePage> {
  final TextEditingController _codeController = TextEditingController();
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  static const String _apiBaseUrl = 'https://black.bmspros.com.au';

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final String code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Code must contain only digits');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/auth/verify-reset-code'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': widget.email.toLowerCase(),
          'code': code,
        }),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      if (!mounted) return;

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        setState(() => _verifying = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _ForgotPasswordResetPage(email: widget.email, code: code),
          ),
        );
      } else {
        setState(() {
          _verifying = false;
          _error = result['error']?.toString() ?? 'Invalid or expired code. Please try again.';
        });
      }
    } catch (e) {
      debugPrint('Error verifying code: $e');
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = 'Network error. Please check your connection and try again.';
      });
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _resending = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/auth/forgot-password'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': widget.email.toLowerCase(),
        }),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      if (!mounted) return;

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code resent successfully. Please check your email.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error']?.toString() ?? 'Failed to resend code. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error resending code: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Network error. Please check your connection and try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: const BoxDecoration(color: AppColors.background),
              child: Row(
                children: const [
                  _BackChevron(),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Enter Code',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
                      ),
                    ),
                  ),
                  SizedBox(width: 24),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'We sent a code to ${widget.email}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _codeController,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          counterText: '',
                          labelText: '6‑digit code',
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                          errorText: _error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _resending ? null : _resendCode,
                            child: _resending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Resend Code'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _verifying ? null : _verify,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: _verifying
                                  ? const SizedBox(
                                      width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('Verify',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForgotPasswordResetPage extends StatefulWidget {
  final String email;
  final String code;
  const _ForgotPasswordResetPage({required this.email, required this.code});
  @override
  State<_ForgotPasswordResetPage> createState() => _ForgotPasswordResetPageState();
}

class _ForgotPasswordResetPageState extends State<_ForgotPasswordResetPage> {
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _saving = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;

  // Password validation flags
  bool _hasLength = false;
  bool _hasUpper = false;
  bool _hasLower = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;

  static const String _apiBaseUrl = 'https://black.bmspros.com.au';

  @override
  void initState() {
    super.initState();
    _passController.addListener(_validatePassword);
  }

  @override
  void dispose() {
    _passController.removeListener(_validatePassword);
    _passController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _validatePassword() {
    final password = _passController.text;
    setState(() {
      _hasLength = password.length >= 8;
      _hasUpper = RegExp(r'[A-Z]').hasMatch(password);
      _hasLower = RegExp(r'[a-z]').hasMatch(password);
      _hasNumber = RegExp(r'[0-9]').hasMatch(password);
      _hasSpecial = RegExp(r'[!@#$%^&*()_+\-=\[\]{};:"\\|,.<>/?]').hasMatch(password);
    });
  }

  List<String> _getPasswordErrors() {
    final errors = <String>[];
    if (!_hasLength) errors.add('At least 8 characters');
    if (!_hasUpper) errors.add('One uppercase letter');
    if (!_hasLower) errors.add('One lowercase letter');
    if (!_hasNumber) errors.add('One number');
    if (!_hasSpecial) errors.add('One special character');
    return errors;
  }

  Future<void> _reset() async {
    final p1 = _passController.text;
    final p2 = _confirmController.text;

    if (p1.isEmpty || p2.isEmpty) {
      setState(() => _error = 'Please fill in all password fields');
      return;
    }

    final passwordErrors = _getPasswordErrors();
    if (passwordErrors.isNotEmpty) {
      setState(() => _error = 'Password must contain: ${passwordErrors.join(", ")}');
      return;
    }

    if (p1 != p2) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/auth/reset-password'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': widget.email.toLowerCase(),
          'code': widget.code,
          'newPassword': p1,
        }),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          return http.Response('{"error": "Request timeout"}', 408);
        },
      );

      if (!mounted) return;

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset successfully! You can now sign in.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        setState(() {
          _saving = false;
          _error = result['error']?.toString() ?? 'Failed to reset password. Please try again.';
        });
      }
    } catch (e) {
      debugPrint('Error resetting password: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Network error. Please check your connection and try again.';
      });
    }
  }

  Widget _buildPasswordRequirements() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password requirements:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text),
          ),
          const SizedBox(height: 8),
          _buildRequirementItem('At least 8 characters', _hasLength),
          _buildRequirementItem('One uppercase letter', _hasUpper),
          _buildRequirementItem('One lowercase letter', _hasLower),
          _buildRequirementItem('One number', _hasNumber),
          _buildRequirementItem('One special character', _hasSpecial),
        ],
      ),
    );
  }

  Widget _buildRequirementItem(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isValid ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circle,
            size: 12,
            color: isValid ? Colors.green : AppColors.muted,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: isValid ? Colors.green : AppColors.muted,
            ),
          ),
        ],
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: const BoxDecoration(color: AppColors.background),
              child: Row(
                children: const [
                  _BackChevron(),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Create New Password',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
                      ),
                    ),
                  ),
                  SizedBox(width: 24),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Create a strong password with at least 8 characters, including uppercase, lowercase, numbers, and special characters.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passController,
                        obscureText: _obscure1,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _passController.text.isNotEmpty && _getPasswordErrors().isEmpty
                                  ? Colors.green
                                  : _passController.text.isNotEmpty && _getPasswordErrors().isNotEmpty
                                      ? Colors.red
                                      : AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _passController.text.isNotEmpty && _getPasswordErrors().isEmpty
                                  ? Colors.green
                                  : _passController.text.isNotEmpty && _getPasswordErrors().isNotEmpty
                                      ? Colors.red
                                      : AppColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscure1 = !_obscure1),
                            icon: Icon(_obscure1 ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash, size: 16, color: AppColors.muted),
                          ),
                          errorText: _error,
                        ),
                      ),
                      if (_passController.text.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildPasswordRequirements(),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmController,
                        obscureText: _obscure2,
                        onChanged: (_) {
                          if (_error != null && _error!.contains('match')) {
                            setState(() => _error = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _confirmController.text.isNotEmpty &&
                                      _passController.text.isNotEmpty &&
                                      _confirmController.text == _passController.text &&
                                      _getPasswordErrors().isEmpty
                                  ? Colors.green
                                  : _confirmController.text.isNotEmpty &&
                                          _passController.text.isNotEmpty &&
                                          _confirmController.text != _passController.text
                                      ? Colors.red
                                      : AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _confirmController.text.isNotEmpty &&
                                      _passController.text.isNotEmpty &&
                                      _confirmController.text == _passController.text &&
                                      _getPasswordErrors().isEmpty
                                  ? Colors.green
                                  : _confirmController.text.isNotEmpty &&
                                          _passController.text.isNotEmpty &&
                                          _confirmController.text != _passController.text
                                      ? Colors.red
                                      : AppColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscure2 = !_obscure2),
                            icon: Icon(_obscure2 ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash, size: 16, color: AppColors.muted),
                          ),
                        ),
                      ),
                      if (_confirmController.text.isNotEmpty &&
                          _passController.text.isNotEmpty &&
                          _confirmController.text != _passController.text)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Passwords do not match',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      if (_confirmController.text.isNotEmpty &&
                          _passController.text.isNotEmpty &&
                          _confirmController.text == _passController.text &&
                          _getPasswordErrors().isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              Icon(FontAwesomeIcons.circleCheck, size: 12, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                'Passwords match',
                                style: TextStyle(color: Colors.green, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_saving ||
                                  _getPasswordErrors().isNotEmpty ||
                                  _passController.text.isEmpty ||
                                  _confirmController.text.isEmpty ||
                                  _passController.text != _confirmController.text)
                              ? null
                              : _reset,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: (_saving ||
                                      _getPasswordErrors().isNotEmpty ||
                                      _passController.text.isEmpty ||
                                      _confirmController.text.isEmpty ||
                                      _passController.text != _confirmController.text)
                                  ? null
                                  : const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                              color: (_saving ||
                                      _getPasswordErrors().isNotEmpty ||
                                      _passController.text.isEmpty ||
                                      _confirmController.text.isEmpty ||
                                      _passController.text != _confirmController.text)
                                  ? Colors.grey.shade300
                                  : null,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: _saving
                                  ? const SizedBox(
                                      width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('Update Password',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


