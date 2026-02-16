import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../routes.dart';
import 'forgot_password_request.dart';
import '../widgets/primary_gradient_button.dart';
import '../services/audit_log_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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
      // 1. Authenticate with Firebase Auth
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

      // 2. Fetch user details from Firestore "users" collection
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
      // Robust role retrieval
      final rawRole = userData['role'];
      final String userRole = rawRole != null ? rawRole.toString().trim() : 'unknown';

      // 3. Validate Role
      bool isAuthorized = false;
      
      // Allowed roles: staff, workshop_owner, branch_admin
      const allowedRoles = ['staff', 'workshop_owner', 'branch_admin'];
      
      if (allowedRoles.contains(userRole)) {
         isAuthorized = true;
      }

      if (!isAuthorized) {
        await FirebaseAuth.instance.signOut();
        throw FirebaseAuthException(
            code: 'permission-denied',
            message: 'Access denied. Role "$userRole" is not authorized.');
      }

      // Log successful login
      final ownerUid = userData['ownerUid'] ?? user.uid;
      final userName = userData['displayName'] ?? userData['name'] ?? user.email ?? 'Unknown';
      
      // Include branch information for branch admins
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color accent = Theme.of(context).colorScheme.secondary;
    const Color background = Color(0xFFFFF5FA);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Logo and title
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOut,
                            tween: Tween(begin: 0, end: 1),
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - value) * 20),
                                  child: child,
                                ),
                              );
                            },
                            child: Column(
                              children: [
                                const SizedBox(height: 12),
                                Container(
                                  width: 84,
                                  height: 84,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: primary.withOpacity(0.15),
                                        blurRadius: 30,
                                        offset: const Offset(0, 12),
                                      )
                                    ],
                                  ),
                                  child: Center(
                                    child: Image.asset(
                                      'assets/icons/bmsblack-icon.jpeg',
                                      width: 64,
                                      height: 64,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'BMS Pro Black',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF1A1A1A),
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: 48,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(99),
                                    gradient: LinearGradient(
                                      colors: [primary, accent],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Card
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOut,
                            tween: Tween(begin: 0, end: 1),
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - value) * 40),
                                  child: child,
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: primary.withOpacity(0.08),
                                    blurRadius: 40,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Header
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: const [
                                      Text(
                                        'Welcome Back',
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1A1A1A),
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'Manage bookings, staff & clients with ease',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Color(0xFF9E9E9E),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 16),

                                  // Email
                                  _FocusGlow(
                                    glowColor: primary.withOpacity(0.10),
                                    child: TextField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(
                                        labelText: 'Email Address',
                                        hintText: 'Enter your email',
                                        prefixIcon: Icon(Icons.email_outlined,
                                            color: Color(0xFF9E9E9E)),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // Password
                                  _FocusGlow(
                                    glowColor: primary.withOpacity(0.10),
                                    child: TextField(
                                      controller: _passwordController,
                                      obscureText: _obscure,
                                      decoration: InputDecoration(
                                        labelText: 'Password',
                                        hintText: 'Enter your password',
                                        prefixIcon: const Icon(
                                            Icons.lock_outline,
                                            color: Color(0xFF9E9E9E)),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(
                                              () => _obscure = !_obscure),
                                          icon: Icon(_obscure
                                              ? Icons.visibility
                                              : Icons.visibility_off),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const ForgotPasswordRequestPage(),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        'Forgot Password?',
                                        style: TextStyle(
                                          color: primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // Gradient Sign In Button
                                  _isLoading
                                      ? Center(
                                          child: CircularProgressIndicator(
                                              color: primary))
                                      : PrimaryGradientButton(
                                          label: 'Sign In',
                                          onTap: _signIn,
                                        ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Bottom text
                          Column(
                            children: [
                              const SizedBox(height: 6),
                              const Text(
                                'Need help? Contact support@bmspro.com',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Color(0xFF9E9E9E), fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Wrapper to route to Register using named route while showing push usage
// removed registration class


class _FocusGlow extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  const _FocusGlow({required this.child, required this.glowColor});

  @override
  State<_FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<_FocusGlow> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: widget.glowColor,
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: const Offset(0, 0),
                )
              ]
            : null,
      ),
      child: Focus(
        onFocusChange: (v) => setState(() => _focused = v),
        child: widget.child,
      ),
    );
  }
}
