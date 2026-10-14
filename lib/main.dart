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
  static const int _chunkSize = 300; // اسکن پله‌ای ۳۰۰ تا ۳۰۰ تا

  late final V2ray v2ray = V2ray(
    onStatusChanged: (status) {
      if (!mounted) return;
      final String st = status.state.toUpperCase();
      setState(() {
        v2rayStatus = status;
        if (st == "CONNECTED") {
          isConnected = true;
          isConnecting = false;
        } else if (st == "DISCONNECTED") {
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

  // فقط سرورهایی که از هسته Xray پینگ واقعی گرفته‌اند وارد این لیست می‌شوند
  final List<ReadyServer> _readyPool = [];
  final Set<String> _deadUris = {};
  ReadyServer? _activeServer;

  // ترتیب بررسی پروتکل‌ها: اول VLESS، اگر پیدا نشد VMess، بعد SS و بعد SSR
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

    _runContinuousWaterfallScan();

    // شارژ مجدد لیست در پس‌زمینه (فقط زمانی که VPN قطع است تا با سرویس فعال تداخل نکند)
    _backgroundPoolTimer = Timer.periodic(const Duration(seconds: 50), (_) {
      if (!isConnected && !isConnecting && !_isScanning) {
        if (_readyPool.length < 3) {
          _runContinuousWaterfallScan();
        }
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
  // ۱. استخراج و نرمال‌سازی کانفیگ‌ها (VLESS, VMess, SS, SSR)
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

  List<String> _extractAllConfigsFromContent(String rawContent) {
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

  Future<int> _measureSocketPing(String host, int port) async {
    final Stopwatch sw = Stopwatch()..start();
    Socket? sock;
    try {
      sock = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 900),
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
  // ۲. اسکن پله‌ای ۳۰۰ تا ۳۰۰ تا با تاییدیه واقعی هسته Xray v26.9.9
  // ===========================================================================

  Future<void> _stopScannerAndWait() async {
    _abortScanRequested = true;
    int waitLoops = 0;
    while (_isScanning && waitLoops < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitLoops++;
    }
  }

  Future<int> _scan300Batch(
    List<String> batchLinks,
    String protocolName,
    int startIndex,
    int endIndex,
  ) async {
    if (_abortScanRequested || isConnected) return 0;

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

        // استفاده از کانفیگ استاندارد و دست‌نخورده خود کتابخانه (سازگار با Xray v26.9.9 و بدون allowInsecure)
        final String configJson = parser.getFullConfiguration();
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

    // مرحله ۱: غربال سریع آی‌پی‌های خاموش در دسته‌های ۳۵ تایی
    const int socketConcurrency = 35;
    final List<ReadyServer> openPortServers = [];

    for (int i = 0; i < parsedCandidates.length; i += socketConcurrency) {
      if (_abortScanRequested || isConnected) return 0;

      final subSlice = parsedCandidates.skip(i).take(socketConcurrency).toList();
      await Future.wait(subSlice.map((cand) async {
        final int tcpPing = await _measureSocketPing(cand.address, cand.port);
        if (tcpPing > 0 && tcpPing < 1200) {
          cand.ping = tcpPing;
          openPortServers.add(cand);
        }
      }));
    }

    if (openPortServers.isEmpty) return 0;

    openPortServers.sort((a, b) => a.ping.compareTo(b.ping));

    // مرحله ۲: تست واقعی ترافیک با هسته Xray (فقط سروری که از هسته پینگ واقعی بگیرد قبول می‌شود)
    int verifiedFound = 0;
    const int xrayBatchSize = 3;
    final List<ReadyServer> topToVerify = openPortServers.take(36).toList();

    for (int j = 0; j < topToVerify.length; j += xrayBatchSize) {
      if (_abortScanRequested || isConnected) break;

      final xraySlice = topToVerify.skip(j).take(xrayBatchSize).toList();
      if (mounted && !isConnected) {
        setState(() {
          statusMessage =
              'Verifying $protocolName ($startIndex-$endIndex) • Testing tunnel...';
        });
      }

      await Future.wait(xraySlice.map((candidate) async {
        try {
          final int realDelay = await v2ray
              .getServerDelay(config: candidate.configJson)
              .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);

          if (realDelay > 0 && realDelay < 3000) {
            candidate.ping = realDelay;
            if (!_readyPool.any((s) => s.rawUri == candidate.rawUri)) {
              _readyPool.add(candidate);
              _readyPool.sort((a, b) => a.ping.compareTo(b.ping));
              verifiedFound++;

              if (mounted && !isConnected) {
                setState(() {
                  currentPing = _readyPool.first.ping;
                  statusMessage =
                      'Ready • ${_readyPool.length} verified (${_readyPool.first.protocol})';
                });
              }
            }
          } else {
            _deadUris.add(candidate.rawUri);
          }
        } catch (_) {}
      }));

      if (isConnecting && _readyPool.isNotEmpty) {
        break;
      }
      if (_readyPool.length >= 5) {
        break;
      }
    }

    return verifiedFound;
  }

  /// اسکن آبشاری: VLESS (۳۰۰ تا ۳۰۰ تا) -> VMess -> SS -> SSR
  Future<void> _runContinuousWaterfallScan() async {
    if (_isScanning || isConnected) return;
    _isScanning = true;
    _abortScanRequested = false;

    try {
      for (final ProtocolTier tier in _protocolWaterfall) {
        if (_abortScanRequested || isConnected) break;
        if (isConnecting && _readyPool.isNotEmpty) break;
        if (!isConnecting && _readyPool.length >= 5) break;

        if (mounted && !isConnected) {
          setState(() {
            statusMessage = 'Downloading ${tier.name} list...';
          });
        }

        List<String> allProtocolConfigs = [];
        for (final String url in tier.urls) {
          if (_abortScanRequested || isConnected) break;
          final String rawBody = await _downloadSourceContent(url);
          if (rawBody.isNotEmpty) {
            final List<String> extracted = _extractAllConfigsFromContent(rawBody);
            if (extracted.length >= 15) {
              extracted.shuffle(Random());
              allProtocolConfigs = extracted;
              break;
            }
          }
        }

        if (allProtocolConfigs.isEmpty) continue;

        for (int offset = 0;
            offset < allProtocolConfigs.length;
            offset += _chunkSize) {
          if (_abortScanRequested || isConnected) break;
          if (isConnecting && _readyPool.isNotEmpty) break;
          if (!isConnecting && _readyPool.length >= 5) break;

          final int end = min(offset + _chunkSize, allProtocolConfigs.length);
          final List<String> chunk300 = allProtocolConfigs.sublist(offset, end);

          await _scan300Batch(
            chunk300,
            tier.name,
            offset + 1,
            end,
          );
        }
      }
    } catch (_) {}

    _isScanning = false;
    if (mounted && !isConnected && !isConnecting) {
      setState(() {
        if (_readyPool.isNotEmpty) {
          currentPing = _readyPool.first.ping;
          statusMessage =
              'Ready • ${_readyPool.length} verified (${_readyPool.first.protocol})';
        } else {
          statusMessage = 'Tap Connect to scan & connect';
        }
      });
    }
  }

  // ===========================================================================
  // ۳. سنجش پینگ از طریق تونل و رفرش کلیکی بالای صفحه
  // ===========================================================================

  Future<int> _measureHttpPingThroughTunnel() async {
    for (final url in [
      'http://cp.cloudflare.com/generate_204',
      'http://www.gstatic.com/generate_204',
      'http://connectivitycheck.gstatic.com/generate_204',
    ]) {
      try {
        final Stopwatch sw = Stopwatch()..start();
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(milliseconds: 3000));
        sw.stop();
        if (res.statusCode == 204 || res.statusCode == 200) {
          return sw.elapsedMilliseconds;
        }
      } catch (_) {}
    }
    return -1;
  }

  Future<void> _refreshPingOnTap() async {
    if (isRefreshingPing) return;
    setState(() => isRefreshingPing = true);

    try {
      if (isConnected && _activeServer != null) {
        int p = await _measureHttpPingThroughTunnel();
        if (p <= 0) {
          p = await _measureSocketPing(_activeServer!.address, _activeServer!.port);
        }
        if (mounted && p > 0) {
          setState(() => currentPing = p);
        }
      } else if (!isConnected && !isConnecting) {
        if (_readyPool.isEmpty) {
          await _runContinuousWaterfallScan();
        } else {
          final int d = await v2ray
              .getServerDelay(config: _readyPool.first.configJson)
              .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);
          if (mounted) {
            if (d > 0) {
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

  // ===========================================================================
  // ۴. تشخیص قطعی کانفیگ یا اینترنت + سوییچ خودکار بعد از ۳۰ ثانیه
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

    int livePing = await _measureHttpPingThroughTunnel();
    if (livePing <= 0) {
      livePing = await _measureSocketPing(_activeServer!.address, _activeServer!.port);
    }

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

    final bool hasNet = await _isUserInternetConnected();

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
        statusMessage = 'Switching to a new verified server...';
      });
    }

    if (_activeServer != null) {
      _deadUris.add(_activeServer!.rawUri);
      _readyPool.removeWhere((s) => s.rawUri == _activeServer!.rawUri);
    }

    try {
      await v2ray.stopV2Ray();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 500));

    await _connectUsingVerifiedPool();
    _isAutoSwitching = false;
  }

  // ===========================================================================
  // ۵. اتصال تمیز و بدون تداخل به سرور تاییدشده
  // ===========================================================================

  Future<bool> _startVerifiedServer(ReadyServer srv) async {
    try {
      await _stopScannerAndWait();

      await v2ray.startV2Ray(
        remark: "Nivexia VPN (${srv.protocol})",
        config: srv.configJson,
        blockedApps: null,
        bypassSubnets: null,
        proxyOnly: false,
      );

      int waitedMs = 0;
      while (!isConnected && waitedMs < 4000) {
        if (_userCancelledConnect) {
          await v2ray.stopV2Ray();
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 250));
        waitedMs += 250;
      }

      if (!isConnected) {
        await v2ray.stopV2Ray();
        return false;
      }

      _activeServer = srv;
      if (mounted) {
        setState(() {
          currentPing = srv.ping;
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

  Future<bool> _connectUsingVerifiedPool() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      if (_userCancelledConnect) return false;

      if (_readyPool.isEmpty && !_isScanning) {
        await _runContinuousWaterfallScan();
      }

      while (_isScanning && _readyPool.isEmpty && !_userCancelledConnect) {
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (_userCancelledConnect) return false;

      if (_readyPool.isNotEmpty) {
        await _stopScannerAndWait();
      }

      _readyPool.sort((a, b) => a.ping.compareTo(b.ping));

      while (_readyPool.isNotEmpty && !_userCancelledConnect) {
        final ReadyServer best = _readyPool.first;
        if (mounted) {
          setState(() {
            currentPing = best.ping;
            statusMessage = 'Connecting to ${best.protocol} (${best.ping} ms)...';
          });
        }

        final bool ok = await _startVerifiedServer(best);
        if (ok) {
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

    if (isConnected || isConnecting) {
      _userCancelledConnect = true;
      _abortScanRequested = true;
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
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
      _userCancelledConnect = false;
      statusMessage = _readyPool.isNotEmpty
          ? 'Connecting to verified server...'
          : 'Scanning 300-by-300 for verified server...';
    });

    final bool ok = await _connectUsingVerifiedPool();

    if (!ok && mounted && !_userCancelledConnect) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'No active config found on this ISP • Tap to retry';
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
