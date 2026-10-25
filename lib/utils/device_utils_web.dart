import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/widgets.dart' show Size, WidgetsBinding;

abstract final class DeviceUtils {
  static const int sdkInt = 0;

  static bool get isTablet => size.shortestSide >= 600;

  static Size get size {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return view.physicalSize / view.devicePixelRatio;
  }

  static String get platformName => 'web';

  static void exitApp() {}

  static const Size desktopMinSize = Size(400, 720);
}
