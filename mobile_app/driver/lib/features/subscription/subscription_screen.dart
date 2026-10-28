import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart' show ActionRunner, AsyncBody, RefRetry, errorMessage;

/// Everything here comes from the operator's configuration (plans, prices, accounts, discount): nothing is
/// hardcoded in the app.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final units = me?.minorUnits ?? 2;
    final currency = me?.currency ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(t.subscriptionTitle)),
      body: AsyncBody<SubscriptionOverview>(
        value: ref.watch(subscriptionProvider),
        onRetry: ref.retry(subscriptionProvider),
        data: (s) {
          final paid = s.plans.where((p) => !p.isTrial).toList();
          final trial = s.plans.where((p) => p.isTrial).firstOrNull;
          final pending = s.recentClaims.where((c) => c.status == 'submitted' || c.status == 'first_approved').firstOrNull;
          final lastRejected = s.recentClaims.isNotEmpty && s.recentClaims.first.status == 'rejected' ? s.recentClaims.first : null;
          final canPay = s.accounts.isNotEmpty && paid.isNotEmpty;
          void pay([Plan? plan]) => RfSheet.show<void>(context, _DepositForm(overview: s, plan: plan, minorUnits: units, currency: currency));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(subscriptionProvider),
            child: ListView(padding: const EdgeInsets.all(RfSpace.md), children: [
              _Summary(overview: s),
              if (pending != null) ...[
                const SizedBox(height: RfSpace.sm),
                Banner2(
                  title: t.pendingReceipt,
                  text: '${formatMoney(pending.amountMinor, pending.currency, units)} · ${pending.reference}',
                  tone: Tone.info,
                  icon: Icons.hourglass_top_rounded,
                ),
              ],
              if (lastRejected != null && pending == null) ...[
                const SizedBox(height: RfSpace.sm),
                Banner2(
                  text: t.rejectedReceipt(lastRejected.decisionNote.isEmpty ? '—' : lastRejected.decisionNote),
                  tone: Tone.danger,
                  icon: Icons.error_outline_rounded,
                  actionLabel: canPay ? t.submitDeposit : null,
                  onAction: canPay ? pay : null,
                ),
              ],
              if (!s.entitled && trial != null) ...[
                const SizedBox(height: RfSpace.md),
                _TrialCard(plan: trial),
              ],
              const SizedBox(height: RfSpace.lg),
              SectionHeader(s.entitled ? t.renew : t.selectPlan),
              for (final p in paid)
                Padding(
                  padding: const EdgeInsets.only(bottom: RfSpace.sm),
                  child: _PlanCard(
                    plan: p,
                    price: formatMoney(p.priceMinor, currency, units),
                    current: s.entitled && p.name == s.currentPlanName,
                    onPay: canPay && pending == null ? () => pay(p) : null,
                  ),
                ),
              if (paid.isEmpty) EmptyState(icon: Icons.workspace_premium_outlined, title: t.plansTitle, message: t.emptyTitle),
              if (s.renewalDiscountPct > 0) Text('${t.renew}: −${s.renewalDiscountPct}%', style: RfType.caption),
              const SizedBox(height: RfSpace.lg),
              SectionHeader(t.depositAccounts, subtitle: t.depositIntro),
              for (final a in s.accounts) _AccountCard(account: a),
              if (s.accounts.isEmpty) EmptyState(icon: Icons.account_balance_outlined, title: t.depositAccounts, message: t.emptyTitle),
              const SizedBox(height: RfSpace.lg),
              SectionHeader(t.claimsTitle),
              if (s.recentClaims.isEmpty)
                EmptyState(icon: Icons.receipt_outlined, title: t.emptyTitle)
              else
                RfCard(
                  padding: const EdgeInsets.symmetric(horizontal: RfSpace.md, vertical: RfSpace.xs),
                  child: Column(children: [
                    for (final c in s.recentClaims)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: RfSpace.xs),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              MoneyText(formatMoney(c.amountMinor, c.currency, units), style: RfType.bodyStrong),
                              Text([c.reference, c.depositedOn].join(' · '), style: RfType.caption),
                              if (c.decisionNote.isNotEmpty) Text(c.decisionNote, style: RfType.caption.copyWith(color: RfColors.coralDeep)),
                            ]),
                          ),
                          StatusPill(claimStatusLabel(t, c.status), tone: toneFor(c.status)),
                        ]),
                      ),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.overview});
  final SubscriptionOverview overview;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = overview;
    final ends = s.endsAt;
    final days = ends == null ? null : (ends.difference(DateTime.now()).inHours / 24).ceil().clamp(0, 9999);
    return Container(
      padding: const EdgeInsets.all(RfSpace.lg),
      decoration: BoxDecoration(
        color: s.entitled ? RfColors.ink : RfColors.amberSoft,
        borderRadius: BorderRadius.circular(RfRadius.xl),
        boxShadow: RfShadow.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(s.entitled ? Icons.verified_rounded : Icons.warning_amber_rounded, color: s.entitled ? RfColors.teal : RfColors.amberDeep),
          const SizedBox(width: RfSpace.xs),
          Expanded(child: Text(t.currentPlan, style: RfType.label.copyWith(color: s.entitled ? RfColors.onInkMuted : RfColors.amberDeep))),
          if (s.currentSource == 'trial') StatusPill(t.trialBadge, tone: Tone.info),
        ]),
        const SizedBox(height: RfSpace.sm),
        if (s.entitled) ...[
          Text(s.currentPlanName ?? '', style: RfType.h1.copyWith(color: RfColors.onInk)),
          const SizedBox(height: RfSpace.xs),
          if (days != null)
            Text(t.daysRemaining('$days'), key: const Key('daysRemaining'), style: RfType.number.copyWith(color: days <= 3 ? RfColors.amber : RfColors.teal)),
          const SizedBox(height: 2),
          Text(t.subscriptionActive(formatDate(ends)), style: RfType.caption.copyWith(color: RfColors.onInkMuted)),
          if (days != null && ends != null) ...[
            const SizedBox(height: RfSpace.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(RfRadius.pill),
              child: LinearProgressIndicator(
                value: (days / 30).clamp(0.04, 1.0),
                minHeight: 6,
                backgroundColor: RfColors.ink3,
                color: days <= 3 ? RfColors.amber : RfColors.teal,
              ),
            ),
          ],
        ] else
          Text(t.subscriptionInactive, style: RfType.bodyStrong.copyWith(color: RfColors.amberDeep)),
      ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.price, required this.current, required this.onPay});
  final Plan plan;
  final String price;
  final bool current;
  final VoidCallback? onPay;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RfCard(
      border: current ? RfColors.teal : null,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(plan.name, style: RfType.h3)),
              if (current) ...[const SizedBox(width: 6), StatusPill(t.currentPlan, tone: Tone.success)],
            ]),
            Text(t.planDays('${plan.durationDays}'), style: RfType.caption),
            const SizedBox(height: RfSpace.xs),
            MoneyText(price, style: RfType.number),
          ]),
        ),
        RfButton(key: Key('pay_${plan.id}'), label: current ? t.renew : t.payWithDeposit, kind: RfButtonKind.primary, expand: false, onPressed: onPay),
      ]),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});
  final DepositAccount account;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final a = account;
    return Padding(
      padding: const EdgeInsets.only(bottom: RfSpace.sm),
      child: RfCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.account_balance_rounded, color: RfColors.ink),
            const SizedBox(width: RfSpace.xs),
            Expanded(child: Text(a.bankName, style: RfType.bodyStrong)),
          ]),
          const SizedBox(height: 2),
          Text(a.accountName, style: RfType.caption),
          const SizedBox(height: RfSpace.xs),
          Container(
            padding: const EdgeInsets.only(left: 4, right: RfSpace.sm),
            decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(RfRadius.sm)),
            child: Row(children: [
              Expanded(child: Ltr(a.accountNumber, style: RfType.h3)),
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(t.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: a.accountNumber));
                  if (context.mounted) showToast(context, t.copied);
                },
              ),
            ]),
          ),
          if (a.instructions.isNotEmpty) ...[const SizedBox(height: RfSpace.xs), Text(a.instructions, style: RfType.caption)],
        ]),
      ),
    );
  }
}

