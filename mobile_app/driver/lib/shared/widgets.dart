import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_exception.dart';
import '../design/components.dart';
import '../design/tokens.dart';

export '../design/components.dart' show Ltr, Tone, toneFor;

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

void showMessage(BuildContext context, String text, {bool error = false}) => showToast(context, text, error: error);

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.all(RfSpace.md), child: SkeletonList());
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final network = error is ApiException && (error as ApiException).isNetwork;
    return EmptyState(
      icon: network ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: t.errorTitle,
      message: errorMessage(context, error),
      action: onRetry == null ? null : RfButton(label: t.retry, icon: Icons.refresh_rounded, kind: RfButtonKind.secondary, expand: false, onPressed: onRetry),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => EmptyState(title: text, icon: icon);
}

/// Renders an AsyncValue with consistent loading (skeleton) / error(+retry) states.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, this.onRetry, this.loading});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;
  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => loading ?? const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: onRetry),
        skipLoadingOnRefresh: true,
      );
}

/// Titled card section (design-system card).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.title, this.trailing, this.padding = const EdgeInsets.all(RfSpace.md)});
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => RfCard(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: RfSpace.sm),
              child: Row(children: [Expanded(child: Text(title!, style: RfType.h3)), if (trailing != null) trailing!]),
            ),
          child,
        ]),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = Tone.neutral});
  final String label;
  final Tone tone;
  @override
  Widget build(BuildContext context) => StatusPill(label, tone: tone);
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
