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

  // لیست کانفیگ‌های سالم ذخیره‌شده از دفعات قبلی (اولویت شماره ۱)
  final List<ReadyServer> _savedWorkingConfigs = [];
  // لیست ساب‌لینک‌ها یا کانفیگ‌های اضافه‌شده توسط ادمین/کاربر
  final List<String> _customUserInputs = [];
  ReadyServer? _activeServer;

  // ۱. لینک فایل ادمین در گیت‌هاب خودت (بدون نیاز به آپدیت برنامه، هر وقت فایل admin_subs.txt را در گیت‌هابت بسازی/ویرایش کنی، اول از همه خوانده می‌شود)
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

  // ۳. ساب‌لینک‌های پشتیبان Epodonios (فقط در صورتی که ساب‌های بالا کار نکنند سراغ این‌ها می‌رود)
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

    // انیمیشن مخصوص حرکت موشک و ستاره‌ها در صفحه اسکن
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

    // بارگذاری کانفیگ‌های سالم قبلی و ساب‌های سفارشی از حافظه دائمی گوشی
    // (توجه: هیچ اسکن خودکاری اینجا انجام نمی‌شود تا زمانی که خود کاربر روی دکمه کانکت بزند!)
    await _loadPersistentData();

    // مانیتورینگ وضعیت اتصال (فقط زمانی که VPN متصل است هر ۱۲ ثانیه چک می‌کند)
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
  // ۱. حافظه دائمی گوشی (بدون پاک شدن بعد از بستن برنامه)
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
      final File workingFile = await _getPermanentFile('nivexia_working_v5.json');
      if (await workingFile.exists()) {
        final String content = await workingFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _savedWorkingConfigs.clear();
        for (final item in list) {
          final srv = ReadyServer.fromMap(Map<String, dynamic>.from(item));
          if (srv.rawUri.isNotEmpty &&
              !_savedWorkingConfigs.any((s) => s.rawUri == srv.rawUri)) {
            _savedWorkingConfigs.add(srv);
          }
        }
      }

      final File customFile = await _getPermanentFile('nivexia_custom_subs_v5.json');
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
      final File workingFile = await _getPermanentFile('nivexia_working_v5.json');
      final List<Map<String, dynamic>> data =
          _savedWorkingConfigs.take(15).map((s) => s.toMap()).toList();
      await workingFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _saveCustomInputsToDisk() async {
    try {
      final File customFile = await _getPermanentFile('nivexia_custom_subs_v5.json');
      await customFile.writeAsString(jsonEncode(_customUserInputs));
    } catch (_) {}
  }

  // ===========================================================================
  // ۲. استخراج و آماده‌سازی کانفیگ‌ها و ساب‌لینک‌ها
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

      parser.dns = {
        "servers": ["1.1.1.1", "8.8.8.8"]
      };

      String proto = uri.split('://').first.toUpperCase();
      if (uri.contains('security=reality')) proto = 'REALITY';

      return ReadyServer(
        rawUri: uri,
        configJson: parser.getFullConfiguration(),
        protocol: proto,
        address: host,
        port: port,
        ping: -1,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _downloadUrl Fast(String url, {int maxBytes = 300000}) async {
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
  // ۳. تست دقیق یک کانفیگ و توقف فوری اسکن به محض پیدا شدن اولین کانفیگ سالم!
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

  /// تست واقعی کانفیگ با هسته Xray (در حالی که VPN خاموش است و هیچ تداخلی وجود ندارد)
  Future<int> _verifyConfigWithXrayCore(ReadyServer candidate) async {
    // ۱. اول چک می‌کنیم آی‌پی و پورت سرور همین لحظه باز باشد (رد کردن پینگ‌های فیک زیر ۲۵ میلی‌ثانیه)
    final int tcpMs = await _checkSocketPing(candidate.address, candidate.port);
    if (tcpMs < 25 || tcpMs > 1000) return -1;

    // ۲. تست واقعی تاخیر تونل با هسته Xray
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

    // ۳. تست دوم با آدرس گوگل در صورتی که کلودفلر روی آن سرور مسدود بود
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

  /// اسکن یک لیست از لینک‌های کانفیگ؛ به محض پیدا کردن اولین کانفیگ سالم، اسکن را متوقف و آن را برمی‌گرداند!
  Future<ReadyServer?> _scanConfigListUntilFirstHealthy(
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

    if (parsedNodes.isEmpty) return null;

    // غربال سریع پورت باز در دسته‌های ۳۰ تایی
    const int batchSize = 30;
    for (int offset = 0; offset < parsedNodes.length; offset += batchSize) {
      if (_userCancelled) return null;

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

      openPortNodes.sort((a, b) => a.ping.compareTo(b.ping));

      // تست تک‌به‌تک با هسته Xray؛ به محض اینکه اولین کانفیگ سالم جواب داد، درجا متوقف شو و برگرد!
      for (int i = 0; i < openPortNodes.length; i++) {
        if (_userCancelled) return null;
        final ReadyServer candidate = openPortNodes[i];

        if (mounted) {
          setState(() {
            rocketScanDetail =
                'Verifying $sourceLabel tunnel (${i + 1}/${openPortNodes.length})...';
          });
        }

        final int verifiedDelay = await _verifyConfigWithXrayCore(candidate);
        if (verifiedDelay >= 40 && verifiedDelay < 3000) {
          candidate.ping = verifiedDelay;
          return candidate; // پیدا شد! توقف کامل ادامه اسکن!
        }
      }
    }

    return null;
  }

  /// دریافت کانفیگ‌های ادمین (هم از گیت‌هاب تو بدون آپدیت برنامه و هم از لیست دستی داخل اپ)
  Future<List<String>> _fetchAdminAndCustomConfigs() async {
    final List<String> allAdminConfigs = [];
    final List<String> subUrlsToFetch = [];

    // ۱. بررسی ورودی‌های دستی داخل برنامه
    for (final item in _customUserInputs) {
      if (item.startsWith('http://') || item.startsWith('https://')) {
        subUrlsToFetch.add(item);
      } else {
        allAdminConfigs.addAll(_extractConfigsFromText(item));
      }
    }

    // ۲. بررسی فایل admin_subs.txt در گیت‌هاب خودت (بدون نیاز به آپدیت برنامه!)
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

    // ۳. دانلود ساب‌لینک‌هایی که ادمین معرفی کرده است
    for (final subUrl in subUrlsToFetch) {
      if (_userCancelled) break;
      final String subBody = await _downloadUrlFast(subUrl, maxBytes: 250000);
      if (subBody.isNotEmpty) {
        allAdminConfigs.addAll(_extractConfigsFromText(subBody));
      }
    }

    return allAdminConfigs;
  }

  /// الگوریتم اصلی پیدا کردن سرور به ترتیب اولویت دقیق خواسته شده:
  /// ۱. کانفیگ‌های سالم قبلی (Saved Working Configs)
  /// ۲. ساب‌لینک‌ها و کانفیگ‌های ادمین (GitHub admin_subs.txt + Custom Subs)
  /// ۳. ساب‌لینک جدید Hiddify Mahsa (حدود ۳۰-۴۰ کانفیگ)
  /// ۴. ساب‌لینک‌های Epodonios
  Future<ReadyServer?> _findWorkingServerByPriority() async {
    // اطمینان از خاموش بودن کامل سرویس قبلی قبل از شروع تست هسته
    try {
      await v2ray.stopV2Ray();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));

    // -------------------------------------------------------------------------
    // اولویت ۱: تست مجدد کانفیگ‌های سالم ذخیره‌شده از دفعات قبلی
    // -------------------------------------------------------------------------
    if (_savedWorkingConfigs.isNotEmpty && !_userCancelled) {
      final List<ReadyServer> savedCopy = List<ReadyServer>.from(_savedWorkingConfigs);
      for (int i = 0; i < savedCopy.length; i++) {
        if (_userCancelled) return null;
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
          // این کانفیگِ ذخیره‌شده هنوز سالم است! درجا برگردان و اسکن را متوقف کن!
          return savedSrv;
        } else {
          // این کانفیگ قبلی دیگر از کار افتاده؛ حذفش کن تا دفعه بعد وقت نگیرد
          _savedWorkingConfigs.removeWhere((s) => s.rawUri == savedSrv.rawUri);
          await _saveWorkingConfigsToDisk();
        }
      }
    }

    // -------------------------------------------------------------------------
    // اولویت ۲: ساب‌لینک‌ها و کانفیگ‌های ادمین (بدون نیاز به آپدیت برنامه)
    // -------------------------------------------------------------------------
    if (!_userCancelled) {
      if (mounted) {
        setState(() {
          rocketScanDetail = 'Checking Admin priority subs & configs...';
        });
      }
      final List<String> adminConfigs = await _fetchAdminAndCustomConfigs();
      if (adminConfigs.isNotEmpty && !_userCancelled) {
        final ReadyServer? winner = await _scanConfigListUntilFirstHealthy(
          adminConfigs,
          'Admin Priority',
        );
        if (winner != null) return winner;
      }
    }

    // -------------------------------------------------------------------------
    // اولویت ۳: ساب‌لینک جدید Hiddify Mahsa (سریع، ۳۰-۴۰ کانفیگ)
    // -------------------------------------------------------------------------
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
        final ReadyServer? winner = await _scanConfigListUntilFirstHealthy(
          mahsaConfigs,
          'Hiddify Mahsa',
        );
        if (winner != null) return winner;
      }
    }

    // -------------------------------------------------------------------------
    // اولویت ۴: منابع Epodonios (در صورتی که هیچ‌کدام از بالایی‌ها جواب ندادند)
    // -------------------------------------------------------------------------
    for (final epUrl in _fallbackEpodoniosUrls) {
      if (_userCancelled) break;
      final String protoLabel = epUrl.split('/').last.replaceAll('.txt', '').toUpperCase();
      if (mounted) {
        setState(() {
          rocketScanDetail = 'Loading Epodonios $protoLabel backup sub...';
        });
      }

      final String body = await _downloadUrlFast(epUrl, maxBytes: 350000);
      if (body.isEmpty) continue;

      final List<String> epConfigs = _extractConfigsFromText(body);
      if (epConfigs.isEmpty) continue;

      final ReadyServer? winner = await _scanConfigListUntilFirstHealthy(
        epConfigs.take(300).toList(),
        'Epodonios $protoLabel',
      );
      if (winner != null) return winner;
    }

    return null;
  }

  // ===========================================================================
  // ۴. شروع اتصال و نمایش صفحه موشک
  // ===========================================================================

  Future<bool> _connectToVerifiedServer(ReadyServer srv) async {
    try {
      if (mounted) {
        setState(() {
          rocketScanDetail = 'Rocket in orbit! Connecting (${srv.ping} ms)...';
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
      while (!_nativeVpnRunning && waitedMs < 3500) {
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

      // ذخیره این کانفیگ سالم در صدر لیست دائمی تا دفعه بعد اول از همه همین بررسی شود!
      _savedWorkingConfigs.removeWhere((s) => s.rawUri == srv.rawUri);
      _savedWorkingConfigs.insert(0, srv);
      await _saveWorkingConfigsToDisk();

      _activeServer = srv;
      _rocketController.stop();

      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
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

    final ReadyServer? winningServer = await _findWorkingServerByPriority();

    if (winningServer != null && !_userCancelled) {
      final bool connectedOk = await _connectToVerifiedServer(winningServer);
      if (connectedOk) return;
    }

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
  // ۵. رفرش کلیکی پینگ + تشخیص قطعی کانفیگ یا اینترنت (۳۰ ثانیه)
  // ===========================================================================

  Future<void> _refreshPingOnTap() async {
    if (isRefreshingPing || isConnecting) return;
    setState(() => isRefreshingPing = true);

    try {
      if (isConnected && _activeServer != null) {
        int delay = await v2ray
            .getConnectedServerDelay()
            .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);
        if (delay <= 0) {
          delay = await _checkSocketPing(_activeServer!.address, _activeServer!.port);
        }
        if (mounted && delay > 0) {
          setState(() => currentPing = delay);
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

    int livePing = -1;
    try {
      livePing = await v2ray
          .getConnectedServerDelay()
          .timeout(const Duration(milliseconds: 2800), onTimeout: () => -1);
    } catch (_) {}

    if (livePing <= 0) {
      livePing = await _checkSocketPing(_activeServer!.address, _activeServer!.port);
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

    final ReadyServer? nextWinner = await _findWorkingServerByPriority();
    if (nextWinner != null && !_userCancelled) {
      await _connectToVerifiedServer(nextWinner);
    } else {
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
  // ۶. پنجره مدیریت ساب‌لینک‌ها و کانفیگ‌های اولویت‌دار
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
  // ۷. صفحه انیمیشنی موشک در حال پرواز (Rocket Launch Scanner Screen)
  // ===========================================================================

  Widget _buildRocketScannerScreen() {
    final double wave = sin(_rocketController.value * 2 * pi);
    final double flameScale = 0.85 + 0.30 * sin(_rocketController.value * 6 * pi).abs();

    return Stack(
      children: [
        // ستاره‌های متحرک در پس‌زمینه که حس پرواز سریع موشک به سمت بالا را می‌دهند
        Positioned.fill(
          child: CustomPaint(
            painter: StarfieldPainter(_stars),
          ),
        ),

        // محتوای مرکزی: موشک متحرک + شعله آتشین + وضعیت زنده اسکن
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // هاله و موشک در حال حرکت به بالا
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
                      child: const Center(
                        child: Transform.rotate(
                          angle: -0.785, // چرخش ۴۵ درجه تا نوک موشک صاف به سمت بالا باشد
                          child: Icon(
                            Icons.rocket_launch_rounded,
                            size: 82,
                            color: Color(0xFF00F5D4),
                          ),
                        ),
                      ),
                    ),
                    // شعله‌های متحرک آتش در زیر موشک
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

              // دکمه لغو اسکن
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
  // ۸. رابط کاربری اصلی
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    // وقتی کاربر روی کانکت می‌زند، صفحه انیمیشنی موشک نمایش داده می‌شود
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
              // ۱. هدر بالا: لوگوی Nivexia + دکمه افزودن ساب‌لینک + باکس پینگ کلیکی
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
      // رسم ستاره و ردِ نورانی حرکت به سمت پایین
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
