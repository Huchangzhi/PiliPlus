import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image_platform_interface_ce/cached_network_image_platform_interface_ce.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

/// Browser image loader. Bytes are fetched with `package:http` so the app can
/// route them through the relay (which supplies bilibili's Referer checks).
class ImageLoader {
  @Deprecated('Use loadImageAsync instead')
  Stream<ui.Codec> loadBufferAsync(
    String url,
    String? cacheKey,
    StreamController<ImageChunkEvent> chunkEvents,
    DecoderBufferCallback decode,
    BaseCacheManager cacheManager,
    int? maxHeight,
    int? maxWidth,
    Map<String, String>? headers,
    ImageRenderMethodForWeb imageRenderMethodForWeb,
    VoidCallback evictImage,
  ) {
    return _load(url, (buffer) => decode(buffer), chunkEvents);
  }

  Stream<ui.Codec> loadImageAsync(
    String url,
    String? cacheKey,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
    BaseCacheManager cacheManager,
    int? maxHeight,
    int? maxWidth,
    Map<String, String>? headers,
    ImageRenderMethodForWeb imageRenderMethodForWeb,
    VoidCallback evictImage,
  ) {
    return _load(url, (buffer) => decode(buffer), chunkEvents);
  }

  Stream<ui.Codec> _load(
    String url,
    Future<ui.Codec> Function(ui.ImmutableBuffer) decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async* {
    final uri = Uri.parse(url);
    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw NetworkImageLoadException(statusCode: response.statusCode, uri: uri);
    }
    chunkEvents.add(
      ImageChunkEvent(
        cumulativeBytesLoaded: bytes.length,
        expectedTotalBytes: bytes.length,
      ),
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    yield await decode(buffer);
  }
}
