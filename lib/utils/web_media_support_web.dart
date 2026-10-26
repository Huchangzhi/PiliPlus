import 'dart:html' as html;

String _mp4(String codecs) =>
    html.VideoElement().canPlayType('video/mp4; codecs="$codecs"');

String _label(String result) => result.isEmpty ? 'no' : result;

bool get browserSupportsHevc => _mp4('hvc1.1.6.L93.B0').isNotEmpty;

/// Compact codec report, surfaced in web playback errors so failures on
/// devices without devtools can still be diagnosed from a screenshot.
String describeWebMediaSupport() =>
    'avc:${_label(_mp4('avc1.42E01E'))} '
    'hevc:${_label(_mp4('hvc1.1.6.L93.B0'))} '
    'av1:${_label(_mp4('av01.0.05M.08'))}';
