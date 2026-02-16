import 'package:flutter/material.dart';

class AnimatedToggle extends StatelessWidget {
  final List<String> values;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color? backgroundColor;
  final Color? indicatorColor;
  final Color? textColor;
  final Color? selectedTextColor;

  const AnimatedToggle({
    super.key,
    required this.values,
    required this.selectedIndex,
    required this.onChanged,
    this.backgroundColor,
    this.indicatorColor,
    this.textColor,
    this.selectedTextColor,
  });

  @override
  Widget build(BuildContext context) {
    // Default colors if not provided
    final bg = backgroundColor ?? const Color(0xFFF1F3F5);
    final indicator = indicatorColor ?? const Color(0xFF1A1A1A);
    final txt = textColor ?? const Color(0xFF6B7280);
    final selectedTxt = selectedTextColor ?? Colors.white;

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double itemWidth = (constraints.maxWidth - 4) / values.length; // accounting for padding
          
          return Stack(
            children: [
              // Sliding Indicator
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  -1.0 + (selectedIndex * 2.0 / (values.length - 1)),
                  0.0,
                ),
                child: Container(
                  width: itemWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: indicator,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: indicator.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              // Text Labels
              Row(
                children: List.generate(values.length, (index) {
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(index),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontFamily: 'Inter', // Assuming app uses Inter or system font
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: selectedIndex == index ? selectedTxt : txt,
                          ),
                          child: Text(values[index]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

