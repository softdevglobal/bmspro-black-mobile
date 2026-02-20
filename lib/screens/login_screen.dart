import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../routes.dart';
import 'forgot_password_request.dart';
import '../services/audit_log_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  late AnimationController _entranceController;
  late AnimationController _gearController;
  late AnimationController _pulseController;

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _emailFocused = false;
  bool _passwordFocused = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _gearController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _emailFocus.addListener(() => setState(() => _emailFocused = _emailFocus.hasFocus));
    _passwordFocus.addListener(() => setState(() => _passwordFocused = _passwordFocus.hasFocus));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _entranceController.dispose();
    _gearController.dispose();
    _pulseController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ─── Auth Logic ──────────────────────────────────────────────────────
  void _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter email and password")),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = userCredential.user;
      if (user == null) {
        throw FirebaseAuthException(
            code: 'user-not-found', message: 'Authentication failed.');
      }

      final DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("User profile not found.")),
          );
        }
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final rawRole = userData['role'];
      String userRole = rawRole != null ? rawRole.toString().trim() : 'unknown';

      bool isAuthorized = false;
      const allowedRoles = ['staff', 'workshop_owner', 'branch_admin'];
      if (allowedRoles.contains(userRole)) isAuthorized = true;

      if (!isAuthorized) {
        await FirebaseAuth.instance.signOut();
        throw FirebaseAuthException(
            code: 'permission-denied',
            message: 'Access denied. Role "$userRole" is not authorized.');
      }

      final ownerUid = userData['ownerUid'] ?? user.uid;
      final userName =
          userData['displayName'] ?? userData['name'] ?? user.email ?? 'Unknown';

      String? branchId;
      String? branchName;
      if (userRole == 'branch_admin') {
        branchId = userData['branchId']?.toString();
        branchName = userData['branchName']?.toString();
      }

      await AuditLogService.logUserLogin(
        ownerUid: ownerUid.toString(),
        performedBy: user.uid,
        performedByName: userName.toString(),
        performedByRole: userRole,
        branchId: branchId,
        branchName: branchName,
      );

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message = "Login failed";
        if (e.code == 'user-not-found') {
          message = 'No user found for that email.';
        } else if (e.code == 'wrong-password') {
          message = 'Wrong password provided for that user.';
        } else if (e.code == 'invalid-credential') {
          message = 'Invalid credentials provided.';
        } else if (e.code == 'permission-denied') {
          message = e.message ?? "Insufficient permissions.";
        } else {
          message = e.message ?? "An unknown error occurred.";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Animated gears + blueprint background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _gearController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _MechanicsBgPainter(time: _gearController.value),
                );
              },
            ),
          ),

          // Content
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: screenH),
              child: Padding(
                padding: EdgeInsets.only(top: topPad),
                child: Column(
                  children: [
                    // ── Logo ──
                    _fadeSlide(
                      interval: const Interval(0, 0.35),
                      yBegin: -0.15,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 50, bottom: 8),
                        child: Column(
                          children: [
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return Container(
                                  width: 92,
                                  height: 92,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(26),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF1A1A1A).withOpacity(
                                          0.10 + _pulseController.value * 0.08,
                                        ),
                                        blurRadius: 28 + _pulseController.value * 12,
                                        spreadRadius: _pulseController.value * 3,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: child,
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(26),
                                  color: Colors.white,
                                  border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.asset(
                                    'assets/icons/bmsblack-icon.jpeg',
                                    width: 92,
                                    height: 92,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            _fadeSlide(
                              interval: const Interval(0.12, 0.45),
                              yBegin: 0.08,
                              child: const Text(
                                'BMS Pro Black',
                                style: TextStyle(
                                  color: Color(0xFF111111),
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            _fadeSlide(
                              interval: const Interval(0.18, 0.5),
                              yBegin: 0.08,
                              child: const Text(
                                'Workshop Management',
                                style: TextStyle(
                                  color: Color(0xFFADB5BD),
                                  fontSize: 13,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Form ──
                    _fadeSlide(
                      interval: const Interval(0.25, 0.7),
                      yBegin: 0.06,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Welcome Back',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Sign in to continue',
                              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                            ),
                            const SizedBox(height: 32),
                            _buildField(
                              label: 'Email',
                              controller: _emailController,
                              hint: 'you@example.com',
                              icon: Icons.email_outlined,
                              focusNode: _emailFocus,
                              isFocused: _emailFocused,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 20),
                            _buildField(
                              label: 'Password',
                              controller: _passwordController,
                              hint: 'Enter password',
                              icon: Icons.lock_outline_rounded,
                              focusNode: _passwordFocus,
                              isFocused: _passwordFocused,
                              obscure: _obscure,
                              suffixIcon: GestureDetector(
                                onTap: () => setState(() => _obscure = !_obscure),
                                child: Icon(
                                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: const Color(0xFFADB5BD),
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => const ForgotPasswordRequestPage(),
                                  ));
                                },
                                child: const Text(
                                  'Forgot Password?',
                                  style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            _isLoading ? _buildLoadingButton() : _buildSignInButton(),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),

                    _fadeSlide(
                      interval: const Interval(0.6, 1.0),
                      yBegin: 0.04,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 36),
                        child: Text(
                          'Need help? Contact support@bmspro.com',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
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
    );
  }

  Widget _fadeSlide({required Interval interval, required double yBegin, required Widget child}) {
    return SlideTransition(
      position: Tween<Offset>(begin: Offset(0, yBegin), end: Offset.zero).animate(
        CurvedAnimation(parent: _entranceController, curve: Interval(interval.begin, interval.end, curve: Curves.easeOut)),
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _entranceController, curve: interval),
        child: child,
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required FocusNode focusNode,
    required bool isFocused,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isFocused ? const Color(0xFF111111) : const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isFocused ? Colors.white : const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isFocused ? const Color(0xFF1A1A1A) : const Color(0xFFE5E7EB),
              width: isFocused ? 1.8 : 1,
            ),
            boxShadow: isFocused
                ? [BoxShadow(color: const Color(0xFF1A1A1A).withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))]
                : [],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            obscureText: obscure,
            style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
            cursorColor: const Color(0xFF1A1A1A),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFFBFC5CC), fontSize: 14),
              prefixIcon: Icon(icon, color: isFocused ? const Color(0xFF1A1A1A) : const Color(0xFFADB5BD), size: 20),
              suffixIcon: suffixIcon != null ? Padding(padding: const EdgeInsets.only(right: 12), child: suffixIcon) : null,
              suffixIconConstraints: const BoxConstraints(maxHeight: 40, maxWidth: 40),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignInButton() {
    return GestureDetector(
      onTap: _signIn,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [Color(0xFF111111), Color(0xFF2A2A2A)]),
          boxShadow: [BoxShadow(color: const Color(0xFF111111).withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.login_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: const Color(0xFF2A2A2A)),
      child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Mechanics-themed Background Painter
// ═══════════════════════════════════════════════════════════════════════
class _MechanicsBgPainter extends CustomPainter {
  final double time;
  const _MechanicsBgPainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    _drawBlueprintGrid(canvas, size);
    _drawGears(canvas, size);
    _drawWrenchIcons(canvas, size);
  }

  void _drawBlueprintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8ECF0).withOpacity(0.5)
      ..strokeWidth = 0.5;

    const spacing = 50.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Small cross marks at intersections
    final crossPaint = Paint()
      ..color = const Color(0xFFD1D5DB).withOpacity(0.5)
      ..strokeWidth = 1.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), crossPaint);
        canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), crossPaint);
      }
    }
  }

  void _drawGears(Canvas canvas, Size size) {
    final gears = <_GearData>[
      _GearData(size.width * 0.08,  size.height * 0.06, 45, 10, 1.0,  0.10),
      _GearData(size.width * 0.88,  size.height * 0.12, 35, 8,  -1.5, 0.08),
      _GearData(size.width * 0.75,  size.height * 0.42, 55, 12, 0.7,  0.12),
      _GearData(size.width * 0.12,  size.height * 0.50, 40, 9,  -1.2, 0.09),
      _GearData(size.width * 0.92,  size.height * 0.72, 50, 11, 0.9,  0.11),
      _GearData(size.width * 0.05,  size.height * 0.85, 38, 8,  -0.8, 0.08),
      _GearData(size.width * 0.55,  size.height * 0.92, 42, 10, 1.3,  0.10),
      // Interlocking pair near top-right
      _GearData(size.width * 0.70,  size.height * 0.08, 30, 8, 1.0,  0.09),
      _GearData(size.width * 0.70 + 48, size.height * 0.08, 22, 6, -1.33, 0.09),
    ];

    for (final g in gears) {
      _drawSingleGear(canvas, g.cx, g.cy, g.radius, g.teeth, time * g.speed * 2 * math.pi, g.opacity);
    }
  }

  void _drawSingleGear(Canvas canvas, double cx, double cy, double radius, int teeth, double angle, double opacity) {
    final paint = Paint()
      ..color = Color.fromRGBO(156, 163, 175, opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);

    // Outer gear teeth
    final path = Path();
    final innerR = radius * 0.78;
    final outerR = radius;
    final toothWidth = math.pi / teeth;

    for (int i = 0; i < teeth; i++) {
      final a = i * 2 * math.pi / teeth;
      final a1 = a - toothWidth * 0.4;
      final a2 = a - toothWidth * 0.25;
      final a3 = a + toothWidth * 0.25;
      final a4 = a + toothWidth * 0.4;

      if (i == 0) {
        path.moveTo(innerR * math.cos(a1), innerR * math.sin(a1));
      } else {
        path.lineTo(innerR * math.cos(a1), innerR * math.sin(a1));
      }
      path.lineTo(outerR * math.cos(a2), outerR * math.sin(a2));
      path.lineTo(outerR * math.cos(a3), outerR * math.sin(a3));
      path.lineTo(innerR * math.cos(a4), innerR * math.sin(a4));

      // Arc to next tooth
      final nextA = (i + 1) * 2 * math.pi / teeth - toothWidth * 0.4;
      path.arcToPoint(
        Offset(innerR * math.cos(nextA), innerR * math.sin(nextA)),
        radius: Radius.circular(innerR),
        clockwise: true,
      );
    }
    path.close();
    canvas.drawPath(path, paint);

    // Center hole
    canvas.drawCircle(Offset.zero, radius * 0.25, paint);

    // Spokes
    for (int i = 0; i < 3; i++) {
      final sa = i * 2 * math.pi / 3;
      canvas.drawLine(
        Offset(radius * 0.28 * math.cos(sa), radius * 0.28 * math.sin(sa)),
        Offset(radius * 0.55 * math.cos(sa), radius * 0.55 * math.sin(sa)),
        paint,
      );
    }

    canvas.restore();
  }

  void _drawWrenchIcons(Canvas canvas, Size size) {
    final icons = <_IconPos>[
      _IconPos(size.width * 0.40, size.height * 0.04, 0.3, 0.08),
      _IconPos(size.width * 0.25, size.height * 0.30, -0.5, 0.07),
      _IconPos(size.width * 0.85, size.height * 0.55, 0.2, 0.06),
      _IconPos(size.width * 0.45, size.height * 0.70, -0.4, 0.07),
      _IconPos(size.width * 0.15, size.height * 0.92, 0.6, 0.06),
    ];

    for (final ic in icons) {
      _drawWrench(canvas, ic.x, ic.y, 18, time * ic.rotSpeed * 2 * math.pi, ic.opacity);
    }
  }

  void _drawWrench(Canvas canvas, double cx, double cy, double len, double angle, double opacity) {
    final paint = Paint()
      ..color = Color.fromRGBO(156, 163, 175, opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);

    // Handle
    canvas.drawLine(Offset(-len * 0.5, 0), Offset(len * 0.3, 0), paint);

    // Jaw (open-end wrench shape)
    final jaw = Path()
      ..moveTo(len * 0.3, -4)
      ..lineTo(len * 0.55, -5)
      ..moveTo(len * 0.3, 4)
      ..lineTo(len * 0.55, 5);
    canvas.drawPath(jaw, paint);

    // Ring end
    canvas.drawCircle(Offset(-len * 0.55, 0), 5, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MechanicsBgPainter old) => old.time != time;
}

class _GearData {
  final double cx, cy, radius, speed, opacity;
  final int teeth;
  const _GearData(this.cx, this.cy, this.radius, this.teeth, this.speed, this.opacity);
}

class _IconPos {
  final double x, y, rotSpeed, opacity;
  const _IconPos(this.x, this.y, this.rotSpeed, this.opacity);
}
