import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Rings spreading from a flag at the destination once the trip is over. Still when the phone asks for less motion.
class ArrivedFlag extends StatefulWidget {
  const ArrivedFlag({super.key});
  @override
  State<ArrivedFlag> createState() => _ArrivedFlagState();
}

class _ArrivedFlagState extends State<ArrivedFlag> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _ring(double delay) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final v = (_c.value + delay) % 1;
          return Transform.scale(
            scale: 0.45 + 0.55 * v,
            child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RfColors.teal.withOpacity(0.8 * (1 - v)), width: 2))),
          );
        },
      );

  @override
  Widget build(BuildContext context) => Stack(key: const Key('arrivedFlag'), alignment: Alignment.center, children: [
        Positioned.fill(child: _ring(0)),
        Positioned.fill(child: _ring(0.5)),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: RfColors.teal, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)]),
          child: Icon(Icons.flag_rounded, color: RfColors.canvas, size: 22),
        ),
      ]);
}
