import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

// ---------------------------------------------------------------- buttons

enum RfButtonKind { primary, go, danger, secondary, ghost, onInk }

/// One button component for the whole app: fixed heights, loading state, disabled state, optional icon.
class RfButton extends StatelessWidget {
  const RfButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = RfButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final RfButtonKind kind;
  final IconData? icon;
  final bool loading, expand, large;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      RfButtonKind.primary => (RfColors.ink, RfColors.onInk, null),
      RfButtonKind.go => (RfColors.teal, Colors.white, null),
      RfButtonKind.danger => (RfColors.coral, Colors.white, null),
      RfButtonKind.secondary => (RfColors.surface, RfColors.text, RfColors.lineStrong),
      RfButtonKind.ghost => (Colors.transparent, RfColors.tealDeep, null),
      RfButtonKind.onInk => (RfColors.onInk, RfColors.ink, null),
    };
    final disabled = onPressed == null || loading;
    final child = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (loading)
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
      else ...[
        if (icon != null) ...[Icon(icon, size: 22, color: fg), const SizedBox(width: 10)],
        Flexible(child: Text(label, style: RfType.cta.copyWith(color: fg, fontSize: large ? 18 : 16), overflow: TextOverflow.ellipsis)),
      ],
    ]);
    final button = Material(
      color: disabled && kind != RfButtonKind.ghost ? bg.withOpacity(0.45) : bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RfRadius.md),
        side: border == null ? BorderSide.none : BorderSide(color: border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(RfRadius.md),
        onTap: disabled ? null : onPressed,
        child: Container(
          height: large ? 60 : 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
    return Semantics(button: true, enabled: !disabled, label: label, child: expand ? SizedBox(width: double.infinity, child: button) : button);
  }
}

// ---------------------------------------------------------------- surfaces

class RfCard extends StatelessWidget {
  const RfCard({super.key, required this.child, this.padding = const EdgeInsets.all(RfSpace.md), this.onTap, this.color, this.border});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;
  @override
  Widget build(BuildContext context) => Material(
        color: color ?? RfColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RfRadius.lg),
          side: BorderSide(color: border ?? RfColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(RfRadius.lg),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: RfSpace.lg, bottom: RfSpace.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: RfType.h3),
              if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: RfType.caption)],
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

// ---------------------------------------------------------------- status

enum Tone { neutral, success, warning, danger, info, dark }

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = Tone.neutral, this.icon, this.dot = false});
  final String label;
  final Tone tone;
  final IconData? icon;
  final bool dot;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(RfRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) Container(width: 8, height: 8, margin: const EdgeInsetsDirectional.only(end: 6), decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Flexible(child: Text(label, style: RfType.caption.copyWith(color: fg, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

(Color, Color) toneColors(Tone tone) => switch (tone) {
      Tone.success => (RfColors.tealSoft, RfColors.tealDeep),
      Tone.warning => (RfColors.amberSoft, RfColors.amberDeep),
      Tone.danger => (RfColors.coralSoft, RfColors.coralDeep),
      Tone.info => (RfColors.blueSoft, const Color(0xFF1D4ED8)),
      Tone.dark => (RfColors.ink, RfColors.onInk),
      Tone.neutral => (RfColors.surfaceSunken, RfColors.textMuted),
    };

Tone toneFor(String status) => switch (status) {
      'approved' || 'active' || 'completed' || 'selected' || 'accepted' => Tone.success,
      'open' || 'pending' || 'pending_documents' || 'under_review' || 'submitted' || 'first_approved' || 'match_pending' || 'bidding' => Tone.warning,
      'rejected' || 'suspended' || 'cancelled' || 'no_show' || 'disputed' || 'lost' || 'expired' || 'declined' || 'withdrawn' => Tone.danger,
      'assigned' || 'en_route' || 'arrived' || 'in_progress' => Tone.info,
      _ => Tone.neutral,
    };

// ---------------------------------------------------------------- route

/// Pickup -> drop-off with a connector line. Long Arabic names wrap instead of being cut.
class RouteStops extends StatelessWidget {
  const RouteStops({super.key, required this.pickupLabel, required this.pickup, required this.dropoffLabel, required this.dropoff, this.dense = false, this.onInk = false});
  final String pickupLabel, pickup, dropoffLabel, dropoff;
  final bool dense, onInk;
  @override
  Widget build(BuildContext context) {
    final main = (dense ? RfType.bodyStrong : RfType.h3).copyWith(color: onInk ? RfColors.onInk : RfColors.text);
    final cap = RfType.caption.copyWith(color: onInk ? RfColors.onInkMuted : RfColors.textMuted);
    Widget stop(Widget marker, String label, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 22, child: Padding(padding: const EdgeInsets.only(top: 3), child: marker)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: cap),
              const SizedBox(height: 1),
              Text(text.isEmpty ? '—' : text, style: main, softWrap: true),
            ]),
          ),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      stop(Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RfColors.teal, width: 4))), pickupLabel, pickup),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 10, top: 2, bottom: 2),
        child: Container(width: 2, height: dense ? 14 : 20, color: onInk ? RfColors.ink3 : RfColors.line),
      ),
      stop(Container(width: 14, height: 14, decoration: BoxDecoration(color: onInk ? RfColors.amber : RfColors.ink, borderRadius: BorderRadius.circular(3))), dropoffLabel, dropoff),
    ]);
  }
}

