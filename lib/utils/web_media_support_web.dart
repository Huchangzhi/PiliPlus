// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

String _can(String mime) => html.VideoElement().canPlayType(mime);

String _best(List<String> codecs) {
  String best = '';
  for (final codec in codecs) {
    final value = _can('video/mp4; codecs="$codec"');
    if (value == 'probably') return value;
    if (value.isNotEmpty) best = value;
  }
  return best.isEmpty ? 'no' : best;
}

bool get browserSupportsHevc =>
    _can('video/mp4; codecs="hvc1.1.6.L93.B0"').isNotEmpty ||
    _can('video/mp4; codecs="hev1.1.6.L93.B0"').isNotEmpty;

/// Compact codec report, surfaced in web playback errors so failures on
/// devices without devtools can still be diagnosed from a screenshot.
String describeWebMediaSupport() {
  final avc = _best(const ['avc1.42001E', 'avc1.4D001E', 'avc1.640028']);
  final hevc = _best(const ['hvc1.1.6.L93.B0', 'hev1.1.6.L93.B0']);
  final mp4Av1 = _best(const ['av01.0.05M.08']);
  final vp9 = _can('video/webm; codecs="vp9"');
  final webmAv1 = _can('video/webm; codecs="av01.0.05M.08"');
  return 'mp4{avc:$avc hevc:$hevc av1:$mp4Av1} '
      'webm{vp9:${vp9.isEmpty ? 'no' : vp9} '
      'av1:${webmAv1.isEmpty ? 'no' : webmAv1}}';
}
