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
  int ping;

  ReadyServer({
    required this.rawUri,
    required this.configJson,
    required this.ping,
  });
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
  bool _isScanningBackground = false;
  bool _isAutoSwitching = false;

  int currentPing = -1;
  String statusMessage = 'Preparing best servers...';

  // متغیرهای تشخیص قطعی کانفیگ یا اینترنت و تایمر ۳۰ ثانیه
  Timer? _backgroundPoolTimer;
  Timer? _healthWatchdogTimer;
  Timer? _failoverCountdownTimer;
  int _configFailSeconds = 0;
  bool _internetIsDown = false;

  // لیست سرورهای تست‌شده و آماده در پس‌زمینه (مرتب‌شده بر اساس کمترین پینگ)
  final List<ReadyServer> _readyPool = [];
  final Set<String> _deadUris = {};
  ReadyServer? _activeServer;

  // ۴ منبع اصلی که مشخص کردی (به همراه لینک کمکی CDN همان ۴ فایل در صورت اختلال گیت‌هاب)
  final List<String> _sources = [
    'https://github.com/Epodonios/v2ray-configs/raw/main/Splitted-By-Protocol/vless.txt',
    'https://github.com/Epodonios/v2ray-configs/raw/main/Splitted-By-Protocol/vmess.txt',
    'https://github.com/Epodonios/v2ray-configs/raw/main/Splitted-By-Protocol/ss.txt',
    'https://github.com/Epodonios/v2ray-configs/raw/main/Splitted-By-Protocol/ssr.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Splitted-By-Protocol/vless.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Splitted-By-Protocol/vmess.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Splitted-By-Protocol/ss.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Splitted-By-Protocol/ssr.txt',
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

    // شروع فوری آماده‌سازی و پینگ گرفتن سرورها در پس‌زمینه
    _maintainBackgroundServerPool();

    // هر ۴۵ ثانیه در پس‌زمینه سرورهای جدید را تست و جایگزین می‌کند تا همیشه آماده باشند
    _backgroundPoolTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _maintainBackgroundServerPool();
    });

    // مانیتورینگ دائمی سلامت اتصال (هر ۱۰ ثانیه) برای تشخیص قطعی نت یا کانفیگ
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
  // ۱. آماده‌سازی و پینگ گرفتن دائمی سرورها در پس‌زمینه
  // ===========================================================================

  List<String> _extractLinks(String rawBody) {
    String text = rawBody.trim();
    if (text.isEmpty) return [];

    // اگر فایل Base64 بود، دیکد شود
    if (!text.contains('://')) {
      try {
        String clean = text.replaceAll(RegExp(r'\s+'), '');
        int mod = clean.length % 4;
        if (mod > 0) clean += '=' * (4 - mod);
        text = utf8.decode(base64.decode(clean), allowMalformed: true);
      } catch (_) {}
    }

    final List<String> results = [];
    for (String line in text.split(RegExp(r'[\r\n]+'))) {
      line = line.trim();
      if (line.isEmpty || _deadUris.contains(line)) continue;
      if (line.startsWith('vless://') ||
          line.startsWith('vmess://') ||
          line.startsWith('ss://') ||
          line.startsWith('ssr://') ||
          line.startsWith('trojan://')) {
        results.add(line);
      }
    }
    return results;
  }

  String _optimizeConfigForStability(String baseJson) {
    try {
      final Map<String, dynamic> cfg = jsonDecode(baseJson);
      cfg['dns'] = {
        "servers": ["1.1.1.1", "8.8.8.8"],
        "queryStrategy": "UseIPv4"
      };
      if (cfg['outbounds'] is List && (cfg['outbounds'] as List).isNotEmpty) {
        final Map<String, dynamic> ob = Map<String, dynamic>.from(cfg['outbounds'][0]);
        ob['streamSettings'] ??= <String, dynamic>{};
        final Map<String, dynamic> stream = Map<String, dynamic>.from(ob['streamSettings']);
        if (stream['security'] == 'tls') {
          stream['tlsSettings'] ??= <String, dynamic>{};
          stream['tlsSettings']['allowInsecure'] = true;
        }
        stream['sockopt'] = {
          "tcpNoDelay": true,
          "tcpKeepAliveIdle": 30,
        };
        ob['streamSettings'] = stream;
        cfg['outbounds'][0] = ob;
      }
      return jsonEncode(cfg);
    } catch (_) {
      return baseJson;
    }
  }

  /// دریافت و تست مداوم سرورها در پس‌زمینه بدون مزاحمت برای کاربر
  Future<void> _maintainBackgroundServerPool() async {
    if (_isScanningBackground) return;
    _isScanningBackground = true;

    try {
      // ۱. اول پینگ سرورهای موجود در صف آماده را به‌روز می‌کنیم
      if (_readyPool.isNotEmpty && !isConnected) {
        final List<ReadyServer> currentPool = List<ReadyServer>.from(_readyPool);
        final List<ReadyServer> verified = [];

        await Future.wait(currentPool.take(8).map((srv) async {
          try {
            final int delay = await v2ray
                .getServerDelay(config: srv.configJson)
                .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);
            if (delay > 0 && delay < 3000) {
              srv.ping = delay;
              verified.add(srv);
            }
          } catch (_) {}
        }));

        verified.sort((a, b) => a.ping.compareTo(b.ping));
        _readyPool
          ..clear()
          ..addAll(verified);

        if (_readyPool.isNotEmpty && !isConnected && mounted) {
          setState(() {
            currentPing = _readyPool.first.ping;
            statusMessage = 'Best Server Ready (${_readyPool.length} active)';
          });
        }
      }

      // ۲. دریافت کانفیگ‌های تازه از ۴ منبع Epodonios
      final List<String> fetchedLinks = [];
      final List<String> shuffledUrls = List<String>.from(_sources)..shuffle(Random());

      await Future.wait(shuffledUrls.take(4).map((url) async {
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
          if (res.statusCode == 200 && res.body.isNotEmpty) {
            final links = _extractLinks(res.body);
            links.shuffle(Random());
            fetchedLinks.addAll(links.take(15));
          }
        } catch (_) {}
      }));

      if (fetchedLinks.isEmpty) {
        _isScanningBackground = false;
        return;
      }

      fetchedLinks.shuffle(Random());
      final List<ReadyServer> candidates = [];

      for (final link in fetchedLinks) {
        if (candidates.length >= 24) break;
        if (_readyPool.any((s) => s.rawUri == link)) continue;
        try {
          final V2RayURL parser = V2ray.parseFromURL(link);
          if (parser.address.isEmpty || parser.port <= 0) continue;
          final String fullCfg = _optimizeConfigForStability(parser.getFullConfiguration());
          candidates.add(ReadyServer(
            rawUri: link,
            configJson: fullCfg,
            ping: -1,
          ));
        } catch (_) {
          // اگر کانفیگی مثل برخی لینک‌های قدیمی SSR با هسته Xray سازگار نبود، نادیده گرفته می‌شود
        }
      }

      // تست دسته‌ای ۶ تایی در پس‌زمینه
      const int batchSize = 6;
      for (int i = 0; i < candidates.length; i += batchSize) {
        if (_readyPool.length >= 12) break;
        final batch = candidates.skip(i).take(batchSize).toList();

        await Future.wait(batch.map((cand) async {
          try {
            final int delay = await v2ray
                .getServerDelay(config: cand.configJson)
                .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);

            if (delay > 0 && delay < 3000) {
              cand.ping = delay;
              if (!_readyPool.any((s) => s.rawUri == cand.rawUri)) {
                _readyPool.add(cand);
                _readyPool.sort((a, b) => a.ping.compareTo(b.ping));

                if (!isConnected && mounted) {
                  setState(() {
                    currentPing = _readyPool.first.ping;
                    statusMessage = 'Best Server Ready (${_readyPool.length} active)';
                  });
                }
              }
            }
          } catch (_) {}
        }));
      }
    } catch (_) {}

    _isScanningBackground = false;
    if (mounted && !isConnected && _readyPool.isEmpty) {
      setState(() {
        statusMessage = 'Tap Connect to scan & start';
      });
    }
  }

  // ===========================================================================
  // ۲. رفرش دستی پینگ با کلیک روی باکس پینگ بالای صفحه
  // ===========================================================================

  Future<void> _refreshPingOnTap() async {
    if (isRefreshingPing) return;
    setState(() => isRefreshingPing = true);

    try {
      if (isConnected && _activeServer != null) {
        // وقتی به VPN وصل هستیم، پینگ واقعی سرور متصل را می‌گیرد
        int delay = await v2ray
            .getConnectedServerDelay()
            .timeout(const Duration(seconds: 3), onTimeout: () => -1);

        if (delay <= 0) {
          delay = await v2ray
              .getServerDelay(config: _activeServer!.configJson)
              .timeout(const Duration(seconds: 3), onTimeout: () => -1);
        }

        if (mounted) {
          setState(() {
            currentPing = delay > 0 ? delay : -1;
          });
        }
      } else {
        // وقتی قطع هستیم، بهترین سرور آماده را دوباره پینگ می‌گیرد
        await _maintainBackgroundServerPool();
        if (_readyPool.isNotEmpty && mounted) {
          final int delay = await v2ray
              .getServerDelay(config: _readyPool.first.configJson)
              .timeout(const Duration(seconds: 3), onTimeout: () => _readyPool.first.ping);
          setState(() {
            if (delay > 0) {
              _readyPool.first.ping = delay;
              currentPing = delay;
            }
          });
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => isRefreshingPing = false);
    }
  }

  // ===========================================================================
  // ۳. تشخیص هوشمند قطعی (مشکل اینترنت یا مشکل کانفیگ) + سوییچ خودکار ۳۰ ثانیه‌ای
  // ===========================================================================

  /// بررسی اینکه آیا اینترنت پایه گوشی کاربر وصل است یا خیر
  Future<bool> _checkUserBaseInternet() async {
    for (final host in ['1.1.1.1', '8.8.8.8', '4.2.2.4']) {
      Socket? s;
      try {
        s = await Socket.connect(host, 53, timeout: const Duration(milliseconds: 1500));
        await s.close();
        return true;
      } catch (_) {
        s?.destroy();
      }
    }
    return false;
  }

  /// بررسی سلامت کانفیگ متصل‌شده
  Future<void> _checkConnectionAndHandleFailover() async {
    if (!isConnected || _activeServer == null || _isAutoSwitching) return;

    int delay = -1;
    try {
      delay = await v2ray
          .getConnectedServerDelay()
          .timeout(const Duration(milliseconds: 3000), onTimeout: () => -1);
    } catch (_) {
      delay = -1;
    }

    // اگر کانفیگ سالم است و پینگ می‌دهد:
    if (delay > 0 && delay < 4000) {
      _failoverCountdownTimer?.cancel();
      _failoverCountdownTimer = null;
      _configFailSeconds = 0;
      _internetIsDown = false;
      if (mounted) {
        setState(() {
          currentPing = delay;
          statusMessage = 'Connected • Optimal Route';
        });
      }
      return;
    }

    // اگر پینگ نداد، بررسی می‌کنیم مشکل از اینترنت کاربر است یا از کانفیگ:
    final bool hasInternet = await _checkUserBaseInternet();

    if (!hasInternet) {
      // مشکل از اینترنت خود کاربر است؛ تایمر تعویض سرور را نگه می‌داریم
      _failoverCountdownTimer?.cancel();
      _failoverCountdownTimer = null;
      _configFailSeconds = 0;
      if (mounted) {
        setState(() {
          _internetIsDown = true;
          currentPing = -1;
          statusMessage = 'Internet Disconnected • Waiting for network...';
        });
      }
      return;
    }

    // اینترنت کاربر وصل است، پس مشکل از کانفیگ است! شروع شمارش ۳۰ ثانیه برای سوییچ خودکار
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
          await _switchToNextBestServerAutomatically();
        }
      });
    }
  }

  /// تعویض خودکار کانفیگ خراب با یک سرور جدید بعد از ۳۰ ثانیه
  Future<void> _switchToNextBestServerAutomatically() async {
    if (_isAutoSwitching || !isConnected) return;
    _isAutoSwitching = true;

    if (mounted) {
      setState(() {
        statusMessage = 'Switching to a new healthy server...';
      });
    }

    // حذف کانفیگ خراب‌شده از صف
    if (_activeServer != null) {
      _deadUris.add(_activeServer!.rawUri);
      _readyPool.removeWhere((s) => s.rawUri == _activeServer!.rawUri);
    }

    try {
      await v2ray.stopV2Ray();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 400));

    if (_readyPool.isEmpty) {
      await _maintainBackgroundServerPool();
    }

    bool switchedSuccess = false;
    while (_readyPool.isNotEmpty) {
      final ReadyServer nextBest = _readyPool.first;
      final bool ok = await _tryStartServer(nextBest);
      if (ok) {
        switchedSuccess = true;
        break;
      } else {
        _deadUris.add(nextBest.rawUri);
        _readyPool.removeAt(0);
      }
    }

    _isAutoSwitching = false;
    if (!switchedSuccess && mounted) {
      setState(() {
        isConnected = false;
        isConnecting = false;
        statusMessage = 'All cached servers dropped • Tap to reconnect';
      });
      _maintainBackgroundServerPool();
    }
  }

  // ===========================================================================
  // ۴. دکمه اتصال اصلی (انتخاب بهترین سرور آماده و اتصال)
  // ===========================================================================

  Future<bool> _tryStartServer(ReadyServer srv) async {
    try {
      await v2ray.startV2Ray(
        remark: "Nivexia VPN (${srv.ping}ms)",
        config: srv.configJson,
        proxyOnly: false,
      );

      await Future.delayed(const Duration(milliseconds: 900));

      int verifyDelay = await v2ray
          .getConnectedServerDelay()
          .timeout(const Duration(milliseconds: 3000), onTimeout: () => -1);

      if (verifyDelay <= 0) {
        verifyDelay = await v2ray
            .getServerDelay(config: srv.configJson)
            .timeout(const Duration(milliseconds: 2500), onTimeout: () => -1);
      }

      if (verifyDelay > 0) {
        _activeServer = srv;
        if (mounted) {
          setState(() {
            isConnected = true;
            isConnecting = false;
            currentPing = verifyDelay;
            statusMessage = 'Connected • Optimal Route';
          });
        }
        return true;
      } else {
        await v2ray.stopV2Ray();
        return false;
      }
    } catch (_) {
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _onConnectButtonPressed() async {
    _failoverCountdownTimer?.cancel();
    _failoverCountdownTimer = null;

    if (isConnected || isConnecting) {
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
        _isAutoSwitching = false;
        statusMessage = _readyPool.isNotEmpty
            ? 'Best Server Ready (${_readyPool.length} active)'
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
      statusMessage = 'Selecting lowest ping server...';
    });

    // اگر هنوز سروری در پس‌زمینه آماده نشده بود، همین لحظه اسکن سریع انجام می‌دهد
    if (_readyPool.isEmpty) {
      await _maintainBackgroundServerPool();
    }

    _readyPool.sort((a, b) => a.ping.compareTo(b.ping));

    bool connectedOk = false;
    while (_readyPool.isNotEmpty && isConnecting) {
      final ReadyServer bestCandidate = _readyPool.first;
      setState(() {
        currentPing = bestCandidate.ping;
        statusMessage = 'Connecting (${bestCandidate.ping} ms)...';
      });

      final bool started = await _tryStartServer(bestCandidate);
      if (started) {
        connectedOk = true;
        break;
      } else {
        _deadUris.add(bestCandidate.rawUri);
        _readyPool.removeAt(0);
      }
    }

    if (!connectedOk && mounted) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'Could not connect • Finding new servers...';
      });
      _maintainBackgroundServerPool();
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
  // ۵. رابط کاربری ساده، شیک و بدون پیچیدگی
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
              // ۱. هدر بالا: لوگوی Nivexia + دکمه پینگ قابل کلیک (Tap to Refresh)
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

                  // باکس پینگ کلیکی: با هر کلیک پینگ را رفرش می‌کند
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
                            isConnected ? v2rayStatus.duration : 'Auto Best Server',
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

              // ۴. نوار وضعیت هوشمند در پایین صفحه (نمایش وضعیت سرورهای آماده یا شمارش معکوس ۳۰ ثانیه)
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
