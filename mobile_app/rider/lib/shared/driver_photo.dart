import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/models.dart';
import '../design/components.dart';

/// The driver's photo, or the first letter of their name until it loads, if it fails, or when there is none.
class DriverPhoto extends ConsumerWidget {
  const DriverPhoto({super.key, required this.driver, this.radius = 24, this.name});
  final Driver? driver;
  final double radius;

  /// When the screen names the driver differently.
  final String? name;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = driver?.photoUrl;
    final image = path == null ? null : ref.watch(photoBytesProvider(path)).valueOrNull;
    return DriverAvatar(name: name ?? driver?.name ?? '', radius: radius, image: image);
  }
}
