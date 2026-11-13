import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

/// Remembers the receipt the driver is waiting on, so its approval is celebrated once (screen 7 of D053).
const awaitingClaimKey = 'subscription_awaiting_claim';

/// "1 day", "2 days", "3 days", "15 days" with the Arabic forms for each count.
String daysPhrase(AppLocalizations t, int n) {
  if (n == 1) return t.dayOne;
  if (n == 2) return t.dayTwo;
  return n >= 3 && n <= 10 ? t.daysFew('$n') : t.daysMany('$n');
}

/// The word under the number in the ring.
String ringUnit(AppLocalizations t, int n) {
  if (n == 1) return t.ringDay;
  if (n == 2) return t.ringDayTwo;
  return n >= 3 && n <= 10 ? t.ringDaysFew : t.ringDaysMany;
}

/// My subscription (D052, D053 model 2 with the remaining-days ring): how long is left, the plans side by side with
/// their value per day, what the driver earned against the price, and invitations. Prices, plans, grace and reward
/// days all come from the operator.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? _selectedId;
  bool _celebrating = false;

  /// A receipt we saw waiting is now approved: show the activation once.
  Future<void> _watchClaims(SubscriptionOverview s) async {
    final prefs = ref.read(prefsProvider);
    final pending = s.recentClaims.where((c) => c.status == 'submitted' || c.status == 'first_approved').firstOrNull;
    try {
      if (pending != null) {
        await prefs.write(awaitingClaimKey, pending.id);
        return;
      }
      final awaited = await prefs.read(awaitingClaimKey);
      if (awaited == null || awaited.isEmpty) return;
      final claim = s.recentClaims.where((c) => c.id == awaited).firstOrNull;
      if (claim == null || claim.status == 'submitted' || claim.status == 'first_approved') return;
      await prefs.write(awaitingClaimKey, '');
      if (claim.status != 'approved' || !mounted || _celebrating) return;
      _celebrating = true;
      await RfSheet.show<void>(context, _Activated(overview: s));
      _celebrating = false;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final units = me?.minorUnits ?? 2;
    final currency = me?.currency ?? '';
    ref.listen<AsyncValue<SubscriptionOverview>>(subscriptionProvider, (_, next) {
      final s = next.valueOrNull;
      if (s != null) _watchClaims(s);
    });
    return Scaffold(
      appBar: AppBar(title: Text(t.subscriptionTitle)),
      body: AsyncBody<SubscriptionOverview>(
        value: ref.watch(subscriptionProvider),
        onRetry: ref.retry(subscriptionProvider),
        data: (s) {
          final paid = s.plans.where((p) => !p.isTrial).toList()..sort((a, b) => a.durationDays.compareTo(b.durationDays));
          final trial = s.plans.where((p) => p.isTrial).firstOrNull;
          final pending = s.recentClaims.where((c) => c.status == 'submitted' || c.status == 'first_approved').firstOrNull;
          final lastRejected = s.recentClaims.isNotEmpty && s.recentClaims.first.status == 'rejected' ? s.recentClaims.first : null;
          final canPay = s.accounts.isNotEmpty && paid.isNotEmpty;
          final selected = paid.where((p) => p.id == _selectedId).firstOrNull ??
              paid.where((p) => p.bestValue).firstOrNull ??
              paid.where((p) => p.name == s.currentPlanName).firstOrNull ??
              paid.lastOrNull;
          String money(int minor) => formatMoney(minor, currency, units);
          void pay([Plan? plan]) => RfSheet.show<void>(context, _DepositForm(overview: s, plan: plan, minorUnits: units, currency: currency));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(subscriptionProvider),
            child: ListView(padding: const EdgeInsets.fromLTRB(RfSpace.md, RfSpace.sm, RfSpace.md, RfSpace.lg), children: [
              _Status(overview: s),
              if (pending != null) ...[
                const SizedBox(height: RfSpace.sm),
                _Review(claim: pending, money: money),
              ],
              if (lastRejected != null && pending == null) ...[
                const SizedBox(height: RfSpace.sm),
                Banner2(
                  text: t.rejectedReceipt(lastRejected.decisionNote.isEmpty ? '—' : lastRejected.decisionNote),
                  tone: Tone.danger,
                  icon: Icons.error_outline_rounded,
                  actionLabel: canPay ? t.submitDeposit : null,
                  onAction: canPay ? () => pay(selected) : null,
                ),
              ],
              if (!s.entitled && trial != null) ...[
                const SizedBox(height: RfSpace.md),
                _TrialCard(plan: trial),
              ],
              if (pending == null && paid.isNotEmpty) ...[
                const SizedBox(height: RfSpace.lg),
                Text(s.entitled ? t.plansHeadingRenew : t.plansHeadingNew, style: RfType.h2),
                const SizedBox(height: 2),
                Text(t.plansHint, style: RfType.caption),
                const SizedBox(height: RfSpace.md),
                _Plans(plans: paid, selected: selected, money: money, onSelect: (p) => setState(() => _selectedId = p.id)),
              ],
              if (paid.isEmpty) EmptyState(icon: Icons.workspace_premium_outlined, title: t.plansTitle, message: t.emptyTitle),
              if (s.renewalDiscountPct > 0) ...[const SizedBox(height: RfSpace.xs), Text('${t.renew}: −${s.renewalDiscountPct}%', style: RfType.caption)],
              if (s.earnings.earnedMinor > 0 && paid.isNotEmpty) ...[
                const SizedBox(height: RfSpace.md),
                _Worth(earnings: s.earnings, plan: _monthly(paid), money: money),
              ],
              if (s.referral.on || s.referral.canEnterCode) ...[
                const SizedBox(height: RfSpace.md),
                RfGroup(children: [
                  if (s.referral.canEnterCode && s.referral.on)
                    RfRow(
                      key: const Key('enterReferralCode'),
                      leading: RfRowIcon(Icons.card_giftcard_rounded, color: RfColors.teal),
                      title: t.enterCodeRow,
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => RfSheet.show<void>(context, const ReferralCodeSheet()),
                    ),
                  if (s.referral.on)
                    RfRow(
                      key: const Key('inviteDriver'),
                      leading: RfRowIcon(Icons.redeem_rounded, color: RfColors.teal),
                      title: t.inviteRow(daysPhrase(t, s.referral.rewardDays)),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => context.push('/subscription/invite'),
                    ),
                ]),
              ],
              if (pending == null && selected != null) ...[
                const SizedBox(height: RfSpace.sm),
                RfButton(
                  key: const Key('choosePlan'),
                  label: t.choosePlanCta(selected.name, money(selected.priceMinor)),
                  kind: RfButtonKind.primary,
                  large: true,
                  onPressed: canPay ? () => pay(selected) : null,
                ),
                if (s.accounts.isEmpty) ...[const SizedBox(height: RfSpace.xs), Text(t.noDepositAccounts, style: RfType.caption, textAlign: TextAlign.center)],
              ],
              if (s.recentClaims.isNotEmpty) ...[
                const SizedBox(height: RfSpace.lg),
                RfGroup(title: t.claimsTitle, children: [
                  for (final c in s.recentClaims)
                    RfRow(
                      titleChild: MoneyText(money(c.amountMinor), style: RfType.bodyStrong),
                      sub: [if (c.planName.isNotEmpty) c.planName, c.reference, c.depositedOn, if (c.decisionNote.isNotEmpty) c.decisionNote].join(' · '),
                      trailing: StatusPill(claimStatusLabel(t, c.status), tone: toneFor(c.status)),
                    ),
                ]),
              ],
            ]),
          );
        },
      ),
    );
  }
}

