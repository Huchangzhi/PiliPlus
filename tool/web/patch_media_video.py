#!/usr/bin/env python3
"""Make media_kit_video's web surface fill its viewport.

Usage: patch_media_video.py <media_kit_video package root>
"""
import pathlib
import sys

pkg = pathlib.Path(sys.argv[1])
web = pkg / 'lib/src/video/video_web.dart'
s = web.read_text()
if 'Let the DOM video fill the viewport' in s:
    print('media_kit_video already patched')
    raise SystemExit(0)
old = '''                ClipRect(
                  child: FittedBox(
                    fit: videoViewParameters.fit,
                    alignment: videoViewParameters.alignment,
                    child: ValueListenableBuilder<PlatformVideoController?>(
                      valueListenable: widget.controller.notifier,
                      builder: (context, notifier, _) => notifier == null
                          ? const SizedBox.shrink()
                          : ValueListenableBuilder<int?>(
                              valueListenable: notifier.id,
                              builder: (context, id, _) {
                                return ValueListenableBuilder<Rect?>(
                                  valueListenable: notifier.rect,
                                  builder: (context, rect, _) {
                                    if (id != null &&
                                        rect != null &&
                                        _visible) {
                                      return SizedBox(
                                        // Apply aspect ratio if provided.
                                        width:
                                            videoViewParameters.aspectRatio ==
                                                    null
                                                ? rect.width
                                                : rect.height *
                                                    videoViewParameters
                                                        .aspectRatio!,
                                        height: rect.height,
                                        child: HtmlElementView(
                                          key: _key,
                                          viewType:
                                              'com.alexmercerind.media_kit_video.$id',
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ),'''
new = '''                // Flutter web platform views cannot be scaled by Flutter
                // transforms. Let the DOM video fill the viewport instead.
                ValueListenableBuilder<PlatformVideoController?>(
                  valueListenable: widget.controller.notifier,
                  builder: (context, notifier, _) => notifier == null
                      ? const SizedBox.shrink()
                      : ValueListenableBuilder<int?>(
                          valueListenable: notifier.id,
                          builder: (context, id, _) {
                            return ValueListenableBuilder<Rect?>(
                              valueListenable: notifier.rect,
                              builder: (context, rect, _) {
                                if (id != null && rect != null && _visible) {
                                  return HtmlElementView(
                                    key: _key,
                                    viewType:
                                        'com.alexmercerind.media_kit_video.$id',
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            );
                          },
                        ),
                ),'''
if old not in s:
    raise SystemExit('media_kit_video web build block not found')
web.write_text(s.replace(old, new))
print('media_kit_video patched')
