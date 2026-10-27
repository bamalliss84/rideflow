import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/app/app.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/realtime/events_socket.dart';

import 'support/fake_backend.dart';

class _NoSocket extends EventsSocket {
  _NoSocket(SessionStore s) : super(session: s);
  @override
  Future<void> start() async {}
}

void main() {
  testWidgets('sign-in with OTP lands on the home screen (Arabic RTL) and shows backend eligibility reasons', (tester) async {
    final store = SessionStore(MemoryKV());
    final backend = FakeBackend({
      'GET auth/app-context': (_) => (200, {'tenant_name': 'مشغل تجريبي', 'app_type': 'driver'}),
      'POST auth/otp/request': (_) => (202, {'sent': true}),
      'POST auth/otp/verify': (r) => (r.body as Map)['code'] == '000000'
          ? (200, {'access': 'a1', 'refresh': 'r1', 'user_id': 'u', 'is_new_user': false})
          : (400, {'code': 'otp_invalid', 'detail': 'Invalid code.'}),
      'GET me': (_) => (200, {
            'user': {'id': 'u', 'phone': '+967722000009', 'full_name': 'سائق اختبار'},
            'tenant': {'tenant_name': 'مشغل تجريبي', 'roles': ['driver']},
            'currency': 'YER',
            'currency_minor_units': 2,
          }),
      'GET driver/eligibility': (_) => (200, {
            'eligible': false,
            'reasons': ['subscription_inactive'],
            'subscription_active': false,
            'status': 'approved',
            'is_online': false,
          }),
      'GET rides': (_) => (200, {'count': 0, 'results': []}),
    });
    await tester.pumpWidget(ProviderScope(overrides: [
      sessionStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver')),
      eventsSocketProvider.overrideWith((ref) => _NoSocket(store)),
    ], child: const DriverApp()));
    await tester.pumpAndSettle();

    expect(find.text('تسجيل دخول السائق'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('تسجيل دخول السائق'))), TextDirection.rtl);

    await tester.enterText(find.byKey(const Key('phone')), '12345');
    await tester.tap(find.byKey(const Key('sendCode')));
    await tester.pumpAndSettle();
    expect(find.textContaining('بالصيغة الدولية يبدأ'), findsOneWidget); // client-side validation, nothing sent
    expect(backend.seen.where((s) => s.path == 'auth/otp/request'), isEmpty);

    await tester.enterText(find.byKey(const Key('phone')), '+967722000009');
    await tester.tap(find.byKey(const Key('sendCode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('code')), '111111');
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();
    expect(find.text('رمز غير صحيح أو منتهٍ.'), findsOneWidget);
    expect(await store.read(), isNull);

    await tester.enterText(find.byKey(const Key('code')), '000000');
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();

    expect((await store.read())!.access, 'a1');
    expect(find.byKey(const Key('toggleOnline')), findsOneWidget);
    expect(find.text('لا يوجد اشتراك ساري.'), findsOneWidget);
    expect(find.text('الاشتراك'), findsWidgets); // shortcut to fix the reason
    final otp = backend.seen.firstWhere((s) => s.path == 'auth/otp/verify');
    expect(otp.headers['X-RideFlow-App'], 'test-driver');
    expect(otp.headers.containsKey('Authorization'), isFalse);
  });
}
