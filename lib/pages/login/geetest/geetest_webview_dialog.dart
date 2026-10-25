import 'dart:async';
import 'dart:convert' show jsonDecode;

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/main.dart';
import 'package:PiliPlus/plugin/linux_webview.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/pages/login/geetest/geetest_web_messages.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class GeetestWebviewDialog extends StatefulWidget {
  const GeetestWebviewDialog(
    this.gt,
    this.challenge, {
    super.key,
    this.recaptchaType,
  });

  final String gt;
  final String challenge;
  final String? recaptchaType;

  @override
  State<GeetestWebviewDialog> createState() => _GeetestWebviewDialogState();

  static Future<Map<String, dynamic>?> geetest(
    String gt,
    String challenge, {
    String? recaptchaType,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: Get.context!,
      builder: (context) => GeetestWebviewDialog(
        gt,
        challenge,
        recaptchaType: recaptchaType,
      ),
    );
  }
}

class _GeetestWebviewDialogState extends State<GeetestWebviewDialog> {
  StreamSubscription<Map<String, dynamic>>? _webSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webSub = geetestWebMessages().listen((message) {
        switch (message['name']) {
          case 'success':
            final data = message['data'];
            if (data is Map) {
              Get.back(result: Map<String, dynamic>.from(data));
            }
            break;
          case 'close':
            Get.back();
            break;
          case 'error':
            debugPrint('geetest error: ${message['data']}');
            SmartDialog.showToast('验证码加载失败，请重试');
            Get.back();
            break;
        }
      });
    }
  }

  @override
  void dispose() {
    _webSub?.cancel();
    super.dispose();
  }

  static const _geetestJsUri =
      'https://static.geetest.com/static/js/fullpage.0.0.0.js';
  static const _geetestConfigUri = 'https://api.geetest.com/gettype.php';

  static String _buildHtml(String gt, String challenge) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final bridge = kIsWeb
        ? "R=(n,o)=>window.top.postMessage(JSON.stringify({type:'pili-geetest',name:n,data:o}),'*')"
        : PlatformUtils.isLinux
        ? "R=(n,o)=>window.webkit.messageHandlers.msgToNative.postMessage(n+':'+JSON.stringify(o))"
        : "R=(n,o)=>window.flutter_inappwebview?.callHandler(n,o)";
    final js =
        'var C,S,T,t;'
        'T=()=>{if(C&&S&&!t){t=Geetest(C).onSuccess(()=>R("success",t.getValidate())).onError(o=>R("error",o)).onClose(o=>R("close",o));t.onReady(()=>t.verify())}};'
        'geetest_$ts=(d)=>{'
        'if(!d||d.status!="success"){R("error",JSON.stringify(d));return};'
        'C=Object.assign({gt:"$gt",challenge:"$challenge",offline:false,new_captcha:true,product:"bind",width:"100%",https:true,protocol:"https://"},d.data);T()'
        '};'
        'G=()=>{S=1;T()};'
        'E=()=>{document.getElementById("E").textContent="验证码加载失败";R("error","geetest script load failed")}';

    return '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width"></head>'
        '<style>#E{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;color:red}</style>'
        '<body><div id="E"></div>'
        '<script>'
        '$bridge;$js'
        '</script>'
        '<script src="$_geetestJsUri" onload="G()" onerror="E()"></script>'
        '<script src="$_geetestConfigUri?gt=$gt&callback=geetest_$ts" onerror="E()"></script>'
        '</body></html>';
  }

  static String _buildV4Html(String gt, String challenge, String bridge) {
    final safeGt = gt.replaceAll('"', '');
    final safeChallenge = challenge.replaceAll('"', '');
    return '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width"></head>'
        '<style>#E{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;color:red}</style>'
        '<body><div id="E"></div>'
        '<script>$bridge</script>'
        '<script src="https://static.geetest.com/v4/gt4.js" onerror="R(\'error\',\'gt4 script load failed\')"></script>'
        '<script>'
        'try{'
        'initGeetest4({captchaId:"$safeGt",challenge:"$safeChallenge",product:"bind",protocol:"https://"},function(c){'
        'c.onSuccess(function(){R("success",c.getValidate())});'
        'c.onError(function(e){R("error",e)});'
        'c.onClose(function(e){R("close",e)});'
        'c.showCaptcha();'
        '})}catch(e){R("error",String(e))}'
        '</script></body></html>';
  }

  @override
  Widget build(BuildContext context) {
    final bridge = kIsWeb
        ? "R=(n,o)=>window.top.postMessage(JSON.stringify({type:'pili-geetest',name:n,data:o}),'*')"
        : PlatformUtils.isLinux
        ? "R=(n,o)=>window.webkit.messageHandlers.msgToNative.postMessage(n+':'+JSON.stringify(o))"
        : "R=(n,o)=>window.flutter_inappwebview?.callHandler(n,o)";
    final html = widget.recaptchaType == 'geetest4'
        ? _buildV4Html(widget.gt, widget.challenge, bridge)
        : _buildHtml(widget.gt, widget.challenge);

    if (PlatformUtils.isLinux) {
      return AlertDialog(
        title: const Text('验证码'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: LinuxWebview(
            initialHtml: html,
            userAgent: BrowserUa.mob,
            incognito: true,
            onWebMessageReceived: (msg) {
              final msgStr = msg.toString();
              if (msgStr.startsWith("success:")) {
                final dataStr = msgStr.substring("success:".length);
                try {
                  final data = jsonDecode(dataStr);
                  Get.back(result: data);
                } catch (e) {
                  debugPrint('geetest decode error: $e');
                }
              } else if (msgStr.startsWith("error:")) {
                debugPrint('geetest error: $msgStr');
              } else if (msgStr.startsWith('close:')) {
                Get.back();
              }
            },
          ),
        ),
      );
    }

    return Stack(
      children: [
        InAppWebView(
          webViewEnvironment: webViewEnvironment,
          initialSettings: InAppWebViewSettings(
            clearCache: true,
            javaScriptEnabled: true,
            forceDark: ForceDark.AUTO,
            useHybridComposition: true,
            algorithmicDarkeningAllowed: true,
            useShouldOverrideUrlLoading: true,
            userAgent: BrowserUa.mob,
            mixedContentMode: .MIXED_CONTENT_ALWAYS_ALLOW,

            incognito: true,
            allowFileAccess: false,
            allowsLinkPreview: false,
            allowContentAccess: false,
            useOnDownloadStart: false,
            geolocationEnabled: false,
            thirdPartyCookiesEnabled: false,
            enterpriseAuthenticationAppLinkPolicyEnabled: false,
            saveFormData: false,
            safeBrowsingEnabled: false,
            isFraudulentWebsiteWarningEnabled: false,
            domStorageEnabled: false,
            databaseEnabled: false,
            cacheEnabled: false,
            cacheMode: .LOAD_NO_CACHE,

            horizontalScrollBarEnabled: false,
            verticalScrollBarEnabled: false,
            overScrollMode: .NEVER,

            pageZoom: PlatformUtils.isIOS ? 3 : 1,
          ),
          initialData: InAppWebViewInitialData(data: html),
          onWebViewCreated: kIsWeb ? null : (ctr) {
            ctr
              ..addJavaScriptHandler(
                handlerName: 'success',
                callback: (args) {
                  if (args.isNotEmpty) {
                    if (args[0] case Map<String, dynamic> data) {
                      Get.back(result: data);
                      return;
                    }
                  }
                  debugPrint('geetest invalid result: $args');
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'error',
                callback: (args) {
                  debugPrint('geetest error: $args');
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'close',
                callback: (args) => Get.back(),
              );
          },
        ),
        Positioned(
          left: 8,
          top: 8,
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: Get.back,
            tooltip: '关闭',
          ),
        ),
      ],
    );
  }
}
