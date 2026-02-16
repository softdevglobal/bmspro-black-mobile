import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/timezone_helper.dart';

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

class SalonSettingsPage extends StatefulWidget {
  const SalonSettingsPage({super.key});

  @override
  State<SalonSettingsPage> createState() => _SalonSettingsPageState();
}

class _SalonSettingsPageState extends State<SalonSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _salonNameController = TextEditingController();
  final _abnController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _termsController = TextEditingController();
  
  // State
  String _email = '';
  String _logoUrl = '';
  String _businessStructure = '';
  String _state = '';
  String _plan = '';
  String _price = '';
  String _selectedTimezone = 'Australia/Sydney';
  bool _gstRegistered = false;
  bool _loading = true;
  bool _savingProfile = false;
  bool _savingTerms = false;
  bool _uploadingLogo = false;
  String _termsPreview = '';

  @override
  void initState() {
    super.initState();
    _termsController.addListener(_onTermsChanged);
    _loadUserData();
  }

  void _onTermsChanged() {
    setState(() {
      _termsPreview = _termsController.text;
    });
  }

  @override
  void dispose() {
    _termsController.removeListener(_onTermsChanged);
    _salonNameController.dispose();
    _abnController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
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
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }

      final data = snap.data()!;
      
      if (mounted) {
        setState(() {
          _salonNameController.text = data['name'] ?? data['displayName'] ?? '';
          _abnController.text = data['abn'] ?? '';
          _phoneController.text = data['contactPhone'] ?? data['phone'] ?? '';
          _addressController.text = data['locationText'] ?? data['address'] ?? '';
          _termsController.text = data['termsAndConditions'] ?? '';
          _termsPreview = data['termsAndConditions'] ?? '';
          _email = user.email ?? data['email'] ?? '';
          _logoUrl = data['logoUrl'] ?? '';
          _businessStructure = data['businessStructure'] ?? '';
          _state = data['state'] ?? '';
          _plan = data['plan'] ?? '';
          _price = data['price'] ?? '';
          _selectedTimezone = data['timezone'] ?? 'Australia/Sydney';
          _gstRegistered = data['gstRegistered'] ?? false;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        setState(() => _loading = false);
        _showSnackBar('Failed to load settings', isError: true);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _savingProfile = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'name': _salonNameController.text.trim(),
        'displayName': _salonNameController.text.trim(),
        'abn': _abnController.text.trim(),
        'contactPhone': _phoneController.text.trim(),
        'locationText': _addressController.text.trim(),
        'timezone': _selectedTimezone,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _showSnackBar('Profile saved successfully!');
    } catch (e) {
      debugPrint('Error saving profile: $e');
      _showSnackBar('Failed to save profile', isError: true);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _saveTerms() async {
    setState(() => _savingTerms = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'termsAndConditions': _termsController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _showSnackBar('Terms & Conditions saved!');
    } catch (e) {
      debugPrint('Error saving terms: $e');
      _showSnackBar('Failed to save terms', isError: true);
    } finally {
      if (mounted) setState(() => _savingTerms = false);
    }
  }

  Future<void> _pickAndUploadLogo() async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 512,
        maxHeight: 512,
      );
      
      if (picked == null) return;

      setState(() => _uploadingLogo = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final file = File(picked.path);
      final ext = picked.path.split('.').last;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('salon-logos')
          .child(user.uid)
          .child('logo-${DateTime.now().millisecondsSinceEpoch}.$ext');

      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'logoUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _logoUrl = downloadUrl);
      _showSnackBar('Logo uploaded successfully!');
    } catch (e) {
      debugPrint('Error uploading logo: $e');
      _showSnackBar('Failed to upload logo', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(FontAwesomeIcons.trash, color: Colors.red.shade600, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Remove Logo'),
          ],
        ),
        content: const Text('Are you sure you want to remove your salon logo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _uploadingLogo = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'logoUrl': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _logoUrl = '');
      _showSnackBar('Logo removed');
    } catch (e) {
      debugPrint('Error removing logo: $e');
      _showSnackBar('Failed to remove logo', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  void _showTermsPreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(
                        FontAwesomeIcons.fileContract,
                        color: Colors.indigo.shade600,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Terms & Conditions Preview',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          'How customers will see your terms',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Terms Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    _termsPreview.isEmpty 
                        ? 'No terms and conditions set yet.' 
                        : _termsPreview,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: _termsPreview.isEmpty 
                          ? AppColors.muted 
                          : AppColors.text,
                    ),
                  ),
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _saveTerms();
                      },
                      icon: const Icon(FontAwesomeIcons.floppyDisk, size: 14),
                      label: const Text('Save Terms'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAccountCard(),
                            const SizedBox(height: 20),
                            _buildLogoSection(),
                            const SizedBox(height: 20),
                            _buildBusinessProfileSection(),
                            const SizedBox(height: 20),
                            _buildTermsSection(),
                            const SizedBox(height: 32),
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
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(FontAwesomeIcons.chevronLeft,
                size: 18, color: AppColors.text),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Salon Settings',
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

  Widget _buildAccountCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.accent],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Logo or Initial
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _logoUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          _logoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildInitial(),
                        ),
                      )
                    : _buildInitial(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _salonNameController.text.isNotEmpty
                          ? _salonNameController.text
                          : 'Your Salon',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _email,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Role', 'Salon Owner'),
                if (_plan.isNotEmpty) _buildStatItem('Plan', _plan),
                _buildStatItem('GST', _gstRegistered ? 'Yes' : 'No'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitial() {
    final name = _salonNameController.text;
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'S',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildLogoSection() {
    return _buildCard(
      title: 'Salon Logo',
      icon: FontAwesomeIcons.image,
      child: Column(
        children: [
          if (_logoUrl.isNotEmpty) ...[
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(FontAwesomeIcons.image, color: AppColors.muted),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                    icon: _uploadingLogo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(FontAwesomeIcons.arrowsRotate, size: 14),
                    label: Text(_uploadingLogo ? 'Uploading...' : 'Change'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _uploadingLogo ? null : _removeLogo,
                  icon: const Icon(FontAwesomeIcons.trash, size: 14),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: Colors.red.shade200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            GestureDetector(
              onTap: _uploadingLogo ? null : _pickAndUploadLogo,
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.border,
                    style: BorderStyle.solid,
                    width: 2,
                  ),
                ),
                child: _uploadingLogo
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            FontAwesomeIcons.cloudArrowUp,
                            size: 32,
                            color: AppColors.muted.withOpacity(0.5),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap to upload logo',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'PNG, JPG or WebP (max 5MB)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBusinessProfileSection() {
    return _buildCard(
      title: 'Business Profile',
      icon: FontAwesomeIcons.building,
      child: Column(
        children: [
          _buildTextField(
            controller: _salonNameController,
            label: 'Salon Name',
            icon: FontAwesomeIcons.store,
            validator: (v) => v?.isEmpty == true ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _abnController,
            label: 'ABN',
            icon: FontAwesomeIcons.hashtag,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _phoneController,
            label: 'Phone',
            icon: FontAwesomeIcons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: TextEditingController(text: _email),
            label: 'Email',
            icon: FontAwesomeIcons.envelope,
            enabled: false,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _addressController,
            label: 'Address',
            icon: FontAwesomeIcons.locationDot,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          _buildTimezoneSelector(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _savingProfile ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _savingProfile
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(FontAwesomeIcons.floppyDisk, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Save Profile',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsSection() {
    return _buildCard(
      title: 'Terms & Conditions',
      icon: FontAwesomeIcons.fileContract,
      iconColor: Colors.indigo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your booking terms that customers must agree to',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.muted.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _termsController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'Enter your terms and conditions...\n\n• Cancellation policy\n• Late arrival policy\n• Payment terms',
              hintStyle: TextStyle(
                color: AppColors.muted.withOpacity(0.5),
                fontSize: 13,
              ),
              filled: true,
              fillColor: AppColors.background,
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
                borderSide: const BorderSide(color: Colors.indigo, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Preview Button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _termsPreview.isEmpty ? null : _showTermsPreview,
                  icon: const Icon(FontAwesomeIcons.eye, size: 14),
                  label: const Text('Preview'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    side: BorderSide(color: _termsPreview.isEmpty ? Colors.grey.shade300 : Colors.indigo.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Save Button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _savingTerms ? null : _saveTerms,
                  icon: _savingTerms
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(FontAwesomeIcons.floppyDisk, size: 14),
                  label: Text(_savingTerms ? 'Saving...' : 'Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimezoneSelector() {
    return GestureDetector(
      onTap: _showTimezoneSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(FontAwesomeIcons.clock, size: 16, color: AppColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Time Zone',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    TimezoneHelper.getTimezoneLabel(_selectedTimezone),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
            Icon(FontAwesomeIcons.chevronDown, size: 12, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  void _showTimezoneSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Icon(FontAwesomeIcons.clock, color: Colors.white, size: 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Select Time Zone',
                        style: TextStyle(
                          fontWeight: FontWeight.w700, 
                          color: AppColors.text, 
                          fontSize: 16,
                        ),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                    _buildTimezoneItem(entry.key, '🇦🇺 ${entry.value}'),
                  ),
                  
                  const Divider(height: 24),
                  
                  // Other Timezones Section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                    _buildTimezoneItem(entry.key, entry.value),
                  ),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimezoneItem(String value, String label) {
    final isSelected = _selectedTimezone == value;
    return InkWell(
      onTap: () {
        setState(() => _selectedTimezone = value);
        Navigator.pop(context);
        // Get just the city name from the label (e.g., "Sydney (NSW)" from "🇦🇺 Sydney (NSW) - AEST/AEDT")
        final label = TimezoneHelper.getTimezoneLabel(value);
        final cityName = label.contains('(') 
            ? label.substring(0, label.indexOf('(')).replaceAll('🇦🇺', '').trim()
            : label.split('-').first.trim();
        _showSnackBar('Timezone set to $cityName');
      },
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

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: iconColor != null
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                        ),
                  color: iconColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(icon, color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      validator: validator,
      style: TextStyle(
        color: enabled ? AppColors.text : AppColors.muted,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        prefixIcon: Icon(icon, size: 16, color: AppColors.muted),
        filled: true,
        fillColor: enabled ? AppColors.background : Colors.grey.shade100,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

