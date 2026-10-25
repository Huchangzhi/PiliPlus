import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Routes browser asset requests through the configured relay. This keeps
/// bilibili's Referer/Hotlink checks happy and avoids CORS surprises.
String? maybeProxyUrl(String? url) {
  if (!kIsWeb || url == null || url.isEmpty) return url;
  if (!url.startsWith('http://') && !url.startsWith('https://')) return url;
  final server = Pref.webApiServer;
  final prefix = '$server/proxy?url=';
  if (url.startsWith(prefix)) return url;
  return '$prefix${Uri.encodeComponent(url)}';
}
