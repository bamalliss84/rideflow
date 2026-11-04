import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/auth/session_store.dart';
import 'design/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    RfLayout.use(RfLayout.decode(await const KeystoreKV().read(layoutKey)) ?? RfLayoutModel.a);
  } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light); // the whole app is dark
  runApp(const ProviderScope(child: DriverApp()));
}