// ---------------------------------------------------------------- money / numbers

/// Amount always rendered left-to-right ("1,500 YER") even inside Arabic text.
class MoneyText extends StatelessWidget {
  const MoneyText(this.value, {super.key, this.style});
  final String value;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.ltr, child: Text(value, style: style ?? RfType.number, maxLines: 1, overflow: TextOverflow.ellipsis));
}

class Ltr extends StatelessWidget {
  const Ltr(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.ltr, child: Text(text, style: style));
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, this.icon, this.onInk = false});
  final String label, value;
  final IconData? icon;
  final bool onInk;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: onInk ? RfColors.onInkMuted : RfColors.textMuted), const SizedBox(width: 6)],
          Flexible(child: Text(label, style: RfType.caption.copyWith(color: onInk ? RfColors.onInkMuted : RfColors.textMuted))),
        ]),
        const SizedBox(height: 4),
        MoneyText(value, style: RfType.number.copyWith(fontSize: 20, color: onInk ? RfColors.onInk : RfColors.text)),
      ]);
}

// ---------------------------------------------------------------- sheets

/// Keyboard-safe, scrollable bottom sheet body with a pinned primary action.
class RfSheet extends StatelessWidget {
  const RfSheet({super.key, required this.title, this.subtitle, required this.body, this.action});
  final String title;
  final String? subtitle;
  final List<Widget> body;
  final Widget? action;

  static Future<T?> show<T>(BuildContext context, Widget sheet) => showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => sheet,
      );

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: insets),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(RfSpace.lg, 0, RfSpace.lg, RfSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: RfType.h2),
                if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: RfType.caption)],
                const SizedBox(height: RfSpace.lg),
                ...body,
              ]),
            ),
          ),
          if (action != null)
            Container(
              padding: const EdgeInsets.fromLTRB(RfSpace.lg, RfSpace.sm, RfSpace.lg, RfSpace.md),
              decoration: const BoxDecoration(color: RfColors.surface, border: Border(top: BorderSide(color: RfColors.line))),
              child: action,
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- states

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: RfSpace.xxl, horizontal: RfSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: RfColors.surfaceSunken, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: RfColors.textMuted),
          ),
          const SizedBox(height: RfSpace.sm),
          Text(title, style: RfType.bodyStrong, textAlign: TextAlign.center),
          if (message != null) ...[const SizedBox(height: 4), Text(message!, style: RfType.caption, textAlign: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: RfSpace.md), action!],
        ]),
      );
}

