import 'dart:io' show Platform;

import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/platform_utils.dart';

abstract final class MaxScreenSize {
  static int? _maxWidth;
  static int? _maxHeight;

  static void init() {
    _initScreenSize();
    if (AndroidHelper.isFoldable) {
      final func = Runnable.implement($Runnable(run: _initScreenSize));
      AndroidHelper$ToDart.onConfigurationChanged = func;
      func.release();
    }
  }

  static void _initScreenSize() {
    final size = PiliAndroidHelper.maxScreenSize();
    if (size != null) {
      _maxWidth = size.$1;
      _maxHeight = size.$2;
    }
  }

  static bool isWindowMode({required num width, required num height}) {
    if (!PlatformUtils.isAndroid) return false;
    width = width.round();
    height = height.round();
    final hasWidthMatch = width == _maxWidth || width == _maxHeight;
    final hasHeightMatch = height == _maxWidth || height == _maxHeight;
    return !(hasWidthMatch && hasHeightMatch);
  }
}
