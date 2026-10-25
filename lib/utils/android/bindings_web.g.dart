// Web stubs for the JNI-generated bindings. Web builds never invoke Android
// platform integration, but the shared UI code still references these symbols.

final class $Runnable {
  const $Runnable({required void Function() run});
}

final class RunnableHandle {
  void release() {}
}

abstract final class Runnable {
  static RunnableHandle implement($Runnable runnable) => RunnableHandle();
}

abstract final class AndroidHelper {
  static bool get isFoldable => false;
  static bool get isPipAvailable => false;
  static bool isPipMode = false;
  static int sdkInt() => 0;
  static void back() {}
  static void openLinkVerifySettings() {}
  static void updateDocProvider(bool value) {}
  static void updatePipActions(int engineId, bool isLive, bool playing) {}
  static List<String> fontFamilies() => const [];
  static (int, int)? maxScreenSize() => null;
}

abstract final class AndroidHelper$ToDart {
  static RunnableHandle? onConfigurationChanged;
  static RunnableHandle? onUserLeaveHint;
}
