import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../routes.dart';
import '../services/auth_state_manager.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  final PageController _controller = PageController();
  int _currentPage = 0;

  late AnimationController _floatController;
  late AnimationController _shimmerController;
  late Animation<double> _floatAnimation;

  final List<_OnboardData> _pages = const [
    _OnboardData(
      icon: Icons.build_circle_outlined,
      title: 'Manage Your\nWorkshop',
      subtitle:
          'Streamline appointments, staff scheduling, and client management all in one powerful platform.',
      gradientColors: [Color(0xFF1A1A1A), Color(0xFF333333)],
    ),
    _OnboardData(
      icon: Icons.insights_rounded,
      title: 'Smart\nAnalytics',
      subtitle:
          'Track revenue, monitor performance, and gain actionable insights with real-time dashboards.',
      gradientColors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)],
    ),
    _OnboardData(
      icon: Icons.rocket_launch_rounded,
      title: 'Ready to\nGet Started?',
      subtitle:
          'Join workshops already using BMS Pro Black to grow their business. Set up takes minutes.',
      gradientColors: [Color(0xFF1A1A1A), Color(0xFF444444)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _floatController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _navigateToLogin() async {
    await AuthStateManager.setFirstLaunchComplete();
    await AuthStateManager.setWelcomeSeen();
    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen dark background ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D0D0D), Color(0xFF1A1A1A)],
              ),
            ),
          ),

          // ── Decorative background circles ──
          Positioned(
            top: -120,
            right: -80,
            child: AnimatedBuilder(
              animation: _floatController,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(0, _floatAnimation.value * 0.3),
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(0.04),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: -60,
            left: -100,
            child: AnimatedBuilder(
              animation: _floatController,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(_floatAnimation.value * 0.2, 0),
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(0.03),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Main content ──
          SafeArea(
            child: Column(
              children: [
                // Skip button
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Page counter
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentPage + 1} / ${_pages.length}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _navigateToLogin,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Pages
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) =>
                        setState(() => _currentPage = i),
                    itemBuilder: (context, index) {
                      final data = _pages[index];
                      return _buildPage(data, index);
                    },
                  ),
                ),

                // ── Bottom section: dots + button ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      // Dots indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children:
                            List.generate(_pages.length, (i) {
                          final bool active = i == _currentPage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin:
                                const EdgeInsets.symmetric(horizontal: 4),
                            height: 4,
                            width: active ? 32 : 8,
                            decoration: BoxDecoration(
                              color: active
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 28),

                      // Action button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: isLast
                            ? _buildGetStartedButton()
                            : _buildNextButton(),
                      ),

                      if (!isLast) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => _controller.previousPage(
                            duration:
                                const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          ),
                          child: Text(
                            _currentPage == 0 ? '' : 'Back',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(_OnboardData data, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Animated icon in glassmorphism container ──
          AnimatedBuilder(
            animation: _floatController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _floatAnimation.value),
                child: child,
              );
            },
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.03),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Center(
                child: ShaderMask(
                  shaderCallback: (bounds) {
                    return const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Color(0xFF888888)],
                    ).createShader(bounds);
                  },
                  child: Icon(
                    data.icon,
                    size: 72,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 48),

          // ── Title with shimmer ──
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              return ShaderMask(
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: const [
                      Colors.white70,
                      Colors.white,
                      Colors.white70,
                    ],
                    stops: [
                      (_shimmerController.value - 0.3).clamp(0.0, 1.0),
                      _shimmerController.value.clamp(0.0, 1.0),
                      (_shimmerController.value + 0.3).clamp(0.0, 1.0),
                    ],
                  ).createShader(bounds);
                },
                child: Text(
                  data.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),

          // ── Subtitle ──
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Colors.white.withOpacity(0.55),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _controller.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Next',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white.withOpacity(0.7),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGetStartedButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _navigateToLogin,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFE0E0E0)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Get Started',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFF1A1A1A),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  const _OnboardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
  });
}
