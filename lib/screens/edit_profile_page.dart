import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../services/audit_log_service.dart';

// --- 1. Theme & Colors ---
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

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage>
    with TickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _abnController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String _avatarUrl = '';
  String _logoUrl = '';
  String _userRole = '';
  bool _hasChanges = false;
  bool _isSaving = false;
  late Map<String, String> _originalValues;

  bool _loadingProfile = true;

  late AnimationController _avatarPulseController;
  late AnimationController _savePulseController;

  late AnimationController _entranceController;
  final List<Animation<Offset>> _slideAnimations = [];
  final List<Animation<double>> _fadeAnimations = [];

  @override
  void initState() {
    super.initState();
    _originalValues = {
      'name': '',
      'email': '',
      'phone': '',
      'abn': '',
      'address': '',
      'avatar': '',
      'logo': '',
    };
    _nameController.addListener(_checkForChanges);
    _emailController.addListener(_checkForChanges);
    _phoneController.addListener(_checkForChanges);
    _abnController.addListener(_checkForChanges);
    _addressController.addListener(_checkForChanges);

    _avatarPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: false);

    _savePulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // Support up to 5 fields (name, email, phone, abn, address)
    for (int i = 0; i < 5; i++) {
      final double start = 0.1 + (i * 0.1);
      final double end = start + 0.4;
      _slideAnimations.add(
        Tween<Offset>(begin: const Offset(-0.1, 0), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _entranceController,
              curve: Interval(start, end, curve: Curves.easeOut)),
        ),
      );
      _fadeAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
              parent: _entranceController,
              curve: Interval(start, end, curve: Curves.easeOut)),
        ),
      );
    }
    _entranceController.forward();

    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _abnController.dispose();
    _addressController.dispose();
    _avatarPulseController.dispose();
    _savePulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    final bool isWorkshopOwner = _userRole.toLowerCase() == 'workshop_owner';
    final String imageValue = isWorkshopOwner ? _logoUrl : _avatarUrl;
    final String originalImageValue = isWorkshopOwner ? _originalValues['logo'] ?? '' : _originalValues['avatar'] ?? '';
    
    final bool hasChanges =
        _nameController.text != _originalValues['name'] ||
        _emailController.text != _originalValues['email'] ||
        _phoneController.text != _originalValues['phone'] ||
        _abnController.text != _originalValues['abn'] ||
        _addressController.text != _originalValues['address'] ||
        imageValue != originalImageValue;
    if (hasChanges != _hasChanges) {
      setState(() {
        _hasChanges = hasChanges;
      });
    }
  }

  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _loadingProfile = false;
        });
        return;
      }

      String name = user.displayName ?? '';
      String email = user.email ?? '';
      String phone = '';
      String avatarUrl = user.photoURL ?? '';
      String abn = '';
      String address = '';

      String logoUrl = '';
      String userRole = '';
      
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (snap.exists) {
          final data = snap.data() as Map<String, dynamic>? ?? {};
          userRole = (data['role'] ?? '').toString();
          // role is already normalized (staff, branch_admin, workshop_owner)
          final bool isWorkshopOwner = userRole.toLowerCase() == 'workshop_owner';
          
          // For salon owners, prioritize business name (name field) over displayName
          if (isWorkshopOwner) {
            name = (data['name'] ?? 
                    data['displayName'] ?? 
                    name ?? 
                    email ?? 
                    'Business')
                .toString();
          } else {
            name = (data['displayName'] ??
                    data['name'] ??
                    name ??
                    email ??
                    'Staff Member')
                .toString();
          }
          
          email = (data['email'] ?? email).toString();
          phone = (data['phone'] ?? data['clientPhone'] ?? data['contactPhone'] ?? '').toString();
          avatarUrl =
              (data['photoURL'] ?? data['avatarUrl'] ?? avatarUrl).toString();
          logoUrl = (data['logoUrl'] ?? '').toString();
          
          // Load salon owner specific fields
          if (isWorkshopOwner) {
            abn = (data['abn'] ?? '').toString();
            address = (data['locationText'] ?? data['address'] ?? '').toString();
          }
        }
      } catch (e) {
        debugPrint('Error loading profile in edit page: $e');
      }

      if (!mounted) return;
      setState(() {
        _nameController.text = name;
        _emailController.text = email;
        _phoneController.text = phone;
        _abnController.text = abn;
        _addressController.text = address;
        _avatarUrl = avatarUrl;
        _logoUrl = logoUrl;
        _userRole = userRole;
        _originalValues = {
          'name': name,
          'email': email,
          'phone': phone,
          'abn': abn,
          'address': address,
          'avatar': avatarUrl,
          'logo': logoUrl,
        };
        _hasChanges = false;
        _loadingProfile = false;
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isSaving = true);

    try {
      final String name = _nameController.text.trim();
      final String email = _emailController.text.trim();
      final String phone = _phoneController.text.trim();
      final String abn = _abnController.text.trim();
      final String address = _addressController.text.trim();

      // Update auth profile (display name & photo)
      if (name.isNotEmpty && name != user.displayName) {
        await user.updateDisplayName(name);
      }
      
      final bool isWorkshopOwner = _userRole.toLowerCase() == 'workshop_owner';
      final String imageUrl = isWorkshopOwner ? _logoUrl : _avatarUrl;
      
      if (imageUrl.isNotEmpty && imageUrl != (user.photoURL ?? '')) {
        await user.updatePhotoURL(imageUrl);
      }

      // Update Firestore user document
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final Map<String, dynamic> update = {
        'displayName': name,
        'name': name,
        'email': email,
        'phone': phone,
        'contactPhone': phone,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // Add salon owner specific fields
      if (isWorkshopOwner) {
        if (abn.isNotEmpty) {
          update['abn'] = abn;
        }
        if (address.isNotEmpty) {
          update['locationText'] = address;
          update['address'] = address;
        }
        // Save logo URL for salon owners
        if (_logoUrl.isNotEmpty) {
          update['logoUrl'] = _logoUrl;
        }
      } else {
        // Save avatar URL for non-salon owners
        if (_avatarUrl.isNotEmpty) {
          update['photoURL'] = _avatarUrl;
          update['avatarUrl'] = _avatarUrl;
        }
      }
      
      await docRef.set(update, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _hasChanges = false;
        final bool isWorkshopOwner = _userRole.toLowerCase() == 'workshop_owner';
        _originalValues = {
          'name': name,
          'email': email,
          'phone': phone,
          'abn': abn,
          'address': address,
          'avatar': _avatarUrl,
          'logo': _logoUrl,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.check, color: Colors.white),
            SizedBox(width: 8),
            Text("Profile updated")
          ]),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save profile: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showPictureModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PictureModal(
        onCamera: () => _pickAndUploadImage(ImageSource.camera),
        onGallery: () => _pickAndUploadImage(ImageSource.gallery),
        onRemove: _removePhoto,
      ),
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    Navigator.pop(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final picker = ImagePicker();
      final bool isWorkshopOwner = _userRole.toLowerCase() == 'workshop_owner';
      
      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: isWorkshopOwner ? 512 : 1024,
        maxHeight: isWorkshopOwner ? 512 : 1024,
      );
      if (picked == null) return;

      // Show loading indicator
      if (!mounted) return;
      setState(() => _isSaving = true);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('Uploading ${isWorkshopOwner ? 'logo' : 'picture'}...'),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );

      final file = File(picked.path);
      final ext = picked.path.split('.').last;
      String url;
      
      // For salon owners, try API endpoint first, fallback to direct storage
      // For staff, use direct storage upload (should work with current rules)
      if (isWorkshopOwner) {
        // Try API endpoint first for salon owner logo upload
        try {
          final token = await user.getIdToken();
          final imageBytes = await file.readAsBytes();
          
          // Check file size (max 5MB)
          if (imageBytes.length > 5 * 1024 * 1024) {
            throw Exception('Image size must be less than 5MB');
          }
          
          final base64Image = base64Encode(imageBytes);
          
          const apiBaseUrl = 'https://black.bmspros.com.au';
          debugPrint('Uploading logo to API: $apiBaseUrl/api/upload/logo');
          debugPrint('Image size: ${imageBytes.length} bytes, Base64 length: ${base64Image.length}');
          
          final response = await http.post(
            Uri.parse('$apiBaseUrl/api/upload/logo'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'imageData': 'data:image/$ext;base64,$base64Image',
              'fileExtension': ext,
            }),
          ).timeout(const Duration(seconds: 30));

          debugPrint('API Response status: ${response.statusCode}');
          debugPrint('API Response body length: ${response.body.length}');

          if (response.statusCode == 200) {
            if (response.body.isEmpty) {
              throw Exception('Empty response from API');
            }
            
            try {
              final responseData = jsonDecode(response.body);
              url = responseData['logoUrl']?.toString() ?? '';
              if (url.isEmpty) {
                throw Exception('No logo URL returned from API');
              }
              debugPrint('Logo URL received from API: $url');
            } catch (e) {
              debugPrint('Error parsing API response: $e');
              throw Exception('Invalid response from API');
            }
          } else {
            String errorMessage = 'API returned status ${response.statusCode}';
            if (response.body.isNotEmpty) {
              try {
                final errorData = jsonDecode(response.body);
                errorMessage = errorData['error']?.toString() ?? 
                              errorData['details']?.toString() ?? 
                              errorMessage;
              } catch (e) {
                // Response is not JSON, use raw body if short enough
                errorMessage = response.body.length < 200 
                    ? 'Server error: ${response.body}' 
                    : 'Server error: ${response.statusCode}';
              }
            }
            debugPrint('API Error: $errorMessage');
            throw Exception(errorMessage);
          }
        } catch (apiError) {
          debugPrint('API upload failed, trying direct storage upload: $apiError');
          // Fallback to direct storage upload
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('salon-logos')
              .child(user.uid)
              .child('logo-$timestamp.$ext');
          
          await storageRef.putFile(file);
          url = await storageRef.getDownloadURL();
          debugPrint('Logo uploaded via direct storage: $url');
        }
      } else {
        // Direct storage upload for staff avatars
        debugPrint('[Upload] ===== Starting staff avatar upload =====');
        debugPrint('[Upload] User UID: ${user.uid}');
        debugPrint('[Upload] File path: ${file.path}');
        final fileSize = await file.length();
        debugPrint('[Upload] File size: $fileSize bytes');
        
        // Verify user is authenticated and refresh token
        if (user.uid.isEmpty) {
          throw Exception('User not authenticated');
        }
        
        // Refresh auth token to ensure it's valid
        try {
          final token = await user.getIdToken(true); // Force refresh
          debugPrint('[Upload] Auth token refreshed successfully. Token length: ${token?.length ?? 0}');
        } catch (tokenError) {
          debugPrint('[Upload] Warning: Failed to refresh token: $tokenError');
        }
        
        // Verify file exists and is readable
        if (!await file.exists()) {
          throw Exception('File does not exist: ${file.path}');
        }
        
        final fileName = '${user.uid}.jpg';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('staff_avatars')
            .child(fileName);

        debugPrint('[Upload] Storage path: staff_avatars/$fileName');
        debugPrint('[Upload] Full storage URL: ${storageRef.fullPath}');
        debugPrint('[Upload] User UID for rule check: ${user.uid}');
        debugPrint('[Upload] FileName for rule check: $fileName');
        debugPrint('[Upload] Expected rule match: fileName should start with ${user.uid}');
        
        // Read file as bytes for more reliable upload
        final fileBytes = await file.readAsBytes();
        debugPrint('[Upload] File bytes read: ${fileBytes.length} bytes');
        
        if (fileBytes.isEmpty) {
          throw Exception('File is empty or could not be read');
        }
        
        // Upload with metadata using putData for better reliability
        debugPrint('[Upload] Starting putData upload...');
        final uploadTask = storageRef.putData(
          fileBytes,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {
              'uploadedBy': user.uid,
              'uploadedAt': DateTime.now().toIso8601String(),
            },
          ),
        );
        
        debugPrint('[Upload] Upload task created, waiting for completion...');
        
        // Monitor upload progress and errors
        StreamSubscription? progressSub;
        try {
          progressSub = uploadTask.snapshotEvents.listen(
            (taskSnapshot) {
              if (taskSnapshot.totalBytes > 0) {
                final progress = (taskSnapshot.bytesTransferred / taskSnapshot.totalBytes * 100);
                debugPrint('[Upload] Progress: ${progress.toStringAsFixed(1)}% (${taskSnapshot.bytesTransferred}/${taskSnapshot.totalBytes})');
              }
              
              // Check for errors in snapshot
              if (taskSnapshot.state == TaskState.error) {
                debugPrint('[Upload] ⚠️ Task error state detected');
              } else if (taskSnapshot.state == TaskState.canceled) {
                debugPrint('[Upload] ⚠️ Task cancelled state detected');
              } else if (taskSnapshot.state == TaskState.success) {
                debugPrint('[Upload] ✅ Task success state detected');
              } else if (taskSnapshot.state == TaskState.running) {
                debugPrint('[Upload] 🔄 Task running...');
              } else if (taskSnapshot.state == TaskState.paused) {
                debugPrint('[Upload] ⏸️ Task paused');
              }
            },
            onError: (error) {
              debugPrint('[Upload] ❌ Progress stream error: $error');
            },
            cancelOnError: false,
          );
          
          // Wait for upload to complete with timeout
          debugPrint('[Upload] Waiting for upload to complete (timeout: 60s)...');
          final taskSnapshot = await uploadTask.timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              debugPrint('[Upload] ❌ Upload timeout after 60 seconds');
              uploadTask.cancel();
              throw Exception('Upload timeout - please check your internet connection');
            },
          );
          
          debugPrint('[Upload] Upload task completed. Final state: ${taskSnapshot.state}');
          debugPrint('[Upload] Bytes transferred: ${taskSnapshot.bytesTransferred}');
          debugPrint('[Upload] Total bytes: ${taskSnapshot.totalBytes}');
          
          if (taskSnapshot.state != TaskState.success) {
            debugPrint('[Upload] ❌ Upload failed. State: ${taskSnapshot.state}');
            throw Exception('Upload failed: ${taskSnapshot.state}');
          }
          
          debugPrint('[Upload] ✅ Upload successful, getting download URL...');
          url = await storageRef.getDownloadURL().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Failed to get download URL - timeout');
            },
          );
          debugPrint('[Upload] ✅ Download URL obtained: $url');

          // Update Firestore immediately after upload
          debugPrint('[Upload] Updating Firestore...');
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'avatarUrl': url,
            'photoURL': url, // Also update photoURL for consistency
            'updatedAt': FieldValue.serverTimestamp(),
          });
          
          debugPrint('[Upload] ✅ Firestore updated successfully');
          debugPrint('[Upload] ===== Upload complete =====');
        } catch (uploadError) {
          debugPrint('[Upload] ❌ Upload error caught: $uploadError');
          debugPrint('[Upload] Error type: ${uploadError.runtimeType}');
          debugPrint('[Upload] Error stack: ${StackTrace.current}');
          
          // Try to get more details about the error
          if (uploadError is FirebaseException) {
            debugPrint('[Upload] Firebase error code: ${uploadError.code}');
            debugPrint('[Upload] Firebase error message: ${uploadError.message}');
            debugPrint('[Upload] Firebase error plugin: ${uploadError.plugin}');
            throw Exception('Upload failed: ${uploadError.code} - ${uploadError.message ?? uploadError.toString()}');
          } else if (uploadError is TimeoutException) {
            throw Exception('Upload timeout - the upload took too long. Please try again.');
          }
          
          rethrow;
        } finally {
          await progressSub?.cancel();
          debugPrint('[Upload] Progress subscription cancelled');
        }
      }

      // Update local state and Firestore for salon owners
      if (isWorkshopOwner) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'logoUrl': url,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Log audit trail
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          String ownerUid = user.uid;
          String userName = (userData['displayName'] ?? 
                            userData['name'] ?? 
                            user.email ?? 
                            'User').toString();
          final role = (userData['role'] ?? '').toString();
          
          // For non-salon owners, get ownerUid from the document
          if (!isWorkshopOwner && userData['ownerUid'] != null) {
            ownerUid = userData['ownerUid'].toString();
          }
          
          await AuditLogService.logProfilePictureChanged(
            ownerUid: ownerUid,
            userId: user.uid,
            userName: userName,
            performedByRole: role.isNotEmpty ? role : null,
            pictureType: isWorkshopOwner ? 'logo' : 'avatar',
          );
        }
      } catch (auditError) {
        debugPrint('Failed to create profile picture change audit log: $auditError');
        // Don't block the upload if audit logging fails
      }

      if (!mounted) return;
      setState(() {
        if (isWorkshopOwner) {
          _logoUrl = url;
          _originalValues['logo'] = url;
        } else {
          _avatarUrl = url;
          _originalValues['avatar'] = url;
        }
        _hasChanges = true;
        _isSaving = false;
      });
      
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check, color: Colors.white),
              const SizedBox(width: 8),
              Text('${isWorkshopOwner ? 'Logo' : 'Picture'} uploaded successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error picking/uploading image: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload ${_userRole.toLowerCase() == 'workshop_owner' ? 'logo' : 'picture'}. Error: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _removePhoto() {
    Navigator.pop(context);
    setState(() {
      final bool isWorkshopOwner = _userRole.toLowerCase() == 'workshop_owner';
      if (isWorkshopOwner) {
        _logoUrl = '';
      } else {
        _avatarUrl = '';
      }
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (!_loadingProfile) _buildProfilePictureSection(),
                    const SizedBox(height: 24),
                    _buildPersonalInfoSection(),
                    const SizedBox(height: 24),
                    _buildSaveButton(),
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

  // --- Widgets ---
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
                'Edit Profile',
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

  Widget _buildProfilePictureSection() {
    // For salon owner, show logo if available
    final bool isWorkshopOwner = _userRole.toLowerCase() == 'workshop_owner';
    final String displayImageUrl = isWorkshopOwner && _logoUrl.isNotEmpty 
        ? _logoUrl 
        : _avatarUrl;
    final bool hasImage = displayImageUrl.isNotEmpty;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          // Show "Salon Logo" label and business name for salon owner
          if (isWorkshopOwner) ...[
            const Text(
              'Salon Logo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _nameController,
              builder: (context, value, child) {
                final businessName = value.text.trim();
                return businessName.isNotEmpty
                    ? Text(
                        businessName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                        textAlign: TextAlign.center,
                      )
                    : const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 16),
          ],
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _avatarPulseController,
                builder: (context, child) {
                  final double value = _avatarPulseController.value;
                  final double scale =
                      1.0 + (math.sin(value * math.pi) * 0.02);
                  final double shadowBlur =
                      30.0 + (math.sin(value * math.pi) * 20.0);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasImage ? null : AppColors.background,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: shadowBlur,
                            spreadRadius: 0,
                          ),
                        ],
                        image: hasImage
                            ? DecorationImage(
                                image: NetworkImage(displayImageUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: !hasImage
                          ? Center(
                              child: Icon(
                                isWorkshopOwner 
                                    ? FontAwesomeIcons.store 
                                    : FontAwesomeIcons.user,
                                color: AppColors.primary.withOpacity(0.5),
                                size: 36,
                              ),
                            )
                          : null,
                    ),
                  );
                },
              ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.2), width: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _showPictureModal,
            child: Text(
              isWorkshopOwner ? 'Change Logo' : 'Change Picture',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    final bool isWorkshopOwner = _userRole.toLowerCase() == 'workshop_owner';
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isWorkshopOwner ? 'Business Information' : 'Personal Information',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),
          _buildAnimatedField(
            0, 
            isWorkshopOwner ? 'Business Name' : 'Full Name', 
            _nameController,
            TextInputType.name,
          ),
          const SizedBox(height: 16),
          _buildAnimatedField(
            1, 
            'Email Address', 
            _emailController,
            TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          _buildAnimatedField(
            2, 
            'Phone Number', 
            _phoneController, 
            TextInputType.phone,
          ),
          if (isWorkshopOwner) ...[
            const SizedBox(height: 16),
            _buildAnimatedField(
              3, 
              'ABN', 
              _abnController, 
              TextInputType.number,
            ),
            const SizedBox(height: 16),
            _buildAnimatedField(
              4, 
              'Address', 
              _addressController, 
              TextInputType.streetAddress,
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimatedField(
    int index, 
    String label,
    TextEditingController controller, 
    TextInputType type, {
    int maxLines = 1,
  }) {
    // Ensure animations list has enough items
    if (index >= _fadeAnimations.length || index >= _slideAnimations.length) {
      // Return non-animated version if animation doesn't exist
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: type,
            maxLines: maxLines,
            style: const TextStyle(color: AppColors.text),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            ),
          ),
        ],
      );
    }
    
    return FadeTransition(
      opacity: _fadeAnimations[index],
      child: SlideTransition(
        position: _slideAnimations[index],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: type,
              maxLines: maxLines,
              style: const TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSaveButton() {
    return AnimatedBuilder(
      animation: _savePulseController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: _hasChanges
                ? const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent])
                : null,
            color: _hasChanges ? null : Colors.grey.shade200,
            boxShadow: _hasChanges
                ? [
                    BoxShadow(
                      color: AppColors.primary
                          .withOpacity(0.3 + (_savePulseController.value * 0.2)),
                      blurRadius: 15 + (_savePulseController.value * 10),
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _hasChanges ? _saveChanges : null,
              borderRadius: BorderRadius.circular(30),
              child: Center(
                child: _isSaving
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Saving...',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600)),
                        ],
                      )
                    : Text(
                        'Save Changes',
                        style: TextStyle(
                          color:
                              _hasChanges ? Colors.white : Colors.grey.shade400,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
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

// --- Helper: Picture Modal ---
class _PictureModal extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onRemove;

  const _PictureModal({
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.muted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2)),
              margin: const EdgeInsets.only(bottom: 24)),
          const Text('Change Profile Picture',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
          const SizedBox(height: 24),
          _buildModalBtn(
              context,
              'Take Photo',
              FontAwesomeIcons.camera,
              const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              onCamera),
          const SizedBox(height: 12),
          _buildModalBtn(
              context,
              'Choose from Gallery',
              FontAwesomeIcons.images,
              const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              onGallery),
          const SizedBox(height: 12),
          _buildModalBtn(context, 'Remove Photo', FontAwesomeIcons.trash, null,
              onRemove,
              isDestructive: true),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style:
                    TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildModalBtn(BuildContext context, String text, IconData icon,
      Gradient? gradient, VoidCallback onTap,
      {bool isDestructive = false}) {
    return Material(
      color: isDestructive ? Colors.red.shade50 : AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: gradient,
                  color: isDestructive ? Colors.red : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                    child:
                        Icon(icon, color: Colors.white, size: 20)),
              ),
              const SizedBox(width: 16),
              Text(
                text,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color:
                        isDestructive ? Colors.red.shade700 : AppColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


