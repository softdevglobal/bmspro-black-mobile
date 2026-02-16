import 'package:flutter/material.dart';
import '../routes.dart';
import '../widgets/primary_gradient_button.dart';
import '../services/auth_state_manager.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<_OnboardData> _pages = const [
    _OnboardData(
      icon: Icons.spa,
      title: 'Beauty, Simplified',
      subtitle: 'Manage appointments and staff with ease in a clean, modern UI.',
    ),
    _OnboardData(
      icon: Icons.brush_rounded,
      title: 'Delightful Experience',
      subtitle: 'Beautiful pink & purple theme with smooth, responsive layouts.',
    ),
    _OnboardData(
      icon: Icons.event_available_rounded,
      title: 'Ready to Start?',
      subtitle: 'Get started to explore the app. No account setup required yet.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color accent = Theme.of(context).colorScheme.secondary;
    const Color background = Color(0xFFFFF5FA);
    final bool isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final data = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 24),
                        // "Image" area - app icon inside rounded card
                        Container(
                          height: MediaQuery.of(context).size.height * 0.33,
                          alignment: Alignment.center,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: primary.withOpacity(0.25),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                )
                              ],
                            ),
                            child: Center(
                              child: Image.asset(
                                'assets/icons/bmspink-icon.jpeg',
                                width: 140,
                                height: 140,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          data.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          data.subtitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final bool active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: active ? 24 : 8,
                  decoration: BoxDecoration(
                    color: active ? primary : primary.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  // Optional: Back or Skip
                  TextButton(
                    onPressed: _currentPage == 0
                        ? () async {
                            // Mark first launch as complete when skipping
                            await AuthStateManager.setFirstLaunchComplete();
                            await AuthStateManager.setWelcomeSeen();
                            if (mounted) {
                              Navigator.pushReplacementNamed(context, AppRoutes.login);
                            }
                          }
                        : () => _controller.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            ),
                    child: Text(
                      _currentPage == 0 ? 'Skip' : 'Back',
                      style: TextStyle(color: primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  if (!isLast)
                    OutlinedButton(
                      onPressed: () => _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('Next'),
                    ),
                  if (isLast)
                    PrimaryGradientButton(
                      label: 'Get Started',
                      width: 160,
                      height: 48,
                      onTap: () async {
                        // Mark first launch as complete and welcome as seen
                        await AuthStateManager.setFirstLaunchComplete();
                        await AuthStateManager.setWelcomeSeen();
                        if (mounted) {
                          Navigator.pushReplacementNamed(context, AppRoutes.login);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardData {
  final IconData icon;
  final String title;
  final String subtitle;
  const _OnboardData({required this.icon, required this.title, required this.subtitle});
}


