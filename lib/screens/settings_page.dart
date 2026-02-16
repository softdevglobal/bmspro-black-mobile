import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'change_password_page.dart';
import '../utils/timezone_helper.dart';

class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool notifications = true;
  bool reminderEnabled = true;
  int reminderMinutes = 15;
  bool soundEffects = true;
  bool haptics = true;
  bool darkMode = false;
  bool dataSaver = false;
  bool autoUpdate = true;
  bool twoFactor = false;
  String language = 'English';
  String _selectedTimezone = 'Australia/Sydney';
  bool _isLoadingTimezone = true;

  @override
  void initState() {
    super.initState();
    _loadUserTimezone();
  }

  Future<void> _loadUserTimezone() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = doc.data();
        if (data != null && data['timezone'] != null) {
          setState(() {
            _selectedTimezone = data['timezone'] as String;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading timezone: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingTimezone = false);
      }
    }
  }

  Future<void> _saveTimezone(String timezone) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'timezone': timezone});
        setState(() => _selectedTimezone = timezone);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Timezone updated to ${TimezoneHelper.getTimezoneLabel(timezone)}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving timezone: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save timezone'),
            duration: Duration(seconds: 2),
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
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('Preferences'),
                    _SettingSwitch(
                      icon: FontAwesomeIcons.bell,
                      title: 'Push Notifications',
                      subtitle: 'Receive task and system alerts',
                      value: notifications,
                      onChanged: (v) => setState(() => notifications = v),
                    ),
                    _SettingSwitch(
                      icon: FontAwesomeIcons.volumeHigh,
                      title: 'Sound Effects',
                      subtitle: 'Play sounds for interactions',
                      value: soundEffects,
                      onChanged: (v) => setState(() => soundEffects = v),
                    ),
                    _SettingSwitch(
                      icon: FontAwesomeIcons.mobileScreen,
                      title: 'Haptic Feedback',
                      subtitle: 'Vibrate on key actions',
                      value: haptics,
                      onChanged: (v) => setState(() => haptics = v),
                    ),
                    _SettingSwitch(
                      icon: FontAwesomeIcons.moon,
                      title: 'Dark Mode',
                      subtitle: 'Use a darker color theme',
                      value: darkMode,
                      onChanged: (v) => setState(() => darkMode = v),
                    ),
                    const SizedBox(height: 16),
                    _ReminderCard(
                      enabled: reminderEnabled,
                      minutes: reminderMinutes,
                      onEnabledChanged: (v) =>
                          setState(() => reminderEnabled = v),
                      onMinutesChanged: (v) =>
                          setState(() => reminderMinutes = v),
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle('App'),
                    _SettingNavRow(
                      icon: FontAwesomeIcons.language,
                      title: 'Language',
                      trailingText: language,
                      onTap: () async {
                        final String? selected = await showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (_) => _LanguageSheet(current: language),
                        );
                        if (selected != null) {
                          setState(() => language = selected);
                        }
                      },
                    ),
                    _SettingNavRow(
                      icon: FontAwesomeIcons.clock,
                      title: 'Time Zone',
                      trailingText: _isLoadingTimezone 
                          ? 'Loading...' 
                          : _selectedTimezone.split('/').last.replaceAll('_', ' '),
                      onTap: () async {
                        final String? selected = await showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => _TimezoneSheet(current: _selectedTimezone),
                        );
                        if (selected != null && selected != _selectedTimezone) {
                          _saveTimezone(selected);
                        }
                      },
                    ),
                    _SettingSwitch(
                      icon: FontAwesomeIcons.gaugeSimpleHigh,
                      title: 'Data Saver',
                      subtitle: 'Reduce network usage',
                      value: dataSaver,
                      onChanged: (v) => setState(() => dataSaver = v),
                    ),
                    _SettingSwitch(
                      icon: FontAwesomeIcons.rotate,
                      title: 'Auto Update',
                      subtitle: 'Update app assets automatically',
                      value: autoUpdate,
                      onChanged: (v) => setState(() => autoUpdate = v),
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle('Security'),
                    _SettingNavRow(
                      icon: FontAwesomeIcons.lock,
                      title: 'Change Password',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ChangePasswordPage()),
                        );
                      },
                    ),
                    _SettingSwitch(
                      icon: FontAwesomeIcons.shieldHalved,
                      title: 'Two‑factor Authentication',
                      subtitle: 'Add extra security to your account',
                      value: twoFactor,
                      onChanged: (v) => setState(() => twoFactor = v),
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle('About'),
                    _SettingNavRow(
                      icon: FontAwesomeIcons.fileLines,
                      title: 'Terms of Service',
                      onTap: () {},
                    ),
                    _SettingNavRow(
                      icon: FontAwesomeIcons.userShield,
                      title: 'Privacy Policy',
                      onTap: () {},
                    ),
                    _AppVersion(),
                    const SizedBox(height: 24),
                    _DangerRow(
                      icon: FontAwesomeIcons.broom,
                      title: 'Clear Cache',
                      subtitle: 'Free up storage used by temporary files',
                      actionText: 'Clear',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Cache cleared'),
                              duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                    _DangerRow(
                      icon: FontAwesomeIcons.rotateLeft,
                      title: 'Reset to Defaults',
                      subtitle: 'Restore settings to original values',
                      actionText: 'Reset',
                      onPressed: _resetSettings,
                    ),
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
        children: const [
          _BackChevron(),
          Expanded(
            child: Center(
              child: Text(
                'Settings',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text),
              ),
            ),
          ),
          SizedBox(width: 24),
        ],
      ),
    );
  }

  void _resetSettings() {
    setState(() {
      notifications = true;
      reminderEnabled = true;
      reminderMinutes = 15;
      soundEffects = true;
      haptics = true;
      darkMode = false;
      dataSaver = false;
      autoUpdate = true;
      twoFactor = false;
      language = 'English';
      _selectedTimezone = 'Australia/Sydney';
    });
    // Also reset timezone in Firestore
    _saveTimezone('Australia/Sydney');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings reset'),
        duration: Duration(seconds: 2),
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
      child: const Icon(FontAwesomeIcons.chevronLeft,
          size: 18, color: AppColors.text),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.accent],
              ),
            ),
            child: Center(child: Icon(icon, color: Colors.white, size: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: AppColors.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: Colors.white,
            activeTrackColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingNavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final VoidCallback onTap;
  const _SettingNavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailingText,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
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
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.accent],
                ),
              ),
              child: Center(child: Icon(icon, color: Colors.white, size: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.text)),
            ),
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(trailingText!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted)),
              ),
            const Icon(FontAwesomeIcons.chevronRight,
                size: 14, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final bool enabled;
  final int minutes;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onMinutesChanged;
  const _ReminderCard({
    required this.enabled,
    required this.minutes,
    required this.onEnabledChanged,
    required this.onMinutesChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(FontAwesomeIcons.bell, color: AppColors.primary, size: 16),
                  SizedBox(width: 8),
                  Text('Appointment Reminder',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.text)),
                ],
              ),
              Switch(
                value: enabled,
                activeColor: Colors.white,
                activeTrackColor: AppColors.primary,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: enabled ? 1 : 0.5,
            child: IgnorePointer(
              ignoring: !enabled,
              child: Row(
                children: [
                  const Text('Remind me',
                      style: TextStyle(color: AppColors.text)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: minutes,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5 min')),
                      DropdownMenuItem(value: 10, child: Text('10 min')),
                      DropdownMenuItem(value: 15, child: Text('15 min')),
                      DropdownMenuItem(value: 30, child: Text('30 min')),
                    ],
                    onChanged: (v) {
                      if (v != null) onMinutesChanged(v);
                    },
                  ),
                  const Text('before start',
                      style: TextStyle(color: AppColors.text)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageSheet extends StatelessWidget {
  final String current;
  const _LanguageSheet({required this.current});
  @override
  Widget build(BuildContext context) {
    final List<String> langs = const ['English', 'Spanish', 'Vietnamese'];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.muted.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('Select Language',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 12),
          ...langs.map((l) => ListTile(
                onTap: () => Navigator.pop(context, l),
                leading: Icon(FontAwesomeIcons.circleDot,
                    size: 14,
                    color: l == current
                        ? AppColors.primary
                        : AppColors.muted),
                title: Text(l),
                trailing: l == current
                    ? const Icon(FontAwesomeIcons.check,
                        size: 14, color: AppColors.primary)
                    : null,
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TimezoneSheet extends StatelessWidget {
  final String current;
  const _TimezoneSheet({required this.current});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.muted.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    const Icon(FontAwesomeIcons.clock, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'Select Time Zone',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(FontAwesomeIcons.xmark, size: 18),
                      color: AppColors.muted,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Timezone List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Australia Section
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '🇦🇺 AUSTRALIA',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ...TimezoneHelper.australianTimezones.entries.map((entry) => 
                  _buildTimezoneItem(context, entry.key, '🇦🇺 ${entry.value}', current == entry.key),
                ),
                
                const Divider(height: 24),
                
                // Other Timezones Section
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '🌍 OTHER TIME ZONES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ...TimezoneHelper.otherTimezones.entries.map((entry) => 
                  _buildTimezoneItem(context, entry.key, entry.value, current == entry.key),
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTimezoneItem(BuildContext context, String value, String label, bool isSelected) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? FontAwesomeIcons.solidCircleCheck : FontAwesomeIcons.circle,
              size: 16,
              color: isSelected ? AppColors.primary : AppColors.muted.withOpacity(0.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? AppColors.primary : AppColors.text,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(FontAwesomeIcons.check, size: 14, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionText;
  final VoidCallback onPressed;
  const _DangerRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionText,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.red.shade400,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
                child: Icon(icon, color: Colors.white, size: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Colors.red.shade500)),
              ],
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade700,
            ),
            child: Text(actionText),
          ),
        ],
      ),
    );
  }
}

class _AppVersion extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Text('App Version',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.text)),
          Text('v1.0.0',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}


