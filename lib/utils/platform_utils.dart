import 'package:flutter/foundation.dart';

abstract final class PlatformUtils {
  static final bool isWeb = kIsWeb;

  static final bool isAndroid =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static final bool isIOS =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static final bool isMacOS =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static final bool isWindows =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static final bool isLinux =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static final bool isMobile = isAndroid || isIOS;

  static final bool isDesktop = isWindows || isMacOS || isLinux;

  static final bool isDarwin = isIOS || isMacOS;

  static String get operatingSystem {
    if (isWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}