/// The plan closest to a month, to weigh against a month of earnings.
Plan _monthly(List<Plan> paid) => paid.reduce((a, b) => (a.durationDays - 30).abs() <= (b.durationDays - 30).abs() ? a : b);

/// The ring with the days left (taken from model 1), or the ended state with its grace.
class _Status extends StatelessWidget {
  const _Status({required this.overview});
  final SubscriptionOverview overview;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = overview;
    final now = DateTime.now();
    if (s.entitled && !s.inGrace) {
      final days = s.daysLeft(now);
      final span = (s.current?['plan'] is Map ? (s.current!['plan'] as Map)['duration_days'] as num? : null)?.toInt() ?? 30;
      final low = days <= (s.reminderDays.isEmpty ? 3 : s.reminderDays.first);
      return RfCard(
        key: const Key('subscriptionRing'),
        child: Row(children: [
          _Ring(value: (days / (span < days ? days : span)).clamp(0.03, 1.0), color: low ? RfColors.amber : RfColors.teal, number: days, unit: ringUnit(t, days)),
          const SizedBox(width: RfSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(s.currentPlanName ?? '', style: RfType.caption)),
                if (s.currentSource == 'trial') ...[const SizedBox(width: 6), StatusPill(t.trialBadge, tone: Tone.info)],
              ]),
              const SizedBox(height: 2),
              Text(t.subEndsOn(formatDate(s.paidUntil?.toLocal())), key: const Key('subscriptionEnds'), style: RfType.h3),
              if (s.graceDays > 0) ...[const SizedBox(height: 2), Text(t.subGraceLine(daysPhrase(t, s.graceDays)), style: RfType.caption)],
            ]),
          ),
        ]),
      );
    }
    return RfCard(
      key: const Key('subscriptionEnded'),
      border: s.inGrace ? RfColors.amber : RfColors.coral,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (s.inGrace) ...[
          StatusPill(t.subInGraceTag(formatDateTime(s.stopsAt?.toLocal())), tone: Tone.warning),
          const SizedBox(height: RfSpace.xs),
        ],
        Text(s.inGrace || s.paidUntil != null ? t.subEndedTitle : t.subNoneTitle, style: RfType.h2),
        const SizedBox(height: 2),
        Text(s.inGrace ? t.subInGraceText : t.subNoneText, style: RfType.caption),
      ]),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.color, required this.number, required this.unit});
  final double value;
  final Color color;
  final int number;
  final String unit;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 78,
        height: 78,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(child: CircularProgressIndicator(value: value, strokeWidth: 7, color: color, backgroundColor: RfColors.surfaceSunken, strokeCap: StrokeCap.round)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$number', key: const Key('daysRemaining'), style: RfType.h1.copyWith(height: 1)),
            Text(unit, style: RfType.caption),
          ]),
        ]),
      );
}

