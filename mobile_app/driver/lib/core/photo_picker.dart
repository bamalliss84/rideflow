import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Rect;
import 'package:image_picker/image_picker.dart';

/// The driver's photo, ready to upload. Null when nothing was chosen.
class PhotoPicker {
  const PhotoPicker();

  Future<Uint8List?> pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1024);
    if (file == null) return null;
    return squarePhoto(await file.readAsBytes());
  }
}

/// Crops to the middle square and draws it again as a new image. Riders can open this file, and a phone's photo can carry
/// where and when it was taken: only the pixels are copied, so none of that goes with it.
Future<Uint8List> squarePhoto(Uint8List source, {int size = 512}) async {
  final codec = await ui.instantiateImageCodec(source);
  final image = (await codec.getNextFrame()).image;
  final side = image.width < image.height ? image.width : image.height;
  final from = Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side.toDouble(), side.toDouble());
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(image, from, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), ui.Paint()..filterQuality = ui.FilterQuality.medium);
  final square = await recorder.endRecording().toImage(size, size);
  final png = await square.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  square.dispose();
  codec.dispose();
  return png!.buffer.asUint8List();
}
