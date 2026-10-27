// On-device GPS path check (emulator): device fix -> app -> POST driver/location -> PostGIS -> "ready".
//   adb emu geo fix 49.1242 14.5426
//   adb shell pm grant com.rideflow.rideflow_driver android.permission.ACCESS_FINE_LOCATION
//   flutter test integration_test/location_test.dart -d emulator-5554 \
//     --dart-define=APP_CLIENT_ID=demo-mukalla-driver --dart-define=DRIVER_PHONE=+967700000001
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rideflow_driver/app/app.dart';
import 'package:rideflow_driver/app/providers.dart';

const driverPhone = String.fromEnvironment('DRIVER_PHONE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an approved, subscribed driver becomes "ready" only after the device location reaches the server', (tester) async {
    expect(driverPhone, isNotEmpty, reason: 'pass --dart-define=DRIVER_PHONE');
    final container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DriverApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    if (find.byKey(const Key('phone')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('phone')), driverPhone);
      await tester.tap(find.byKey(const Key('sendCode')));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await tester.enterText(find.byKey(const Key('code')), '000000');
      await tester.tap(find.byKey(const Key('verify')));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }

    final ready = find.text('متصل — تستقبل الطلبات');
    for (var attempt = 0; attempt < 3 && ready.evaluate().isEmpty; attempt++) {
      final sendNow = find.byKey(const Key('sendLocationNow'));
      if (sendNow.evaluate().isNotEmpty) {
        await tester.tap(sendNow); // online on the server but location stale/missing
      } else {
        final status = tester.widget<Text>(find.byKey(const Key('availabilityStatus'))).data;
        if (status == 'غير متصل') await tester.tap(find.byKey(const Key('toggleOnline')));
      }
      for (var i = 0; i < 25 && ready.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(seconds: 1));
        container.invalidate(eligibilityProvider);
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    final online = container.read(onlineControllerProvider);
    expect(online.locationError, isNull, reason: '${online.locationError}');
    expect(online.lastSentAt, isNotNull);
    expect(ready, findsOneWidget);
    final eligibility = await container.read(eligibilityProvider.future);
    expect(eligibility.isOnline, isTrue);
    expect(eligibility.locationFresh, isTrue);
    expect(DateTime.now().difference(eligibility.locationServerTs!).inSeconds.abs(), lessThan(120));
  });
}
