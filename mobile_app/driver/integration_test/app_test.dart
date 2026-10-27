// On-device test (Android emulator) against the local stack through 10.0.2.2:
//   flutter test integration_test -d emulator-5554 --dart-define=APP_CLIENT_ID=e2e-qa-driver
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rideflow_driver/app/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real sign-in on the device: OTP -> home, application status, logout', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DriverApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Arabic, right-to-left by default.
    final title = find.text('تسجيل دخول السائق');
    expect(title, findsOneWidget);
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);

    final phone = '+9677${1000000 + Random().nextInt(8999999)}${Random().nextInt(10)}';
    await tester.enterText(find.byKey(const Key('phone')), phone);
    await tester.tap(find.byKey(const Key('sendCode')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await tester.enterText(find.byKey(const Key('code')), '000000');
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Home with the backend's eligibility verdict for a brand-new driver.
    expect(find.byKey(const Key('toggleOnline')), findsOneWidget);
    expect(find.text('لا يمكنك الاتصال الآن'), findsOneWidget);
    expect(find.text('الوثائق ناقصة — أكمل طلب الانضمام.'), findsOneWidget);

    // Onboarding screen loads the real driver profile.
    await tester.tap(find.text('أكمل طلب الانضمام'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('بانتظار الوثائق'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Account -> sign out returns to the sign-in screen.
    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.scrollUntilVisible(find.byKey(const Key('logout')), 200);
    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('تسجيل دخول السائق'), findsOneWidget);
  });
}
