import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'edit_profile_page.dart';
import 'change_password_page.dart';
import 'privacy_policy_page.dart';
import 'terms_of_service_page.dart';
import 'help_support_page.dart';
import '../utils/timezone_helper.dart';
import '../services/audit_log_service.dart';
import '../services/staff_check_in_service.dart';

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

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _floatController;
  late AnimationController _shimmerController;
  late Animation<double> _floatAnimation;

  // Live user data
  String _name = '';
  String _role = '';
  String _photoUrl = '';
  String _logoUrl = '';
  String _systemRole = '';
  String? _ratingLabel;
  String? _experienceLabel;
  int _totalBookings = 0;
  bool _loadingProfile = true;
  
  // Salon owner details
  String _ownerEmail = '';
  String _ownerPhone = '';
  String _ownerAddress = '';
  String _ownerABN = '';
  
  // Timezone state
  String _selectedTimezone = 'Australia/Sydney';
  bool _isLoadingTimezone = true;
  String? _branchId; // For branch admins to update branch timezone

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _floatAnimation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
    
    _entranceController.forward();
    _loadProfile();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _floatController.dispose();
    _shimmerController.dispose();
    super.dispose();
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
      String role = '';
      String photoUrl = user.photoURL ?? '';
      String logoUrl = '';
      String systemRole = '';
      String? ratingLabel;
      String? experienceLabel;
      int totalBookings = 0;

      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (snap.exists) {
          final data = snap.data() as Map<String, dynamic>? ?? {};

          final displayName = (data['displayName'] ?? '').toString().trim();
          final businessName = (data['name'] ?? '').toString().trim();
          final email = user.email ?? '';

          String rawRoleValue = (data['role'] ?? '').toString().trim().toLowerCase();
          // role is already normalized (staff, branch_admin, workshop_owner)
          systemRole = rawRoleValue;
          
          logoUrl = (data['logoUrl'] ?? '').toString();

          if (systemRole == 'workshop_owner' && businessName.isNotEmpty) {
            name = businessName;
          } else if (displayName.isNotEmpty) {
            name = displayName;
          } else if (businessName.isNotEmpty) {
            name = businessName;
          } else {
            name = name.isNotEmpty
                ? name
                : (email.isNotEmpty ? email : 'Team Member');
          }

          final staffRole = data['staffRole'];
          if (staffRole != null && staffRole.toString().trim().isNotEmpty) {
            role = staffRole.toString();
          } else {
            if (systemRole == 'workshop_owner') {
              role = 'Workshop Owner';
            } else if (systemRole == 'branch_admin') {
              role = 'Branch Admin';
            } else if (systemRole == 'staff') {
              role = 'Staff Member';
            } else if (rawRoleValue.isNotEmpty) {
              role = rawRoleValue;
            } else {
              role = 'Team Member';
            }
          }
          photoUrl = (data['photoURL'] ?? data['avatarUrl'] ?? photoUrl)
              .toString();

          final avatarField = data['avatar'];
          if (avatarField is String &&
              (avatarField.startsWith('http://') ||
                  avatarField.startsWith('https://'))) {
            photoUrl = avatarField;
          }

          final rating = data['rating'];
          if (rating is num) {
            ratingLabel = rating.toStringAsFixed(1);
          }

          final expYears = data['experienceYears'];
          if (expYears is num && expYears > 0) {
            experienceLabel = '${expYears.toInt()} Years';
          } else if (data['createdAt'] != null) {
            final ts = data['createdAt'];
            DateTime? created;
            if (ts is Timestamp) {
              created = ts.toDate();
            }
            if (created != null) {
              final years =
                  DateTime.now().difference(created).inDays ~/ 365;
              if (years >= 1) {
                experienceLabel = '$years Year${years == 1 ? '' : 's'}';
              } else {
                experienceLabel = 'New';
              }
            }
          }
          
          // Get total bookings count for staff
          if (systemRole == 'staff') {
            final ownerUid = data['ownerUid'] ?? '';
            if (ownerUid.isNotEmpty) {
              final bookingsSnap = await FirebaseFirestore.instance
                  .collection('bookings')
                  .where('ownerUid', isEqualTo: ownerUid)
                  .where('staffId', isEqualTo: user.uid)
                  .get();
              totalBookings = bookingsSnap.docs.length;
            }
          }
          
          // Load timezone and branchId for branch admins
          if (systemRole == 'branch_admin') {
            // For branch admins, load branch timezone instead of user timezone
            _branchId = data['branchId']?.toString();
            debugPrint('ProfileScreen: Branch admin detected, branchId: $_branchId');
            
            if (_branchId != null && _branchId!.isNotEmpty) {
              try {
                final branchDoc = await FirebaseFirestore.instance
                    .collection('branches')
                    .doc(_branchId)
                    .get();
                if (branchDoc.exists) {
                  final branchData = branchDoc.data();
                  debugPrint('ProfileScreen: Branch found, timezone: ${branchData?['timezone']}');
                  if (branchData != null && branchData['timezone'] != null) {
                    _selectedTimezone = branchData['timezone'] as String;
                  } else {
                    // Branch exists but no timezone set, use default
                    _selectedTimezone = 'Australia/Sydney';
                  }
                } else {
                  debugPrint('ProfileScreen: Branch document not found for branchId: $_branchId');
                  // Fallback to user timezone if branch not found
                  if (data['timezone'] != null) {
                    _selectedTimezone = data['timezone'] as String;
                  }
                }
              } catch (e) {
                debugPrint('Error loading branch timezone: $e');
                // Fallback to user timezone if branch not found
                if (data['timezone'] != null) {
                  _selectedTimezone = data['timezone'] as String;
                }
              }
            } else {
              debugPrint('ProfileScreen: Branch admin but no branchId found in user document');
              // Fallback to user timezone if no branchId
              if (data['timezone'] != null) {
                _selectedTimezone = data['timezone'] as String;
              }
            }
          } else {
            // For other users, load user timezone
            if (data['timezone'] != null) {
              _selectedTimezone = data['timezone'] as String;
            }
          }
          
          // Load salon owner details if user is a salon owner
          if (systemRole == 'workshop_owner') {
            final ownerEmail = user.email ?? data['email'] ?? '';
            final ownerPhone = data['contactPhone'] ?? data['phone'] ?? '';
            final ownerAddress = data['locationText'] ?? data['address'] ?? '';
            final ownerABN = data['abn'] ?? '';
            
            if (!mounted) return;
            setState(() {
              _ownerEmail = ownerEmail;
              _ownerPhone = ownerPhone.toString();
              _ownerAddress = ownerAddress.toString();
              _ownerABN = ownerABN.toString();
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading profile from Firestore: $e');
      }

      if (!mounted) return;
      setState(() {
        _name = name.isNotEmpty ? name : (user.email ?? 'Team Member');
        _role = role.isNotEmpty ? role : 'Team Member';
        _photoUrl = photoUrl;
        _logoUrl = logoUrl;
        _systemRole = systemRole;
        _ratingLabel = ratingLabel;
        _experienceLabel = experienceLabel;
        _totalBookings = totalBookings;
        _loadingProfile = false;
        _isLoadingTimezone = false;
        // _branchId is already set in the timezone loading section above
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Animated background shapes
          ..._buildBackgroundShapes(),
          
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        _buildProfileCard(),
                        const SizedBox(height: 24),
                        _buildStatsRow(),
                        // Only show Edit Profile button for non-salon owners
                        if (_systemRole != 'workshop_owner') ...[
                          const SizedBox(height: 24),
                          _buildQuickActions(),
                        ],
                        const SizedBox(height: 24),
                        _buildMenuSection(),
                        const SizedBox(height: 32),
                      ],
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

  List<Widget> _buildBackgroundShapes() {
    return [
      // Top-right decorative circle
      Positioned(
        top: -100,
        right: -80,
        child: AnimatedBuilder(
          animation: _floatController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _floatAnimation.value * 0.5),
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.15),
                      AppColors.accent.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      // Bottom-left decorative circle
      Positioned(
        bottom: 100,
        left: -60,
        child: AnimatedBuilder(
          animation: _floatController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_floatAnimation.value * 0.3, 0),
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withOpacity(0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (widget.showBackButton)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Icon(
                    FontAwesomeIcons.chevronLeft,
                    size: 20,
                    color: AppColors.text,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 44),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _entranceController,
              curve: const Interval(0, 0.5, curve: Curves.easeOut),
            )),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _entranceController,
                curve: const Interval(0, 0.5),
              ),
              child: const Text(
                'Profile',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, {VoidCallback? onTap, bool showBadge = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(icon, size: 18, color: AppColors.text),
            ),
            if (showBadge)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.6, curve: Curves.easeOut),
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _entranceController,
          curve: const Interval(0.1, 0.6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AnimatedBuilder(
            animation: _floatController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _floatAnimation.value * 0.3),
                child: child,
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0D0D0D),
                    Color(0xFF1A1A1A),
                    Color(0xFF333333),
                    Color(0xFF4A4A4A),
                  ],
                  stops: [0.0, 0.3, 0.7, 1.0],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                    spreadRadius: -5,
                  ),
                  BoxShadow(
                    color: const Color(0xFF333333).withOpacity(0.2),
                    blurRadius: 60,
                    offset: const Offset(0, 25),
                    spreadRadius: -10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Avatar with animated ring
                  _buildAnimatedAvatar(),
                  const SizedBox(height: 20),
                  // Name with shimmer effect
                  _buildShimmerText(
                    _name.isNotEmpty ? _name : 'Loading...',
                    const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Role badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getRoleIcon(),
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _role.isNotEmpty ? _role : '',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Verified badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              FontAwesomeIcons.circleCheck,
                              size: 12,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Salon owner details section
                  if (_systemRole == 'workshop_owner') ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_name.isNotEmpty) ...[
                            _buildOwnerDetailRow(
                              FontAwesomeIcons.store,
                              _name,
                            ),
                            if (_ownerEmail.isNotEmpty || _ownerPhone.isNotEmpty || _ownerAddress.isNotEmpty || _ownerABN.isNotEmpty)
                              const SizedBox(height: 12),
                          ],
                          if (_ownerEmail.isNotEmpty) ...[
                            _buildOwnerDetailRow(
                              FontAwesomeIcons.envelope,
                              _ownerEmail,
                            ),
                            if (_ownerPhone.isNotEmpty || _ownerAddress.isNotEmpty || _ownerABN.isNotEmpty)
                              const SizedBox(height: 12),
                          ],
                          if (_ownerPhone.isNotEmpty) ...[
                            _buildOwnerDetailRow(
                              FontAwesomeIcons.phone,
                              _ownerPhone,
                            ),
                            if (_ownerAddress.isNotEmpty || _ownerABN.isNotEmpty)
                              const SizedBox(height: 12),
                          ],
                          if (_ownerAddress.isNotEmpty) ...[
                            _buildOwnerDetailRow(
                              FontAwesomeIcons.locationDot,
                              _ownerAddress,
                            ),
                            if (_ownerABN.isNotEmpty)
                              const SizedBox(height: 12),
                          ],
                          if (_ownerABN.isNotEmpty)
                            _buildOwnerDetailRow(
                              FontAwesomeIcons.hashtag,
                              'ABN: $_ownerABN',
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 14,
          color: Colors.white.withOpacity(0.9),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedAvatar() {
    final bool isWorkshopOwner = _systemRole == 'workshop_owner';
    final String displayImageUrl = isWorkshopOwner && _logoUrl.isNotEmpty 
        ? _logoUrl 
        : _photoUrl;
    final bool hasImage = displayImageUrl.isNotEmpty;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Animated outer ring with gold/silver shimmer
        AnimatedBuilder(
          animation: _shimmerController,
          builder: (context, child) {
            return Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: const [
                    Color(0xFF555555),
                    Colors.white70,
                    Color(0xFF888888),
                    Colors.white70,
                    Color(0xFF555555),
                  ],
                  transform: GradientRotation(_shimmerController.value * 2 * math.pi),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
            );
          },
        ),
        // Inner white border
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
        // Avatar image
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasImage ? null : Colors.white,
            image: hasImage
                ? DecorationImage(
                    image: NetworkImage(displayImageUrl),
                    fit: BoxFit.cover,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: !hasImage
              ? Center(
                  child: isWorkshopOwner
                      ? const Icon(
                          FontAwesomeIcons.store,
                          size: 36,
                          color: AppColors.primary,
                        )
                      : Text(
                          (_name.isNotEmpty ? _name.trim()[0] : 'S').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                )
              : null,
        ),
        // Online indicator
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerText(String text, TextStyle style) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: const [
                Colors.white,
                Colors.white70,
                Colors.white,
              ],
              stops: [
                _shimmerController.value - 0.3,
                _shimmerController.value,
                _shimmerController.value + 0.3,
              ].map((e) => e.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          child: Text(text, style: style),
        );
      },
    );
  }

  IconData _getRoleIcon() {
    switch (_systemRole) {
      case 'workshop_owner':
        return FontAwesomeIcons.crown;
      case 'branch_admin':
        return FontAwesomeIcons.userTie;
      case 'staff':
        return FontAwesomeIcons.scissors;
      default:
        return FontAwesomeIcons.user;
    }
  }

  Widget _buildStatsRow() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _entranceController,
          curve: const Interval(0.2, 0.7),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: FontAwesomeIcons.solidStar,
                  iconColor: const Color(0xFFFBBF24),
                  value: _ratingLabel ?? '5.0',
                  label: 'Rating',
                  gradient: [const Color(0xFFFEF3C7), const Color(0xFFFDE68A)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: FontAwesomeIcons.calendarCheck,
                  iconColor: const Color(0xFF10B981),
                  value: _totalBookings > 0 ? '$_totalBookings' : '0',
                  label: 'Bookings',
                  gradient: [const Color(0xFFD1FAE5), const Color(0xFFA7F3D0)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: FontAwesomeIcons.award,
                  iconColor: const Color(0xFF8B5CF6),
                  value: _experienceLabel ?? 'New',
                  label: 'Experience',
                  gradient: [const Color(0xFFEDE9FE), const Color(0xFFDDD6FE)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required List<Color> gradient,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient[1].withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: iconColor.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, size: 18, color: iconColor),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _entranceController,
          curve: const Interval(0.3, 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildQuickActionButton(
            icon: FontAwesomeIcons.penToSquare,
            label: 'Edit Profile',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EditProfilePage()),
              );
              _loadProfile();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.4, 0.9, curve: Curves.easeOut),
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _entranceController,
          curve: const Interval(0.4, 0.9),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildMenuTile(
                  icon: FontAwesomeIcons.lock,
                  iconBgColor: const Color(0xFFFFF3E0),
                  iconColor: const Color(0xFFFF9800),
                  title: 'Change Password',
                  subtitle: 'Update your account password',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
                    );
                  },
                ),
                // Only show timezone for salon owners and branch admins (not salon staff)
                if (_systemRole != 'staff') ...[
                  _buildDivider(),
                  _buildMenuTile(
                    icon: FontAwesomeIcons.clock,
                    iconBgColor: const Color(0xFFE3F2FD),
                    iconColor: const Color(0xFF2196F3),
                    title: _systemRole == 'branch_admin' ? 'Branch Time Zone' : 'Time Zone',
                    subtitle: _isLoadingTimezone 
                        ? 'Loading...' 
                        : TimezoneHelper.getTimezoneLabel(_selectedTimezone),
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
                  _buildDivider(),
                ],
                _buildMenuTile(
                  icon: FontAwesomeIcons.fileLines,
                  iconBgColor: const Color(0xFFEDE9FE),
                  iconColor: const Color(0xFF8B5CF6),
                  title: 'Terms of Service',
                  subtitle: 'Read our terms and conditions',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TermsOfServicePage()),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuTile(
                  icon: FontAwesomeIcons.userShield,
                  iconBgColor: const Color(0xFFE0F2F1),
                  iconColor: const Color(0xFF009688),
                  title: 'Privacy Policy',
                  subtitle: 'Learn how we protect your data',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuTile(
                  icon: FontAwesomeIcons.circleQuestion,
                  iconBgColor: const Color(0xFFD1FAE5),
                  iconColor: const Color(0xFF10B981),
                  title: 'Help & Support',
                  subtitle: 'Contact us for assistance',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HelpSupportPage()),
                    );
                  },
                ),
                _buildDivider(),
                _buildMenuTile(
                  icon: FontAwesomeIcons.rightFromBracket,
                  iconBgColor: const Color(0xFFFEE2E2),
                  iconColor: const Color(0xFFEF4444),
                  title: 'Logout',
                  subtitle: 'Sign out of your account',
                  isLogout: true,
                  onTap: _showLogoutConfirmDialog,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool isLogout = false,
    bool showBadge = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(icon, size: 20, color: iconColor),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isLogout ? const Color(0xFFEF4444) : AppColors.text,
                          ),
                        ),
                        if (showBadge) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '3',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isLogout 
                            ? const Color(0xFFEF4444).withOpacity(0.7) 
                            : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                FontAwesomeIcons.chevronRight,
                size: 14,
                color: isLogout 
                    ? const Color(0xFFEF4444).withOpacity(0.5) 
                    : AppColors.muted.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey.shade100,
      ),
    );
  }

  void _showLogoutConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Icon(
                      FontAwesomeIcons.rightFromBracket,
                      color: Color(0xFFEF4444),
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Logout?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to sign out of your account?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            // Check if staff has an active check-in and check them out
                            try {
                              final activeCheckIn = await StaffCheckInService.getActiveCheckIn();
                              if (activeCheckIn != null && activeCheckIn.id != null) {
                                await StaffCheckInService.checkOut(activeCheckIn.id!);
                              }
                            } catch (e) {
                              // Log error but continue with logout even if checkout fails
                              debugPrint('Error checking out on logout: $e');
                            }

                            final userDoc = await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .get();
                            final userData = userDoc.data();
                            final ownerUid = userData?['ownerUid'] ?? user.uid;
                            final userName = userData?['displayName'] ?? 
                                userData?['name'] ?? 
                                user.email ?? 
                                'Unknown';
                            final userRole = userData?['role'] ?? 'unknown';
                            
                            await AuditLogService.logUserLogout(
                              ownerUid: ownerUid.toString(),
                              performedBy: user.uid,
                              performedByName: userName.toString(),
                              performedByRole: userRole.toString(),
                            );
                          }
                          await FirebaseAuth.instance.signOut();
                          Navigator.of(context).pop();
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            '/login',
                            (route) => false,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFFF87171)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEF4444).withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveTimezone(String timezone) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('ProfileScreen: Cannot save timezone - user is null');
        return;
      }

      debugPrint('ProfileScreen: Saving timezone - role: $_systemRole, branchId: $_branchId, timezone: $timezone');

      // For branch admins, update branch timezone via API (they don't have direct Firestore write permission)
      if (_systemRole == 'branch_admin') {
        // Try to get branchId from user document if not already set
        if (_branchId == null || _branchId!.isEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            final userData = userDoc.data();
            _branchId = userData?['branchId']?.toString();
            debugPrint('ProfileScreen: Retrieved branchId from user document: $_branchId');
          } catch (e) {
            debugPrint('ProfileScreen: Error getting branchId: $e');
          }
        }

        if (_branchId != null && _branchId!.isNotEmpty) {
          debugPrint('ProfileScreen: Updating branch timezone via API for branchId: $_branchId');
          
          // Use API endpoint to update branch timezone (branch admins don't have direct Firestore write permission)
          try {
            final token = await user.getIdToken();
            final apiUrl = 'https://black.bmspros.com.au/api/branches/$_branchId/timezone';
            
            final response = await http.patch(
              Uri.parse(apiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({'timezone': timezone}),
            );

            if (response.statusCode == 200) {
              debugPrint('ProfileScreen: Branch timezone updated successfully via API');
              setState(() => _selectedTimezone = timezone);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Branch timezone updated to ${TimezoneHelper.getTimezoneLabel(timezone)}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } else {
              final errorBody = jsonDecode(response.body);
              throw Exception(errorBody['error'] ?? 'Failed to update branch timezone');
            }
          } catch (e) {
            debugPrint('ProfileScreen: Error updating branch timezone via API: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to update branch timezone: ${e.toString()}'),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            return; // Don't update user timezone if branch update failed
          }
        } else {
          debugPrint('ProfileScreen: Branch admin but no branchId available');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot update timezone: Branch ID not found'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      } else {
        // For salon owners and others, update user timezone
        debugPrint('ProfileScreen: Updating user timezone for role: $_systemRole');
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
          SnackBar(
            content: Text('Failed to save timezone: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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
