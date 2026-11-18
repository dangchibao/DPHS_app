import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Future<Uint8List> prepareImage(Uint8List bytes, {bool qr = false}) =>
    compute(_encode, {'bytes': bytes, 'qr': qr});
Uint8List _encode(Map<String, Object?> input) {
  try {
    return _encodeValidated(input);
  } catch (error) {
    if (error is ArgumentError) rethrow;
    throw ArgumentError('Không đọc được ảnh PNG/JPEG.');
  }
}

Uint8List _encodeValidated(Map<String, Object?> input) {
  final bytes = input['bytes'] as Uint8List, qr = input['qr'] == true;
  if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
    throw ArgumentError('Chọn ảnh PNG/JPEG tối đa 8MB.');
  }
  const maxPixels = 8000000;
  final img.Decoder decoder;
  if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71) {
    decoder = img.PngDecoder(maxPixels: maxPixels);
  } else if (bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 216) {
    decoder = img.JpegDecoder(maxPixels: maxPixels);
  } else {
    throw ArgumentError('Chỉ nhận ảnh PNG/JPEG.');
  }
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width > 10000 ||
      info.height > 10000 ||
      info.width * info.height > maxPixels ||
      decoder.numFrames() > 1) {
    throw ArgumentError(
      'Ảnh không hợp lệ, ảnh động hoặc quá 8 triệu điểm ảnh.',
    );
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) throw ArgumentError('Không đọc được ảnh.');
  final oriented = img.bakeOrientation(decoded);
  var side = qr ? 768 : 1024;
  while (side >= 256) {
    final resized = (oriented.width <= side && oriented.height <= side)
        ? oriented
        : img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? side : null,
            height: oriented.height > oriented.width ? side : null,
            interpolation: qr
                ? img.Interpolation.nearest
                : img.Interpolation.average,
          );
    // New RGB canvas strips EXIF/GPS/ICC/text metadata and flattens transparency.
    final clean = img.Image(
      width: resized.width,
      height: resized.height,
      numChannels: 3,
    );
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, resized);
    final output = qr
        ? img.encodePng(clean)
        : img.encodeJpg(clean, quality: 80);
    if (output.length <= (qr ? 65536 : 204800)) {
      return Uint8List.fromList(output);
    }
    side = side * 3 ~/ 4;
  }
  throw ArgumentError(
    qr
        ? 'Ảnh QR sau nén quá 64KB. Chọn ảnh chỉ chứa mã QR, không chụp cả trang.'
        : 'Ảnh sau nén quá 200KB. Chọn ảnh nhỏ hơn.',
  );
}
