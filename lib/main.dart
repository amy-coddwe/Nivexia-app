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
        ping: map['ping'] ?? 150,
      );
}

class StarParticle {
  double x;
  double y;
  double speed;
  double size;
  double opacity;

  StarParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
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
  late AnimationController _rocketController;
  final List<StarParticle> _stars = [];
  V2RayStatus v2rayStatus = V2RayStatus();

  bool _nativeVpnRunning = false;
  bool isConnected = false;
  bool isConnecting = false;
  bool isRefreshingPing = false;
  bool _isAutoSwitching = false;
  bool _userCancelled = false;

  int currentPing = -1;
  String statusMessage = 'Tap Connect to launch';
  String rocketScanDetail = 'Preparing launch sequence...';

  Timer? _healthWatchdogTimer;
  Timer? _failoverCountdownTimer;
  int _configFailSeconds = 0;
  bool _internetIsDown = false;

  // لیست کانفیگ‌های سالم ذخیره‌شده از دفعات قبلی (اولویت ۱)
  final List<ReadyServer> _savedWorkingConfigs = [];
  // لیست ساب‌لینک‌ها یا کانفیگ‌های اضافه‌شده توسط ادمین/کاربر
  final List<String> _customUserInputs = [];
  ReadyServer? _activeServer;

  // ۱. فایل کنترل از راه دور ادمین در گیت‌هاب خودت (بدون نیاز به آپدیت برنامه)
  final List<String> _remoteAdminControlUrls = const [
    'https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/admin_subs.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/admin_subs.txt',
    'https://cdn.jsdelivr.net/gh/amy-coddwe/Nivexia-app@main/admin_subs.txt',
  ];

  // ۲. ساب‌لینک اولویت‌دار هیدیفای / مهسا (۳۰-۴۰ کانفیگ سریع و تست‌شده)
  final List<String> _priorityMahsaSubUrls = const [
    'https://raw.githubusercontent.com/hiddify/hiddify-app/refs/heads/main/test.configs/mahsa',
    'https://ghfast.top/https://raw.githubusercontent.com/hiddify/hiddify-app/refs/heads/main/test.configs/mahsa',
    'https://cdn.jsdelivr.net/gh/hiddify/hiddify-app@main/test.configs/mahsa',
  ];

  // ۳. ساب‌لینک‌های پشتیبان Epodonios
  final List<String> _fallbackEpodoniosUrls = const [
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    final Random rnd = Random();
    for (int i = 0; i < 45; i++) {
      _stars.add(StarParticle(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        speed: 0.008 + rnd.nextDouble() * 0.022,
        size: 1.2 + rnd.nextDouble() * 2.5,
        opacity: 0.25 + rnd.nextDouble() * 0.75,
      ));
    }

    _rocketController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(() {
        if (isConnecting && mounted) {
          for (final star in _stars) {
            star.y += star.speed;
            if (star.y > 1.0) {
              star.y = 0.0;
              star.x = Random().nextDouble();
            }
          }
          setState(() {});
        }
      });

    _initEngine();
  }

  Future<void> _initEngine() async {
    await v2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );

    await _loadPersistentData();

