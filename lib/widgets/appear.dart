import 'package:flutter/material.dart';

/// Fades and slides [child] up the first time it is built. A higher [index]
/// starts a little later, so a column of cards arrives one after another.
class Appear extends StatelessWidget {
  const Appear({super.key, this.index = 0, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = 60 * index;
    final total = 420 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
