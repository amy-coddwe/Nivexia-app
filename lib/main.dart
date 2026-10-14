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
  int ping;
  bool coreVerified;

  ReadyServer({
    required this.rawUri,
    required this.configJson,
    required this.protocol,
    required this.address,
    required this.port,
    required this.ping,
    this.coreVerified = false,
  });
}

class ProtocolTier {
  final String name;
  final List<String> urls;

  const ProtocolTier({
    required this.name,
    required this.urls,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const int _chunkSize = 300; // بررسی پله‌ای ۳۰۰ تا ۳۰۰ تا

  late final V2ray v2ray = V2ray(
    onStatusChanged: (status) {
      if (!mounted) return;
      final String st = status.state.toUpperCase();
      setState(() {
        v2rayStatus = status;
        if (st == "CONNECTED") {
          isConnected = true;
          isConnecting = false;
        } else if (st == "DISCONNECTED" && !isConnecting && !_isAutoSwitching) {
          isConnected = false;
        }
      });
    },
  );

  late AnimationController _pulseController;
  V2RayStatus v2rayStatus = V2RayStatus();

  bool isConnected = false;
  bool isConnecting = false;
  bool isRefreshingPing = false;
  bool _isScanning = false;
  bool _isAutoSwitching = false;
  bool _userCancelledConnect = false;

  int currentPing = -1;
  String statusMessage = 'Initializing scanner...';

  Timer? _backgroundPoolTimer;
  Timer? _healthWatchdogTimer;
  Timer? _failoverCountdownTimer;
  int _configFailSeconds = 0;
  bool _internetIsDown = false;

  final List<ReadyServer> _readyPool = [];
  final Set<String> _deadUris = {};
  ReadyServer? _activeServer;

  // ترتیب اولویت پروتکل‌ها: اول VLESS، اگر پیدا نشد VMess، بعد SS و بعد SSR
  // برای هر پروتکل، لینک‌های مستقیم Epodonios + پروکسی‌های ضدتحریم + منابع کمکی قرار داده شده است
  final List<ProtocolTier> _protocolWaterfall = const [
    ProtocolTier(
      name: 'VLESS',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
        'https://ghp.ci/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/vless.txt',
        'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vless_configs.txt',
      ],
    ),
    ProtocolTier(
      name: 'VMess',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
        'https://ghp.ci/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/vmess.txt',
        'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vmess_configs.txt',
      ],
    ),
    ProtocolTier(
      name: 'Shadowsocks (SS)',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
        'https://ghp.ci/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/ss.txt',
        'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/ss_configs.txt',
      ],
    ),
    ProtocolTier(
      name: 'SSR / Other',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
        'https://ghp.ci/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/trojan.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/trojan.txt',
      ],
    ),
  ];

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

    // شروع فوری اسکن پله‌ای (۳۰۰ تا ۳۰۰ تا) به محض باز شدن برنامه
    _runContinuousWaterfallScan();

    // بررسی دوره‌ای در پس‌زمینه برای تازه نگه داشتن لیست سرورهای آماده
    _backgroundPoolTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!isConnecting && !_isScanning) {
        _refreshExistingPoolAndTopUp();
      }
    });

    // مانیتورینگ سلامت اتصال هر ۱۰ ثانیه وقتی VPN روشن است
    _healthWatchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
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
  // ۱. پردازش و نرمال‌سازی کانفیگ‌ها (VLESS, VMess, SS, SSR و Base64)
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

  /// تبدیل لینک‌های SSR به فرمت استاندارد SS تا هسته Xray بدون خطا آن را اجرا کند
  String? _convertSsrToStandardSs(String ssrUri) {
    try {
      final String b64Part = ssrUri.substring(6).trim();
      final String decoded = _decodeBase64Safe(b64Part);
      if (decoded.isEmpty) return null;

      // فرمت استاندارد SSR: host:port:protocol:method:obfs:base64pass/?params
      final String mainPart = decoded.split('/?').first;
      final List<String> parts = mainPart.split(':');
      if (parts.length < 6) return null;

      final String host = parts[0].trim();
      final String port = parts[1].trim();
      final String method = parts[3].trim();
      final String passB64 = parts[5].trim();
      final String password = _decodeBase64Safe(passB64);

      if (host.isEmpty || password.isEmpty) return null;
      final String userInfoB64 = base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
      return 'ss://$userInfoB64@$host:$port#SSR-Node';
    } catch (_) {
      return null;
    }
  }

  /// استانداردسازی لینک‌های SS قدیمی به فرمت SIP002
  String _normalizeSsUri(String ssUri) {
    try {
      if (!ssUri.startsWith('ss://')) return ssUri;
      final String withoutPrefix = ssUri.substring(5);
      final String mainPart = withoutPrefix.split('#').first;
      if (!mainPart.contains('@')) {
        final String decoded = _decodeBase64Safe(mainPart);
        if (decoded.contains('@')) {
          final List<String> atParts = decoded.split('@');
          final String methodPass = atParts.first;
          final String hostPort = atParts.last;
          final String encodedUser = base64Url.encode(utf8.encode(methodPass)).replaceAll('=', '');
          return 'ss://$encodedUser@$hostPort#SS-Node';
        }
      }
    } catch (_) {}
    return ssUri;
  }

  /// استخراج تمام لینک‌های معتبر از متن خام یا فایل‌های Base64
  List<String> _extractAllConfigsFromContent(String rawContent) {
    String text = rawContent.trim();
    if (text.isEmpty) return [];

    // اگر کل فایل Base64 بود (مثل فایل‌های vmess.txt و ss.txt در Epodonios)، کامل رمزگشایی شود
    if (!text.contains('://')) {
      final String decoded = _decodeBase64Safe(text);
      if (decoded.isNotEmpty) {
        text = decoded;
      }
    }

    final List<String> validLinks = [];
    final Set<String> seenInFile = {};

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
        if (seenInFile.add(line)) {
          validLinks.add(line);
        }
      }
    }
    return validLinks;
  }

  /// دانلود محتوای منبع با مدیریت جریان (تا سقف ۳ مگابایت از هر فایل برای پوشش هزاران کانفیگ بدون هنگ کردن رم)
  Future<String> _downloadSourceContent(String url) async {
    final http.Client client = http.Client();
    try {
      final http.Request req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'Mozilla/5.0 (Android; Mobile)';

      final http.StreamedResponse response =
          await client.send(req).timeout(const Duration(seconds: 7));

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
          // دریافت تا ۲.۵ مگابایت (شامل بیش از ۵۰۰۰ تا ۸۰۰۰ کانفیگ برای اسکن پله‌ای ۳۰۰ تایی)
          if (bytes.length >= 2500000) {
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
        const Duration(seconds: 8),
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

  String _prepareCleanXrayJson(String rawJson) {
    try {
      final Map<String, dynamic> cfg = jsonDecode(rawJson);
      cfg['dns'] = {
        "servers": ["1.1.1.1", "8.8.8.8"],
      };
      if (cfg['outbounds'] is List && (cfg['outbounds'] as List).isNotEmpty) {
        final Map<String, dynamic> ob = Map<String, dynamic>.from(cfg['outbounds'][0]);
        if (ob['streamSettings'] is Map) {
          final Map<String, dynamic> stream = Map<String, dynamic>.from(ob['streamSettings']);
          if (stream['security'] == 'tls') {
            stream['tlsSettings'] ??= <String, dynamic>{};
            stream['tlsSettings']['allowInsecure'] = true;
          }
          ob['streamSettings'] = stream;
        }
        cfg['outbounds'][0] = ob;
      }
      return jsonEncode(cfg);
    } catch (_) {
      return rawJson;
    }
  }

  /// تست سریع باز بودن پورت و پینگ اولیه
  Future<int> _measureSocketPing(String host, int port) async {
    final Stopwatch sw = Stopwatch()..start();
    Socket? sock;
    try {
      sock = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 1000),
      );
      sw.stop();
      await sock.close();
      return sw.elapsedMilliseconds;
    } catch (_) {
      sock?.destroy();
      return -1;
    }
  }

  // ===========================================================================
  // ۲. موتور اسکن پله‌ای (۳۰۰ تا ۳۰۰ تا) + سوییچ خودکار پروتکل (VLESS -> VMess -> SS -> SSR)
  // ===========================================================================

  /// تست یک دسته ۳۰۰ تایی از کانفیگ‌ها و بازگرداندن تعداد سرورهای سالم پیدا شده در این دسته
  Future<int> _scan300Batch(
    List<String> batchLinks,
    String protocolName,
    int startIndex,
    int endIndex,
  ) async {
    if (mounted && !isConnected) {
      setState(() {
        statusMessage = 'Scanning $protocolName ($startIndex - $endIndex)...';
      });
    }

    final List<ReadyServer> parsedCandidates = [];
    for (final uri in batchLinks) {
      if (_readyPool.any((s) => s.rawUri == uri)) continue;
      try {
        final V2RayURL parser = V2ray.parseFromURL(uri);
        final String host = parser.address.trim();
        final int port = parser.port;
        if (host.isEmpty || port <= 0 || host == '127.0.0.1') continue;

        final String configJson = _prepareCleanXrayJson(parser.getFullConfiguration());
        parsedCandidates.add(ReadyServer(
          rawUri: uri,
          configJson: configJson,
          protocol: protocolName,
          address: host,
          port: port,
          ping: -1,
        ));
      } catch (_) {}
    }

    if (parsedCandidates.isEmpty) return 0;

    int foundInThisBatch = 0;

    // تست ۳۰۰ کانفیگ در زیرگروه‌های ۳۰ تایی موازی برای سرعت بالا بدون هنگ کردن گوشی
    const int socketConcurrency = 30;
    final List<ReadyServer> socketSurvivors = [];

    for (int i = 0; i < parsedCandidates.length; i += socketConcurrency) {
      if (_userCancelledConnect && isConnecting) break;

      final subSlice = parsedCandidates.skip(i).take(socketConcurrency).toList();
      await Future.wait(subSlice.map((cand) async {
        final int tcpPing = await _measureSocketPing(cand.address, cand.port);
        if (tcpPing > 0 && tcpPing < 1800) {
          cand.ping = tcpPing;
          socketSurvivors.add(cand);
        }
      }));
    }

    if (socketSurvivors.isEmpty) return 0;

    // مرتب‌سازی سرورهایی که پورتشان باز است بر اساس کمترین پینگ
    socketSurvivors.sort((a, b) => a.ping.compareTo(b.ping));

    // تست تک‌به‌تک با هسته Xray روی بهترین کاندیداهای این دسته ۳۰۰ تایی
    for (final survivor in socketSurvivors.take(15)) {
      int coreDelay = -1;
      try {
        coreDelay = await v2ray
            .getServerDelay(config: survivor.configJson)
            .timeout(const Duration(milliseconds: 2200), onTimeout: () => -1);
      } catch (_) {
        coreDelay = -1;
      }

      if (coreDelay > 0 && coreDelay < 3500) {
        survivor.ping = coreDelay;
        survivor.coreVerified = true;
      }

      // اضافه کردن به لیست آماده (اولویت اول با سرورهای تاییدشده هسته، سپس کمترین پینگ)
      if (!_readyPool.any((s) => s.rawUri == survivor.rawUri)) {
        _readyPool.add(survivor);
        foundInThisBatch++;
        _sortReadyPool();

        if (mounted && !isConnected) {
          setState(() {
            currentPing = _readyPool.first.ping;
            statusMessage =
                'Ready • ${_readyPool.length} servers (${_readyPool.first.protocol})';
          });
        }

        // اگر کاربر دکمه Connect را زده و منتظر اولین سرور سالم است، به محض پیدا شدن ۳ سرور خوب، معطل نکن!
        if (isConnecting && _readyPool.length >= 3) {
          break;
        }
      }
    }

    return foundInThisBatch;
  }

  void _sortReadyPool() {
    _readyPool.sort((a, b) {
      if (a.coreVerified != b.coreVerified) {
        return a.coreVerified ? -1 : 1;
      }
      return a.ping.compareTo(b.ping);
    });
  }

  /// حلقه اصلی اسکن آبشاری:
  /// اول VLESS را ۳۰۰ تا ۳۰۰ تا می‌گردد -> اگر پیدا نشد می‌رود سراغ VMess -> بعد SS -> بعد SSR
  Future<void> _runContinuousWaterfallScan() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      for (final ProtocolTier tier in _protocolWaterfall) {
        // اگر به اندازه کافی سرور سالم آماده داریم، نیازی به رفتن به پروتکل بعدی نیست
        if (_readyPool.length >= 8) break;

        if (mounted && !isConnected) {
          setState(() {
            statusMessage = 'Fetching ${tier.name} configs...';
          });
        }

        // تلاش برای دانلود لیست کانفیگ‌های این پروتکل از لینک‌های آن
        List<String> allProtocolConfigs = [];
        for (final String url in tier.urls) {
          final String rawBody = await _downloadSourceContent(url);
          if (rawBody.isNotEmpty) {
            final List<String> extracted = _extractAllConfigsFromContent(rawBody);
            if (extracted.length >= 20) {
              allProtocolConfigs = extracted;
              break; // به محض دریافت موفق از اولین آینه سالم، می‌رویم سراغ اسکن ۳۰۰ تایی
            }
          }
        }

        if (allProtocolConfigs.isEmpty) {
          // اگر این پروتکل دانلود نشد، مستقیم برو سراغ پروتکل بعدی
          continue;
        }

        // پیمایش پله‌ای ۳۰۰ تا ۳۰۰ تا در کل کانفیگ‌های این پروتکل!
        for (int offset = 0;
            offset < allProtocolConfigs.length;
            offset += _chunkSize) {
          final int end = min(offset + _chunkSize, allProtocolConfigs.length);
          final List<String> chunk300 = allProtocolConfigs.sublist(offset, end);

          final int foundCount = await _scan300Batch(
            chunk300,
            tier.name,
            offset + 1,
            end,
          );

          // اگر در این ۳۰۰ تا، سرورهای سالم پیدا شد و به حد نصاب رسیدیم، متوقف می‌شویم
          // اما اگر هیچی پیدا نشد (foundCount == 0)، حلقه خودکار می‌رود سراغ ۳۰۰ تای بعدی (301-600، 601-900 و...)!
          if (foundCount > 0 && _readyPool.length >= 6) {
            break;
          }
        }
      }
    } catch (_) {}

    _isScanning = false;
    if (mounted && !isConnected && !isConnecting) {
      setState(() {
        if (_readyPool.isNotEmpty) {
          currentPing = _readyPool.first.ping;
          statusMessage =
              'Ready • ${_readyPool.length} servers (${_readyPool.first.protocol})';
        } else {
          statusMessage = 'Tap Connect to deep-scan all protocols';
        }
      });
    }
  }

  /// به‌روزرسانی پینگ سرورهای آماده در پس‌زمینه
  Future<void> _refreshExistingPoolAndTopUp() async {
    if (_readyPool.isNotEmpty && !isConnected) {
      final List<ReadyServer> current = List<ReadyServer>.from(_readyPool);
      final List<ReadyServer> stillAlive = [];

      await Future.wait(current.map((srv) async {
        final int p = await _measureSocketPing(srv.address, srv.port);
        if (p > 0 && p < 2000) {
          srv.ping = p;
          stillAlive.add(srv);
        }
      }));

      _readyPool
        ..clear()
        ..addAll(stillAlive);
      _sortReadyPool();

      if (_readyPool.isNotEmpty && mounted && !isConnected) {
        setState(() {
          currentPing = _readyPool.first.ping;
        });
      }
    }

    if (_readyPool.length < 5) {
      await _runContinuousWaterfallScan();
    }
  }

  // ===========================================================================
  // ۳. تست واقعی پینگ و رفرش کلیکی بالای صفحه
  // ===========================================================================

  Future<int> _measureLiveTunnelPing() async {
    // ۱. تست از طریق متد داخلی هسته
    try {
      final int coreDelay = await v2ray
          .getConnectedServerDelay()
          .timeout(const Duration(milliseconds: 2500), onTimeout: () => -1);
      if (coreDelay > 0 && coreDelay < 4000) return coreDelay;
    } catch (_) {}

    // ۲. تست درخواست سبک 204
    for (final url in [
      'http://www.gstatic.com/generate_204',
      'http://cp.cloudflare.com/generate_204',
    ]) {
      try {
        final Stopwatch sw = Stopwatch()..start();
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(milliseconds: 2500));
        sw.stop();
        if (res.statusCode == 204 || res.statusCode == 200) {
          return sw.elapsedMilliseconds;
        }
      } catch (_) {}
    }

    // ۳. پینگ مستقیم سرور متصل
    if (_activeServer != null) {
      return await _measureSocketPing(_activeServer!.address, _activeServer!.port);
    }
    return -1;
  }

  /// با هر کلیک روی پینگ بالای صفحه، پینگ رفرش و نمایش داده می‌شود
  Future<void> _refreshPingOnTap() async {
    if (isRefreshingPing) return;
    setState(() => isRefreshingPing = true);

    try {
      if (isConnected) {
        final int p = await _measureLiveTunnelPing();
        if (mounted && p > 0) {
          setState(() => currentPing = p);
        }
      } else {
        if (_readyPool.isEmpty) {
          await _runContinuousWaterfallScan();
        } else {
          final int p = await _measureSocketPing(
            _readyPool.first.address,
            _readyPool.first.port,
          );
          if (mounted && p > 0) {
            setState(() {
              _readyPool.first.ping = p;
              currentPing = p;
            });
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => isRefreshingPing = false);
    }
  }

  // ===========================================================================
  // ۴. تشخیص قطعی کانفیگ یا اینترنت + اتصال خودکار به سرور جدید بعد از ۳۰ ثانیه
  // ===========================================================================

  Future<bool> _isUserInternetConnected() async {
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

    final int livePing = await _measureLiveTunnelPing();

    // اگر کانفیگ سالم است:
    if (livePing > 0 && livePing < 3500) {
      _failoverCountdownTimer?.cancel();
      _failoverCountdownTimer = null;
      _configFailSeconds = 0;
      _internetIsDown = false;
      if (mounted) {
        setState(() {
          currentPing = livePing;
          statusMessage = 'Connected • ${_activeServer!.protocol} Active';
        });
      }
      return;
    }

    // بررسی اینکه مشکل از اینترنت کاربر است یا از کانفیگ:
    final bool hasNet = await _isUserInternetConnected();

    if (!hasNet) {
      _failoverCountdownTimer?.cancel();
      _failoverCountdownTimer = null;
      _configFailSeconds = 0;
      if (mounted) {
        setState(() {
          _internetIsDown = true;
          currentPing = -1;
          statusMessage = 'No Internet • Waiting for network connection...';
        });
      }
      return;
    }

    // اینترنت وصل است ولی کانفیگ قطع شده -> شمارش ۳۰ ثانیه و اتصال به سرور جدید
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
          await _switchToNewServerAutomatically();
        }
      });
    }
  }

  Future<void> _switchToNewServerAutomatically() async {
    if (_isAutoSwitching || !isConnected) return;
    _isAutoSwitching = true;

    if (mounted) {
      setState(() {
        statusMessage = 'Switching to a new healthy server...';
      });
    }

    if (_activeServer != null) {
      _deadUris.add(_activeServer!.rawUri);
      _readyPool.removeWhere((s) => s.rawUri == _activeServer!.rawUri);
    }

    try {
      await v2ray.stopV2Ray();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 400));

    await _connectUsingPoolOrScan();
    _isAutoSwitching = false;
  }

  // ===========================================================================
  // ۵. منطق اتصال بدون خطا (اگر لیست خالی شد، خودش ۳۰۰ تای بعدی را می‌گردد تا وصل شود)
  // ===========================================================================

  Future<bool> _tryStartSingleServer(ReadyServer srv) async {
    try {
      final int prePing = await _measureSocketPing(srv.address, srv.port);
      if (prePing <= 0) return false;

      await v2ray.startV2Ray(
        remark: "Nivexia VPN (${srv.protocol})",
        config: srv.configJson,
        proxyOnly: false,
      );

      // صبر برای بالا آمدن سرویس VPN اندروید
      int waited = 0;
      while (!isConnected && waited < 3500) {
        if (_userCancelledConnect) {
          await v2ray.stopV2Ray();
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 250));
        waited += 250;
      }

      final int postPing = await _measureLiveTunnelPing();
      final int finalPing = postPing > 0 ? postPing : prePing;

      _activeServer = srv;
      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
          currentPing = finalPing;
          statusMessage = 'Connected • ${srv.protocol} Active';
        });
      }
      return true;
    } catch (_) {
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      return false;
    }
  }

  /// تلاش برای اتصال؛ اگر اسکن در حال انجام است صبر می‌کند و اگر سرورها تمام شدند ۳۰۰ تای بعدی را اسکن می‌کند
  Future<bool> _connectUsingPoolOrScan() async {
    for (int cycle = 0; cycle < 3; cycle++) {
      if (_userCancelledConnect) return false;

      // اگر اسکنر در حال کار است و هنوز سروری پیدا نکرده، صبر کن تا اولین دسته ۳۰۰ تایی نتیجه بدهد
      while (_isScanning && _readyPool.isEmpty && !_userCancelledConnect) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // اگر لیست خالی است، اسکن آبشاری ۳۰۰ تایی را اجرا کن
      if (_readyPool.isEmpty && !_userCancelledConnect) {
        await _runContinuousWaterfallScan();
      }

      _sortReadyPool();

      while (_readyPool.isNotEmpty && !_userCancelledConnect) {
        final ReadyServer best = _readyPool.first;
        if (mounted) {
          setState(() {
            currentPing = best.ping;
            statusMessage = 'Connecting to ${best.protocol} (${best.ping} ms)...';
          });
        }

        final bool connectedOk = await _tryStartSingleServer(best);
        if (connectedOk) {
          return true;
        } else {
          _deadUris.add(best.rawUri);
          _readyPool.removeAt(0);
        }
      }
    }
    return false;
  }

  Future<void> _onConnectButtonPressed() async {
    _failoverCountdownTimer?.cancel();
    _failoverCountdownTimer = null;

    // قطع اتصال یا لغو تلاش جاری
    if (isConnected || isConnecting) {
      _userCancelledConnect = true;
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
        _isAutoSwitching = false;
        statusMessage = _readyPool.isNotEmpty
            ? 'Ready • ${_readyPool.length} servers (${_readyPool.first.protocol})'
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
      _userCancelledConnect = false;
      statusMessage = 'Finding best server...';
    });

    final bool ok = await _connectUsingPoolOrScan();

    if (!ok && mounted && !_userCancelledConnect) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'No server responded on your network • Tap to retry';
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

                  // باکس پینگ: با هر بار کلیک پینگ را رفرش می‌کند
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
                                : (isConnecting ? 'Tap to cancel' : 'Auto Best Server'),
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

              // ۴. نوار وضعیت پایین صفحه (نمایش زنده شماره دسته ۳۰۰ تایی و پروتکل در حال اسکن)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF151924),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primaryNeon.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isScanning && !isConnected)
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
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
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
