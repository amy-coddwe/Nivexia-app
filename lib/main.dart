import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
  final int localHttpPort;
  int ping;

  ReadyServer({
    required this.rawUri,
    required this.configJson,
    required this.protocol,
    required this.address,
    required this.port,
    required this.localHttpPort,
    required this.ping,
  });

  Map<String, dynamic> toMap() => {
        'rawUri': rawUri,
        'configJson': configJson,
        'protocol': protocol,
        'address': address,
        'port': port,
        'localHttpPort': localHttpPort,
        'ping': ping,
      };

  factory ReadyServer.fromMap(Map<String, dynamic> map) => ReadyServer(
        rawUri: map['rawUri'] ?? '',
        configJson: map['configJson'] ?? '',
        protocol: map['protocol'] ?? 'VLESS',
        address: map['address'] ?? '',
        port: map['port'] ?? 443,
        localHttpPort: map['localHttpPort'] ?? 10809,
        ping: map['ping'] ?? 180,
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
  bool _isBackgroundScanning = false;
  bool _abortScan = false;
  bool _isAutoSwitching = false;
  bool _userCancelled = false;

  int currentPing = -1;
  String statusMessage = 'Preparing verified servers...';

  Timer? _backgroundPoolTimer;
  Timer? _healthWatchdogTimer;
  Timer? _failoverCountdownTimer;
  int _configFailSeconds = 0;
  bool _internetIsDown = false;

  final List<ReadyServer> _readyPool = [];
  final Set<String> _deadUris = {};
  ReadyServer? _activeServer;

  // منابع ترکیبی: مخازن تست‌شده خودکار + ۴ مخزن اصلی Epodonios
  final List<String> _autoVpnSources = const [
    'https://cdn.jsdelivr.net/gh/MatinGhanbari/v2ray-configs@main/subscriptions/filtered/subs/vless.txt',
    'https://cdn.jsdelivr.net/gh/MatinGhanbari/v2ray-configs@main/subscriptions/filtered/subs/vmess.txt',
    'https://cdn.jsdelivr.net/gh/yebekhe/TVC@main/subscriptions/xray/normal/vless',
    'https://cdn.jsdelivr.net/gh/yebekhe/TVC@main/subscriptions/xray/normal/vmess',
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/vless.txt',
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/vmess.txt',
    'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vless_configs.txt',
    'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vmess_configs.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
  ];

  int _sourceIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initEngine();
  }

  Future<void> _initEngine() async {
    await v2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );

    await _loadWorkingCache();
    _scanAndVerifyInBackground();

    _backgroundPoolTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!isConnected && !isConnecting && !_isBackgroundScanning) {
        if (_readyPool.length < 4) {
          _scanAndVerifyInBackground();
        }
      }
    });

    // بررسی واقعی دانلود هر ۱۲ ثانیه در زمان اتصال
    _healthWatchdogTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (isConnected && !isConnecting && !_isAutoSwitching) {
        _checkConnectionAndHandleFailover();
      }
    });
  }

  @override
  void dispose() {
    _abortScan = true;
    _pulseController.dispose();
    _backgroundPoolTimer?.cancel();
    _healthWatchdogTimer?.cancel();
    _failoverCountdownTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // ۱. ذخیره و بازیابی سرورهایی که واقعاً دانلود داشته‌اند
  // ===========================================================================

  File get _cacheFile =>
      File('${Directory.systemTemp.path}/nivexia_real_dl_v4.json');

  Future<void> _loadWorkingCache() async {
    try {
      if (await _cacheFile.exists()) {
        final String content = await _cacheFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        for (final item in list) {
          final srv = ReadyServer.fromMap(Map<String, dynamic>.from(item));
          // فیلتر کردن هرگونه پینگ فیک زیر ۴۵ میلی‌ثانیه
          if (srv.rawUri.isNotEmpty &&
              srv.ping >= 45 &&
              !_readyPool.any((s) => s.rawUri == srv.rawUri)) {
            _readyPool.add(srv);
          }
        }
        if (_readyPool.isNotEmpty && mounted) {
          setState(() {
            currentPing = _readyPool.first.ping;
            statusMessage = 'Ready • Verified Server Prepared';
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveWorkingCache() async {
    try {
      final List<Map<String, dynamic>> data =
          _readyPool.take(10).map((s) => s.toMap()).toList();
      await _cacheFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  // ===========================================================================
  // ۲. پارس و اصلاح کانفیگ‌ها + فیلتر کردن آی‌پی‌های مسموم/داخلی
  // ===========================================================================

  bool _isPoisonedOrLocalAddress(String address) {
    final String a = address.trim().toLowerCase();
    if (a.isEmpty || a == 'localhost') return true;
    if (a.startsWith('127.') ||
        a.startsWith('10.') ||
        a.startsWith('192.168.') ||
        a.startsWith('0.') ||
        a.startsWith('172.16.') ||
        a.startsWith('172.17.') ||
        a.startsWith('172.18.') ||
        a.startsWith('172.19.') ||
        a.startsWith('172.2') ||
        a.startsWith('172.30.') ||
        a.startsWith('172.31.')) {
      return true;
    }
    return false;
  }

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

  /// آماده‌سازی کانفیگ استاندارد Xray و اطمینان از وجود پورت HTTP لوکال (10809) برای تست واقعی دانلود
  ReadyServer? _parseAndPrepareServer(String uri) {
    try {
      final V2RayURL parser = V2ray.parseFromURL(uri);
      final String host = parser.address.trim();
      final int port = parser.port;
      if (_isPoisonedOrLocalAddress(host) || port <= 0 || port > 65535) {
        return null;
      }

      // اصلاح مسیر WebSocket و رمزگشایی %2F
      if (parser.streamSetting['wsSettings'] is Map) {
        final Map ws = parser.streamSetting['wsSettings'];
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
      }

      // اصلاح spiderX در کانفیگ‌های Reality
      if (parser.streamSetting['realitySettings'] is Map) {
        final Map rl = parser.streamSetting['realitySettings'];
        if (rl['spiderX'] is String) {
          try {
            rl['spiderX'] = Uri.decodeComponent(rl['spiderX']);
          } catch (_) {}
        }
        // اگر پابلیک‌کی خالی است، کانفیگ Reality خراب است
        if ((rl['publicKey'] ?? '').toString().trim().isEmpty) {
          return null;
        }
      }

      if (parser.streamSetting['security'] == 'tls' &&
          parser.streamSetting['tlsSettings'] is Map) {
        parser.streamSetting['tlsSettings']['allowInsecure'] = true;
      }

      final Map<String, dynamic> cfg =
          Map<String, dynamic>.from(jsonDecode(parser.getFullConfiguration()));

      cfg['dns'] = {
        "servers": ["1.1.1.1", "8.8.8.8"]
      };

      // بررسی یا افزودن پورت HTTP لوکال (10809) تا بتوانیم بعد از اتصال، دانلود واقعی را از داخل تونل تست کنیم
      int httpPort = 10809;
      if (cfg['inbounds'] is List) {
        final List inbounds = cfg['inbounds'] as List;
        bool foundHttp = false;
        for (final ib in inbounds) {
          if (ib is Map && ib['protocol'] == 'http' && ib['port'] is int) {
            httpPort = ib['port'];
            foundHttp = true;
            break;
          }
        }
        if (!foundHttp) {
          inbounds.add({
            "tag": "http",
            "port": 10809,
            "listen": "127.0.0.1",
            "protocol": "http",
            "sniffing": {
              "enabled": true,
              "destOverride": ["http", "tls"]
            },
            "settings": {}
          });
        }
      }

      String proto = uri.split('://').first.toUpperCase();
      if (uri.contains('security=reality')) proto = 'REALITY';

      return ReadyServer(
        rawUri: uri,
        configJson: jsonEncode(cfg),
        protocol: proto,
        address: host,
        port: port,
        localHttpPort: httpPort,
        ping: -1,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _fetchSourceContent(String url) async {
    final http.Client client = http.Client();
    try {
      final http.Request req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'v2rayNG/1.8.23';

      final http.StreamedResponse response =
          await client.send(req).timeout(const Duration(seconds: 6));

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
          if (bytes.length >= 350000) {
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
        const Duration(seconds: 6),
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

  Future<int> _checkPortOpen(String host, int port) async {
    Socket? s;
    try {
      final Stopwatch sw = Stopwatch()..start();
      s = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 750),
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
  // ۳. اسکن و تست واقعی با هسته Xray (حذف ۱۰۰٪ سرورهای بدون دانلود و پینگ فیک 6ms)
  // ===========================================================================

  Future<void> _stopBackgroundScanAndWait() async {
    _abortScan = true;
    int wait = 0;
    while (_isBackgroundScanning && wait < 25) {
      await Future.delayed(const Duration(milliseconds: 100));
      wait++;
    }
  }

  /// تست واقعی سرور با هسته Xray؛ هیچ فال‌بک فیکی (مثل SecureSocket) وجود ندارد!
  /// پینگ‌های غیرواقعی زیر ۴۵ میلی‌ثانیه (مثل 6ms) هم به عنوان آی‌پی فیلترینگ رد می‌شوند.
  Future<int> _testRealXrayCoreDelay(ReadyServer node) async {
    try {
      final int delay = await v2ray
          .getServerDelay(
            config: node.configJson,
            url: 'http://cp.cloudflare.com/generate_204',
          )
          .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);

      // پینگ واقعی یک تونل خارجی از ایران همیشه بین 45 تا 2800 میلی‌ثانیه است
      if (delay >= 45 && delay < 2800) {
        return delay;
      }
    } catch (_) {}
    return -1;
  }

  Future<void> _scanAndVerifyInBackground() async {
    if (_isBackgroundScanning || isConnected) return;
    _isBackgroundScanning = true;
    _abortScan = false;

    try {
      for (int round = 0; round < 4; round++) {
        if (_abortScan || isConnected) break;
        if (isConnecting && _readyPool.isNotEmpty) break;
        if (!isConnecting && _readyPool.length >= 6) break;

        // دریافت موازی از ۳ منبع در هر دور
        final List<String> urls = [];
        for (int i = 0; i < 3; i++) {
          urls.add(_autoVpnSources[_sourceIndex % _autoVpnSources.length]);
          _sourceIndex++;
        }

        if (mounted && !isConnected) {
          setState(() {
            statusMessage = 'Fetching fresh configs...';
          });
        }

        final List<String> fetchedUris = [];
        await Future.wait(urls.map((u) async {
          final String body = await _fetchSourceContent(u);
          if (body.isNotEmpty) {
            final links = _extractValidConfigs(body);
            fetchedUris.addAll(links.take(150));
          }
        }));

        if (fetchedUris.isEmpty || _abortScan || isConnected) continue;

        final List<ReadyServer> parsedList = [];
        for (final uri in fetchedUris) {
          if (parsedList.length >= 160) break;
          if (_readyPool.any((s) => s.rawUri == uri)) continue;
          final ReadyServer? srv = _parseAndPrepareServer(uri);
          if (srv != null) {
            parsedList.add(srv);
          }
        }

        if (parsedList.isEmpty) continue;

        // مرحله ۱: غربال سریع پورت باز (رد کردن آی‌پی‌های فیک زیر ۲۰ میلی‌ثانیه)
        final List<ReadyServer> openNodes = [];
        const int sockBatch = 40;
        for (int i = 0; i < parsedList.length; i += sockBatch) {
          if (_abortScan || isConnected) break;
          final slice = parsedList.skip(i).take(sockBatch).toList();
          await Future.wait(slice.map((n) async {
            final int tcpMs = await _checkPortOpen(n.address, n.port);
            // پینگ سوکت زیر 20ms در ایران یعنی آی‌پی داخلی/فیلترینگ (مثل 6ms) -> رد شود!
            if (tcpMs >= 20 && tcpMs < 900) {
              n.ping = tcpMs;
              openNodes.add(n);
            }
          }));
        }

        if (openNodes.isEmpty || _abortScan || isConnected) continue;

        // اولویت دادن به VLESS و VMess معمولی قبل از Reality (چون Realityهای عمومی کلید منقضی زیاد دارند)
        openNodes.sort((a, b) {
          final int aIsReality = a.protocol == 'REALITY' ? 1 : 0;
          final int bIsReality = b.protocol == 'REALITY' ? 1 : 0;
          if (aIsReality != bIsReality) return aIsReality.compareTo(bIsReality);
          return a.ping.compareTo(b.ping);
        });

        // مرحله ۲: تست واقعی هسته Xray در دسته‌های کوچک ۲ تایی تا هسته قفل نکند و فقط سرورهای دارای دانلود واقعی تایید شوند
        final List<ReadyServer> topCandidates = openNodes.take(28).toList();
        for (int j = 0; j < topCandidates.length; j += 2) {
          if (_abortScan || isConnected) break;
          final pair = topCandidates.skip(j).take(2).toList();

          if (mounted && !isConnected) {
            setState(() {
              statusMessage =
                  'Verifying real download (${j + 1}/${topCandidates.length})...';
            });
          }

          await Future.wait(pair.map((cand) async {
            final int realDelay = await _testRealXrayCoreDelay(cand);
            if (realDelay >= 45 && realDelay < 2800) {
              cand.ping = realDelay;
              if (!_readyPool.any((s) => s.rawUri == cand.rawUri)) {
                _readyPool.add(cand);
                _readyPool.sort((a, b) => a.ping.compareTo(b.ping));

                if (mounted && !isConnected) {
                  setState(() {
                    currentPing = _readyPool.first.ping;
                    statusMessage =
                        'Ready • ${_readyPool.length} verified (${_readyPool.first.protocol})';
                  });
                }
              }
            } else {
              _deadUris.add(cand.rawUri);
            }
          }));

          if (_readyPool.isNotEmpty) {
            await _saveWorkingCache();
          }

          // اگر کاربر دکمه Connect را زده است، به محض پیدا شدن اولین سرور واقعی معطل نکن!
          if (isConnecting && _readyPool.isNotEmpty) {
            break;
          }
          if (!isConnecting && _readyPool.length >= 6) {
            break;
          }
        }
      }
    } catch (_) {}

    _isBackgroundScanning = false;
    if (mounted && !isConnected && !isConnecting) {
      setState(() {
        if (_readyPool.isNotEmpty) {
          currentPing = _readyPool.first.ping;
          statusMessage =
              'Ready • ${_readyPool.length} verified (${_readyPool.first.protocol})';
        } else {
          statusMessage = 'Tap Connect to find & start server';
        }
      });
    }
  }

  // ===========================================================================
  // ۴. تست ۱۰۰٪ واقعی دانلود از طریق پورت پروکسی لوکال هسته Xray (127.0.0.1:10809)
  // ===========================================================================

  /// این تابع یک درخواست HTTP واقعی را مستقیماً به پورت لوکال هسته Xray (127.0.0.1:10809) می‌فرستد
  /// و دیتای واقعی دانلود می‌کند. اگر سروری فقط آپلود داشته باشد و دانلودش 0 باشد، این تست شکست می‌خورد!
  Future<int> _verifyRealDownloadThroughLocalProxy(int localHttpPort) async {
    final List<String> testUrls = [
      'http://cp.cloudflare.com/generate_204',
      'http://www.gstatic.com/generate_204',
      'http://connectivitycheck.gstatic.com/generate_204',
    ];

    for (final String url in testUrls) {
      HttpClient? proxyClient;
      try {
        proxyClient = HttpClient();
        proxyClient.connectionTimeout = const Duration(milliseconds: 2800);
        // اجبار به عبور ۱۰۰٪ ترافیک از داخل پورت HTTP هسته Xray (بدون امکان دور زدن توسط سیم‌کارت!)
        proxyClient.findProxy = (uri) => "PROXY 127.0.0.1:$localHttpPort";

        final Stopwatch sw = Stopwatch()..start();
        final HttpClientRequest req = await proxyClient
            .getUrl(Uri.parse(url))
            .timeout(const Duration(milliseconds: 2800));
        req.headers.set('User-Agent', 'Mozilla/5.0');

        final HttpClientResponse res =
            await req.close().timeout(const Duration(milliseconds: 2800));
        // خواندن بایت‌های دانلود شده از پاسخ سرور
        await res.drain().timeout(const Duration(milliseconds: 1500));
        sw.stop();
        proxyClient.close(force: true);

        if ((res.statusCode == 204 || res.statusCode == 200) &&
            sw.elapsedMilliseconds >= 40) {
          return sw.elapsedMilliseconds;
        }
      } catch (_) {
        proxyClient?.close(force: true);
      }
    }

    // بررسی کمکی با متد خود هسته در صورتی که پورت متفاوت باشد
    try {
      final int coreDelay = await v2ray
          .getConnectedServerDelay()
          .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);
      if (coreDelay >= 45 && coreDelay < 3500) {
        return coreDelay;
      }
    } catch (_) {}

    return -1;
  }

  /// دانلود چند کیلوبایت دیتای واقعی از داخل تونل در لحظه اتصال تا شمارنده DOWNLOAD و UPLOAD بلافاصله حرکت کند
  Future<void> _warmupDownloadCounter(int localHttpPort) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      client.findProxy = (uri) => "PROXY 127.0.0.1:$localHttpPort";
      final req = await client
          .getUrl(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'))
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain();
      client.close(force: true);
    } catch (_) {
      client?.close(force: true);
    }
  }

  // ===========================================================================
  // ۵. اتصال و تایید نهایی دانلود (رد کردن خودکار سرورهای Upload-Only)
  // ===========================================================================

  Future<bool> _startAndVerifyRealDownload(ReadyServer srv) async {
    try {
      await _stopBackgroundScanAndWait();

      if (mounted) {
        setState(() {
          currentPing = srv.ping;
          statusMessage = 'Testing download on ${srv.protocol} (${srv.ping} ms)...';
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
        if (_userCancelled) {
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

      // صبر کوتاه برای باز شدن پورت 10809 هسته و سپس تست واقعی دانلود!
      await Future.delayed(const Duration(milliseconds: 500));
      if (_userCancelled) {
        await v2ray.stopV2Ray();
        return false;
      }

      final int realDownloadPing =
          await _verifyRealDownloadThroughLocalProxy(srv.localHttpPort);

      // اگر سرور فقط آپلود می‌فرستاد و هیچ دیتایی دانلود نکرد (realDownloadPing < 40)، درجا قطعش کن و برو سرور بعدی!
      if (realDownloadPing < 40 || !_nativeVpnRunning) {
        await v2ray.stopV2Ray();
        await Future.delayed(const Duration(milliseconds: 250));
        return false;
      }

      // سرور واقعاً دانلود و آپلود دارد!
      srv.ping = realDownloadPing;
      _activeServer = srv;
      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
          currentPing = realDownloadPing;
          statusMessage = 'Connected • ${srv.protocol} (Download Verified)';
        });
      }

      // ارسال یک درخواست واقعی برای به حرکت درآوردن شمارنده سرعت دانلود و آپلود روی صفحه
      _warmupDownloadCounter(srv.localHttpPort);
      await _saveWorkingCache();
      return true;
    } catch (_) {
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      return false;
    }
  }

  Future<bool> _connectToFirstDownloadWorkingServer() async {
    for (int attempt = 0; attempt < 5; attempt++) {
      if (_userCancelled) return false;

      if (_readyPool.isEmpty && !_isBackgroundScanning) {
        await _scanAndVerifyInBackground();
      }

      while (_isBackgroundScanning && _readyPool.isEmpty && !_userCancelled) {
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (_userCancelled) return false;

      if (_readyPool.isNotEmpty) {
        await _stopBackgroundScanAndWait();
      }

      _readyPool.sort((a, b) => a.ping.compareTo(b.ping));

      while (_readyPool.isNotEmpty && !_userCancelled) {
        final ReadyServer best = _readyPool.first;
        final bool worksWithDownload = await _startAndVerifyRealDownload(best);
        if (worksWithDownload) {
          return true;
        } else {
          // این سرور دانلود نداشت؛ حذف از لیست و کش، و رفتن فوری به سرور بعدی!
          _deadUris.add(best.rawUri);
          _readyPool.removeAt(0);
          await _saveWorkingCache();
        }
      }

      if (!_userCancelled) {
        await _scanAndVerifyInBackground();
      }
    }
    return false;
  }

  Future<void> _onConnectButtonPressed() async {
    _failoverCountdownTimer?.cancel();
    _failoverCountdownTimer = null;

    if (isConnected || isConnecting) {
      _userCancelled = true;
      _abortScan = true;
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
        _nativeVpnRunning = false;
        _isAutoSwitching = false;
        statusMessage = _readyPool.isNotEmpty
            ? 'Ready • ${_readyPool.length} verified (${_readyPool.first.protocol})'
            : 'Tap Connect to start';
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
      _userCancelled = false;
      statusMessage = 'Connecting & verifying download...';
    });

    final bool ok = await _connectToFirstDownloadWorkingServer();

    if (!ok && mounted && !_userCancelled) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'Could not verify download • Tap Connect to retry';
      });
      _scanAndVerifyInBackground();
    }
  }

  /// دکمه تعویض فوری سرور (Next Server)
  Future<void> _switchToNextServerInstantly() async {
    if (_isAutoSwitching) return;
    _isAutoSwitching = true;
    _userCancelled = false;

    if (_activeServer != null) {
      _deadUris.add(_activeServer!.rawUri);
      _readyPool.removeWhere((s) => s.rawUri == _activeServer!.rawUri);
      await _saveWorkingCache();
    }

    if (mounted) {
      setState(() {
        isConnecting = true;
        isConnected = false;
        statusMessage = 'Switching to next verified server...';
      });
    }

    try {
      await v2ray.stopV2Ray();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 300));
    await _connectToFirstDownloadWorkingServer();
    _isAutoSwitching = false;
  }

  // ===========================================================================
  // ۶. رفرش کلیکی پینگ واقعی + تشخیص قطعی کانفیگ یا اینترنت (۳۰ ثانیه)
  // ===========================================================================

  Future<void> _refreshPingOnTap() async {
    if (isRefreshingPing) return;
    setState(() => isRefreshingPing = true);

    try {
      if (isConnected && _activeServer != null) {
        final int realPing =
            await _verifyRealDownloadThroughLocalProxy(_activeServer!.localHttpPort);
        if (mounted) {
          setState(() {
            currentPing = realPing >= 40 ? realPing : -1;
          });
        }
      } else if (!isConnecting) {
        if (_readyPool.isEmpty) {
          await _scanAndVerifyInBackground();
        } else {
          final int d = await _testRealXrayCoreDelay(_readyPool.first);
          if (mounted) {
            if (d >= 45) {
              setState(() {
                _readyPool.first.ping = d;
                currentPing = d;
              });
            } else {
              _readyPool.removeAt(0);
              setState(() {
                currentPing = _readyPool.isNotEmpty ? _readyPool.first.ping : -1;
              });
            }
          }
        }
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

    final int dlPing =
        await _verifyRealDownloadThroughLocalProxy(_activeServer!.localHttpPort);

    if (dlPing >= 40 && dlPing < 3500) {
      _failoverCountdownTimer?.cancel();
      _failoverCountdownTimer = null;
      _configFailSeconds = 0;
      _internetIsDown = false;
      if (mounted) {
        setState(() {
          currentPing = dlPing;
          statusMessage = 'Connected • ${_activeServer!.protocol} (Download Active)';
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
  // ۷. رابط کاربری (UI)
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
                                : (isConnecting ? 'Tap to cancel' : 'Verified Auto Server'),
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

              // ۴. نوار وضعیت پایین صفحه + دکمه تعویض فوری سرور
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
                          if ((_isBackgroundScanning || isConnecting) && !isConnected)
                            const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00F5D4),
                              ),
                            )
                          else
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