class _TrialCard extends ConsumerStatefulWidget {
  const _TrialCard({required this.plan});
  final Plan plan;
  @override
  ConsumerState<_TrialCard> createState() => _TrialCardState();
}

class _TrialCardState extends ConsumerState<_TrialCard> {
  final _runner = ActionRunner();
  final _key = newActionKey();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RfCard(
      color: RfColors.tealSoft,
      child: Row(children: [
        const Icon(Icons.card_giftcard_rounded, color: RfColors.tealDeep, size: 32),
        const SizedBox(width: RfSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.plan.name, style: RfType.bodyStrong),
            Text(t.planDays('${widget.plan.durationDays}'), style: RfType.caption),
          ]),
        ),
        RfButton(
          key: const Key('startTrial'),
          label: t.startTrial,
          kind: RfButtonKind.go,
          expand: false,
          loading: _runner.busy,
          onPressed: () async {
            await _runner.run(context, () => ref.read(driverApiProvider).startTrial(actionKey: _key), onChanged: () => setState(() {}), success: t.trialStarted);
            ref.invalidate(subscriptionProvider);
            ref.invalidate(eligibilityProvider);
          },
        ),
      ]),
    );
  }
}

class _DepositForm extends ConsumerStatefulWidget {
  const _DepositForm({required this.overview, required this.plan, required this.minorUnits, required this.currency});
  final SubscriptionOverview overview;
  final Plan? plan;
  final int minorUnits;
  final String currency;
  @override
  ConsumerState<_DepositForm> createState() => _DepositFormState();
}

