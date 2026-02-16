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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 30,
                offset: const Offset(0, -4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 60,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final double barWidth = constraints.maxWidth;
            final double slotWidth = barWidth / icons.length;

            return Stack(
              alignment: Alignment.center,
              children: [
                // ── Glowing dot under selected ──
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
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
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
                      height: 78,
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
                              child: AnimatedOpacity(
                                duration:
                                    const Duration(milliseconds: 200),
                                opacity: selected ? 1.0 : 0.45,
                                child: Icon(
                                  icons[i],
                                  size: 26,
                                  color: Colors.white,
                                ),
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
