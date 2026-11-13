import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/external_apps.dart';
import 'package:rideflow_driver/data/models.dart';
import 'package:rideflow_driver/design/theme.dart';
import 'package:rideflow_driver/features/subscription/invite_screen.dart';
import 'package:rideflow_driver/features/subscription/subscription_screen.dart';

import 'support/fake_backend.dart';

Map<String, dynamic> plan(String id, String name, int days, int price, int perDay, {int saving = 0, bool best = false, bool trial = false}) => {
      'id': id,
      'code': id,
      'name': name,
      'price_minor': price,
      'duration_days': days,
      'is_trial': trial,
      'per_day_minor': perDay,
      'saving_pct': saving,
      'best_value': best,
    };

Map<String, dynamic> overview({
  bool entitled = true,
  bool inGrace = false,
  Duration left = const Duration(days: 10),
  List<Map<String, dynamic>> claims = const [],
  int earned = 18640000,
  bool canEnterCode = false,
  int rewardDays = 7,
}) {
  final ends = DateTime.now().add(left).toUtc().toIso8601String();
  return {
    'entitled': entitled,
    'current': entitled ? {'plan_name': 'شهرية', 'ends_at': ends, 'source': 'paid', 'plan': {'duration_days': 30}} : null,
    'cover_ends_at': entitled || inGrace ? ends : null,
    'grace_days': 1,
    'reminder_days': [3, 1],
    'in_grace': inGrace,
    'plans': [
      plan('w', 'أسبوع', 7, 140000, 20000),
      plan('m', 'شهر', 30, 500000, 16700, saving: 17),
      plan('q', '3 أشهر', 90, 1200000, 13300, saving: 33, best: true),
    ],
    'deposit_accounts': [
      {'id': 'a1', 'bank_name': 'بنك تجريبي', 'account_name': 'مؤسسة النقل', 'account_number': '3001 2245', 'instructions': ''}
    ],
    'renewal_discount_pct': 0,
    'recent_claims': claims,
    'earnings': {'days': 30, 'trips': 212, 'earned_minor': earned},
    'referral': {'code': 'K7M2QX', 'reward_days': rewardDays, 'invited': 3, 'rewarded': 2, 'days_earned': 14, 'can_enter_code': canEnterCode},
  };
}

class ShareApps extends ExternalApps {
  final shared = <String>[];
  @override
  Future<bool> shareWhatsApp(String text) async {
    shared.add(text);
    return true;
  }
}

