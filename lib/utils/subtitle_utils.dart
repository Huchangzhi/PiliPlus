import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/models/video/subtitle_cue.dart';
import 'package:collection/collection.dart' show IterableExtension;

enum SubtitleFormat implements EnumWithLabel {
  json('JSON'),
  vtt('WEBVTT'),
  srt('SRT');

  @override
  final String label;
  const SubtitleFormat(this.label);
}

abstract final class SubtitleUtils {
  static String _vttTimecode(num seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    seconds %= 3600;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    seconds %= 60;
    final sms = seconds.toStringAsFixed(3).padLeft(6, '0');
    return "$h:$m:$sms";
  }

  static String json2Vtt(List list) {
    final sb = StringBuffer('WEBVTT\n\n')
      ..writeAll(
        list.map(
          (item) =>
              '${_vttTimecode(item['from'])} --> ${_vttTimecode(item['to'])}\n${item['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }

  static String _srtTimecode(num seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    seconds %= 3600;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    seconds %= 60;
    final s = seconds.toInt();
    final ms = ((seconds - s) * 1000).round().toString().padLeft(3, '0');
    return '$h:$m:${s.toString().padLeft(2, '0')},$ms';
  }

  static String json2Srt(List list) {
    final sb = StringBuffer()
      ..writeAll(
        list.mapIndexed(
          (i, e) =>
              '${i + 1}\n${_srtTimecode(e['from'])} --> ${_srtTimecode(e['to'])}\n${e['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }

  static final RegExp _timing = RegExp(
    r'((?:\d{1,2}:)?\d{1,2}:\d{2}[.,]\d{1,3})\s*-->\s*((?:\d{1,2}:)?\d{1,2}:\d{2}[.,]\d{1,3})',
  );

  /// Web 端没有 mpv 字幕轨，字幕要自己解析成时间轴再绘制。
  static List<SubtitleCue> json2Cues(List list) {
    final cues = <SubtitleCue>[];
    for (final item in list) {
      if (item case Map json) {
        final text = '${json['content'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        cues.add(
          SubtitleCue(
            start: Duration(
              milliseconds: ((json['from'] as num? ?? 0) * 1000).round(),
            ),
            end: Duration(
              milliseconds: ((json['to'] as num? ?? 0) * 1000).round(),
            ),
            text: text,
          ),
        );
      }
    }
    return cues..sort();
  }

  static Duration? _parseTimecode(String value) {
    final parts = value.trim().split(RegExp(r'[:.,]'));
    if (parts.length < 3) return null;
    final ms = int.tryParse(parts.last.padRight(3, '0')) ?? 0;
    final seconds = int.tryParse(parts[parts.length - 2]) ?? 0;
    final minutes = int.tryParse(parts[parts.length - 3]) ?? 0;
    final hours = parts.length > 3
        ? (int.tryParse(parts[parts.length - 4]) ?? 0)
        : 0;
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: ms,
    );
  }

  /// Parses WEBVTT / SRT text into cues.
  static List<SubtitleCue> text2Cues(String source) {
    final cues = <SubtitleCue>[];
    Duration? start;
    Duration? end;
    final text = StringBuffer();

    void flush() {
      if (start != null && end != null) {
        final body = text.toString().trim();
        if (body.isNotEmpty) {
          cues.add(SubtitleCue(start: start!, end: end!, text: body));
        }
      }
      start = null;
      end = null;
      text.clear();
    }

    for (final raw in source.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) {
        flush();
        continue;
      }
      final match = _timing.firstMatch(line);
      if (match != null) {
        flush();
        start = _parseTimecode(match.group(1)!);
        end = _parseTimecode(match.group(2)!);
      } else if (start != null) {
        if (text.isNotEmpty) text.write('\n');
        text.write(line.replaceAll(RegExp(r'<[^>]*>'), ''));
      }
    }
    flush();
    return cues..sort();
  }
}
