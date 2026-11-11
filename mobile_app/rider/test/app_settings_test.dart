// D051: the operator's region and settings come from the server, are kept on the phone, and refresh on their own.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_rider/app/providers.dart';
import 'package:rideflow_rider/core/api/api_client.dart';
import 'package:rideflow_rider/core/app_settings.dart';
import 'package:rideflow_rider/core/auth/session_store.dart';
import 'package:rideflow_rider/core/format.dart';
import 'package:rideflow_rider/core/realtime/events_socket.dart';

import 'support/fake_backend.dart';

Map<String, dynamic> config({String version = '3.100', String unit = 'km', int refresh = 20, List<int>? etas}) => {
      'version': version,
      'region': {
        'operator_name': 'Operator',
        'country': 'YE',
        'currency': 'YER',
        'currency_symbol': 'ر.ي',
        'currency_minor_units': 2,
        'distance_unit': unit,
        'phone_country_code': '+967',
        'time_zone': 'Asia/Aden',
        'locale': 'ar',
        'map_center': {'lat': 14.5, 'lng': 49.1},
      },
      'settings': {
        'app.driver_requests_refresh_seconds': refresh,
        'app.connection_cut_grace_seconds': 9,
        'app.offer_eta_choices_minutes': etas ?? [4, 6, 12],
      },
    };

void main() {
  tearDown(() => currentSettings = const AppSettings());

  group('AppSettings', () {
    test('reads the region and settings, and survives being kept on the phone', () {
      final s = AppSettings.fromJson(config());
      final again = AppSettings.decode(s.encode())!;
      expect(again.version, '3.100');
      expect(again.region.country, 'YE');
      expect(again.region.phoneCode, '+967');
      expect(again.region.mapLat, 14.5);
      expect(again.driverRequestsRefresh, const Duration(seconds: 20));
      expect(again.connectionCutGrace, const Duration(seconds: 9));
      expect(again.offerEtaChoices, [4, 6, 12]);
    });

    test('a copy that cannot be read is ignored', () {
      expect(AppSettings.decode(null), isNull);
      expect(AppSettings.decode('not json'), isNull);
    });

    test('the operator symbol for its own currency, the code for any other', () {
      currentSettings = AppSettings.fromJson(config());
      expect(formatMoney(150000, 'YER', 2), '1,500 ر.ي');
      expect(formatMoney(150000, 'SAR', 2), '1,500 SAR');
    });

    test('distance in the operator unit', () {
      currentSettings = AppSettings.fromJson(config());
      expect(formatDistance(12200), '12.2 km');
      currentSettings = AppSettings.fromJson(config(unit: 'mi'));
      expect(formatDistance(16093), '10.0 mi');
      expect(formatDistance(30), '98 ft');
    });
  });

  test('every response reports the settings version it was answered under', () async {
    final backend = FakeBackend({'GET me': (_) => (200, {})}, responseHeaders: {'x-rideflow-config': '7.1'});
    final client = ApiClient(session: SessionStore(MemoryKV()), dio: backend.dio(), appClientId: 'test-rider');
    final seen = <String>[];
    client.onConfigVersion = seen.add;
    await client.get('me');
    expect(seen, ['7.1']);
  });

  test('the event stream passes on a settings change', () async {
    final socket = EventsSocket(session: SessionStore(MemoryKV()));
    final got = <String>[];
    final sub = socket.configChanges.listen(got.add);
    socket.debugReceive('{"type":"config","version":"8.2"}');
    await Future<void>.delayed(Duration.zero);
    expect(got, ['8.2']);
    await sub.cancel();
  });

  group('AppSettingsController', () {
    late FakeBackend backend;
    late MemoryKV kv;
    late ProviderContainer container;
    var served = config();

    setUp(() {
      served = config();
      backend = FakeBackend({'GET app/config': (_) => (200, served)});
      kv = MemoryKV();
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(ApiClient(session: SessionStore(MemoryKV()), dio: backend.dio(), appClientId: 'test-rider')),
        prefsProvider.overrideWithValue(kv),
      ]);
    });
    tearDown(() => container.dispose());

    int reads() => backend.seen.where((s) => s.path == 'app/config').length;

    test('reads the server, applies it everywhere and keeps a copy on the phone', () async {
      await container.read(appSettingsProvider.notifier).refresh();
      expect(container.read(appSettingsProvider).version, '3.100');
      expect(currentSettings.region.currencySymbol, 'ر.ي');
      await Future<void>.delayed(Duration.zero);
      expect(AppSettings.decode(await kv.read(appSettingsKey))!.version, '3.100');
    });

    test('a new version reported anywhere is read once; the same version is not', () async {
      final notifier = container.read(appSettingsProvider.notifier);
      await notifier.refresh();
      notifier.noteVersion('3.100');
      await Future<void>.delayed(Duration.zero);
      expect(reads(), 1);
      served = config(version: '4.100', refresh: 45);
      notifier.noteVersion('4.100');
      notifier.noteVersion('4.100');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reads(), 2, reason: 'one read in flight serves both reports');
      expect(container.read(appSettingsProvider).driverRequestsRefresh, const Duration(seconds: 45));
    });

    test('without the server the last copy stays', () async {
      currentSettings = AppSettings.fromJson(config(version: '2.1'));
      final offline = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(ApiClient(session: SessionStore(MemoryKV()), dio: FakeBackend({}).dio(), appClientId: 'x')),
        prefsProvider.overrideWithValue(MemoryKV()),
      ]);
      addTearDown(offline.dispose);
      await offline.read(appSettingsProvider.notifier).refresh();
      expect(offline.read(appSettingsProvider).version, '2.1');
    });
  });
}
