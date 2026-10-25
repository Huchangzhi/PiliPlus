import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/retry_interceptor.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/accounts/account_manager/account_mgr.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:archive/archive.dart' show GZipDecoder;
import 'package:brotli/brotli.dart';
import 'package:collection/collection.dart';
import 'package:dio/browser.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// Web transport.
///
/// Every dio request keeps its original bilibili URI (so cookie domains and
/// signatures are unaffected) and is handed to the configured relay server
/// through a custom header. Headers that browsers forbid scripts from setting
/// are forwarded via x-pili-* aliases.
class Request {
  static final Request _instance = Request._internal();
  static late AccountManager accountManager;
  static late final Dio dio;

  static final gzip = _GzipCodec();
  static const brotli = BrotliDecoder();

  factory Request() => _instance;

  static Dio get http11Dio => dio;

  static void setCookie() {
    accountManager = AccountManager();
    dio.interceptors.add(accountManager);
    Accounts.refresh();
    if (Accounts.main.isLogin) {
      final coin = Pref.userInfoCache?.money;
      if (coin == null) {
        setCoin();
      } else {
        GlobalData().coins = coin;
      }
    }
  }

  static Future<void> setCoin() async {
    final res = await UserHttp.getCoin();
    if (res case Success(:final response)) {
      GlobalData().coins = response;
    }
  }

  static Future<void> buvidActive(Account account) async {
    if (account.activated) return;
    account.activated = true;
    try {
      final String randPngEnd = base64.encode([
        ...Iterable<int>.generate(32, (_) => Utils.random.nextInt(256)),
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        ...Iterable<int>.generate(4, (_) => Utils.random.nextInt(256)),
      ]);

      final jsonData = json.encode({
        '3064': 1,
        '39c8': '333.1387.fp.risk',
        '3c43': {
          'adca': 'Linux',
          'bfe9': randPngEnd.substring(randPngEnd.length - 50),
        },
      });

      await Request().post(
        Api.activateBuvidApi,
        data: {'payload': jsonData},
        options: Options(
          extra: {'account': account},
          contentType: Headers.jsonContentType,
        ),
      );
    } catch (_) {}
  }

  Request._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: HttpString.apiBaseUrl,
        connectTimeout: const Duration(milliseconds: 15000),
        receiveTimeout: const Duration(milliseconds: 30000),
        validateStatus: (int? status) =>
            status != null && status >= 200 && status < 300,
      ),
    )
      ..httpClientAdapter = _ProxyAdapter(() => Pref.webApiServer, BrowserHttpClientAdapter())
      ..transformer = BackgroundTransformer();

    if (Pref.retryCount != 0) {
      dio.interceptors.add(
        RetryInterceptor(dio, Pref.retryCount, Pref.retryDelay),
      );
    }

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: false,
          requestHeader: false,
          responseHeader: false,
        ),
      );
    }
  }

  Future<Response> get<T>(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await dio.get<T>(
        url,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      return Response(
        data: {'message': await AccountManager.dioError(e)},
        statusCode: e.response?.statusCode ?? -1,
        requestOptions: e.requestOptions,
      );
    }
  }

  Future<Response> post<T>(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await dio.post<T>(
        url,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      AccountManager.toast(e);
      return Response(
        data: {'message': await AccountManager.dioError(e)},
        statusCode: e.response?.statusCode ?? -1,
        requestOptions: e.requestOptions,
      );
    }
  }

  Future<Response> request<T>(
    String url, {
    Map<String, dynamic>? queryParameters,
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await dio.request<T>(
        url,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      return Response(
        data: {'message': await AccountManager.dioError(e)},
        statusCode: e.response?.statusCode ?? -1,
        requestOptions: e.requestOptions,
      );
    }
  }

  Future<Response> downloadFile(
    String urlPath,
    String savePath, {
    CancelToken? cancelToken,
  }) {
    throw UnsupportedError('File downloads are not supported by the web build');
  }

  static List<int> responseBytesDecoder(
    List<int> responseBytes,
    Map<String, List<String>> headers,
  ) => responseBytes;
}

class _GzipCodec {
  List<int> convert(List<int> data) => GZipDecoder().decodeBytes(data);
}

class _ProxyAdapter implements HttpClientAdapter {
  _ProxyAdapter(this._server, this._inner);

  final String Function() _server;
  final BrowserHttpClientAdapter _inner;

  static const _forbidden = {
    'accept-encoding',
    'connection',
    'content-length',
    'cookie',
    'host',
    'origin',
    'referer',
    'user-agent',
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final target = options.uri;
    final headers = <String, dynamic>{};
    options.headers.forEach((key, value) {
      final lower = key.toLowerCase();
      switch (lower) {
        case 'cookie':
          headers['x-pili-cookie'] = value;
          break;
        case 'referer':
          headers['x-pili-referer'] = value;
          break;
        case 'user-agent':
          headers['x-pili-user-agent'] = value;
          break;
        case 'origin':
          headers['x-pili-origin'] = value;
          break;
        default:
          if (!_forbidden.contains(lower)) headers[key] = value;
      }
    });
    headers['x-pili-target'] = target.toString();

    final proxy = Uri.parse('${_server()}/proxy');
    final proxyOptions = options.copyWith(
      path: proxy.toString(),
      baseUrl: '',
      queryParameters: const {},
      headers: headers,
    );

    final body = await _inner.fetch(proxyOptions, requestStream, cancelFuture);
    final encoded = body.headers['x-pili-set-cookie']?.firstOrNull;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final cookies = (jsonDecode(utf8.decode(base64Decode(encoded))) as List)
            .cast<String>();
        body.headers
          ..remove('x-pili-set-cookie')
          ..['set-cookie'] = cookies;
      } catch (_) {
        // Malformed relay header: ignore it rather than breaking the request.
      }
    }
    return body;
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
