import 'dart:io' show File;

import 'package:cached_network_image_ce/cached_network_image.dart';

/// Browser builds have no file cache. The web image loader fetches bytes
/// directly, but cached_network_image still dereferences its default cache
/// manager before loading, so provide a harmless implementation.
class WebCacheManager implements BaseCacheManager {
  const WebCacheManager();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> emptyCache() async {}

  @override
  Future<FileInfo?> getFileFromMemory(
    String key, {
    bool ignoreMemCache = false,
  }) async => null;

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => null;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => const Stream.empty();

  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) =>
      Future.error(UnsupportedError('file cache is not available on web'));

  @override
  Future<File> putFile(
    String url,
    List<int> fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) =>
      Future.error(UnsupportedError('file cache is not available on web'));

  @override
  Future<void> removeFile(String key) async {}
}
