import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveFile(String name, String mimeType, Uint8List bytes) async {
  await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: mimeType, name: name)], fileNameOverrides: [name]));
}