/// Plans side by side; the best value is crowned and picked unless the driver picks another.
class _Plans extends StatelessWidget {
  const _Plans({required this.plans, required this.selected, required this.money, required this.onSelect});
  final List<Plan> plans;
  final Plan? selected;
  final String Function(int) money;
  final ValueChanged<Plan> onSelect;
  @override
  Widget build(BuildContext context) {
    final tiles = [for (final p in plans) _PlanTile(plan: p, selected: p.id == selected?.id, money: money, onTap: () => onSelect(p))];
    if (plans.length <= 3) {
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, tile) in tiles.indexed) ...[if (i > 0) const SizedBox(width: RfSpace.xs), Expanded(child: tile)],
        ]),
      );
    }
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: RfSpace.xs),
        itemBuilder: (_, i) => SizedBox(width: 112, child: tiles[i]),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.selected, required this.money, required this.onTap});
  final Plan plan;
  final bool selected;
  final String Function(int) money;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final border = selected ? RfColors.gold : (plan.bestValue ? RfColors.gold.withOpacity(0.45) : RfColors.line);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Material(
          color: selected ? RfColors.gold.withOpacity(0.10) : RfColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border, width: selected ? 2 : 1)),
          child: InkWell(
            key: Key('plan_${plan.id}'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 16, 6, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(plan.name, style: RfType.bodyStrong, textAlign: TextAlign.center, maxLines: 2),
                const SizedBox(height: 6),
                FittedBox(fit: BoxFit.scaleDown, child: MoneyText(money(plan.priceMinor), style: RfType.number.copyWith(color: RfColors.gold))),
                Text(t.planDays('${plan.durationDays}'), style: RfType.caption),
                Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10), color: RfColors.line),
                FittedBox(fit: BoxFit.scaleDown, child: Text(t.perDay(money(plan.perDayMinor)), style: RfType.caption)),
                const SizedBox(height: 4),
                if (plan.savingPct > 0)
                  StatusPill(t.saveBadge('${plan.savingPct}'), tone: Tone.success)
                else
                  const SizedBox(height: 22),
              ]),
            ),
          ),
        ),
        if (plan.bestValue)
          Positioned(
            top: -10,
            child: Container(
              key: Key('best_${plan.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: RfColors.gold, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.workspace_premium_rounded, size: 13, color: RfColors.onGold),
                const SizedBox(width: 3),
                Text(t.bestValue, style: RfType.caption.copyWith(color: RfColors.onGold, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// What the driver earned in cash against the plan closest to a month.
class _Worth extends StatelessWidget {
  const _Worth({required this.earnings, required this.plan, required this.money});
  final Earnings earnings;
  final Plan plan;
  final String Function(int) money;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final share = (plan.priceMinor / earnings.earnedMinor).clamp(0.06, 1.0);
    Widget bar(double f, Color c, Color fg, String text) => LayoutBuilder(
          builder: (_, box) => Container(
            width: box.maxWidth * f,
            height: 30,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(text, style: RfType.bodyStrong.copyWith(color: fg))),
          ),
        );
    return RfCard(
      key: const Key('worthIt'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.worthTitle, style: RfType.h3),
        const SizedBox(height: RfSpace.sm),
        bar(1, RfColors.teal, RfColors.canvas, '${money(earnings.earnedMinor)}  ${t.worthYou}'),
        const SizedBox(height: 6),
        Align(alignment: AlignmentDirectional.centerStart, child: bar(share, RfColors.gold, RfColors.onGold, money(plan.priceMinor))),
        const SizedBox(height: RfSpace.xs),
        Text(t.worthCaption('${earnings.days}', '${earnings.trips}', plan.name), style: RfType.caption),
      ]),
    );
  }
}

/// The receipt waiting for the operator (screen 6).
class _Review extends StatelessWidget {
  const _Review({required this.claim, required this.money});
  final DepositClaim claim;
  final String Function(int) money;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget kv(String k, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(k, style: RfType.caption)), v]),
        );
    return RfCard(
      key: const Key('receiptInReview'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.hourglass_top_rounded, color: RfColors.blue),
          const SizedBox(width: RfSpace.xs),
          Expanded(child: Text(t.reviewTitle, style: RfType.h3)),
        ]),
        const SizedBox(height: 4),
        Text(t.reviewText, style: RfType.caption),
        const SizedBox(height: RfSpace.xs),
        if (claim.planName.isNotEmpty) kv(t.plan, Text(claim.planName, style: RfType.bodyStrong)),
        kv(t.amount, MoneyText(money(claim.amountMinor), style: RfType.bodyStrong)),
        kv(t.reference, Ltr(claim.reference, style: RfType.bodyStrong)),
      ]),
    );
  }
}

