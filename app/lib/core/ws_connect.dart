// WebSocket with the session: the browser sends the cookie by itself, the Android app
// needs the bearer header (only the io implementation can set headers).
export 'ws_connect_web.dart' if (dart.library.io) 'ws_connect_io.dart';