Future<FakeBackend> pump(WidgetTester tester, Map<String, Handler> routes, {String initial = '/subscription', SecureKV? prefs, ExternalApps apps = const ExternalApps()}) async {
  final backend = FakeBackend(routes);
  final store = SessionStore(MemoryKV());
  await store.save(const Tokens('a', 'r'));
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    GoRoute(path: '/subscription', builder: (_, __) => const SubscriptionScreen()),
    GoRoute(path: '/subscription/invite', builder: (_, __) => const InviteScreen()),
  ]);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sessionStoreProvider.overrideWithValue(store),
      prefsProvider.overrideWithValue(prefs ?? MemoryKV()),
      externalAppsProvider.overrideWithValue(apps),
      apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver')),
    ],
    child: MaterialApp.router(
      theme: buildRideFlowTheme(),
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  late AppLocalizations t;
  setUpAll(() async => t = await AppLocalizations.delegate.load(const Locale('ar')));

  test('day counts read naturally in Arabic', () {
    expect(daysPhrase(t, 1), 'يوم واحد');
    expect(daysPhrase(t, 2), 'يومين');
    expect(daysPhrase(t, 3), '3 أيام');
    expect(daysPhrase(t, 15), '15 يومًا');
  });

  test('the reminder starts at the first day the operator set, and in the grace', () {
    final now = DateTime.now();
    expect(SubscriptionOverview(overview(left: const Duration(days: 10))).remindNow(now), isFalse);
    expect(SubscriptionOverview(overview(left: const Duration(days: 2, hours: 12))).remindNow(now), isTrue);
    expect(SubscriptionOverview(overview(inGrace: true, left: const Duration(hours: -3))).remindNow(now), isTrue);
    expect(SubscriptionOverview(overview(entitled: false)).remindNow(now), isFalse);
  });

  testWidgets('the ring shows the days left, the best value is picked, and its price is on the button', (tester) async {
    await pump(tester, {'GET driver/subscription': (_) => (200, overview())});
    expect(find.byKey(const Key('subscriptionRing')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('daysRemaining'))).data, '10');
    expect(find.byKey(const Key('best_q')), findsOneWidget);
    expect(find.textContaining('3 أشهر ·'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plan_m')));
    await tester.pump();
    expect(find.textContaining('شهر ·'), findsOneWidget);
    expect(find.byKey(const Key('worthIt')), findsOneWidget);
  });

  testWidgets('in the grace: the ended card with its grace tag', (tester) async {
    await pump(tester, {'GET driver/subscription': (_) => (200, overview(inGrace: true, left: const Duration(hours: -2)))});
    expect(find.byKey(const Key('subscriptionEnded')), findsOneWidget);
    expect(find.text(t.subInGraceText), findsOneWidget);
  });

  testWidgets('a receipt in review replaces the plans', (tester) async {
    final claim = {'id': 'c1', 'reference': 'TX-55210', 'amount_minor': 1200000, 'currency': 'YER', 'status': 'submitted', 'deposited_on': '2026-11-12', 'decision_note': '', 'plan': {'name': '3 أشهر'}};
    await pump(tester, {'GET driver/subscription': (_) => (200, overview(claims: [claim]))});
    expect(find.byKey(const Key('receiptInReview')), findsOneWidget);
    expect(find.byKey(const Key('choosePlan')), findsNothing);
  });

  testWidgets('the activation shows once when the awaited receipt is approved', (tester) async {
    final prefs = MemoryKV()..values[awaitingClaimKey] = 'c1';
    final approved = {'id': 'c1', 'reference': 'TX-1', 'amount_minor': 500000, 'currency': 'YER', 'status': 'approved', 'deposited_on': '2026-11-12', 'decision_note': '', 'plan': {'name': 'شهر'}};
    await pump(tester, {'GET driver/subscription': (_) => (200, overview(claims: [approved]))}, prefs: prefs);
    expect(find.text(t.activatedTitle), findsOneWidget);
    expect(prefs.values[awaitingClaimKey], '');
    await tester.tap(find.byKey(const Key('startReceiving')));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a new driver enters an invitation code; a wrong one says why', (tester) async {
    var calls = 0;
    final backend = await pump(tester, {
      'GET driver/subscription': (_) => (200, overview(entitled: false, canEnterCode: true)),
      'POST driver/subscription/referral': (r) {
        calls++;
        return calls == 1 ? (422, {'code': 'referral_invalid', 'detail': 'x'}) : (200, {'code': 'MINE01', 'reward_days': 7, 'invited': 0, 'rewarded': 0, 'days_earned': 0, 'can_enter_code': false});
      },
    });
    await tester.tap(find.byKey(const Key('enterReferralCode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('referralCode')), 'k7m2qx');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmReferralCode')));
    await tester.pumpAndSettle();
    expect(find.text(t.referral_invalid), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmReferralCode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('referralCode')), findsNothing);
    final sent = backend.seen.lastWhere((r) => r.path == 'driver/subscription/referral');
    expect((sent.body as Map)['code'], 'K7M2QX');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('invitations off: no invite row', (tester) async {
    await pump(tester, {'GET driver/subscription': (_) => (200, overview(rewardDays: 0))});
    expect(find.byKey(const Key('inviteDriver')), findsNothing);
  });

  testWidgets('the invite screen shows the code and shares it on WhatsApp', (tester) async {
    final apps = ShareApps();
    await pump(tester, {'GET driver/subscription': (_) => (200, overview())}, initial: '/subscription/invite', apps: apps);
    expect(find.text('K7M2QX'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shareWhatsApp')));
    await tester.pump();
    expect(apps.shared.single, contains('K7M2QX'));
  });
}
