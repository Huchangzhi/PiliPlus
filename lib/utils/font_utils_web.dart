import 'dart:typed_data';
import 'dart:ui' show loadFontFromList;

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

typedef AppFont = ({String? fontFamily, bool isCustom});

/// Browser font support. Custom fonts are kept in the browser's Hive storage
/// instead of on disk, so no data leaves the machine.
abstract final class FontUtils {
  static const kFontName = 'customFont.otf';
  static const _kFontExts = ['ttf', 'ttc', 'otf'];
  static const _storageKey = 'webCustomFontBytes';
  static const _storageNameKey = 'webCustomFontName';

  static Uint8List? _bytes;

  static AppFont _appFont = _initAppFont();
  static AppFont get appFont => _appFont;
  static set appFont(AppFont value) {
    _appFont = value;
  }

  static bool _isCutsomFont(String? fontFamily) {
    return fontFamily?.contains('/') ?? false;
  }

  static AppFont _initAppFont() {
    final String? appFont = GStorage.setting.get(SettingBoxKey.appFont);
    if (_isCutsomFont(appFont)) {
      return (fontFamily: appFont, isCustom: true);
    }
    return (fontFamily: appFont, isCustom: false);
  }

  static String? get fontFamily => _appFont.fontFamily;
  static bool get isCustom => _appFont.isCustom;

  static final WebFontFile fontFile = WebFontFile();

  static Future<void>? init() async {
    if (!isCustom) return;
    await _readAndLoad();
  }

  static Future<void> _readAndLoad() async {
    try {
      final bytes = await fontFile.readAsBytes();
      await _loadFont(bytes, fontFamily: fontFamily!);
    } catch (_) {}
  }

  static void removeFontIfExists() {
    fontFile.delete();
  }

  static Future<void> _loadFont(
    Uint8List bytes, {
    required String fontFamily,
  }) async {
    try {
      await loadFontFromList(bytes, fontFamily: fontFamily);
    } catch (_) {}
  }

  static Future<Map<String, Uint8List>?> pickFonts() async {
    try {
      final files = await FilePicker.pickFiles(
        type: .custom,
        allowedExtensions: _kFontExts,
      );
      if (files.isNotEmpty) {
        final Map<String, Uint8List> fonts = {};
        final now = DateTime.now().millisecondsSinceEpoch.toString();
        for (final file in files) {
          final bytes = await file.readAsBytes();
          final name = '$now/${file.name.split('.').first}';
          await _loadFont(bytes, fontFamily: name);
          fonts[name] = bytes;
        }
        return fonts;
      }
    } catch (_) {
      if (kDebugMode) rethrow;
    }
    return null;
  }

  static Set<String> getFont() {
    final name = fontFamily;
    return name == null ? const {} : {name};
  }

  static Future<Uint8List?> readBytes() async {
    _bytes ??= GStorage.localCache.get(_storageKey) as Uint8List?;
    return _bytes;
  }

  static Future<void> writeBytes(Uint8List bytes) async {
    _bytes = bytes;
    await GStorage.localCache.put(_storageKey, bytes);
    await GStorage.localCache.put(_storageNameKey, kFontName);
  }

  static Future<void> deleteBytes() async {
    _bytes = null;
    await GStorage.localCache.delete(_storageKey);
    await GStorage.localCache.delete(_storageNameKey);
  }
}

/// Small file-like facade so shared code keeps working without dart:io.
class WebFontFile {
  String get path => FontUtils.kFontName;

  bool existsSync() => FontUtils._bytes != null;

  Future<Uint8List> readAsBytes() async {
    final bytes = await FontUtils.readBytes();
    if (bytes == null) {
      throw StateError('custom font is not available');
    }
    return bytes;
  }

  Future<void> writeAsBytes(List<int> bytes) =>
      FontUtils.writeBytes(Uint8List.fromList(bytes));

  void delete() => FontUtils.deleteBytes();
}