class _DepositFormState extends ConsumerState<_DepositForm> {
  late Plan _plan = widget.plan ?? widget.overview.plans.firstWhere((p) => !p.isTrial);
  late DepositAccount _account = widget.overview.accounts.first;
  late final TextEditingController _amount = TextEditingController(text: minorToInput(_plan.priceMinor, widget.minorUnits));
  final _reference = TextEditingController();
  DateTime _date = DateTime.now();
  Uint8List? _receipt;
  String _filename = 'receipt.jpg';
  bool _busy = false;
  final _key = newActionKey();
  ApiException? _error;

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _receipt = bytes;
        _filename = file.name;
      });
    } catch (e) {
      if (mounted) showToast(context, '$e', error: true);
    }
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(driverApiProvider).submitDeposit(
            planId: _plan.id,
            accountId: _account.id,
            amountMinor: inputToMinor(_amount.text, widget.minorUnits)!,
            reference: _reference.text.trim(),
            depositedOn: _date.toIso8601String().substring(0, 10),
            receipt: _receipt!,
            filename: _filename,
            actionKey: _key,
          );
      ref.invalidate(subscriptionProvider);
      if (mounted) {
        showToast(context, t.depositSubmitted);
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      setState(() => _error = e);
      if (mounted) showToast(context, e.detail is String ? e.detail as String : errorMessage(context, e), error: true);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ready = _receipt != null && _reference.text.trim().isNotEmpty && inputToMinor(_amount.text, widget.minorUnits) != null;
    return RfSheet(
      title: t.depositTitle,
      subtitle: t.depositIntro,
      body: [
        DropdownButtonFormField<Plan>(
          value: _plan,
          decoration: InputDecoration(labelText: t.plan),
          items: [for (final p in widget.overview.plans.where((p) => !p.isTrial)) DropdownMenuItem(value: p, child: Text(p.name))],
          onChanged: (p) => setState(() {
            _plan = p!;
            _amount.text = minorToInput(p.priceMinor, widget.minorUnits);
          }),
        ),
        const SizedBox(height: RfSpace.md),
        DropdownButtonFormField<DepositAccount>(
          value: _account,
          decoration: InputDecoration(labelText: t.account),
          items: [for (final a in widget.overview.accounts) DropdownMenuItem(value: a, child: Text(a.bankName))],
          onChanged: (a) => setState(() => _account = a!),
        ),
        const SizedBox(height: RfSpace.md),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: '${t.amount} (${widget.currency})', errorText: _error?.fieldError('amount_minor')),
        ),
        const SizedBox(height: RfSpace.md),
        TextField(
          key: const Key('depositReference'),
          controller: _reference,
          textDirection: TextDirection.ltr,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: t.reference, errorText: _error?.fieldError('reference')),
        ),
        const SizedBox(height: RfSpace.md),
        RfButton(
          icon: Icons.event_rounded,
          label: '${t.depositedOn}: ${formatDate(_date)}',
          kind: RfButtonKind.secondary,
          onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 60)), lastDate: DateTime.now(), initialDate: _date);
            if (d != null) setState(() => _date = d);
          },
        ),
        const SizedBox(height: RfSpace.md),
        Text(t.receipt, style: RfType.label),
        const SizedBox(height: RfSpace.xs),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: RfColors.surfaceSunken,
            borderRadius: BorderRadius.circular(RfRadius.lg),
            border: Border.all(color: _error?.fieldError('receipt') != null ? RfColors.coral : RfColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: _receipt == null
              ? const Center(child: Icon(Icons.receipt_long_rounded, size: 40, color: RfColors.textMuted))
              : Image.memory(_receipt!, fit: BoxFit.cover, width: double.infinity),
        ),
        const SizedBox(height: RfSpace.sm),
        Row(children: [
          Expanded(child: RfButton(label: t.useCamera, icon: Icons.photo_camera_rounded, kind: RfButtonKind.secondary, onPressed: () => _pick(ImageSource.camera))),
          const SizedBox(width: RfSpace.sm),
          Expanded(child: RfButton(label: t.chooseFromGallery, icon: Icons.photo_library_rounded, kind: RfButtonKind.secondary, onPressed: () => _pick(ImageSource.gallery))),
        ]),
      ],
      action: RfButton(key: const Key('submitDeposit'), label: t.submitDeposit, kind: RfButtonKind.primary, loading: _busy, onPressed: ready ? _submit : null),
    );
  }
}
