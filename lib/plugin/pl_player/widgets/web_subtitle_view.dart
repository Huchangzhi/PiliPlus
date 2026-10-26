import 'dart:math' show sqrt;

import 'package:PiliPlus/models/video/subtitle_cue.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Web 后端没有 mpv 字幕轨，字幕由时间轴自己绘制，样式沿用「字幕设置」。
class WebSubtitleView extends StatefulWidget {
  const WebSubtitleView({
    required this.plPlayerController,
    required this.configuration,
    super.key,
  });

  final PlPlayerController plPlayerController;
  final SubtitleViewConfiguration configuration;

  @override
  State<WebSubtitleView> createState() => _WebSubtitleViewState();
}

class _WebSubtitleViewState extends State<WebSubtitleView> {
  static const _referenceSize = 1920 * 1080;

  List<SubtitleCue> _cues = const [];
  int _cursor = 0;
  String _text = '';

  PlPlayerController get _controller => widget.plPlayerController;

  @override
  void initState() {
    super.initState();
    _controller.webSubtitleCues.addListener(_onCuesChanged);
    _controller.addPositionListener(_onPosition);
    _cues = _controller.webSubtitleCues.value;
  }

  @override
  void dispose() {
    _controller.webSubtitleCues.removeListener(_onCuesChanged);
    _controller.removePositionListener(_onPosition);
    super.dispose();
  }

  void _onCuesChanged() {
    // 播放器可能在 overlay 之后才创建，这里补注册高频位置事件。
    _controller.addPositionListener(_onPosition);
    setState(() {
      _cues = _controller.webSubtitleCues.value;
      _cursor = 0;
    });
  }

  void _onPosition(Duration position) {
    final text = _resolve(position);
    if (text != _text && mounted) {
      setState(() => _text = text);
    }
  }

  String _resolve(Duration position) {
    if (_cues.isEmpty) return '';
    while (_cursor + 1 < _cues.length && _cues[_cursor + 1].start <= position) {
      _cursor++;
    }
    while (_cursor > 0 && _cues[_cursor].start > position) {
      _cursor--;
    }
    final cue = _cues[_cursor];
    return cue.contains(position) ? cue.text : '';
  }

  @override
  Widget build(BuildContext context) {
    final configuration = widget.configuration;
    return Obx(() {
      // 高频位置事件不可用时（播放器尚未就绪），至少按秒刷新。
      _text = _resolve(Duration(seconds: _controller.position.value));
      return LayoutBuilder(
        builder: (context, constraints) {
          final ratio =
              (constraints.maxWidth * constraints.maxHeight) / _referenceSize;
          final textScaler =
              configuration.textScaler ??
              TextScaler.linear(sqrt(ratio.clamp(0.0, 1.0)));
          return Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              padding: configuration.padding,
              alignment: Alignment.bottomCenter,
              child: Text(
                _text,
                style: configuration.style,
                textAlign: configuration.textAlign,
                textScaler: textScaler,
              ),
            ),
          );
        },
      );
    });
  }
}