class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = RfRadius.sm});
  final double height;
  final double? width;
  final double radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(widget.radius)),
        ),
      );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.height = 112});
  final int count;
  final double height;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < count; i++) Padding(padding: const EdgeInsets.only(bottom: RfSpace.sm), child: Skeleton(height: height, radius: RfRadius.lg)),
      ]);
}

/// Inline banner for warnings/errors with an optional action (never a silent failure).
class Banner2 extends StatelessWidget {
  const Banner2({super.key, required this.text, this.tone = Tone.warning, this.icon, this.actionLabel, this.onAction, this.title});
  final String text;
  final String? title;
  final Tone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(tone);
    return Container(
      padding: const EdgeInsets.all(RfSpace.md),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(RfRadius.lg)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon ?? Icons.info_outline_rounded, color: fg),
        const SizedBox(width: RfSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) Text(title!, style: RfType.bodyStrong.copyWith(color: fg)),
            Text(text, style: RfType.body.copyWith(color: tone == Tone.dark ? RfColors.onInk : RfColors.text)),
            if (actionLabel != null) ...[
              const SizedBox(height: RfSpace.xs),
              GestureDetector(onTap: onAction, child: Text(actionLabel!, style: RfType.bodyStrong.copyWith(color: fg, decoration: TextDecoration.underline))),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- countdown / stages

/// Ring countdown to [deadline]; calls [onExpired] once.
class CountdownRing extends StatefulWidget {
  const CountdownRing({super.key, required this.deadline, required this.total, required this.unitLabel, this.onExpired, this.size = 132});
  final DateTime deadline;
  final String unitLabel;
  final Duration total;
  final VoidCallback? onExpired;
  final double size;
  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing> {
  late Timer _t;
  bool _fired = false;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_fired && _remaining == Duration.zero) {
        _fired = true;
        widget.onExpired?.call();
      }
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  Duration get _remaining {
    final r = widget.deadline.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  @override
  Widget build(BuildContext context) {
    final r = _remaining;
    final frac = widget.total.inMilliseconds == 0 ? 0.0 : (r.inMilliseconds / widget.total.inMilliseconds).clamp(0.0, 1.0);
    final urgent = r.inSeconds <= 15;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size.square(widget.size), painter: _RingPainter(frac, urgent ? RfColors.coral : RfColors.amber)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Ltr('${r.inSeconds}', style: RfType.display.copyWith(color: RfColors.onInk, fontSize: 40)),
          Text(widget.unitLabel, style: RfType.caption.copyWith(color: RfColors.onInkMuted)),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac, this.color);
  final double frac;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.075;
    final base = Paint()
      ..color = RfColors.ink3
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect.deflate(stroke / 2), 0, math.pi * 2, false, base);
    canvas.drawArc(rect.deflate(stroke / 2), -math.pi / 2, math.pi * 2 * frac, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.frac != frac || old.color != color;
}

/// Horizontal trip stage indicator (reading direction aware).
class StageStepper extends StatelessWidget {
  const StageStepper({super.key, required this.labels, required this.current});
  final List<String> labels;
  final int current;
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Column(children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: i <= current ? RfColors.teal : RfColors.line,
                  borderRadius: BorderRadius.circular(RfRadius.pill),
                ),
              ),
              const SizedBox(height: 6),
              Text(labels[i],
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: RfType.caption.copyWith(
                    fontSize: 11.5,
                    color: i == current ? RfColors.text : RfColors.textMuted,
                    fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                  )),
            ]),
          ),
          if (i < labels.length - 1) const SizedBox(width: 6),
        ],
      ]);
}

void showToast(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: error ? RfColors.coral : RfColors.teal),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: RfType.body.copyWith(color: RfColors.onInk))),
      ]),
    ));
}
