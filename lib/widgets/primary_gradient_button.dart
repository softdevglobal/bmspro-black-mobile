import 'package:flutter/material.dart';

class PrimaryGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double height;
  final double? width;
  final IconData? leadingIcon;

  const PrimaryGradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 52,
    this.width,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color accent = Theme.of(context).colorScheme.secondary;

    final Widget content = SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [primary, accent]),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(0.25),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leadingIcon != null) ...[
                    Icon(leadingIcon, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return content;
  }
}
