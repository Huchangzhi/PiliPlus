// Web no-op implementation of the Android integration surface.
abstract final class PiliAndroidHelper {
  static const bool isPipAvailable = false;

  static void biliSendCommAntifraud(
    int action,
    int oid,
    int type,
    int rpId,
    int root,
    int parent,
    int ctime,
    String commentText,
    List pictures,
    String sourceId,
    int uid,
    String cookie,
  ) {}

  static bool openMusic(String title, String? artist, String? album) => false;

  static void enterPip(
    int width,
    int height, {
    required bool autoEnter,
    required bool isLive,
    required bool isPlaying,
  }) {}

  static void disableAutoEnterPip() {}

  static (int, int)? maxScreenSize() => null;

  static void createShortcut(String id, String uri, String label, String path) {}

  static void openUrl(String url, {String domain = '*.bilibili.com'}) {}
}
