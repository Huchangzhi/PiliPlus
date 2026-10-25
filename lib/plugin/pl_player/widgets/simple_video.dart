import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit_video/media_kit_video.dart';

/// Minimal video surface used by the player and gallery viewer.
class SimpleVideo extends StatelessWidget {
  const SimpleVideo({
    super.key,
    required this.controller,
    this.fill = Colors.black,
    this.aspectRatio,
  });

  final VideoController controller;
  final Color fill;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Flutter web renders the video as a DOM platform view; wrapping it in
      // FittedBox/Transform prevents it from following layout changes.
      return LayoutBuilder(
        builder: (context, constraints) {
          final video = Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
            fill: fill,
          );
          if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
            return SizedBox.expand(child: video);
          }
          return SizedBox(width: 1280, height: 720, child: video);
        },
      );
    }
    return Video(
      controller: controller,
      controls: NoVideoControls,
      fill: fill,
      aspectRatio: aspectRatio,
    );
  }
}
