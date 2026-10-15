import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const NivexiaApp());
}

class NivexiaApp extends StatelessWidget {
  const NivexiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nivexia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090B10),
        primaryColor: const Color(0xFF00F5D4),
      ),
      home: const HomeScreen(),
    );
  }
}

class ReadyServer {
  final String rawUri;
  final String configJson;
  final String protocol;
  final String address;
  final int port;
  int ping;

  ReadyServer({
    required this.rawUri,
    required this.configJson,
    required this.protocol,
    required this.address,
    required this.port,
    required this.ping,
  });

  Map<String, dynamic> toMap() => {
        'rawUri': rawUri,
        'configJson': configJson,
        'protocol': protocol,
        'address': address,
        'port': port,
        'ping': ping,
      };

  factory ReadyServer.fromMap(Map<String, dynamic> map) => ReadyServer(
        rawUri: map['rawUri'] ?? '',
        configJson: map['configJson'] ?? '',
        protocol: map['protocol'] ?? 'VLESS',
        address: map['address'] ?? '',
        port: map['port'] ?? 443,
        ping: map['ping'] ?? 120,
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final V2ray v2ray = V2ray(
    onStatusChanged: (status) {
      if (!mounted) return;
      final String st = status.state.toUpperCase();
      setState(() {
        v2rayStatus = status;
        if (st == "CONNECTED") {
          _nativeVpnRunning = true;
          isConnected = true;
          isConnecting = false;
        } else if (st == "DISCONNECTED") {
          _nativeVpnRunning = false;
          if (!isConnecting && !_isAutoSwitching) {
            isConnected = false;
          }
        }
      });
    },
  );

  late AnimationController _pulseController;
  V2RayStatus v2rayStatus = V2RayStatus();

  bool _nativeVpnRunning = false;
  bool isConnected = false;
  bool isConnecting = false;
  bool isRefreshingPing = false;
  bool _isBackgroundWorking = false;
  bool _isAutoSwitching = false;
  bool _userCancelledConnect = false;

  int currentPing = -1;
  String statusMessage = 'Ready to connect';

  Timer? _backgroundPoolTimer;
  Timer? _healthWatchdogTimer;
  Timer? _failoverCountdownTimer;
  int _configFailSeconds = 0;
  bool _internetIsDown = false;

  final List<ReadyServer> _readyPool = [];
  final Set<String> _deadUris = {};
  ReadyServer? _activeServer;

  // لایه ۱: منابع از قبل تست‌شده و فیلترشده مخصوص ایران (برای اتصال فوری زیر ۱ ثانیه)
  // لایه ۲: ۴ منبع بزرگ Epodonios برای پشتیبانی بی‌پایان
  final List<String> _fastFilteredSources = const [
    // منابع فیلترشده که ربات‌های گیت‌هاب هر ۱۵ دقیقه فقط کانفیگ‌های سالم را در آن‌ها می‌گذارند
    'https://cdn.jsdelivr.net/gh/MatinGhanbari/v2ray-configs@main/subscriptions/filtered/subs/vless.txt',
    'https://cdn.jsdelivr.net/gh/MatinGhanbari/v2ray-configs@main/subscriptions/filtered/subs/vmess.txt',
    'https://cdn.jsdelivr.net/gh/yebekhe/TVC@main/subscriptions/xray/normal/vless',
    'https://cdn.jsdelivr.net/gh/yebekhe/TVC@main/subscriptions/xray/normal/mix',
    'https://cdn.jsdelivr.net/gh/soroushmirzaei/telegram-configs-collector@main/subscribe/protocols/vless',
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Sub1.txt',
    'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vless_configs.txt',
    // ۴ منبع اصلی Epodonios (از طریق پروکسی سریع و لینک مستقیم)
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
  ];

  int _sourceCursor = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initVpnEngine();
  }

  Future<void> _initVpnEngine() async {
    await v2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );

    // ۱. بارگذاری فوری سرورهای سالم ذخیره‌شده در حافظه گوشی (اتصال ۰.۵ ثانیه‌ای بدون اسکن!)
    await _loadCachedServersFromDisk();

    // ۲. آماده‌سازی بی‌صدا و موازی سرورهای جدید در پس‌زمینه
    _fillServerPoolInBackground();

