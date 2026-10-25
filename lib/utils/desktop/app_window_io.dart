import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/utils/desktop/calc_window_position.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

Future<void> initDesktopWindow() async {
  final window = WindowManager.instance.getCurrent();
  if (window == null) return;
  window
    ..titleBarStyle = Pref.showWindowTitleBar ? .normal : .hidden
    ..isWindowControlButtonsVisible = true
    ..bounds = calcWindowBounds()
    ..minimumSize = DeviceUtils.desktopMinSize
    ..isVisibleInTaskbar = true
    ..title = Constants.appName;
  if (Pref.isWindowMaximized) window.maximize();
  void show([_]) => window
    ..focus()
    ..show();
  switch (WidgetsBinding.instance.schedulerPhase) {
    case .idle || .postFrameCallbacks:
      WidgetsBinding.instance.scheduleFrameCallback(show);
    case .transientCallbacks || .midFrameMicrotasks || .persistentCallbacks:
      WidgetsBinding.instance.addPostFrameCallback(show);
  }
}
