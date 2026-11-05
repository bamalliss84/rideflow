import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/auth/session_store.dart';
import 'design/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read before the first frame, so a driver on day doesn't see a flash of night.
  try {
    RfColors.use(decodeAppearance(await const KeystoreKV().read(appearanceKey)) ?? RfAppearance.night);
  } catch (_) {}
  try {
    RfLayout.use(RfLayout.decode(await const KeystoreKV().read(layoutKey)) ?? RfLayoutModel.a);
  } catch (_) {}
  applyAppearanceToSystemBars();
  runApp(const ProviderScope(child: DriverApp()));
}
