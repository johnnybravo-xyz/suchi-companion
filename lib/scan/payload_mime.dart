import 'dart:convert';
import 'dart:io';

const _signatureCheckedMimeTypes = <String>{
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/heic',
  'image/heif',
};

Future<bool> payloadMatchesDeclaredMime(File file, String mimeType) async {
  if (!_signatureCheckedMimeTypes.contains(mimeType)) return true;
  return await _detectMime(file) == mimeType;
}

Future<String?> _detectMime(File file) async {
  final handle = await file.open();
  try {
    final bytes = await handle.read(4096);
    if (bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2d) {
      return 'application/pdf';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    const png = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (bytes.length >= png.length && _bytesEqual(bytes, png)) {
      return 'image/png';
    }
    if (bytes.length >= 16 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      final boxSize =
          bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3];
      if (boxSize >= 16 &&
          boxSize <= bytes.length &&
          boxSize <= 4096 &&
          (boxSize - 16) % 4 == 0) {
        final brands = <String>[];
        for (var offset = 8; offset < boxSize; offset += 4) {
          if (offset == 12) continue;
          brands.add(
            ascii.decode(bytes.sublist(offset, offset + 4)).toLowerCase(),
          );
        }
        if (brands.any(const {'heic', 'heix', 'hevc', 'hevx'}.contains)) {
          return 'image/heic';
        }
        if (brands.any(const {'mif1', 'msf1'}.contains)) return 'image/heif';
      }
    }
    return null;
  } on FormatException {
    return null;
  } finally {
    await handle.close();
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  for (var index = 0; index < right.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
