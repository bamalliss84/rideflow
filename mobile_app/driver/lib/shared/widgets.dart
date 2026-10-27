import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../core/api/api_exception.dart';

String errorMessage(BuildContext context, Object error) {
  final t = AppLocalizations.of(context);
  if (error is! ApiException) return t.errorTitle;
  return switch (error.code) {
    'network' => t.errorNetwork,
    'not_authenticated' => t.errorSessionExpired,
    'throttled' => t.errorThrottled,
    'service_unavailable' => t.errorUnavailable,
    'invalid' => t.errorValidation,
    'otp_invalid' || 'otp_expired' || 'otp_locked' => t.invalidCode,
    _ when error.status == 403 => t.errorForbidden,
    _ when error.status == 409 => t.errorConflict,
    _ when error.status >= 500 => t.errorServer,
    _ => (error.detail is String ? error.detail as String : t.errorTitle),
  };
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? Brand.coral : Brand.navy));
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final network = error is ApiException && (error as ApiException).isNetwork;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Brand.coralSoft,
            child: Icon(network ? Icons.wifi_off_rounded : Icons.error_outline_rounded, color: Brand.coral),
          ),
          const SizedBox(height: 12),
          Text(t.errorTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(errorMessage(context, error), textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(t.retry)),
          ],
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: Brand.muted),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
        ]),
      );
}

/// Renders an AsyncValue with consistent loading / error(+retry) states.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: onRetry),
        skipLoadingOnRefresh: true,
      );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.title, this.trailing, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  if (trailing != null) trailing!,
                ]),
              ),
            child,
          ]),
        ),
      );
}

enum Tone { neutral, success, warning, danger, info }

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = Tone.neutral});
  final String label;
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      Tone.success => (Brand.tealSoft, Brand.teal700),
      Tone.warning => (Brand.amberSoft, const Color(0xFF82511A)),
      Tone.danger => (Brand.coralSoft, Brand.coral),
      Tone.info => (const Color(0xFFE3E9F1), Brand.navy700),
      Tone.neutral => (Brand.surface, Brand.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Tone toneFor(String status) => switch (status) {
      'approved' || 'active' || 'completed' || 'selected' || 'accepted' => Tone.success,
      'open' || 'pending' || 'pending_documents' || 'under_review' || 'submitted' || 'first_approved' || 'match_pending' || 'bidding' => Tone.warning,
      'rejected' || 'suspended' || 'cancelled' || 'no_show' || 'disputed' || 'lost' || 'expired' || 'declined' || 'withdrawn' => Tone.danger,
      'assigned' || 'en_route' || 'arrived' || 'in_progress' => Tone.info,
      _ => Tone.neutral,
    };

/// Text that must read left-to-right inside Arabic (phones, plates, amounts, codes).
class Ltr extends StatelessWidget {
  const Ltr(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.ltr, child: Text(text, style: style));
}

/// Runs an async action once at a time (prevents double taps -> duplicate bids/transitions) and reports errors.
class ActionRunner {
  bool _busy = false;
  bool get busy => _busy;
  Future<bool> run(BuildContext context, Future<void> Function() action, {VoidCallback? onChanged, String? success}) async {
    if (_busy) return false;
    _busy = true;
    onChanged?.call();
    try {
      await action();
      if (success != null && context.mounted) showMessage(context, success);
      return true;
    } catch (e) {
      if (context.mounted) showMessage(context, errorMessage(context, e), error: true);
      return false;
    } finally {
      _busy = false;
      onChanged?.call();
    }
  }
}

extension RefRetry on WidgetRef {
  VoidCallback retry(ProviderOrFamily p) => () => invalidate(p);
}
