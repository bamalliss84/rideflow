import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/auth/session_store.dart';
import 'design/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read before the first frame, so a rider on night doesn't see a flash of day.
  try {
    RfColors.use(decodeAppearance(await const KeystoreKV().read(appearanceKey)) ?? RfAppearance.day);
  } catch (_) {}
  applyAppearanceToSystemBars();
  runApp(const ProviderScope(child: RiderApp()));
}
