import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/glass.dart';

class LiquidGlassTabItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const LiquidGlassTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// A floating capsule tab bar in the style of Apple's Liquid Glass (iOS 26):
/// heavy backdrop blur, a translucent tinted fill lit from the top-left, a
/// specular gradient rim, soft drop shadow, and a morphing selection pill that
/// glides between destinations. Content is expected to scroll underneath
/// (pair with `Scaffold.extendBody: true`).
class LiquidGlassTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<LiquidGlassTabItem> items;

  const LiquidGlassTabBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dark = glass.brightness == Brightness.dark;

    final fill = dark
        ? glass.tint.withValues(alpha: 0.52)
        : Colors.white.withValues(alpha: 0.62);
    final highlight = dark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.75);
    // Specular rim: bright where light "hits" (top-left), fading below.
    final rimTop = dark
        ? Colors.white.withValues(alpha: 0.30)
        : Colors.white.withValues(alpha: 0.95);
    final rimBottom = dark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.05);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [rimTop, rimBottom],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.34 : 0.14),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          // 1px padding lets the gradient behind read as a specular rim.
          padding: const EdgeInsets.all(1),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(31),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.alphaBlend(highlight, fill), fill],
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final slotWidth = constraints.maxWidth / items.length;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          left: slotWidth * currentIndex + 6,
                          top: 6,
                          bottom: 6,
                          width: slotWidth - 12,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              color: scheme.primary.withValues(
                                alpha: dark ? 0.26 : 0.16,
                              ),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: 0.28),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < items.length; i++)
                              Expanded(child: _buildItem(context, i)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    final item = items[index];
    final selected = index == currentIndex;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () {
          if (!selected) {
            HapticFeedback.selectionClick();
            onSelected(index);
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.selectedIcon : item.icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
