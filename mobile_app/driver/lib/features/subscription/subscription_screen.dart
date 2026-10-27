
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final units = me?.minorUnits ?? 2;
    return Scaffold(
      appBar: AppBar(title: Text(t.subscriptionTitle)),
      body: AsyncBody<SubscriptionOverview>(
        value: ref.watch(subscriptionProvider),
        onRetry: ref.retry(subscriptionProvider),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(subscriptionProvider),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              color: s.entitled ? Brand.tealSoft : Brand.amberSoft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(s.entitled ? Icons.verified_rounded : Icons.warning_amber_rounded, color: s.entitled ? Brand.teal700 : Brand.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.entitled ? '${s.currentPlanName ?? ''}\n${t.subscriptionActive(formatDate(s.endsAt))}' : t.subscriptionInactive,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: t.plansTitle,
              child: Column(children: [
                for (final p in s.plans)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: Text(t.planDays('${p.durationDays}')),
                    trailing: p.isTrial
                        ? (s.entitled ? null : _TrialButton())
                        : Ltr(formatMoney(p.priceMinor, me?.currency ?? '', units), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: t.depositAccounts,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(t.depositIntro, style: const TextStyle(color: Brand.muted)),
                const SizedBox(height: 8),
                for (final a in s.accounts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_balance_rounded),
                    title: Text('${a.bankName} — ${a.accountName}'),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Ltr(a.accountNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (a.instructions.isNotEmpty) Text(a.instructions),
                    ]),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: Text(t.depositTitle),
                  onPressed: s.accounts.isEmpty || s.plans.where((p) => !p.isTrial).isEmpty
                      ? null
                      : () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => _DepositForm(overview: s, minorUnits: units, currency: me?.currency ?? ''),
                          ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: t.claimsTitle,
              child: s.recentClaims.isEmpty
                  ? EmptyView(text: t.emptyTitle, icon: Icons.receipt_outlined)
                  : Column(children: [
                      for (final c in s.recentClaims)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Ltr(c.reference),
                          subtitle: Text([formatMoney(c.amountMinor, c.currency, units), c.depositedOn, if (c.decisionNote.isNotEmpty) c.decisionNote].join(' · ')),
                          trailing: StatusChip(claimStatusLabel(t, c.status), tone: toneFor(c.status)),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TrialButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TrialButton> createState() => _TrialButtonState();
}

class _TrialButtonState extends ConsumerState<_TrialButton> {
  final _runner = ActionRunner();
  final _key = newActionKey();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return TextButton(
      onPressed: _runner.busy
          ? null
          : () async {
              await _runner.run(context, () => ref.read(driverApiProvider).startTrial(actionKey: _key), onChanged: () => setState(() {}), success: t.trialStarted);
              ref.invalidate(subscriptionProvider);
              ref.invalidate(eligibilityProvider);
            },
      child: Text(t.startTrial),
    );
  }
}

class _DepositForm extends ConsumerStatefulWidget {
  const _DepositForm({required this.overview, required this.minorUnits, required this.currency});
  final SubscriptionOverview overview;
  final int minorUnits;
  final String currency;
  @override
  ConsumerState<_DepositForm> createState() => _DepositFormState();
}

class _DepositFormState extends ConsumerState<_DepositForm> {
  late Plan _plan = widget.overview.plans.firstWhere((p) => !p.isTrial);
  late DepositAccount _account = widget.overview.accounts.first;
  late final TextEditingController _amount = TextEditingController(text: minorToInput(_plan.priceMinor, widget.minorUnits));
  final _reference = TextEditingController();
  DateTime _date = DateTime.now();
  Uint8List? _receipt;
  String _filename = 'receipt.jpg';
  final _runner = ActionRunner();
  final _key = newActionKey();
  ApiException? _error;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ready = _receipt != null && _reference.text.trim().isNotEmpty && inputToMinor(_amount.text, widget.minorUnits) != null;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.depositTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          DropdownButtonFormField<Plan>(
            value: _plan,
            decoration: InputDecoration(labelText: t.plan),
            items: [for (final p in widget.overview.plans.where((p) => !p.isTrial)) DropdownMenuItem(value: p, child: Text(p.name))],
            onChanged: (p) => setState(() {
              _plan = p!;
              _amount.text = minorToInput(p.priceMinor, widget.minorUnits);
            }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<DepositAccount>(
            value: _account,
            decoration: InputDecoration(labelText: t.account),
            items: [for (final a in widget.overview.accounts) DropdownMenuItem(value: a, child: Text(a.bankName))],
            onChanged: (a) => setState(() => _account = a!),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: '${t.amount} (${widget.currency})', errorText: _error?.fieldError('amount_minor')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reference,
            textDirection: TextDirection.ltr,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: t.reference, errorText: _error?.fieldError('reference')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('${t.depositedOn}: ${formatDate(_date)}'),
            onPressed: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 60)), lastDate: DateTime.now(), initialDate: _date);
              if (d != null) setState(() => _date = d);
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: Icon(_receipt == null ? Icons.add_photo_alternate_outlined : Icons.check_circle, color: _receipt == null ? null : Brand.teal),
            label: Text(_receipt == null ? t.receipt : t.imageSelected),
            onPressed: () async {
              final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 85);
              if (file == null) return;
              final bytes = await file.readAsBytes();
              setState(() {
                _receipt = bytes;
                _filename = file.name;
              });
            },
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: !ready || _runner.busy
                ? null
                : () async {
                    try {
                      setState(() => _error = null);
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
                      if (context.mounted) {
                        showMessage(context, t.depositSubmitted);
                        Navigator.pop(context);
                      }
                    } on ApiException catch (e) {
                      setState(() => _error = e);
                      if (context.mounted) showMessage(context, e.detail is String ? e.detail as String : errorMessage(context, e), error: true);
                    }
                  },
            child: Text(t.submitDeposit),
          ),
        ]),
      ),
    );
  }
}
