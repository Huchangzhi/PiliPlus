class TrayController {
  TrayController._();

  static TrayController get instance => _instance;
  static final TrayController _instance = TrayController._();

  bool showTrayIcon = false;

  void init() {}
  void dispose() {}
}
