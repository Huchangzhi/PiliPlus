class WindowController {
  WindowController._();

  static WindowController get instance => _instance;
  static final WindowController _instance = WindowController._();

  /// No native window exists in the browser. Callers are all desktop-only
  /// paths, so a null handle is sufficient.
  dynamic window;

  bool minimizeOnExit = false;
  bool pauseOnMinimize = false;

  void init() {}
  void dispose() {}
  void show() {}
  void onClose() {}
  void toggleVisibility() {}
  void setTitleBarStyle(bool visible) {}
}
