// The transport is selected at compile time: native builds keep dio/http2,
// web builds relay every request through the user-configured proxy server.
export 'init_io.dart' if (dart.library.js_interop) 'init_web.dart';
