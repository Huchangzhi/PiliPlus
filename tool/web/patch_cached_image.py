#!/usr/bin/env python3
"""Patch cached_network_image_ce with a browser loader.

Usage: patch_cached_image.py <package>/cached_network_image/lib <project-root>
"""
import pathlib
import shutil
import sys

lib = pathlib.Path(sys.argv[1])
project = pathlib.Path(sys.argv[2])
loader = lib / 'src/image_provider/_image_loader_web.dart'
template = project / 'tool/web/patches/cached_network_image_loader_web.dart'
shutil.copy(template, loader)

provider = lib / 'src/image_provider/cached_network_image_provider.dart'
s = provider.read_text()
old_import = """import 'package:cached_network_image_platform_interface_ce/cached_network_image_platform_interface_ce.dart'
    if (dart.library.io) '_image_loader.dart'
    show ImageLoader;"""
new_import = """import 'package:cached_network_image_platform_interface_ce/cached_network_image_platform_interface_ce.dart'
    if (dart.library.io) '_image_loader.dart'
    if (dart.library.js_interop) '_image_loader_web.dart'
    show ImageLoader;"""
if old_import in s:
    s = s.replace(old_import, new_import)
elif '_image_loader_web.dart' not in s:
    raise SystemExit('cached_network_image import block not found')

marker = "  /// Web url of the image to load\n  final String url;"
if 'webImageUrlTransformer' not in s:
    s = s.replace(
        marker,
        "  /// Optional URL rewriter used by the web build to route requests\n"
        "  /// through the configured relay.\n"
        "  static String Function(String)? webImageUrlTransformer;\n\n"
        "  /// Web url of the image to load\n  final String url;",
    )
    s = s.replace(
        "  @override\n  Future<CachedNetworkImageProvider> obtainKey(",
        "  String get _effectiveUrl =>\n"
        "      webImageUrlTransformer?.call(url) ?? url;\n\n"
        "  @override\n  Future<CachedNetworkImageProvider> obtainKey(",
    )
    s = s.replace(
        "    return ImageLoader().loadBufferAsync(\n      url,",
        "    return ImageLoader().loadBufferAsync(\n      _effectiveUrl,",
    )
    s = s.replace(
        "    return ImageLoader().loadImageAsync(\n      url,",
        "    return ImageLoader().loadImageAsync(\n      _effectiveUrl,",
    )
provider.write_text(s)
print('cached_network_image web loader ready')
