import 'package:flutter/material.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<IconData> icons;
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    this.icons = const <IconData>[
      Icons.home_rounded,
      Icons.calendar_month_rounded,
      Icons.groups_rounded,
      Icons.bar_chart_rounded,
      Icons.person_rounded,
    ],
  });

  @override
  Widget build(BuildContext context) {
    const Color activeColor = Color(0xFF1A1A1A);
    const Color inactiveColor = Color(0xFFB0B0B0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 40,
                offset: const Offset(0, -8),
              ),
            ],
            border: Border.all(
              color: const Color(0xFFE8E8E8).withOpacity(0.6),
              width: 1,
            ),
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final double barWidth = constraints.maxWidth;
            final double slotWidth = barWidth / icons.length;

            return Stack(
              alignment: Alignment.center,
              children: [
                // ── Small dot under selected icon ──
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: (currentIndex * slotWidth) +
                      (slotWidth / 2) -
                      3,
                  bottom: 10,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: activeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                // ── Icons row ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(icons.length, (i) {
                    final bool selected = i == currentIndex;
                    return SizedBox(
                      width: slotWidth,
                      height: 72,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => onChanged(i),
                          child: Center(
                            child: AnimatedScale(
                              duration:
                                  const Duration(milliseconds: 200),
                              scale: selected ? 1.1 : 1.0,
                              child: Icon(
                                icons[i],
                                size: 26,
                                color: selected
                                    ? activeColor
                                    : inactiveColor,
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