    _backgroundPoolTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!isConnected && !isConnecting && !_isBackgroundWorking) {
        if (_readyPool.length < 5) {
          _fillServerPoolInBackground();
        }
      }
    });

    // ۳. مانیتورینگ سلامت اتصال هر ۱۲ ثانیه برای تشخیص قطعی کانفیگ یا اینترنت
    _healthWatchdogTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (isConnected && !isConnecting && !_isAutoSwitching) {
        _checkConnectionAndHandleFailover();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _backgroundPoolTimer?.cancel();
    _healthWatchdogTimer?.cancel();
    _failoverCountdownTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // ۱. کش محلی روی حافظه گوشی (برای اتصال آنی بدون انتظار در دفعات بعدی)
  // ===========================================================================

  File get _cacheFile =>
      File('${Directory.systemTemp.path}/nivexia_verified_pool_v2.json');

  Future<void> _loadCachedServersFromDisk() async {
    try {
      if (await _cacheFile.exists()) {
        final String content = await _cacheFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        for (final item in list) {
          final srv = ReadyServer.fromMap(Map<String, dynamic>.from(item));
          if (srv.rawUri.isNotEmpty && !_readyPool.any((s) => s.rawUri == srv.rawUri)) {
            _readyPool.add(srv);
          }
        }
        if (_readyPool.isNotEmpty && mounted) {
          setState(() {
            currentPing = _readyPool.first.ping;
            statusMessage = 'Ready • Instant Connect (${_readyPool.first.protocol})';
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveVerifiedServersToDisk() async {
    try {
      final List<Map<String, dynamic>> data =
          _readyPool.take(15).map((s) => s.toMap()).toList();
      await _cacheFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  // ===========================================================================
  // ۲. استخراج و اصلاح استاندارد کانفیگ‌ها (بدون تگ مخرب stats که هسته را قفل می‌کرد)
  // ===========================================================================

  String _decodeBase64Safe(String input) {
    try {
      String clean = input
          .trim()
          .replaceAll('-', '+')
          .replaceAll('_', '/')
          .replaceAll(RegExp(r'\s+'), '');
      int mod = clean.length % 4;
      if (mod > 0) clean += '=' * (4 - mod);
      return utf8.decode(base64.decode(clean), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  String? _convertSsrToStandardSs(String ssrUri) {
    try {
      final String b64Part = ssrUri.substring(6).trim();
      final String decoded = _decodeBase64Safe(b64Part);
      if (decoded.isEmpty) return null;

      final String mainPart = decoded.split('/?').first;
      final List<String> parts = mainPart.split(':');
      if (parts.length < 6) return null;

      final String host = parts[0].trim();
      final String port = parts[1].trim();
      final String method = parts[3].trim();
      final String passB64 = parts[5].trim();
      final String password = _decodeBase64Safe(passB64);

      if (host.isEmpty || password.isEmpty) return null;
      final String userInfoB64 =
          base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
      return 'ss://$userInfoB64@$host:$port#SSR';
    } catch (_) {
      return null;
    }
  }

  String _normalizeSsUri(String ssUri) {
    try {
      if (!ssUri.startsWith('ss://')) return ssUri;
      final String withoutPrefix = ssUri.substring(5);
      final String mainPart = withoutPrefix.split('#').first;
      if (!mainPart.contains('@')) {
        final String decoded = _decodeBase64Safe(mainPart);
        if (decoded.contains('@')) {
          final List<String> atParts = decoded.split('@');
          final String encodedUser =
              base64Url.encode(utf8.encode(atParts.first)).replaceAll('=', '');
          return 'ss://$encodedUser@${atParts.last}#SS';
        }
      }
    } catch (_) {}
    return ssUri;
  }

  List<String> _extractValidConfigs(String rawContent) {
    String text = rawContent.trim();
    if (text.isEmpty) return [];

    if (!text.contains('://')) {
      final String decoded = _decodeBase64Safe(text);
      if (decoded.isNotEmpty) text = decoded;
    }

    final List<String> validLinks = [];
    final Set<String> seen = {};

    for (String line in text.split(RegExp(r'[\r\n]+'))) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('ssr://')) {
        final String? converted = _convertSsrToStandardSs(line);
        if (converted != null) line = converted;
      } else if (line.startsWith('ss://')) {
        line = _normalizeSsUri(line);
      }

      if (line.startsWith('vless://') ||
          line.startsWith('vmess://') ||
          line.startsWith('ss://') ||
          line.startsWith('trojan://')) {
        if (line.contains('ech=')) continue;
        if (_deadUris.contains(line)) continue;
        if (seen.add(line)) {
          validLinks.add(line);
        }
      }
    }
    return validLinks;
  }

  /// اصلاح دقیق JSON خروجی بدون اضافه کردن فیلدهای غیرمجاز
  String _fixCleanXrayJson(String rawConfigJson) {
    try {
      final Map<String, dynamic> cfg = jsonDecode(rawConfigJson);
      cfg['dns'] = {
        "servers": ["1.1.1.1", "8.8.8.8"]
      };

      if (cfg['outbounds'] is List && (cfg['outbounds'] as List).isNotEmpty) {
        final Map<String, dynamic> ob =
            Map<String, dynamic>.from(cfg['outbounds'][0]);
        if (ob['streamSettings'] is Map) {
          final Map<String, dynamic> stream =
              Map<String, dynamic>.from(ob['streamSettings']);

          // اصلاح کاراکترهای %2F در مسیر WebSocket
          if (stream['wsSettings'] is Map) {
            final Map<String, dynamic> ws =
                Map<String, dynamic>.from(stream['wsSettings']);
            if (ws['path'] is String) {
              String p = ws['path'];
              try {
                p = Uri.decodeComponent(p);
              } catch (_) {}
              if (p.contains('?ed=')) {
                p = p.split('?ed=').first;
              }
              ws['path'] = p.isEmpty ? '/' : p;
            }
            stream['wsSettings'] = ws;
          }

          ob['streamSettings'] = stream;
        }
        cfg['outbounds'][0] = ob;
      }
      return jsonEncode(cfg);
    } catch (_) {
      return rawConfigJson;
    }
  }

  ReadyServer? _parseSingleUri(String uri) {
    try {
      final V2RayURL parser = V2ray.parseFromURL(uri);
      final String host = parser.address.trim();
      final int port = parser.port;
      if (host.isEmpty || port <= 0 || host == '127.0.0.1') return null;

      String proto = uri.split('://').first.toUpperCase();
      if (uri.contains('security=reality')) proto = 'REALITY';

      final String fixedJson = _fixCleanXrayJson(parser.getFullConfiguration());
      return ReadyServer(
        rawUri: uri,
        configJson: fixedJson,
        protocol: proto,
        address: host,
        port: port,
        ping: -1,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _fetchFastChunk(String url) async {
    final http.Client client = http.Client();
    try {
      final http.Request req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'v2rayNG/1.8.23';

      final http.StreamedResponse response =
          await client.send(req).timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        client.close();
        return '';
      }

      final List<int> bytes = [];
      final Completer<String> completer = Completer<String>();
      late StreamSubscription<List<int>> sub;

      sub = response.stream.listen(
        (chunk) {
          bytes.addAll(chunk);
          // دریافت فقط ۲۵۰ کیلوبایت اول برای سرعت فوق‌العاده بالا
          if (bytes.length >= 250000) {
            sub.cancel();
            client.close();
            if (!completer.isCompleted) {
              completer.complete(utf8.decode(bytes, allowMalformed: true));
            }
          }
        },
        onDone: () {
          client.close();
          if (!completer.isCompleted) {
            completer.complete(utf8.decode(bytes, allowMalformed: true));
          }
        },
        onError: (_) {
          client.close();
          if (!completer.isCompleted) completer.complete('');
        },
        cancelOnError: true,
      );

      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          sub.cancel();
          client.close();
          return bytes.isNotEmpty ? utf8.decode(bytes, allowMalformed: true) : '';
        },
      );
    } catch (_) {
      client.close();
      return '';
    }
  }

  Future<int> _measureFastSocket(String host, int port) async {
    Socket? s;
    try {
      final Stopwatch sw = Stopwatch()..start();
      s = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 700),
      );
      sw.stop();
      await s.close();
      return sw.elapsedMilliseconds;
    } catch (_) {
      s?.destroy();
      return -1;
    }
  }

  // ===========================================================================
  // ۳. موتور «مسابقه موازی» (Happy Eyeballs Race) — پیدا کردن سرور در ۱ ثانیه!
  // ===========================================================================

  /// تست یک سرور با هسته واقعی Xray و در صورت عدم پاسخ متد پلاگین، بررسی دست‌دهی واقعی TLS
  Future<int> _verifyNodeFast(ReadyServer node) async {
    try {
      final int coreDelay = await v2ray
          .getServerDelay(config: node.configJson)
          .timeout(const Duration(milliseconds: 2200), onTimeout: () => -1);
      if (coreDelay > 0 && coreDelay < 3000) {
        return coreDelay;
      }
    } catch (_) {}

    // اگر متد پلاگین به خاطر محدودیت اندروید -1 داد، با دست‌دهی کامل TLS بررسی می‌کنیم
    SecureSocket? sec;
    try {
      final Stopwatch sw = Stopwatch()..start();
      sec = await SecureSocket.connect(
        node.address,
        node.port,
        timeout: const Duration(milliseconds: 1200),
        onBadCertificate: (_) => true,
      );
      sw.stop();
      await sec.close();
      if (sw.elapsedMilliseconds > 0 && sw.elapsedMilliseconds < 1500) {
        return sw.elapsedMilliseconds;
      }
    } catch (_) {
      sec?.destroy();
    }

    return -1;
  }

  /// آماده‌سازی موازی سرورها در پس‌زمینه (بدون اینکه کاربر را منتظر بگذارد!)
  Future<void> _fillServerPoolInBackground() async {
    if (_isBackgroundWorking || isConnected) return;
    _isBackgroundWorking = true;

    try {
      // برداشتن ۳ منبع به نوبت (ابتدا منابع فیلترشده و تست‌شده ایران، سپس Epodonios)
      final List<String> batchUrls = [];
      for (int i = 0; i < 3; i++) {
        batchUrls.add(_fastFilteredSources[_sourceCursor % _fastFilteredSources.length]);
        _sourceCursor++;
      }

      final List<String> rawLinks = [];
      await Future.wait(batchUrls.map((url) async {
        final String body = await _fetchFastChunk(url);
        if (body.isNotEmpty) {
          rawLinks.addAll(_extractValidConfigs(body).take(120));
        }
      }));

      final List<ReadyServer> candidates = [];
      for (final link in rawLinks) {
        if (candidates.length >= 90) break;
        if (_readyPool.any((s) => s.rawUri == link)) continue;
        final ReadyServer? parsed = _parseSingleUri(link);
        if (parsed != null) {
          candidates.add(parsed);
        }
      }

      if (candidates.isNotEmpty) {
        // ۱. غربال فوق سریع سوکت در دسته‌های ۴۵ تایی (کمتر از ۰.۸ ثانیه)
        final List<ReadyServer> socketOpen = [];
        for (int i = 0; i < candidates.length; i += 45) {
          if (isConnected) break;
          final slice = candidates.skip(i).take(45).toList();
          await Future.wait(slice.map((c) async {
            final int p = await _measureFastSocket(c.address, c.port);
            if (p > 0 && p < 750) {
              c.ping = p;
              socketOpen.add(c);
            }
          }));
        }

        socketOpen.sort((a, b) => a.ping.compareTo(b.ping));

        // ۲. مسابقه موازی ۸ تایی (به جای یکی‌یکی!) — هر کدام زودتر جواب داد درجا آماده می‌شود!
        final List<ReadyServer> topRace = socketOpen.take(16).toList();
        for (int j = 0; j < topRace.length; j += 8) {
          if (isConnected) break;
          final raceGroup = topRace.skip(j).take(8).toList();

          await Future.wait(raceGroup.map((cand) async {
            final int realPing = await _verifyNodeFast(cand);
            if (realPing > 0 && realPing < 2500) {
              cand.ping = realPing;
              if (!_readyPool.any((s) => s.rawUri == cand.rawUri)) {
                _readyPool.add(cand);
                _readyPool.sort((a, b) => a.ping.compareTo(b.ping));

                if (mounted && !isConnected) {
                  setState(() {
                    currentPing = _readyPool.first.ping;
                    statusMessage =
                        'Ready • Instant Connect (${_readyPool.first.protocol})';
                  });
                }
              }
            }
          }));

          if (_readyPool.isNotEmpty) {
            await _saveVerifiedServersToDisk();
          }
          if (_readyPool.length >= 8) break;
        }
      }
    } catch (_) {}

    _isBackgroundWorking = false;
  }

  // ===========================================================================
  // ۴. اتصال فوری با یک کلیک (بدون نگه داشتن کاربر در صفحه اسکن!) + دکمه تعویض سرور
  // ===========================================================================

  Future<bool> _startServerImmediately(ReadyServer srv) async {
    try {
      if (mounted) {
        setState(() {
          currentPing = srv.ping;
          statusMessage = 'Connecting (${srv.protocol} • ${srv.ping} ms)...';
        });
      }

      _nativeVpnRunning = false;
      await v2ray.startV2Ray(
        remark: "Nivexia VPN (${srv.protocol})",
        config: srv.configJson,
        blockedApps: null,
        bypassSubnets: null,
        proxyOnly: false,
      );

      int waitedMs = 0;
      while (!_nativeVpnRunning && waitedMs < 3000) {
        if (_userCancelledConnect) {
          await v2ray.stopV2Ray();
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 150));
        waitedMs += 150;
      }

      if (!_nativeVpnRunning) {
        await v2ray.stopV2Ray();
        return false;
      }

      _activeServer = srv;
      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
          currentPing = srv.ping;
          statusMessage = 'Connected • ${srv.protocol} Active';
        });
      }

      // بررسی نامحسوس پینگ واقعی بعد از اتصال؛ اگر سرور کار نکرد، خودکار می‌پرد روی سرور بعدی!
      Future.delayed(const Duration(seconds: 2), () async {
        if (!isConnected || _activeServer?.rawUri != srv.rawUri) return;
        int liveDelay = -1;
        try {
          liveDelay = await v2ray
              .getConnectedServerDelay()
              .timeout(const Duration(milliseconds: 3000), onTimeout: () => -1);
        } catch (_) {}

        if (liveDelay > 0 && mounted) {
          setState(() => currentPing = liveDelay);
        }
      });

      return true;
    } catch (_) {
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      return false;
    }
  }

  /// وقتی کاربر دکمه CONNECT را می‌زند:
  /// اگر سرور در کش/صف آماده است، درجا (زیر ۱ ثانیه) وصل می‌شود!
  Future<void> _onConnectButtonPressed() async {
    _failoverCountdownTimer?.cancel();
    _failoverCountdownTimer = null;

    if (isConnected || isConnecting) {
      _userCancelledConnect = true;
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
        _nativeVpnRunning = false;
        _isAutoSwitching = false;
        statusMessage = _readyPool.isNotEmpty
            ? 'Ready • Instant Connect (${_readyPool.first.protocol})'
            : 'Ready to connect';
      });
      return;
    }

    final bool hasPerm = await v2ray.requestPermission();
    if (!hasPerm) {
      setState(() => statusMessage = 'VPN Permission Required');
      return;
    }

    setState(() {
      isConnecting = true;
      _userCancelledConnect = false;
      statusMessage = 'Connecting...';
    });

    // اگر هنوز هیچ سروری در کش نبود، یک مسابقه سریع ۱.۵ ثانیه‌ای اجرا کن
    if (_readyPool.isEmpty) {
      await _fillServerPoolInBackground();
    }

    _readyPool.sort((a, b) => a.ping.compareTo(b.ping));

    bool connected = false;
    while (_readyPool.isNotEmpty && !_userCancelledConnect) {
      final ReadyServer best = _readyPool.first;
      final bool ok = await _startServerImmediately(best);
      if (ok) {
        connected = true;
        break;
      } else {
        _deadUris.add(best.rawUri);
        _readyPool.removeAt(0);
      }
    }

    if (!connected && mounted && !_userCancelledConnect) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'Refreshing servers • Tap Connect again';
      });
      _fillServerPoolInBackground();
    }
  }

  /// دکمه تعویض فوری به سرور بعدی در ۱ ثانیه
  Future<void> _switchToNextServerInstantly() async {
    if (_isAutoSwitching) return;
    _isAutoSwitching = true;

    if (_activeServer != null) {
      _deadUris.add(_activeServer!.rawUri);
      _readyPool.removeWhere((s) => s.rawUri == _activeServer!.rawUri);
    }

    if (mounted) {
      setState(() {
        statusMessage = 'Switching to next fast server...';
      });
    }

    try {
      await v2ray.stopV2Ray();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 300));

    if (_readyPool.isEmpty) {
      await _fillServerPoolInBackground();
    }

    while (_readyPool.isNotEmpty) {
      final ReadyServer nextSrv = _readyPool.first;
      final bool ok = await _startServerImmediately(nextSrv);
      if (ok) break;
      _deadUris.add(nextSrv.rawUri);
      _readyPool.removeAt(0);
    }

    _isAutoSwitching = false;
    if (_readyPool.length < 4) {
      _fillServerPoolInBackground();
    }
  }

  // ===========================================================================
  // ۵. رفرش کلیکی پینگ + تشخیص قطعی کانفیگ یا اینترنت (تایمر ۳۰ ثانیه)
  // ===========================================================================

  Future<void> _refreshPingOnTap() async {
    if (isRefreshingPing) return;
    setState(() => isRefreshingPing = true);

    try {
      if (isConnected && _activeServer != null) {
        int delay = await v2ray
            .getConnectedServerDelay()
            .timeout(const Duration(milliseconds: 2500), onTimeout: () => -1);
        if (delay <= 0) {
          delay = await _measureFastSocket(_activeServer!.address, _activeServer!.port);
        }
        if (mounted && delay > 0) {
          setState(() => currentPing = delay);
        }
      } else if (_readyPool.isNotEmpty) {
        final int p = await _measureFastSocket(
          _readyPool.first.address,
          _readyPool.first.port,
        );
        if (mounted && p > 0) {
          setState(() {
            _readyPool.first.ping = p;
            currentPing = p;
          });
        }
      } else {
        await _fillServerPoolInBackground();
      }
    } catch (_) {}

    if (mounted) {
      setState(() => isRefreshingPing = false);
    }
  }

  Future<bool> _isUserBaseInternetConnected() async {
    for (final ip in ['10.202.10.10', '178.22.122.100', '1.1.1.1', '8.8.8.8']) {
      Socket? s;
      try {
        s = await Socket.connect(ip, 53, timeout: const Duration(milliseconds: 1200));
        await s.close();
        return true;
      } catch (_) {
        s?.destroy();
      }
    }
    return false;
  }

  Future<void> _checkConnectionAndHandleFailover() async {
    if (!isConnected || _activeServer == null || _isAutoSwitching) return;

    int delay = -1;
    try {
      delay = await v2ray
          .getConnectedServerDelay()
          .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);
    } catch (_) {}

    if (delay <= 0) {
      delay = await _measureFastSocket(_activeServer!.address, _activeServer!.port);
    }

    if (delay > 0 && delay < 3500) {
      _failoverCountdownTimer?.cancel();
      _failoverCountdownTimer = null;
      _configFailSeconds = 0;
      _internetIsDown = false;
      if (mounted) {
        setState(() {
          currentPing = delay;
          statusMessage = 'Connected • ${_activeServer!.protocol} Active';
        });
      }
      return;
    }

    final bool hasNet = await _isUserBaseInternetConnected();
    if (!hasNet) {
      _failoverCountdownTimer?.cancel();
      _failoverCountdownTimer = null;
      _configFailSeconds = 0;
      if (mounted) {
        setState(() {
          _internetIsDown = true;
          currentPing = -1;
          statusMessage = 'No Internet • Waiting for network...';
        });
      }
      return;
    }

    _internetIsDown = false;
    if (_failoverCountdownTimer == null) {
      _configFailSeconds = 30;
      if (mounted) {
        setState(() {
          currentPing = -1;
          statusMessage = 'Config dropped • Auto-switching in $_configFailSeconds s...';
        });
      }

      _failoverCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (!isConnected || !mounted) {
          timer.cancel();
          _failoverCountdownTimer = null;
          return;
        }

        _configFailSeconds--;
        if (_configFailSeconds > 0) {
          setState(() {
            statusMessage = 'Config dropped • Auto-switching in $_configFailSeconds s...';
          });
        } else {
          timer.cancel();
          _failoverCountdownTimer = null;
          await _switchToNextServerInstantly();
        }
      });
    }
  }

  String _formatSpeed(dynamic speed) {
    if (speed == null) return '0 B/s';
    final int? val = int.tryParse(speed.toString());
    if (val == null || val <= 0) return '0 B/s';
    if (val < 1024) return '$val B/s';
    if (val < 1048576) return '${(val / 1024).toStringAsFixed(1)} KB/s';
    return '${(val / 1048576).toStringAsFixed(1)} MB/s';
  }

  // ===========================================================================
  // ۶. رابط کاربری (UI)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final Color primaryNeon = isConnected
        ? (_internetIsDown || _failoverCountdownTimer != null
            ? Colors.amberAccent
            : const Color(0xFF00F5D4))
        : (isConnecting ? Colors.amberAccent : const Color(0xFF7B2CBF));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
          child: Column(
            children: [
              // ۱. هدر بالا: لوگوی Nivexia + باکس پینگ کلیکی
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NIVEXIA',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.5,
                          color: Color(0xFF00F5D4),
                        ),
                      ),
                      Text(
                        'SMART AUTO VPN',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),

                  GestureDetector(
                    onTap: _refreshPingOnTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151924),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: primaryNeon.withOpacity(0.55)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isRefreshingPing)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00F5D4),
                              ),
                            )
                          else
                            Icon(Icons.bolt_rounded, color: primaryNeon, size: 17),
                          const SizedBox(width: 6),
                          Text(
                            currentPing > 0 ? '$currentPing ms' : '-- ms',
                            style: TextStyle(
                              color: primaryNeon,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white54,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // ۲. دکمه بزرگ اتصال در مرکز صفحه
              GestureDetector(
                onTap: _onConnectButtonPressed,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final double glowSpread = isConnected
                        ? (6.0 + (_pulseController.value * 10.0))
                        : (2.0 + (_pulseController.value * 4.0));
                    return Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF11151F),
                        boxShadow: [
                          BoxShadow(
                            color: primaryNeon.withOpacity(isConnected ? 0.38 : 0.18),
                            blurRadius: isConnected ? 45 : 25,
                            spreadRadius: glowSpread,
                          ),
                        ],
                        border: Border.all(
                          color: primaryNeon,
                          width: 3.2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isConnecting
                                ? Icons.sync_rounded
                                : Icons.power_settings_new_rounded,
                            size: 66,
                            color: primaryNeon,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isConnecting
                                ? 'CONNECTING...'
                                : (isConnected ? 'CONNECTED' : 'CONNECT'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                              color: isConnected ? const Color(0xFF00F5D4) : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isConnected
                                ? v2rayStatus.duration
                                : (isConnecting ? 'Tap to cancel' : 'Instant Auto Server'),
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const Spacer(),

              // ۳. نمایشگر سرعت دانلود و آپلود
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131722),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.south_rounded, color: Color(0xFF00F5D4), size: 18),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DOWNLOAD',
                                style: TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 1),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isConnected ? _formatSpeed(v2rayStatus.downloadSpeed) : '0 B/s',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131722),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.north_rounded, color: Color(0xFF7B2CBF), size: 18),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'UPLOAD',
                                style: TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 1),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isConnected ? _formatSpeed(v2rayStatus.uploadSpeed) : '0 B/s',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ۴. نوار وضعیت پایین صفحه + دکمه تعویض فوری سرور (Switch Server)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF151924),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primaryNeon.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            _internetIsDown
                                ? Icons.wifi_off_rounded
                                : Icons.shield_rounded,
                            color: primaryNeon,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              statusMessage,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // دکمه تعویض سریع سرور در ۱ ثانیه (اگر سرور فعلی کند بود)
                    GestureDetector(
                      onTap: _switchToNextServerInstantly,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F5D4).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swap_horiz_rounded, color: Color(0xFF00F5D4), size: 15),
                            SizedBox(width: 4),
                            Text(
                              'Next Server',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00F5D4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
