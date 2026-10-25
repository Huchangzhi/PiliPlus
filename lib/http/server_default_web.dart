import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const _buildTimeDefault = String.fromEnvironment(
  'PILI_SERVER',
  defaultValue: 'http://127.0.0.1:8787',
);

/// Runtime default from `pili-config.js`, so a static deployment can point at
/// its relay without rebuilding.
String get webServerDefault {
  final value = globalContext.getProperty<JSAny?>('PILI_SERVER'.toJS);
  final raw = value?.dartify();
  if (raw is String) {
    final server = raw.trim();
    if (server.isNotEmpty) return server.replaceFirst(RegExp(r'/+$'), '');
  }
  return _buildTimeDefault;
}