/// Shown once when the receipt we waited on is approved (screen 7).
class _Activated extends StatelessWidget {
  const _Activated({required this.overview});
  final SubscriptionOverview overview;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final days = overview.daysLeft(DateTime.now());
    return RfSheet(
      title: t.activatedTitle,
      body: [
        Center(child: Icon(Icons.check_circle_rounded, size: 64, color: RfColors.teal)),
        const SizedBox(height: RfSpace.sm),
        Text(t.activatedText(overview.currentPlanName ?? '', formatDate(overview.paidUntil?.toLocal())), style: RfType.body, textAlign: TextAlign.center),
        const SizedBox(height: RfSpace.md),
        Center(child: _Ring(value: 1, color: RfColors.teal, number: days, unit: ringUnit(t, days))),
      ],
      action: RfButton(
        key: const Key('startReceiving'),
        label: t.startReceiving,
        kind: RfButtonKind.go,
        onPressed: () {
          Navigator.pop(context);
          context.go('/');
        },
      ),
    );
  }
}

/// A new driver enters the code of the driver who invited them (screen 9).
class ReferralCodeSheet extends ConsumerStatefulWidget {
  const ReferralCodeSheet({super.key});
  @override
  ConsumerState<ReferralCodeSheet> createState() => _ReferralCodeSheetState();
}

class _ReferralCodeSheetState extends ConsumerState<ReferralCodeSheet> {
  final _code = TextEditingController();
  final _key = newActionKey();
  bool _busy = false;
  String? _error;

  String _message(AppLocalizations t, Object e) {
    if (e is ApiException) {
      switch (e.code) {
        case 'referral_invalid':
          return t.referral_invalid;
        case 'referral_self':
          return t.referral_self;
        case 'referral_too_late':
          return t.referral_too_late;
        case 'referral_already_set':
          return t.referral_already_set;
      }
    }
    return errorMessage(context, e);
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(driverApiProvider).useReferralCode(_code.text.trim().toUpperCase(), actionKey: _key);
      ref.invalidate(subscriptionProvider);
      if (!mounted) return;
      showToast(context, t.codeSaved);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = _message(t, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RfSheet(
      title: t.codeTitle,
      subtitle: t.codeText,
      body: [
        TextField(
          key: const Key('referralCode'),
          controller: _code,
          autofocus: true,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(12)],
          style: RfType.h2.copyWith(letterSpacing: 4),
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(labelText: t.referralCodeLabel, errorText: _error),
        ),
      ],
      action: Column(mainAxisSize: MainAxisSize.min, children: [
        RfButton(key: const Key('confirmReferralCode'), label: t.codeConfirm, kind: RfButtonKind.primary, loading: _busy, onPressed: _code.text.trim().length >= 4 ? _submit : null),
        const SizedBox(height: RfSpace.xs),
        RfButton(label: t.codeNone, kind: RfButtonKind.ghost, onPressed: () => Navigator.pop(context)),
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
            Icon(Icons.account_balance_rounded, color: RfColors.text),
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
        Icon(Icons.card_giftcard_rounded, color: RfColors.tealDeep, size: 32),
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
        const SizedBox(height: RfSpace.sm),
        _AccountCard(account: _account),
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
              ? Center(child: Icon(Icons.receipt_long_rounded, size: 40, color: RfColors.textMuted))
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
