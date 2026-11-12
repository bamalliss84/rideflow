import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/battery.dart';
import 'package:rideflow_driver/design/theme.dart';
import 'package:rideflow_driver/features/battery/battery_screen.dart';

class FakeGuard extends BatteryGuard {
  FakeGuard(this.current, {this.opens = true});
  BatteryState current;
  final bool opens;
  int requests = 0, settings = 0;
  @override
  Future<BatteryState> state() async => current;
  @override
  Future<bool> requestExemption() async {
    requests++;
    return true;
  }

  @override
  Future<bool> openMakerSettings() async {
    settings++;
    return opens;
  }
}

/// Home has one button that runs [maybeShowBatteryGuide], as going online does.
Future<void> pump(WidgetTester tester, FakeGuard guard, {MemoryKV? prefs, String initial = '/battery'}) async {
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(onPressed: () => maybeShowBatteryGuide(context, ref), child: const Text('ONLINE')),
        ),
      ),
    ),
    GoRoute(path: '/battery', builder: (_, __) => const BatteryGuideScreen()),
  ]);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      batteryGuardProvider.overrideWithValue(guard),
      prefsProvider.overrideWithValue(prefs ?? MemoryKV()),
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
}

void main() {
  test('makers group by whose settings look alike', () {
    expect(makerOf('INFINIX'), PhoneMaker.transsion);
    expect(makerOf('tecno'), PhoneMaker.transsion);
    expect(makerOf('Redmi'), PhoneMaker.xiaomi);
    expect(makerOf('realme'), PhoneMaker.oppo);
    expect(makerOf('Google'), PhoneMaker.other);
  });

  test('the guide is needed without the exemption, or on makers with their own saver', () {
    expect(const BatteryState().needsGuide, isFalse); // not Android
    expect(const BatteryState(supported: true, exempt: false).needsGuide, isTrue);
    expect(const BatteryState(supported: true, exempt: true).needsGuide, isFalse);
    expect(const BatteryState(supported: true, exempt: true, maker: PhoneMaker.transsion).needsGuide, isTrue);
  });

  testWidgets('without the exemption: Allow asks for it, and the maker steps show', (tester) async {
    final guard = FakeGuard(const BatteryState(supported: true, exempt: false, maker: PhoneMaker.transsion));
    await pump(tester, guard);
    final t = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(find.text(t.batteryStep1Text), findsOneWidget);
    expect(find.text(t.batteryMakerTranssion), findsOneWidget);
    await tester.tap(find.byKey(const Key('batteryAllow')));
    await tester.pump();
    expect(guard.requests, 1);
  });

  testWidgets('coming back after allowing reads the exemption again', (tester) async {
    final guard = FakeGuard(const BatteryState(supported: true, exempt: false));
    await pump(tester, guard);
    final t = await AppLocalizations.delegate.load(const Locale('ar'));
    guard.current = const BatteryState(supported: true, exempt: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(t.batteryStep1Done), findsOneWidget);
    expect(find.byKey(const Key('batteryAllow')), findsNothing);
    expect(find.text(t.batteryMakerOther), findsOneWidget);
  });

  testWidgets('settings that do not open say so', (tester) async {
    final guard = FakeGuard(const BatteryState(supported: true, exempt: true, maker: PhoneMaker.xiaomi), opens: false);
    await pump(tester, guard);
    final t = await AppLocalizations.delegate.load(const Locale('ar'));
    await tester.tap(find.byKey(const Key('batteryOpenSettings')));
    await tester.pump();
    expect(guard.settings, 1);
    expect(find.text(t.batterySettingsFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('going online opens the guide once, on phones that need it', (tester) async {
    final prefs = MemoryKV();
    final guard = FakeGuard(const BatteryState(supported: true, exempt: false));
    await pump(tester, guard, prefs: prefs, initial: '/');
    await tester.tap(find.text('ONLINE'));
    await tester.pumpAndSettle();
    expect(find.byType(BatteryGuideScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ONLINE'));
    await tester.pumpAndSettle();
    expect(find.byType(BatteryGuideScreen), findsNothing);
  });

  testWidgets('a phone that needs nothing never opens it', (tester) async {
    final prefs = MemoryKV();
    await pump(tester, FakeGuard(const BatteryState(supported: true, exempt: true)), prefs: prefs, initial: '/');
    await tester.tap(find.text('ONLINE'));
    await tester.pumpAndSettle();
    expect(find.byType(BatteryGuideScreen), findsNothing);
    expect(prefs.values[batteryGuideSeenKey], isNull);
  });
}
