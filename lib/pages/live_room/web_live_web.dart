// ignore_for_file: deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class WebLivePlayer extends StatefulWidget {
  const WebLivePlayer({super.key, required this.url});

  /// Relay URL of the HLS playlist (e.g. http://host:port/hls?url=...).
  final String url;

  @override
  State<WebLivePlayer> createState() => _WebLivePlayerState();
}

class _WebLivePlayerState extends State<WebLivePlayer> {
  late final String _viewType =
      'pili-live-${DateTime.now().microsecondsSinceEpoch}';
  late final html.IFrameElement _iframe;

  String get _src => '/live.html?url=${Uri.encodeComponent(widget.url)}';

  @override
  void initState() {
    super.initState();
    _iframe = html.IFrameElement()
      ..src = _src
      ..allowFullscreen = true
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#000';
    _iframe.setAttribute('allow', 'autoplay; fullscreen; picture-in-picture');
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _iframe,
    );
  }

  @override
  void didUpdateWidget(covariant WebLivePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _iframe.src = _src;
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
