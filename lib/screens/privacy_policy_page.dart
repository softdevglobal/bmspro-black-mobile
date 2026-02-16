import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AppColors {
  static const primary = Color(0xFFFF2D8F);
  static const primaryDark = Color(0xFFD81F75);
  static const accent = Color(0xFFFF6FB5);
  static const background = Color(0xFFFFF5FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF9E9E9E);
  static const border = Color(0xFFF2D2E9);
}

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _openPrivacyURL();
  }

  Future<void> _openPrivacyURL() async {
    setState(() => _isLoading = true);
    final Uri url = Uri.parse('https://bmspros.com.au/privacy');
    
    try {
      // Try launching directly with external application mode first
      bool launched = false;
      try {
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('External application mode failed, trying platform default: $e');
        // If external application fails, try platform default
        try {
          launched = await launchUrl(url, mode: LaunchMode.platformDefault);
        } catch (e2) {
          debugPrint('Platform default mode also failed: $e2');
        }
      }
      
      if (launched && mounted) {
        // Navigate back after a short delay to allow browser to open
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        // If launch failed, show error and allow retry
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to open Privacy Policy. Please tap "Open Link" to try again.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error opening Privacy Policy: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Opening Privacy Policy...',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      FontAwesomeIcons.globe,
                      size: 64,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Privacy Policy',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Unable to open link automatically. Tap below to open in your browser.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    InkWell(
                      onTap: _openPrivacyURL,
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(FontAwesomeIcons.globe, size: 16, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Open Link',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Go Back',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
