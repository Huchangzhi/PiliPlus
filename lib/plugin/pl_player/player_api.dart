import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

/// Compatibility helpers for the small set of fork-only media_kit APIs used by
/// the original app. On the web there is no libmpv, so unsupported operations
/// are ignored while the standard playback API keeps working.

Future<void> setPlayerProperty(Player player, String name, String value) async {
  switch (name) {
    case 'volume':
      final volume = double.tryParse(value);
      if (volume != null) await player.setVolume(volume);
      break;
    case 'speed':
      final speed = double.tryParse(value);
      if (speed != null) await player.setRate(speed);
      break;
    case 'pause':
      value == 'yes' ? await player.pause() : await player.play();
      break;
  }
}

Future<String?> getPlayerProperty(Player player, String name) async {
  return playerPropertyLabel(player, name);
}

/// Synchronous display value used by player-info panels.
String? playerPropertyLabel(Player player, String name) {
  switch (name) {
    case 'volume':
      return player.state.volume.toStringAsFixed(0);
    case 'speed':
      return player.state.rate.toString();
    case 'hwdec-current':
      return 'N/A';
    default:
      return null;
  }
}

Future<void> playerCommand(Player player, List<String> args) async {
  // Shader selection is a native libmpv feature and has no browser equivalent.
}

void setMediaHeaders(
  Player player, {
  required String userAgent,
  required String referer,
}) {
  // Browser media requests cannot override Referer/User-Agent. The relay
  // server supplies those headers when media is fetched through it.
}

Stream<(int, int)> playerSizeStream(Player player) => player.stream.videoParams
    .where((params) => params.w != null && params.h != null)
    .map((params) => (params.w!, params.h!));


/// Route browser media requests through the relay so Referer/User-Agent and
/// Range handling match a bilibili web page.
String maybeProxyMediaUrl(String url) {
  if (!kIsWeb) return url;
  if (!url.startsWith('http://') && !url.startsWith('https://')) return url;
  final server = Pref.webApiServer;
  final prefix = '$server/proxy?url=';
  if (url.startsWith(prefix)) return url;
  return '$prefix${Uri.encodeComponent(url)}';
}
