// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

Stream<Map<String, dynamic>> geetestWebMessages() {
  late StreamController<Map<String, dynamic>> controller;
  StreamSubscription<html.MessageEvent>? subscription;
  controller = StreamController<Map<String, dynamic>>(
    onListen: () {
      subscription = html.window.onMessage.listen((event) {
        final raw = event.data;
        if (raw is! String) return;
        try {
          final data = jsonDecode(raw);
          if (data is Map && data['type'] == 'pili-geetest') {
            controller.add(Map<String, dynamic>.from(data));
          }
        } catch (_) {}
      });
    },
    onCancel: () => subscription?.cancel(),
  );
  return controller.stream;
}
