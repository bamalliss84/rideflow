import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/app/providers.dart';
import 'package:rideflow_driver/core/auth/session_store.dart';
import 'package:rideflow_driver/design/components.dart';
import 'package:rideflow_driver/design/theme.dart';
import 'package:rideflow_driver/design/tokens.dart';

void main() {
  tearDown(() => RfLayout.use(RfLayoutModel.a));

  test('the choice is kept on the phone, and a bad saved value is ignored', () async {
    final prefs = MemoryKV();
    final scope = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    addTearDown(scope.dispose);
    expect(scope.read(layoutProvider), RfLayoutModel.a);
    await scope.read(layoutProvider.notifier).set(RfLayoutModel.c);
    expect(prefs.values['rf_layout_model'], 'c');
    expect(RfLayout.decode('c'), RfLayoutModel.c);
    expect(RfLayout.decode('x'), isNull);
  });

  for (final (model, background, tall) in [(RfLayoutModel.a, RfColors.canvas, true), (RfLayoutModel.b, RfColors.surface, true), (RfLayoutModel.c, RfColors.canvas, false)]) {
    testWidgets('model ${model.name} draws groups its own way', (tester) async {
      RfLayout.use(model);
      await tester.pumpWidget(MaterialApp(
        theme: buildRideFlowTheme(),
        home: const Scaffold(body: RfGroup(title: 'T', children: [RfRow(key: Key('row'), title: 'x')])),
      ));
      expect(Theme.of(tester.element(find.byKey(const Key('row')))).scaffoldBackgroundColor, background);
      expect(tester.getSize(find.byKey(const Key('row'))).height, tall ? 50 : 42);
      final card = tester.widget<Material>(find.descendant(of: find.byType(RfCard), matching: find.byType(Material)).first);
      expect(card.shape, model == RfLayoutModel.b ? isA<Border>() : isA<RoundedRectangleBorder>());
    });
  }
}