    _healthWatchdogTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (isConnected && !isConnecting && !_isAutoSwitching) {
        _checkConnectionAndHandleFailover();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rocketController.dispose();
    _healthWatchdogTimer?.cancel();
    _failoverCountdownTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // ۱. حافظه دائمی گوشی برای ذخیره کانفیگ‌های سالم و ساب‌های ادمین
  // ===========================================================================

  Future<File> _getPermanentFile(String fileName) async {
    final List<String> paths = [
      '/data/user/0/com.nivexia.nivexia_ping/files',
      '/data/data/com.nivexia.nivexia_ping/files',
      Directory.systemTemp.path,
    ];
    for (final p in paths) {
      try {
        final dir = Directory(p);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return File('${dir.path}/$fileName');
      } catch (_) {}
    }
    return File('${Directory.systemTemp.path}/$fileName');
  }

  Future<void> _loadPersistentData() async {
    try {
      final File workingFile = await _getPermanentFile('nivexia_working_v6.json');
      if (await workingFile.exists()) {
        final String content = await workingFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _savedWorkingConfigs.clear();
        for (final item in list) {
          final srv = ReadyServer.fromMap(Map<String, dynamic>.from(item));
          if (srv.rawUri.isNotEmpty &&
              srv.ping >= 40 &&
              !_savedWorkingConfigs.any((s) => s.rawUri == srv.rawUri)) {
            _savedWorkingConfigs.add(srv);
          }
        }
      }

      final File customFile = await _getPermanentFile('nivexia_custom_subs_v6.json');
      if (await customFile.exists()) {
        final String content = await customFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _customUserInputs.clear();
        for (final item in list) {
          final String s = item.toString().trim();
          if (s.isNotEmpty && !_customUserInputs.contains(s)) {
            _customUserInputs.add(s);
          }
        }
      }

      if (_savedWorkingConfigs.isNotEmpty && mounted) {
        setState(() {
          currentPing = _savedWorkingConfigs.first.ping;
          statusMessage =
              'Ready • ${_savedWorkingConfigs.length} saved config(s) ready';
        });
      }
    } catch (_) {}
  }

  Future<void> _saveWorkingConfigsToDisk() async {
    try {
      final File workingFile = await _getPermanentFile('nivexia_working_v6.json');
      final List<Map<String, dynamic>> data =
          _savedWorkingConfigs.take(15).map((s) => s.toMap()).toList();
      await workingFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _saveCustomInputsToDisk() async {
    try {
      final File customFile = await _getPermanentFile('nivexia_custom_subs_v6.json');
      await customFile.writeAsString(jsonEncode(_customUserInputs));
    } catch (_) {}
  }

  // ===========================================================================
  // ۲. استخراج و آماده‌سازی کانفیگ‌ها
  // ===========================================================================

  bool _isInvalidOrLocalIp(String address) {
    final String a = address.trim().toLowerCase();
    if (a.isEmpty || a == 'localhost') return true;
    if (a.startsWith('127.') ||
        a.startsWith('10.') ||
        a.startsWith('192.168.') ||
        a.startsWith('0.')) {
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

  List<String> _extractConfigsFromText(String rawContent) {
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
        if (seen.add(line)) {
          validLinks.add(line);
        }
      }
    }
    return validLinks;
  }

  ReadyServer? _parseUriToServer(String uri) {
    try {
      final V2RayURL parser = V2ray.parseFromURL(uri);
      final String host = parser.address.trim();
      final int port = parser.port;
      if (_isInvalidOrLocalIp(host) || port <= 0 || port > 65535) {
        return null;
      }

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

      if (parser.streamSetting['realitySettings'] is Map) {
        final Map rl = parser.streamSetting['realitySettings'];
        if (rl['spiderX'] is String) {
          try {
            rl['spiderX'] = Uri.decodeComponent(rl['spiderX']);
          } catch (_) {}
        }
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

  Future<String> _downloadUrlFast(String url, {int maxBytes = 300000}) async {
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
          if (bytes.length >= maxBytes) {
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

  // ===========================================================================
  // ۳. اسکن و تست واقعی کانفیگ‌ها و توقف کامل به محض اتصال
  // ===========================================================================

  Future<int> _checkSocketPing(String host, int port) async {
    Socket? s;
    try {
      final Stopwatch sw = Stopwatch()..start();
      s = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 800),
      );
      sw.stop();
      await s.close();
      return sw.elapsedMilliseconds;
    } catch (_) {
      s?.destroy();
      return -1;
    }
  }

  Future<int> _verifyConfigWithXrayCore(ReadyServer candidate) async {
    final int tcpMs = await _checkSocketPing(candidate.address, candidate.port);
    if (tcpMs < 25 || tcpMs > 1000) return -1;

    try {
      final int coreDelay = await v2ray
          .getServerDelay(
            config: candidate.configJson,
            url: 'http://cp.cloudflare.com/generate_204',
          )
          .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);

      if (coreDelay >= 40 && coreDelay < 3000) {
        return coreDelay;
      }
    } catch (_) {}

    try {
      final int googleDelay = await v2ray
          .getServerDelay(
            config: candidate.configJson,
            url: 'http://www.gstatic.com/generate_204',
          )
          .timeout(const Duration(milliseconds: 2500), onTimeout: () => -1);

      if (googleDelay >= 40 && googleDelay < 3000) {
        return googleDelay;
      }
    } catch (_) {}

    return -1;
  }

  /// تست واقعی دانلود از طریق پورت لوکال هسته Xray بعد از روشن شدن تانل
  Future<int> _verifyRealDownloadThroughLocalProxy(int localHttpPort) async {
    final List<String> testUrls = [
      'http://cp.cloudflare.com/generate_204',
      'http://www.gstatic.com/generate_204',
    ];

    for (final String url in testUrls) {
      HttpClient? proxyClient;
      try {
        proxyClient = HttpClient();
        proxyClient.connectionTimeout = const Duration(milliseconds: 2800);
        proxyClient.findProxy = (uri) => "PROXY 127.0.0.1:$localHttpPort";

        final Stopwatch sw = Stopwatch()..start();
        final HttpClientRequest req = await proxyClient
            .getUrl(Uri.parse(url))
            .timeout(const Duration(milliseconds: 2800));
        req.headers.set('User-Agent', 'Mozilla/5.0');

        final HttpClientResponse res =
            await req.close().timeout(const Duration(milliseconds: 2800));
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

  /// تست و اتصال واقعی؛ اگر سرور وصل شد و دانلود واقعی داشت، true برمی‌گرداند و اسکن متوقف می‌شود
  Future<bool> _tryStartAndVerifyServer(ReadyServer srv) async {
    try {
      if (mounted) {
        setState(() {
          rocketScanDetail =
              'Testing download on ${srv.protocol} (${srv.ping} ms)...';
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
      while (!_nativeVpnRunning && waitedMs < 3200) {
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

      await Future.delayed(const Duration(milliseconds: 450));
      if (_userCancelled) {
        await v2ray.stopV2Ray();
        return false;
      }

      final int realDownloadPing =
          await _verifyRealDownloadThroughLocalProxy(srv.localHttpPort);

      if (realDownloadPing < 40 || !_nativeVpnRunning) {
        await v2ray.stopV2Ray();
        await Future.delayed(const Duration(milliseconds: 250));
        return false;
      }

      srv.ping = realDownloadPing;
      _savedWorkingConfigs.removeWhere((s) => s.rawUri == srv.rawUri);
      _savedWorkingConfigs.insert(0, srv);
      await _saveWorkingConfigsToDisk();

      _activeServer = srv;
      _rocketController.stop();

      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
          currentPing = realDownloadPing;
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

  /// اسکن یک لیست از کانفیگ‌ها و اتصال فوری به اولین کانفیگ سالم (و توقف کامل ادامه اسکن)
  Future<bool> _scanAndConnectFirstWorking(
    List<String> rawUris,
    String sourceLabel,
  ) async {
    final List<ReadyServer> parsedNodes = [];
    for (final uri in rawUris) {
      final ReadyServer? node = _parseUriToServer(uri);
      if (node != null) {
        parsedNodes.add(node);
      }
    }

    if (parsedNodes.isEmpty) return false;

    const int batchSize = 30;
    for (int offset = 0; offset < parsedNodes.length; offset += batchSize) {
      if (_userCancelled) return false;

      final int end = min(offset + batchSize, parsedNodes.length);
      final List<ReadyServer> batch = parsedNodes.sublist(offset, end);

      if (mounted) {
        setState(() {
          rocketScanDetail =
              'Scanning $sourceLabel (${offset + 1}-$end of ${parsedNodes.length})...';
        });
      }

      final List<ReadyServer> openPortNodes = [];
      await Future.wait(batch.map((node) async {
        final int tcp = await _checkSocketPing(node.address, node.port);
        if (tcp >= 25 && tcp < 900) {
          node.ping = tcp;
          openPortNodes.add(node);
        }
      }));

      if (openPortNodes.isEmpty) continue;

      openPortNodes.sort((a, b) {
        final int aIsReality = a.protocol == 'REALITY' ? 1 : 0;
        final int bIsReality = b.protocol == 'REALITY' ? 1 : 0;
        if (aIsReality != bIsReality) return aIsReality.compareTo(bIsReality);
        return a.ping.compareTo(b.ping);
      });

      for (int i = 0; i < openPortNodes.length; i++) {
        if (_userCancelled) return false;
        final ReadyServer candidate = openPortNodes[i];

        if (mounted) {
          setState(() {
            rocketScanDetail =
                'Verifying $sourceLabel (${i + 1}/${openPortNodes.length})...';
          });
        }

        final int verifiedDelay = await _verifyConfigWithXrayCore(candidate);
        if (verifiedDelay >= 40 && verifiedDelay < 3000) {
          candidate.ping = verifiedDelay;
          final bool connected = await _tryStartAndVerifyServer(candidate);
          if (connected) {
            return true; // متصل شد! توقف کامل اسکن!
          }
        }
      }
    }

    return false;
  }

  Future<List<String>> _fetchAdminAndCustomConfigs() async {
    final List<String> allAdminConfigs = [];
    final List<String> subUrlsToFetch = [];

    for (final item in _customUserInputs) {
      if (item.startsWith('http://') || item.startsWith('https://')) {
        subUrlsToFetch.add(item);
      } else {
        allAdminConfigs.addAll(_extractConfigsFromText(item));
      }
    }

    for (final adminUrl in _remoteAdminControlUrls) {
      if (_userCancelled) break;
      final String body = await _downloadUrlFast(adminUrl, maxBytes: 150000);
      if (body.isNotEmpty && !body.contains('404: Not Found')) {
        for (String line in body.split(RegExp(r'[\r\n]+'))) {
          line = line.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          if (line.startsWith('http://') || line.startsWith('https://')) {
            if (!subUrlsToFetch.contains(line)) subUrlsToFetch.add(line);
          } else {
            allAdminConfigs.addAll(_extractConfigsFromText(line));
          }
        }
        break;
      }
    }

    for (final subUrl in subUrlsToFetch) {
      if (_userCancelled) break;
      final String subBody = await _downloadUrlFast(subUrl, maxBytes: 250000);
      if (subBody.isNotEmpty) {
        allAdminConfigs.addAll(_extractConfigsFromText(subBody));
      }
    }

    return allAdminConfigs;
  }

  Future<bool> _launchPriorityScanAndConnect() async {
    try {
      await v2ray.stopV2Ray();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 400));

    // ۱. اولویت اول: کانفیگ‌های سالم ذخیره‌شده از دفعات قبلی
    if (_savedWorkingConfigs.isNotEmpty && !_userCancelled) {
      final List<ReadyServer> savedCopy = List<ReadyServer>.from(_savedWorkingConfigs);
      for (int i = 0; i < savedCopy.length; i++) {
        if (_userCancelled) return false;
        final ReadyServer savedSrv = savedCopy[i];

        if (mounted) {
          setState(() {
            rocketScanDetail =
                'Checking saved working config (${i + 1}/${savedCopy.length})...';
          });
        }

        final int delay = await _verifyConfigWithXrayCore(savedSrv);
        if (delay >= 40 && delay < 3000) {
          savedSrv.ping = delay;
          final bool ok = await _tryStartAndVerifyServer(savedSrv);
          if (ok) return true;
        }
        _savedWorkingConfigs.removeWhere((s) => s.rawUri == savedSrv.rawUri);
        await _saveWorkingConfigsToDisk();
      }
    }

    // ۲. اولویت دوم: ساب‌لینک‌ها و کانفیگ‌های ادمین (GitHub admin_subs.txt + لیست دستی)
    if (!_userCancelled) {
      if (mounted) {
        setState(() {
          rocketScanDetail = 'Checking Admin priority subs & configs...';
        });
      }
      final List<String> adminConfigs = await _fetchAdminAndCustomConfigs();
      if (adminConfigs.isNotEmpty && !_userCancelled) {
        final bool ok = await _scanAndConnectFirstWorking(
          adminConfigs,
          'Admin Priority',
        );
        if (ok) return true;
      }
    }

    // ۳. اولویت سوم: ساب‌لینک جدید Hiddify Mahsa (حدود ۳۰-۴۰ کانفیگ سریع)
    if (!_userCancelled) {
      if (mounted) {
        setState(() {
          rocketScanDetail = 'Fetching Hiddify Mahsa priority sub...';
        });
      }
      List<String> mahsaConfigs = [];
      for (final url in _priorityMahsaSubUrls) {
        if (_userCancelled) break;
        final String body = await _downloadUrlFast(url, maxBytes: 250000);
        if (body.isNotEmpty) {
          mahsaConfigs = _extractConfigsFromText(body);
          if (mahsaConfigs.isNotEmpty) break;
        }
      }

      if (mahsaConfigs.isNotEmpty && !_userCancelled) {
        final bool ok = await _scanAndConnectFirstWorking(
          mahsaConfigs,
          'Hiddify Mahsa',
        );
        if (ok) return true;
      }
    }

    // ۴. اولویت چهارم: ساب‌لینک‌های پشتیبان Epodonios
    for (final epUrl in _fallbackEpodoniosUrls) {
      if (_userCancelled) break;
      final String protoLabel =
          epUrl.split('/').last.replaceAll('.txt', '').toUpperCase();
      if (mounted) {
        setState(() {
          rocketScanDetail = 'Loading Epodonios $protoLabel backup sub...';
        });
      }

      final String body = await _downloadUrlFast(epUrl, maxBytes: 350000);
      if (body.isEmpty) continue;

      final List<String> epConfigs = _extractConfigsFromText(body);
      if (epConfigs.isEmpty) continue;

      final bool ok = await _scanAndConnectFirstWorking(
        epConfigs.take(250).toList(),
        'Epodonios $protoLabel',
      );
      if (ok) return true;
    }

    return false;
  }

  Future<void> _onConnectButtonPressed() async {
    _failoverCountdownTimer?.cancel();
    _failoverCountdownTimer = null;

    if (isConnected || isConnecting) {
      _userCancelled = true;
      _rocketController.stop();
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
        _nativeVpnRunning = false;
        _isAutoSwitching = false;
        statusMessage = _savedWorkingConfigs.isNotEmpty
            ? 'Ready • ${_savedWorkingConfigs.length} saved config(s) ready'
            : 'Tap Connect to launch';
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
      rocketScanDetail = 'Igniting engines...';
    });
    _rocketController.repeat();

    final bool connectedOk = await _launchPriorityScanAndConnect();
    if (connectedOk) return;

    _rocketController.stop();
    if (mounted && !_userCancelled) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'No active server responded • Tap to retry';
      });
    }
  }

  // ===========================================================================
  // ۴. رفرش کلیکی پینگ + تشخیص قطعی کانفیگ یا اینترنت (۳۰ ثانیه)
  // ===========================================================================

  Future<void> _refreshPingOnTap() async {
    if (isRefreshingPing || isConnecting) return;
    setState(() => isRefreshingPing = true);

    try {
      if (isConnected && _activeServer != null) {
        final int realPing =
            await _verifyRealDownloadThroughLocalProxy(_activeServer!.localHttpPort);
        if (mounted) {
          setState(() => currentPing = realPing >= 40 ? realPing : -1);
        }
      } else if (_savedWorkingConfigs.isNotEmpty) {
        final int p = await _checkSocketPing(
          _savedWorkingConfigs.first.address,
          _savedWorkingConfigs.first.port,
        );
        if (mounted && p > 0) {
          setState(() {
            _savedWorkingConfigs.first.ping = p;
            currentPing = p;
          });
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

    final int livePing =
        await _verifyRealDownloadThroughLocalProxy(_activeServer!.localHttpPort);

    if (livePing >= 40 && livePing < 3500) {
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
          await _autoReconnectOnDrop();
        }
      });
    }
  }

  Future<void> _autoReconnectOnDrop() async {
    if (_isAutoSwitching) return;
    _isAutoSwitching = true;

    if (_activeServer != null) {
      _savedWorkingConfigs.removeWhere((s) => s.rawUri == _activeServer!.rawUri);
      await _saveWorkingConfigsToDisk();
    }

    if (mounted) {
      setState(() {
        isConnected = false;
        isConnecting = true;
        rocketScanDetail = 'Re-launching rocket for new server...';
      });
    }
    _rocketController.repeat();

    final bool ok = await _launchPriorityScanAndConnect();
    if (!ok) {
      _rocketController.stop();
      if (mounted) {
        setState(() {
          isConnecting = false;
          isConnected = false;
          statusMessage = 'Connection lost • Tap Connect to retry';
        });
      }
    }

    _isAutoSwitching = false;
  }

  // ===========================================================================
  // ۵. پنجره مدیریت ساب‌لینک‌ها و کانفیگ‌های اولویت‌دار
  // ===========================================================================

  void _openCustomSubManagerDialog() {
    final TextEditingController inputCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11151F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'PRIORITY SUBS & CONFIGS',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00F5D4),
                          letterSpacing: 1.1,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white54),
                      ),
                    ],
                  ),
                  const Text(
                    'Add any Subscription URL (https://...) or direct config (vless://...). These are scanned with #1 Priority!',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: inputCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'https://sub-link... or vless://...',
                            filled: true,
                            fillColor: const Color(0xFF090B10),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F5D4),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final String val = inputCtrl.text.trim();
                          if (val.isEmpty) return;
                          if (!_customUserInputs.contains(val)) {
                            _customUserInputs.insert(0, val);
                            await _saveCustomInputsToDisk();
                          }
                          inputCtrl.clear();
                          setModalState(() {});
                          setState(() {});
                        },
                        child: const Text(
                          'Add',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_customUserInputs.isNotEmpty)
                    SizedBox(
                      height: 140,
                      child: ListView.builder(
                        itemCount: _customUserInputs.length,
                        itemBuilder: (context, idx) {
                          final item = _customUserInputs[idx];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.star_rounded,
                              color: Color(0xFF00F5D4),
                              size: 18,
                            ),
                            title: Text(
                              item,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              onPressed: () async {
                                _customUserInputs.removeAt(idx);
                                await _saveCustomInputsToDisk();
                                setModalState(() {});
                                setState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
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
  // ۶. صفحه انیمیشنی موشک در حال پرواز (Rocket Launch Scanner Screen)
  // ===========================================================================

  Widget _buildRocketScannerScreen() {
    final double wave = sin(_rocketController.value * 2 * pi);
    final double flameScale = 0.85 + 0.30 * sin(_rocketController.value * 6 * pi).abs();

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: StarfieldPainter(_stars),
          ),
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Transform.translate(
                offset: Offset(wave * 4.0, -10.0 * wave.abs()),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 135,
                      height: 135,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF00F5D4).withOpacity(0.28),
                            const Color(0xFF7B2CBF).withOpacity(0.12),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Transform.rotate(
                          angle: -0.785,
                          child: const Icon(
                            Icons.rocket_launch_rounded,
                            size: 82,
                            color: Color(0xFF00F5D4),
                          ),
                        ),
                      ),
                    ),
                    Transform.scale(
                      scaleY: flameScale,
                      scaleX: 0.9 + (0.2 * wave.abs()),
                      child: Container(
                        width: 22,
                        height: 55,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(30),
                            top: Radius.circular(8),
                          ),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF00F5D4),
                              Colors.amberAccent,
                              Colors.deepOrangeAccent,
                              Colors.transparent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amberAccent.withOpacity(0.6),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              const Text(
                'LAUNCHING CONNECTION...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  color: Color(0xFF00F5D4),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  rocketScanDetail,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const Spacer(flex: 2),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  backgroundColor: const Color(0xFF161B28),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Colors.white12),
                  ),
                ),
                onPressed: _onConnectButtonPressed,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text(
                  'Cancel Launch',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // ۷. رابط کاربری اصلی
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (isConnecting) {
      return Scaffold(
        body: SafeArea(
          child: _buildRocketScannerScreen(),
        ),
      );
    }

    final Color primaryNeon = isConnected
        ? (_internetIsDown || _failoverCountdownTimer != null
            ? Colors.amberAccent
            : const Color(0xFF00F5D4))
        : const Color(0xFF7B2CBF);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'NIVEXIA',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3.2,
                              color: Color(0xFF00F5D4),
                            ),
                          ),
                          Text(
                            'SMART AUTO VPN',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.4,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Add Priority Sub / Config',
                        onPressed: _openCustomSubManagerDialog,
                        icon: const Icon(
                          Icons.add_link_rounded,
                          color: Color(0xFF00F5D4),
                          size: 22,
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
                            isConnected
                                ? Icons.power_settings_new_rounded
                                : Icons.rocket_launch_rounded,
                            size: 62,
                            color: primaryNeon,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isConnected ? 'CONNECTED' : 'CONNECT',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                              color: isConnected ? const Color(0xFF00F5D4) : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isConnected ? v2rayStatus.duration : 'Tap to Launch',
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Spacer(),
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

class StarfieldPainter extends CustomPainter {
  final List<StarParticle> stars;

  StarfieldPainter(this.stars);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.fill;
    for (final star in stars) {
      paint.color = Colors.white.withOpacity(star.opacity);
      final double dx = star.x * size.width;
      final double dy = star.y * size.height;
      canvas.drawCircle(Offset(dx, dy), star.size, paint);
      paint.color = const Color(0xFF00F5D4).withOpacity(star.opacity * 0.4);
      canvas.drawLine(
        Offset(dx, dy),
        Offset(dx, dy - (star.speed * 600)),
        paint..strokeWidth = star.size * 0.8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
