import 'package:flutter/material.dart';

class PinkBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<IconData> icons;
  const PinkBottomNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    this.icons = const <IconData>[
      Icons.home_rounded,
      Icons.calendar_month_rounded,
      Icons.groups_rounded, // Clients (3rd)
      Icons.bar_chart_rounded,
      Icons.person_rounded,
    ],
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(0.18),
                blurRadius: 24,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final double barWidth = constraints.maxWidth;
            final double slotWidth = barWidth / icons.length;

            return Stack(
              children: [
                // Icons row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(icons.length, (i) {
                    final bool selected = i == currentIndex;
                    return SizedBox(
                      width: slotWidth,
                      height: 78,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => onChanged(i),
                          child: Center(
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 160),
                              scale: selected ? 1.12 : 1.0,
                              child: Icon(
                                icons[i],
                                size: 30,
                                color: selected
                                    ? primary
                                    : const Color(0xFF9E9E9E),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
