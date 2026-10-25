import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Bilibili risk control expects a browser-like buvid3/buvid4 pair. The app's
/// hand-generated buvid3 is not enough for some endpoints (live danmaku token,
/// login captcha), so fetch the anonymous pair and store it in the browser.
Future<void> ensureWebBuvid() async {
  if (!kIsWeb) return;
  try {
    final jar = Accounts.main.cookieJar;
    final saved = jar.domainCookies.values.any(
      (paths) => paths.values.any((cookies) => cookies['buvid4'] != null),
    );
    if (saved) return;
    final response = await Request().get(
      'https://api.bilibili.com/x/frontend/finger/spi',
      options: Options(extra: {'account': const NoAccount()}),
    );
    final data = response.data;
    if (data is! Map) return;
    final payload = data['data'];
    if (payload is! Map) return;
    final buvid3 = payload['b_3'];
    final buvid4 = payload['b_4'];
    if (buvid3 is! String || buvid4 is! String) return;
    final now = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final cookies = <Cookie>[
      for (final entry in {
        'buvid3': buvid3,
        'buvid4': buvid4,
        'b_nut': now,
      }.entries)
        Cookie(entry.key, entry.value)
          ..domain = '.bilibili.com'
          ..path = '/',
    ];
    await jar.saveFromResponse(
      Uri.parse('https://www.bilibili.com'),
      cookies,
    );
  } catch (_) {
    // Risk-control cookies are best effort; do not block startup.
  }
}
