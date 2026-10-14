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

  ReadyServer({
    required this.rawUri,
    required this.configJson,
    required this.protocol,
    required this.address,
    required this.port,
    required this.ping,
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
  static const int _chunkSize = 300; // بررسی پله‌ای ۳۰۰ تا ۳۰۰ تا به ترتیب خطوط فایل

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
  bool _isScanning = false;
  bool _abortScanRequested = false;
  bool _isAutoSwitching = false;
  bool _userCancelledConnect = false;

  int currentPing = -1;
  String statusMessage = 'Preparing scanner...';

  Timer? _backgroundPoolTimer;
  Timer? _healthWatchdogTimer;
  Timer? _failoverCountdownTimer;
  int _configFailSeconds = 0;
  bool _internetIsDown = false;

  final List<ReadyServer> _readyPool = [];
  final Set<String> _deadUris = {};
  ReadyServer? _activeServer;

  // به خاطر سپردن نقطه اسکن در هر پروتکل تا اگر ۳۰۰ تای اول جواب نداد، برود ۳۰۰ تای بعدی
  int _currentTierIndex = 0;
  int _currentOffsetInTier = 0;
  final Map<String, List<String>> _cachedProtocolLines = {};

  // ۴ منبع اصلی Epodonios به ترتیب: VLESS -> VMess -> SS -> SSR
  final List<ProtocolTier> _protocolWaterfall = const [
    ProtocolTier(
      name: 'VLESS',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/vless.txt',
        'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vless_configs.txt',
      ],
    ),
    ProtocolTier(
      name: 'VMess',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/vmess.txt',
        'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vmess_configs.txt',
      ],
    ),
    ProtocolTier(
      name: 'Shadowsocks',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/ss.txt',
        'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/ss_configs.txt',
      ],
    ),
    ProtocolTier(
      name: 'SSR / Trojan',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
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

    // اسکن دسته ۳۰۰ تایی اول در پس‌زمینه به محض ورود به برنامه
    _scanNextAvailableChunk();

    // به‌روزرسانی پینگ سرورهای آماده در پس‌زمینه (فقط زمانی که VPN قطع است)
    _backgroundPoolTimer = Timer.periodic(const Duration(seconds: 40), (_) {
      if (!isConnected && !isConnecting && !_isScanning) {
        _refreshReadyPoolPings();
      }
    });

    // بررسی سلامت اتصال هر ۱۲ ثانیه وقتی VPN روشن است
    _healthWatchdogTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (isConnected && !isConnecting && !_isAutoSwitching) {
        _checkConnectionAndHandleFailover();
      }
    });
  }

  @override
  void dispose() {
    _abortScanRequested = true;
    _pulseController.dispose();
    _backgroundPoolTimer?.cancel();
    _healthWatchdogTimer?.cancel();
    _failoverCountdownTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // ۱. استخراج و نرمال‌سازی کانفیگ‌ها به ترتیب دقیق فایل (بدون بر زدن تصادفی)
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

  List<String> _extractOrderedConfigs(String rawContent) {
    String text = rawContent.trim();
    if (text.isEmpty) return [];

    if (!text.contains('://')) {
      final String decoded = _decodeBase64Safe(text);
      if (decoded.isNotEmpty) text = decoded;
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
        if (line.contains('ech=') || line.contains('allowInsecure=')) continue;
        if (_deadUris.contains(line)) continue;
        if (seenInFile.add(line)) {
          validLinks.add(line);
        }
      }
    }
    return validLinks;
  }

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
          if (bytes.length >= 2200000) {
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

  /// اصلاح باگ URL-Encoding در خروجی پارسر (تبدیل %2F به / در مسیرهای WebSocket)
  String _fixParsedConfigJson(String rawConfigJson) {
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

  /// تست دو مرحله‌ای سوکت (حذف سرورهای دارای پکت‌لاس)
  Future<int> _measureStableSocketPing(String host, int port) async {
    Socket? s1;
    try {
      final Stopwatch sw1 = Stopwatch()..start();
      s1 = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 850),
      );
      sw1.stop();
      await s1.close();
      final int p1 = sw1.elapsedMilliseconds;
      if (p1 <= 0 || p1 > 900) return -1;

      // تست دوم برای اطمینان از پایدار بودن پورت سرور
      Socket? s2;
      try {
        final Stopwatch sw2 = Stopwatch()..start();
        s2 = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 850),
        );
        sw2.stop();
        await s2.close();
        return (p1 + sw2.elapsedMilliseconds) ~/ 2;
      } catch (_) {
        s2?.destroy();
        return -1;
      }
    } catch (_) {
      s1?.destroy();
      return -1;
    }
  }

  // ===========================================================================
  // ۲. اسکن پله‌ای ۳۰۰ تا ۳۰۰ تا (۱-۳۰۰، ۳۰۱-۶۰۰ و...) + سوییچ خودکار پروتکل
  // ===========================================================================

  Future<void> _stopScannerAndWait() async {
    _abortScanRequested = true;
    int loops = 0;
    while (_isScanning && loops < 25) {
      await Future.delayed(const Duration(milliseconds: 100));
      loops++;
    }
  }

  /// اسکن یک دسته ۳۰۰ تایی و اضافه کردن سرورهای باز به صف آماده
  Future<int> _scanSingle300Batch(
    List<String> batchLinks,
    String protocolName,
    int startIdx,
    int endIdx,
  ) async {
    if (_abortScanRequested || isConnected) return 0;

    if (mounted && !isConnected) {
      setState(() {
        statusMessage = 'Scanning $protocolName ($startIdx - $endIdx)...';
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

        final String fixedJson = _fixParsedConfigJson(parser.getFullConfiguration());
        parsedCandidates.add(ReadyServer(
          rawUri: uri,
          configJson: fixedJson,
          protocol: protocolName,
          address: host,
          port: port,
          ping: -1,
        ));
      } catch (_) {}
    }

    if (parsedCandidates.isEmpty) return 0;

    int addedCount = 0;
    const int batchConcurrency = 40;

    for (int i = 0; i < parsedCandidates.length; i += batchConcurrency) {
      if (_abortScanRequested || isConnected) break;

      final slice = parsedCandidates.skip(i).take(batchConcurrency).toList();
      await Future.wait(slice.map((cand) async {
        final int ping = await _measureStableSocketPing(cand.address, cand.port);
        if (ping > 0 && ping < 900) {
          cand.ping = ping;
          if (!_readyPool.any((s) => s.rawUri == cand.rawUri)) {
            _readyPool.add(cand);
            _readyPool.sort((a, b) => a.ping.compareTo(b.ping));
            addedCount++;

            if (mounted && !isConnected) {
              setState(() {
                currentPing = _readyPool.first.ping;
                statusMessage =
                    'Ready • ${_readyPool.length} servers found ($protocolName)';
              });
            }
          }
        }
      }));
    }

    return addedCount;
  }

  /// اسکن دسته ۳۰۰ تایی بعدی؛ اگر در ۳۰۰ تای فعلی چیزی پیدا نشد، خودکار می‌رود ۳۰۰ تای بعدی و پروتکل بعدی
  Future<void> _scanNextAvailableChunk() async {
    if (_isScanning || isConnected) return;
    _isScanning = true;
    _abortScanRequested = false;

    try {
      while (_currentTierIndex < _protocolWaterfall.length &&
          !_abortScanRequested &&
          !isConnected) {
        final ProtocolTier tier = _protocolWaterfall[_currentTierIndex];

        // دانلود لیست کانفیگ‌های این پروتکل در صورت نبودن در حافظه
        if (!_cachedProtocolLines.containsKey(tier.name) ||
            _cachedProtocolLines[tier.name]!.isEmpty) {
          if (mounted && !isConnected) {
            setState(() {
              statusMessage = 'Loading ${tier.name} configs...';
            });
          }

          List<String> lines = [];
          for (final String url in tier.urls) {
            if (_abortScanRequested || isConnected) break;
            final String body = await _downloadSourceContent(url);
            if (body.isNotEmpty) {
              final List<String> extracted = _extractOrderedConfigs(body);
              if (extracted.length >= 15) {
                lines = extracted;
                break;
              }
            }
          }

          if (lines.isEmpty) {
            // اگر این پروتکل دانلود نشد، برو سراغ پروتکل بعدی
            _currentTierIndex++;
            _currentOffsetInTier = 0;
            continue;
          }
          _cachedProtocolLines[tier.name] = lines;
        }

        final List<String> allLines = _cachedProtocolLines[tier.name]!;
        if (_currentOffsetInTier >= allLines.length) {
          // کل کانفیگ‌های این پروتکل بررسی شدند؛ برو سراغ پروتکل بعدی (VMess -> SS -> SSR)
          _currentTierIndex++;
          _currentOffsetInTier = 0;
          continue;
        }

        final int start = _currentOffsetInTier;
        final int end = min(start + _chunkSize, allLines.length);
        _currentOffsetInTier = end;

        final List<String> chunk300 = allLines.sublist(start, end);
        final int found = await _scanSingle300Batch(
          chunk300,
          tier.name,
          start + 1,
          end,
        );

        // اگر در این دسته ۳۰۰ تایی حداقل ۵ سرور کاندید پیدا شد، همین‌جا متوقف شو تا تست اتصال انجام شود
        // اگر کمتر بود یا صفر بود، حلقه بدون توقف می‌رود سراغ ۳۰۰ تای بعدی (301-600 و...)!
        if (found > 0 && _readyPool.length >= 5) {
          break;
        }
      }

      // اگر به انتهای تمام پروتکل‌ها رسیدیم، از اول ریست کن
      if (_currentTierIndex >= _protocolWaterfall.length) {
        _currentTierIndex = 0;
        _currentOffsetInTier = 0;
      }
    } catch (_) {}

    _isScanning = false;
    if (mounted && !isConnected && !isConnecting) {
      setState(() {
        if (_readyPool.isNotEmpty) {
          currentPing = _readyPool.first.ping;
          statusMessage =
              'Ready • ${_readyPool.length} servers prepared (${_readyPool.first.protocol})';
        } else {
          statusMessage = 'Tap Connect to scan & connect';
        }
      });
    }
  }

  Future<void> _refreshReadyPoolPings() async {
    if (_readyPool.isNotEmpty && !isConnected) {
      final List<ReadyServer> copy = List<ReadyServer>.from(_readyPool);
      final List<ReadyServer> alive = [];

      await Future.wait(copy.map((srv) async {
        final int p = await _measureStableSocketPing(srv.address, srv.port);
        if (p > 0 && p < 1000) {
          srv.ping = p;
          alive.add(srv);
        }
      }));

      alive.sort((a, b) => a.ping.compareTo(b.ping));
      _readyPool
        ..clear()
        ..addAll(alive);

      if (_readyPool.isNotEmpty && mounted && !isConnected) {
        setState(() => currentPing = _readyPool.first.ping);
      }
    }

    if (_readyPool.length < 4 && !isConnected) {
      await _scanNextAvailableChunk();
    }
  }

  // ===========================================================================
  // ۳. تست واقعی عبور اینترنت از داخل تونل VPN (جلوگیری ۱۰۰٪ از اتصال فیک)
  // ===========================================================================

  /// بررسی اینکه آیا سرور متصل‌شده واقعاً اینترنت را باز کرده است یا خیر (درخواست واقعی HTTP 204 از داخل تونل)
  Future<int> _verifyRealInternetThroughTunnel() async {
    final List<String> testEndpoints = [
      'http://cp.cloudflare.com/generate_204',
      'http://connectivitycheck.gstatic.com/generate_204',
      'http://www.gstatic.com/generate_204',
    ];

    for (final String url in testEndpoints) {
      try {
        final Stopwatch sw = Stopwatch()..start();
        final http.Response res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(milliseconds: 2600));
        sw.stop();
        if (res.statusCode == 204 || res.statusCode == 200) {
          return sw.elapsedMilliseconds;
        }
      } catch (_) {}
    }
    return -1;
  }

  /// رفرش پینگ با کلیک روی باکس بالای صفحه
  Future<void> _refreshPingOnTap() async {
    if (isRefreshingPing) return;
    setState(() => isRefreshingPing = true);

    try {
      if (isConnected) {
        final int livePing = await _verifyRealInternetThroughTunnel();
        if (mounted && livePing > 0) {
          setState(() => currentPing = livePing);
        }
      } else if (!isConnecting) {
        await _refreshReadyPoolPings();
      }
    } catch (_) {}

    if (mounted) {
      setState(() => isRefreshingPing = false);
    }
  }

  // ===========================================================================
  // ۴. تشخیص هوشمند قطعی (مشکل اینترنت یا کانفیگ) + سوییچ ۳۰ ثانیه‌ای
  // ===========================================================================

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

    final int tunnelPing = await _verifyRealInternetThroughTunnel();

    // اگر کانفیگ سالم است و اینترنت واقعی دارد:
    if (tunnelPing > 0 && tunnelPing < 3500) {
      _failoverCountdownTimer?.cancel();
      _failoverCountdownTimer = null;
      _configFailSeconds = 0;
      _internetIsDown = false;
      if (mounted) {
        setState(() {
          currentPing = tunnelPing;
          statusMessage = 'Connected • ${_activeServer!.protocol} Active';
        });
      }
      return;
    }

    // اگر اینترنت از تونل رد نشد، چک می‌کنیم مشکل از اینترنت خط کاربر است یا از کانفیگ:
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

    // اینترنت کاربر وصل است ولی کانفیگ قطع شده -> شروع شمارش ۳۰ ثانیه برای اتصال به سرور جدید
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
    if (_isAutoSwitching) return;
    _isAutoSwitching = true;

    if (mounted) {
      setState(() {
        statusMessage = 'Switching to next working server...';
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

    await _findAndConnectWorkingTunnel();
    _isAutoSwitching = false;
  }

  // ===========================================================================
  // ۵. تست تک‌به‌تک سرورهای کاندید تا پیدا شدن سروری که واقعاً اینترنت را باز کند!
  // ===========================================================================

  /// سرور را روشن می‌کند و چک می‌کند آیا واقعاً اینترنت (HTTP 204) از تونل رد می‌شود یا نه.
  /// اگر اینترنت نداشت، بلافاصله قطع می‌کند و false برمی‌گرداند تا برود سراغ سرور بعدی!
  Future<bool> _testAndLockServerTunnel(ReadyServer srv, int tryNumber) async {
    try {
      await _stopScannerAndWait();

      if (mounted) {
        setState(() {
          currentPing = srv.ping;
          statusMessage =
              'Testing ${srv.protocol} candidate #$tryNumber (${srv.ping} ms)...';
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

      // صبر برای بالا آمدن سرویس VPN اندروید
      int waitedMs = 0;
      while (!_nativeVpnRunning && waitedMs < 3000) {
        if (_userCancelledConnect) {
          await v2ray.stopV2Ray();
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 200));
        waitedMs += 200;
      }

      if (!_nativeVpnRunning) {
        await v2ray.stopV2Ray();
        return false;
      }

      // مکث کوتاه برای برقراری مسیر TUN در اندروید و سپس تست واقعی اینترنت!
      await Future.delayed(const Duration(milliseconds: 700));
      if (_userCancelledConnect) {
        await v2ray.stopV2Ray();
        return false;
      }

      final int realTunnelPing = await _verifyRealInternetThroughTunnel();

      // قانون طلایی: اگر سرور اینترنت واقعی نداشت (realTunnelPing <= 0)، روی آن نمان! قطعش کن تا برود سراغ بعدی!
      if (realTunnelPing <= 0 || !_nativeVpnRunning) {
        await v2ray.stopV2Ray();
        await Future.delayed(const Duration(milliseconds: 250));
        return false;
      }

      // سرور واقعاً اینترنت را باز کرده است! قفل کردن اتصال:
      _activeServer = srv;
      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
          currentPing = realTunnelPing;
          statusMessage = 'Connected • ${srv.protocol} Tunnel Verified';
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

  /// پیمایش سرورهای کاندید در ۳۰۰ تای اول؛ اگر هیچ‌کدام اینترنت نداشتند، اسکن ۳۰۰ تای بعدی (301-600 و...)
  Future<bool> _findAndConnectWorkingTunnel() async {
    int tryCounter = 0;

    // تا ۱۰ دسته ۳۰۰ تایی (۳۰۰۰ کانفیگ در کل پروتکل‌ها) را ادامه می‌دهد تا سروری که واقعاً اینترنت دارد پیدا شود
    for (int chunkAttempt = 0; chunkAttempt < 10; chunkAttempt++) {
      if (_userCancelledConnect) return false;

      if (_readyPool.isEmpty && !_isScanning) {
        await _scanNextAvailableChunk();
      }

      while (_isScanning && _readyPool.isEmpty && !_userCancelledConnect) {
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (_userCancelledConnect) return false;

      await _stopScannerAndWait();
      _readyPool.sort((a, b) => a.ping.compareTo(b.ping));

      while (_readyPool.isNotEmpty && !_userCancelledConnect) {
        tryCounter++;
        final ReadyServer candidate = _readyPool.first;

        final bool hasRealInternet =
            await _testAndLockServerTunnel(candidate, tryCounter);
        if (hasRealInternet) {
          return true; // اتصال واقعی برقرار شد!
        } else {
          // این کانفیگ پورتش باز بود ولی اینترنت نداشت؛ حذفش کن و بلافاصله برو سراغ کاندیدای بعدی!
          _deadUris.add(candidate.rawUri);
          _readyPool.removeAt(0);
        }
      }

      // اگر تمام سرورهای باز در این ۳۰۰ تا تست شدند و اینترنت نداشتند، برو سراغ ۳۰۰ تای بعدی!
      if (!_userCancelledConnect) {
        await _scanNextAvailableChunk();
      }
    }

    return false;
  }

  Future<void> _onConnectButtonPressed() async {
    _failoverCountdownTimer?.cancel();
    _failoverCountdownTimer = null;

    if (isConnected || isConnecting) {
      _userCancelledConnect = true;
      _abortScanRequested = true;
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
        _nativeVpnRunning = false;
        _isAutoSwitching = false;
        statusMessage = _readyPool.isNotEmpty
            ? 'Ready • ${_readyPool.length} servers prepared'
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
      statusMessage = 'Finding working tunnel...';
    });

    final bool connectedOk = await _findAndConnectWorkingTunnel();

    if (!connectedOk && mounted && !_userCancelledConnect) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'No working tunnel found in current batch • Tap to retry';
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

              // ۴. نوار وضعیت پایین صفحه
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
                    if ((_isScanning || isConnecting) && !isConnected)
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
