import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> saveFile(String name, String mimeType, Uint8List bytes) async {
  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType)));
  (web.HTMLAnchorElement()
        ..href = url
        ..download = name)
      .click();
  web.URL.revokeObjectURL(url);
}
