import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/api/api_client.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/core/photo_picker.dart';
import 'package:rideflow_driver/design/theme.dart';
import 'package:rideflow_driver/features/account/account_screen.dart';

import 'support/fake_backend.dart';

final _pixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAEBgIApD5fRAAAAABJRU5ErkJggg==');

Map<String, dynamic> _profile({String? photo}) => {
      'id': 'd1',
      'full_name': 'سعيد',
      'phone': '+967700000000',
      'status': 'approved',
      'photo_url': photo,
      'vehicles': [],
      'documents': [],
    };

class _Picker extends PhotoPicker {
  _Picker(this.result);
  final Uint8List? result;
  final sources = <ImageSource>[];
  @override
  Future<Uint8List?> pick(ImageSource source) async {
    sources.add(source);
    return result;
  }
}

Future<FakeBackend> _pump(WidgetTester tester, Map<String, Handler> routes, PhotoPicker picker) async {
  final backend = FakeBackend(routes);
  final store = SessionStore(MemoryKV());
  await store.save(const Tokens('a', 'r'));
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      sessionStoreProvider.overrideWithValue(store),
      prefsProvider.overrideWithValue(MemoryKV()),
      photoPickerProvider.overrideWithValue(picker),
      apiClientProvider.overrideWith((ref) => ApiClient(session: store, dio: backend.dio(), appClientId: 'test-driver')),
    ],
    child: MaterialApp(
      theme: buildRideFlowTheme(),
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: const AccountScreen(),
    ),
  ));
  await _settle(tester);
  return backend;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await _settle(tester);
}

ImageProvider? _shown(WidgetTester tester) => tester.widget<CircleAvatar>(find.byKey(const Key('profilePhoto'))).backgroundImage;

Iterable<Seen> _sent(FakeBackend b, String method) => b.seen.where((s) => s.method == method && s.path == 'driver/photo');

/// [source] with a text note placed after its header, the way a phone's file carries extra details.
Uint8List _withNote(Uint8List source, String note) {
  int crc(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c ^= b;
      for (var k = 0; k < 8; k++) {
        c = c & 1 == 1 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
      }
    }
    return c ^ 0xFFFFFFFF;
  }

  final body = [...ascii.encode('tEXt'), ...ascii.encode('Comment'), 0, ...ascii.encode(note)];
  final length = ByteData(4)..setUint32(0, body.length - 4);
  final check = ByteData(4)..setUint32(0, crc(body));
  const afterHeader = 33; // the signature and the first chunk
  return Uint8List.fromList([...source.take(afterHeader), ...length.buffer.asUint8List(), ...body, ...check.buffer.asUint8List(), ...source.skip(afterHeader)]);
}

void main() {
  testWidgets('with no photo it offers to add one; the photo then shows at once', (tester) async {
    var profile = _profile();
    final picker = _Picker(_pixel);
    final backend = await _pump(tester, {
      'GET driver/profile': (_) => (200, profile),
      'POST driver/photo': (_) {
        profile = _profile(photo: 'drivers/d1/photo?v=1');
        return (200, profile);
      },
      'GET drivers/d1/photo': (_) => (200, _pixel),
    }, picker);
    expect(_shown(tester), isNull);
    expect(find.text('إضافة صورتي'), findsOneWidget);

    await _tap(tester, 'addPhoto');
    expect(find.byKey(const Key('photoRemove')), findsNothing, reason: 'nothing to remove yet');
    await _tap(tester, 'photoGallery');

    expect(picker.sources, [ImageSource.gallery]);
    final post = _sent(backend, 'POST').single;
    expect(post.headers['Idempotency-Key'], isNotNull);
    expect((post.body! as FormData).files.single.key, 'file');
    expect((_shown(tester)! as MemoryImage).bytes, _pixel);
    expect(find.text('إضافة صورتي'), findsNothing);
    expect(find.text('تظهر للراكب عند عرضك وفي الرحلة.'), findsOneWidget);
  });

  testWidgets('taking a photo uses the camera, and removing it goes back to the letter', (tester) async {
    var profile = _profile(photo: 'drivers/d1/photo?v=1');
    final picker = _Picker(_pixel);
    final backend = await _pump(tester, {
      'GET driver/profile': (_) => (200, profile),
      'GET drivers/d1/photo': (_) => (200, _pixel),
      'POST driver/photo': (_) => (200, profile),
      'DELETE driver/photo': (_) {
        profile = _profile();
        return (204, null);
      },
    }, picker);
    expect(_shown(tester), isA<MemoryImage>());

    await _tap(tester, 'changePhoto');
    await _tap(tester, 'photoCamera');
    expect(picker.sources, [ImageSource.camera]);
    expect(_sent(backend, 'POST'), hasLength(1));

    await _tap(tester, 'changePhoto');
    await _tap(tester, 'photoRemove');
    expect(_sent(backend, 'DELETE'), hasLength(1));
    expect(_shown(tester), isNull);
    expect(find.text('إضافة صورتي'), findsOneWidget);
  });

  testWidgets('choosing nothing sends nothing, and leaves no spinner', (tester) async {
    final backend = await _pump(tester, {'GET driver/profile': (_) => (200, _profile())}, _Picker(null));
    await _tap(tester, 'addPhoto');
    await _tap(tester, 'photoGallery');
    expect(_sent(backend, 'POST'), isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a refused photo says so and changes nothing', (tester) async {
    final backend = await _pump(tester, {
      'GET driver/profile': (_) => (200, _profile()),
      'POST driver/photo': (_) => (400, {'code': 'validation_error', 'detail': 'bad'}),
    }, _Picker(_pixel));
    await _tap(tester, 'addPhoto');
    await _tap(tester, 'photoGallery');
    expect(_sent(backend, 'POST'), hasLength(1));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(_shown(tester), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a photo is cut to the middle square and loses what the file carried', (tester) async {
    await tester.runAsync(() async {
      // Wider than tall: red on the left, blue on the right, a green stripe down the middle.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 40, 20), ui.Paint()..color = const Color(0xFFFF0000));
      canvas.drawRect(const Rect.fromLTWH(40, 0, 40, 20), ui.Paint()..color = const Color(0xFF0000FF));
      canvas.drawRect(const Rect.fromLTWH(30, 0, 20, 20), ui.Paint()..color = const Color(0xFF00FF00));
      final wide = await recorder.endRecording().toImage(80, 20);
      final png = (await wide.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final source = _withNote(png, 'GPS 14.5426 49.1242');
      expect(latin1.decode(source), contains('GPS 14.5426'));

      final out = await squarePhoto(source, size: 32);

      expect(latin1.decode(out), isNot(contains('GPS 14.5426')));
      final image = (await (await ui.instantiateImageCodec(out)).getNextFrame()).image;
      expect((image.width, image.height), (32, 32));
      final pixels = (await image.toByteData())!;
      List<int> at(int x, int y) => [for (var c = 0; c < 3; c++) pixels.getUint8((y * 32 + x) * 4 + c)];
      expect(at(16, 16), [0, 255, 0]);
      // Scaling softens the outermost pixels a little. The red and blue parts must still be gone.
      for (final edge in [at(0, 16), at(31, 16)]) {
        expect(edge[1], greaterThan(edge[0] + edge[2]), reason: 'only the middle of the picture is left: $edge');
      }
    });
  });
}
