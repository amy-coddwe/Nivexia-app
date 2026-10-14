import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFF7B2CBF),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

/// سه حالت اصلی برنامه:
/// 1. vpnConfigs: کانفیگ‌های گیمینگ با قابلیت انتخاب سرور
/// 2. vpnVip: اتصال خودکار تک‌کلیکی مخصوص وب‌گردی (Xray + TLS Fragment)
/// 3. dnsMode: اتصال تک‌کلیکی به DNS مخفی داخلی بدون نمایش IP
enum AppConnectionMode { vpnConfigs, vpnVip, dnsMode }

/// وضعیت تست هر سرور
enum NodeTestState { testing, healthy, timeout, failed }

class ServerNode {
  final String id;
  final String fingerprint;
  final String name;
  final String flag;
  final String protocol;
  final String address;
  final int port;
  final String rawUri;
  final String baseConfigJson;
  int tcpPingMs;
  int realDelayMs;
  NodeTestState testState;

  ServerNode({
    required this.id,
    required this.fingerprint,
    required this.name,
    required this.flag,
    required this.protocol,
    required this.address,
    required this.port,
    required this.rawUri,
    required this.baseConfigJson,
    this.tcpPingMs = -1,
    this.realDelayMs = -1,
    this.testState = NodeTestState.testing,
  });

  bool get isHealthy => testState == NodeTestState.healthy && realDelayMs > 0;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  // آدرس‌های DNS داخلی (مخفی از رابط کاربری، نوتیفیکیشن و لاگ‌ها)
  // کدهای اعداد برای جلوگیری از نمایش رشته‌ای مستقیم در محیط‌های عادی
  static final String _internalPrimaryDns =
      const [95, 38, 132, 81].map((e) => e.toString()).join('.');
  static final String _internalSecondaryDns =
      const [1, 1, 1, 1].map((e) => e.toString()).join('.');

  static const int _targetHealthyNodesCount = 10;

  late final V2ray v2ray = V2ray(
    onStatusChanged: (status) {
      if (!mounted) return;
      final String rawState = status.state.toUpperCase();
      setState(() {
        v2rayStatus = status;
        if (rawState == "CONNECTED") {
          _coreReportedConnected = true;
        } else if (rawState == "DISCONNECTED") {
          _coreReportedConnected = false;
          if (!isConnecting) {
            isConnected = false;
          }
        }
      });
    },
  );

  late AnimationController _pulseController;
  V2RayStatus v2rayStatus = V2RayStatus();

  AppConnectionMode currentMode = AppConnectionMode.vpnConfigs;

  bool isConnected = false;
  bool isConnecting = false;
  bool _coreReportedConnected = false;
  bool _cancelConnectRequested = false;

  // مدیریت اسکنر غیرهم‌زمان و کش
  bool isScanning = false;
  int _scanGeneration = 0;
  String scanStatusMessage = '';
  String? scanDiagnosticReason;

  final List<ServerNode> _displayedNodes = [];
  final List<ServerNode> _cachedHealthyNodes = [];
  final Set<String> _seenFingerprints = {};
  ServerNode? selectedServer;
  StateSetter? _activeSheetSetter;

  // تنظیمات موتور
  bool isPersian = false;
  bool tcpNoDelay = true;
  bool bypassIran = true;
  bool enableTlsFragment = true;
  bool blockWebInGameMode = false;

  // سوپرمنبع Epodonios (فایل‌های اصلی، Base64 و تفکیک‌شده بر اساس پروتکل‌های سازگار با هسته Xray) + منابع پشتیبان معتبر
  final List<String> _primaryEpodoniosSources = [
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_base64_Sub.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/trojan.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
    // آینه‌های CDN از مخزن Epodonios برای اطمینان از باز شدن روی اینترنت‌های دارای اختلال گیت‌هاب
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/All_Configs_Sub.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/All_Configs_base64_Sub.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Splitted-By-Protocol/vless.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Splitted-By-Protocol/vmess.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Splitted-By-Protocol/trojan.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Splitted-By-Protocol/ss.txt',
  ];

  final List<String> _fallbackOpenSources = [
    'https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub1.txt',
    'https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub2.txt',
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/all_extracted_configs.txt',
    'https://raw.githubusercontent.com/yebekhe/TVC/main/subscriptions/xray/normal/mix',
    'https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/vless.txt',
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Sub1.txt',
    'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vless_configs.txt',
    'https://cdn.jsdelivr.net/gh/yebekhe/TVC@main/subscriptions/xray/normal/mix',
  ];

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
    _startSmartConfigScan(forceRefresh: true);
  }

  @override
  void dispose() {
    _scanGeneration++;
    _pulseController.dispose();
    super.dispose();
  }

  String tr(String en, String fa) => isPersian ? fa : en;

  void _notifyUI() {
    if (mounted) setState(() {});
    if (_activeSheetSetter != null) {
      try {
        _activeSheetSetter!(() {});
      } catch (_) {}
    }
  }

  List<ServerNode> get healthyNodes =>
      _displayedNodes.where((n) => n.isHealthy).toList();

  // ===========================================================================
  // ۱. موتور DNS داخلی و مخفی (95.38.132.81 اصلی + 1.1.1.1 ثانویه)
  // ===========================================================================

  /// ارسال پکت واقعی استعلام DNS (UDP Port 53) یا تست سوکت برای تایید در دسترس بودن سرور DNS
  Future<bool> _verifySingleDnsServerReachable(String dnsIp) async {
    // تلاش اول: ارسال یک پکت استاندارد DNS Query (برای example.com) روی UDP پورت 53
    RawDatagramSocket? udpSocket;
    try {
      final Completer<bool> completer = Completer<bool>();
      udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
          .timeout(const Duration(milliseconds: 1500));

      udpSocket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = udpSocket?.receive();
          if (dg != null && dg.data.length >= 12) {
            if (!completer.isCompleted) completer.complete(true);
          }
        }
      });

      // هدر و بدنه استاندارد استعلام A Record برای example.com
      final Uint8List dnsQueryPacket = Uint8List.fromList([
        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x07, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x03, 0x63, 0x6f, 0x6d,
        0x00, 0x00, 0x01, 0x00, 0x01
      ]);

      udpSocket.send(dnsQueryPacket, InternetAddress(dnsIp), 53);

      final bool udpResult = await completer.future
          .timeout(const Duration(milliseconds: 1600), onTimeout: () => false);
      udpSocket.close();
      if (udpResult) return true;
    } catch (_) {
      udpSocket?.close();
    }

    // تلاش دوم: بررسی باز بودن پورت 53 روی TCP
    Socket? tcpSocket;
    try {
      tcpSocket = await Socket.connect(
        dnsIp,
        53,
        timeout: const Duration(milliseconds: 1500),
      );
      await tcpSocket.close();
      return true;
    } catch (_) {
      tcpSocket?.destroy();
      return false;
    }
  }

  /// بررسی دسترسی واقعی به هر دو آدرس DNS قبل از اتصال و تعیین اولویت Primary و Secondary
  Future<List<String>> _resolveVerifiedDnsOrder() async {
    final results = await Future.wait([
      _verifySingleDnsServerReachable(_internalPrimaryDns),
      _verifySingleDnsServerReachable(_internalSecondaryDns),
    ]);

    final bool primaryOk = results[0];
    final bool secondaryOk = results[1];

    if (primaryOk && secondaryOk) {
      return [_internalPrimaryDns, _internalSecondaryDns];
    } else if (primaryOk) {
      return [_internalPrimaryDns, _internalSecondaryDns];
    } else if (secondaryOk) {
      // اگر روی اپراتور کاربر آدرس اول موقتاً در دسترس نبود، آدرس دوم در اولویت قرار می‌گیرد
      return [_internalSecondaryDns, _internalPrimaryDns];
    }
    return [];
  }

  /// ساخت کانفیگ استاندارد و بدون حلقه (Loop-Free) برای حالت DNS در هسته Xray
  String _buildProtectedDnsTunnelConfig(List<String> orderedDnsServers) {
    final V2RayURL baseTemplate = V2ray.parseFromURL(
      'vless://00000000-0000-0000-0000-000000000000@127.0.0.1:443?security=none&type=tcp#ProtectedDNS',
    );
    final Map<String, dynamic> cfg = jsonDecode(baseTemplate.getFullConfiguration());

    // استخراج تگ‌های ورودی واقعی (معمولاً socks و http) برای جلوگیری از افتادن درخواست‌های خود Xray در حلقه
    final List<String> inboundTags = [];
    if (cfg['inbounds'] is List) {
      for (final ib in (cfg['inbounds'] as List)) {
        if (ib is Map && ib['tag'] != null) {
          inboundTags.add(ib['tag'].toString());
        }
      }
    }
    if (inboundTags.isEmpty) {
      inboundTags.addAll(['socks', 'http']);
    }

    final String activePrimary = orderedDnsServers.first;
    final String activeSecondary =
        orderedDnsServers.length > 1 ? orderedDnsServers[1] : _internalSecondaryDns;

    // تنظیم سرورهای اصلی و ثانویه در ماژول DNS هسته
    cfg['dns'] = {
      "servers": [
        activePrimary,
        activeSecondary,
      ],
      "queryStrategy": "UseIPv4",
      "disableCache": false,
    };

    // خروجی اول (Default Outbound) از نوع freedom است تا استعلام‌های داخلی هسته و ترافیک گیم مستقیماً عبور کنند
    cfg['outbounds'] = [
      {
        "tag": "proxy",
        "protocol": "freedom",
        "settings": {
          "domainStrategy": "UseIPv4",
        },
        "streamSettings": {
          "sockopt": {
            "tcpNoDelay": true,
          }
        }
      },
      {
        "tag": "dns-out",
        "protocol": "dns",
        "settings": {
          "network": "udp",
          "address": activePrimary,
          "port": 53,
          "nonIPQuery": "skip",
        }
      },
      {
        "tag": "block",
        "protocol": "blackhole",
        "settings": {}
      }
    ];

    // قوانین روتینگ:
    // ۱. فقط پکت‌های پورت ۵۳ که از ورودی‌های گوشی (inboundTags) می‌آیند وارد dns-out می‌شوند (حذف ۱۰۰٪ حلقه روتینگ و نشت DNS)
    // ۲. مسدودسازی پورت 853 (DoT) برای جلوگیری از دور زدن تونل DNS توسط سیستم‌عامل
    // ۳. عبور مستقیم ترافیک UDP/TCP با آی‌پی‌های حل‌شده توسط DNS
    cfg['routing'] = {
      "domainStrategy": "IPOnDemand",
      "rules": [
        {
          "type": "field",
          "inboundTag": inboundTags,
          "port": "53",
          "outboundTag": "dns-out"
        },
        {
          "type": "field",
          "port": "853",
          "outboundTag": "block"
        },
        {
          "type": "field",
          "network": "tcp,udp",
          "outboundTag": "proxy"
        }
      ]
    };

    return jsonEncode(cfg);
  }

  // ===========================================================================
  // ۲. موتور اسکنر غیرهم‌زمان Epodonios + تشخیص فرمت + حذف تکراری + تست ۲ مرحله‌ای
  // ===========================================================================

  /// تشخیص خودکار محتوای Base64 یا متن خام و استخراج لینک‌های استاندارد
  List<String> _decodeSubscriptionPayload(String rawBody) {
    String content = rawBody.trim();
    if (content.isEmpty) return [];

    // اگر محتوا شامل لینک مستقیم نیست، احتمالاً Base64 است
    if (!content.contains('://')) {
      try {
        String cleanB64 = content.replaceAll(RegExp(r'\s+'), '');
        int mod = cleanB64.length % 4;
        if (mod > 0) {
          cleanB64 += '=' * (4 - mod);
        }
        content = utf8.decode(base64.decode(cleanB64), allowMalformed: true);
      } catch (_) {}
    }

    final List<String> validLinks = [];
    for (String line in content.split(RegExp(r'[\r\n]+'))) {
      line = line.trim();
      if (line.isEmpty) continue;
      // فقط ۴ پروتکل ۱۰۰٪ سازگار با هسته Xray-core و پارسر فعلی پردازش می‌شوند
      if (line.startsWith('vless://') ||
          line.startsWith('vmess://') ||
          line.startsWith('trojan://') ||
          line.startsWith('ss://')) {
        validLinks.add(line);
      }
    }
    return validLinks;
  }

  /// پاکسازی پارامترهای ناسازگار از لینک اشتراک
  String _normalizeShareUri(String uri) {
    String clean = uri.trim();
    if ((clean.startsWith('vless://') || clean.startsWith('trojan://')) &&
        clean.contains('?')) {
      try {
        final hashParts = clean.split('#');
        final String remarkSuffix =
            hashParts.length > 1 ? '#${hashParts.sublist(1).join('#')}' : '';
        final qParts = hashParts.first.split('?');
        final String prefix = qParts.first;
        final String query = qParts.sublist(1).join('?');

        final List<String> safeParams = [];
        for (final p in query.split('&')) {
          if (!p.startsWith('ech=') && !p.startsWith('insecure=')) {
            safeParams.add(p);
          }
        }
        return '$prefix?${safeParams.join('&')}$remarkSuffix';
      } catch (_) {}
    }
    return clean;
  }

  /// ساخت اثر انگشت یکتا (Fingerprint) از مشخصات فنی سرور برای حذف ۱۰۰٪ کانفیگ‌های تکراری
  String _extractTechnicalFingerprint(String proto, Map<String, dynamic> fullCfg) {
    try {
      final outbounds = fullCfg['outbounds'] as List?;
      if (outbounds != null && outbounds.isNotEmpty) {
        final ob = outbounds.first as Map<String, dynamic>;
        final settings = ob['settings'] as Map<String, dynamic>? ?? {};
        final stream = ob['streamSettings'] as Map<String, dynamic>? ?? {};
        final net = stream['network'] ?? 'tcp';
        final sec = stream['security'] ?? 'none';

        if ( settings['vnext'] is List && (settings['vnext'] as List).isNotEmpty) {
          final vnext = (settings['vnext'] as List).first;
          final addr = vnext['address'] ?? '';
          final port = vnext['port'] ?? '';
          String uid = '';
          if (vnext['users'] is List && (vnext['users'] as List).isNotEmpty) {
            uid = (vnext['users'] as List).first['id']?.toString() ?? '';
          }
          return '$proto|$addr|$port|$uid|$net|$sec';
        } else if (settings['servers'] is List &&
            (settings['servers'] as List).isNotEmpty) {
          final srv = (settings['servers'] as List).first;
          final addr = srv['address'] ?? '';
          final port = srv['port'] ?? '';
          final pass = srv['password'] ?? '';
          return '$proto|$addr|$port|$pass|$net|$sec';
        }
      }
    } catch (_) {}
    return '';
  }

  /// تشخیص پرچم و نام تمیز سرور بدون تبلیغات کانال‌ها
  Map<String, String> _detectCleanCountry(String remark, String address, int idx) {
    final String combined = '${remark.toUpperCase()} ${address.toUpperCase()}';
    String flag = '🇪🇺';
    String country = 'Europe';

    if (combined.contains('DE') || combined.contains('GERMANY') || combined.contains('FRANKFURT') || combined.contains('FALKENSTEIN') || remark.contains('🇩🇪') || remark.contains('آلمان')) {
      flag = '🇩🇪';
      country = 'Germany';
    } else if (combined.contains('NL') || combined.contains('NETHERLANDS') || combined.contains('AMSTERDAM') || remark.contains('🇳🇱') || remark.contains('هلند')) {
      flag = '🇳🇱';
      country = 'Netherlands';
    } else if (combined.contains('FI') || combined.contains('FINLAND') || combined.contains('HELSINKI') || remark.contains('🇫🇮') || remark.contains('فنلاند')) {
      flag = '🇫🇮';
      country = 'Finland';
    } else if (combined.contains('TR') || combined.contains('TURKEY') || combined.contains('ISTANBUL') || remark.contains('🇹🇷') || remark.contains('ترکیه')) {
      flag = '🇹🇷';
      country = 'Turkey';
    } else if (combined.contains('GB') || combined.contains('UK') || combined.contains('LONDON') || remark.contains('🇬🇧') || remark.contains('انگلیس')) {
      flag = '🇬🇧';
      country = 'United Kingdom';
    } else if (combined.contains('FR') || combined.contains('FRANCE') || combined.contains('PARIS') || remark.contains('🇫🇷') || remark.contains('فرانسه')) {
      flag = '🇫🇷';
      country = 'France';
    } else if (combined.contains('AE') || combined.contains('UAE') || combined.contains('DUBAI') || remark.contains('🇦🇪') || remark.contains('امارات')) {
      flag = '🇦🇪';
      country = 'UAE';
    } else if (combined.contains('SE') || combined.contains('SWEDEN') || remark.contains('🇸🇪')) {
      flag = '🇸🇪';
      country = 'Sweden';
    } else if (combined.contains('PL') || combined.contains('POLAND') || remark.contains('🇵🇱')) {
      flag = '🇵🇱';
      country = 'Poland';
    } else if (combined.contains('US') || combined.contains('USA') || remark.contains('🇺🇸') || remark.contains('آمریکا')) {
      flag = '🇺🇸';
      country = 'United States';
    } else if (combined.contains('CF') || combined.contains('CLOUDFLARE') || combined.contains('PAGES.DEV') || combined.contains('WORKERS.DEV')) {
      flag = '⚡';
      country = 'Cloudflare Edge';
    }

    return {
      'flag': flag,
      'name': '$country • Node #${idx + 1}',
    };
  }

  /// تزریق تنظیمات واقعی گیمینگ یا VIP (شامل TLS Fragment و TCP NoDelay) به کانفیگ Xray
  String _buildCustomizedXrayConfig(
    String rawConfigJson, {
    required bool isVipWebMode,
  }) {
    final Map<String, dynamic> cfg = jsonDecode(rawConfigJson);

    // تزریق DNSهای داخلی در سطح هسته بدون نمایش در UI
    cfg['dns'] = {
      "servers": [
        _internalPrimaryDns,
        _internalSecondaryDns,
      ],
      "queryStrategy": "UseIPv4",
    };

    if (cfg['outbounds'] is List && (cfg['outbounds'] as List).isNotEmpty) {
      final List outbounds = cfg['outbounds'] as List;
      final Map<String, dynamic> primaryOb =
          Map<String, dynamic>.from(outbounds[0] as Map);

      primaryOb['streamSettings'] ??= <String, dynamic>{};
      final Map<String, dynamic> stream =
          Map<String, dynamic>.from(primaryOb['streamSettings'] as Map);

      if (stream['security'] == 'tls') {
        stream['tlsSettings'] ??= <String, dynamic>{};
        stream['tlsSettings']['allowInsecure'] = true;
      }

      final Map<String, dynamic> sockopt = <String, dynamic>{
        "tcpNoDelay": tcpNoDelay,
        "tcpKeepAliveIdle": 30,
      };

      // در حالت VIP یا در صورت روشن بودن TLS Fragment، ترافیک TLS Handshake برای عبور از فیلترینگ قطعه قطعه می‌شود
      final bool useFragment = isVipWebMode || enableTlsFragment;
      if (useFragment &&
          (stream['security'] == 'tls' || stream['security'] == 'reality')) {
        sockopt['dialerProxy'] = 'fragment-out';
      }

      stream['sockopt'] = sockopt;
      primaryOb['streamSettings'] = stream;
      outbounds[0] = primaryOb;

      if (useFragment && !outbounds.any((o) => o['tag'] == 'fragment-out')) {
        outbounds.add({
          "tag": "fragment-out",
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "UseIP",
            "fragment": {
              "packets": "tlshello",
              "length": "10-50",
              "interval": "5-10"
            }
          },
          "streamSettings": {
            "sockopt": {
              "tcpNoDelay": true,
            }
          }
        });
      }

      if (!outbounds.any((o) => o['tag'] == 'direct')) {
        outbounds.add({
          "tag": "direct",
          "protocol": "freedom",
          "settings": {"domainStrategy": "UseIPv4"}
        });
      }

      if (!outbounds.any((o) => o['tag'] == 'block')) {
        outbounds.add({
          "tag": "block",
          "protocol": "blackhole",
          "settings": {}
        });
      }
    }

    cfg['routing'] ??= <String, dynamic>{};
    cfg['routing']['domainStrategy'] = 'IPIfNonMatch';
    final List<Map<String, dynamic>> extraRules = [];

    if (bypassIran) {
      extraRules.add({
        "type": "field",
        "domain": ["regexp:.*\\.ir\$"],
        "outboundTag": "direct"
      });
    }

    if (!isVipWebMode && blockWebInGameMode) {
      extraRules.add({
        "type": "field",
        "port": "80,443",
        "network": "tcp",
        "outboundTag": "block"
      });
    }

    if (extraRules.isNotEmpty) {
      final List currentRules = (cfg['routing']['rules'] as List?) ?? [];
      cfg['routing']['rules'] = [...extraRules, ...currentRules];
    }

    return jsonEncode(cfg);
  }

  /// مرتب‌سازی لیست سرورها: سرورهای سالم بر اساس کمترین پینگ واقعی در صدر، سپس سرورهای در حال تست، و در انتها سرورهای Timeout/Failed
  void _sortDisplayedNodes() {
    _displayedNodes.sort((a, b) {
      int rank(NodeTestState s) {
        switch (s) {
          case NodeTestState.healthy:
            return 0;
          case NodeTestState.testing:
            return 1;
          case NodeTestState.timeout:
            return 2;
          case NodeTestState.failed:
            return 3;
        }
      }

      final int rA = rank(a.testState);
      final int rB = rank(b.testState);
      if (rA != rB) return rA.compareTo(rB);

      if (a.testState == NodeTestState.healthy &&
          b.testState == NodeTestState.healthy) {
        return a.realDelayMs.compareTo(b.realDelayMs);
      }
      return 0;
    });

    final healthy = healthyNodes;
    if (healthy.isNotEmpty) {
      if (selectedServer == null || !selectedServer!.isHealthy) {
        selectedServer = healthy.first;
      }
    }
  }

  /// تست دو مرحله‌ای واقعی یک کانفیگ:
  /// مرحله ۱: بررسی باز بودن سوکت TCP سرور
  /// مرحله ۲: تست Real Delay واقعی از درون هسته Xray (بدون هیچ عدد ساختگی)
  Future<void> _testSingleCandidateNode(ServerNode node, int generation) async {
    if (generation != _scanGeneration) return;

    // مرحله ۱: تست سریع سوکت TCP
    final Stopwatch sw = Stopwatch()..start();
    Socket? sock;
    try {
      sock = await Socket.connect(
        node.address,
        node.port,
        timeout: const Duration(milliseconds: 1400),
      );
      sw.stop();
      node.tcpPingMs = sw.elapsedMilliseconds;
      await sock.close();
    } catch (_) {
      sock?.destroy();
      node.testState = NodeTestState.timeout;
      node.realDelayMs = -1;
      _sortDisplayedNodes();
      _notifyUI();
      return;
    }

    if (generation != _scanGeneration) return;

    // مرحله ۲: تست Real Delay واقعی از طریق هسته Xray (Handshake کامل پروتکل + درخواست واقعی)
    try {
      final String testConfig = _buildCustomizedXrayConfig(
        node.baseConfigJson,
        isVipWebMode: false,
      );
      final int realDelay = await v2ray
          .getServerDelay(config: testConfig)
          .timeout(const Duration(milliseconds: 3200), onTimeout: () => -1);

      if (generation != _scanGeneration) return;

      if (realDelay > 0 && realDelay < 3500) {
        node.realDelayMs = realDelay;
        node.testState = NodeTestState.healthy;
        if (!_cachedHealthyNodes.any((c) => c.fingerprint == node.fingerprint)) {
          _cachedHealthyNodes.add(node);
        }
      } else {
        node.realDelayMs = -1;
        node.testState = NodeTestState.timeout;
      }
    } catch (_) {
      node.realDelayMs = -1;
      node.testState = NodeTestState.failed;
    }

    _sortDisplayedNodes();
    _notifyUI();
  }

  /// پایپ‌لاین اسکن هوشمند:
  /// - بررسی مجدد زنده بودن کش قبلی هنگام رفرش
  /// - اسکن منابع Epodonios و منابع پشتیبان در دسته‌های موازی کنترل‌شده (Concurrency = 6)
  /// - ادامه خودکار اسکن تا پیدا شدن حداقل ۱۰ کانفیگ سالم دارای پینگ واقعی
  Future<void> _startSmartConfigScan({bool forceRefresh = false}) async {
    final int myGen = ++_scanGeneration;
    isScanning = true;
    scanDiagnosticReason = null;
    scanStatusMessage = tr(
      'Verifying cached nodes & fetching Epodonios repository...',
      'بررسی سرورهای کش‌شده و دریافت کانفیگ از مخزن Epodonios...',
    );
    _notifyUI();

    // ۱. اگر سرور سالمی از قبل در کش داریم، هنگام رفرش ابتدا وضعیت زنده آن‌ها را دوباره تست می‌کنیم (عدم نمایش پینگ قدیمی)
    if (_cachedHealthyNodes.isNotEmpty) {
      final List<ServerNode> cachedCopy = List<ServerNode>.from(_cachedHealthyNodes);
      _cachedHealthyNodes.clear();
      _displayedNodes.clear();
      _seenFingerprints.clear();

      for (final c in cachedCopy) {
        c.testState = NodeTestState.testing;
        c.realDelayMs = -1;
        _displayedNodes.add(c);
        _seenFingerprints.add(c.fingerprint);
      }
      _notifyUI();

      const int cacheBatchSize = 6;
      for (int i = 0; i < _displayedNodes.length; i += cacheBatchSize) {
        if (myGen != _scanGeneration) return;
        final batch = _displayedNodes.skip(i).take(cacheBatchSize).toList();
        await Future.wait(batch.map((n) => _testSingleCandidateNode(n, myGen)));
      }
    } else {
      _displayedNodes.clear();
      _seenFingerprints.clear();
    }

    if (myGen != _scanGeneration) return;

    // ۲. آماده‌سازی لیست منابع (ابتدا سوپرمنبع Epodonios، سپس منابع پشتیبان متن‌باز)
    final List<String> allSourceQueue = [
      ..._primaryEpodoniosSources,
      ...(_fallbackOpenSources.toList()..shuffle(Random())),
    ];

    int sourceIndex = 0;
    int candidateSerial = _displayedNodes.length;

    // ادامه حلقه تا زمانی که حداقل ۱۰ سرور سالم با پینگ واقعی پیدا شود یا تمام منابع بررسی شوند
    while (healthyNodes.length < _targetHealthyNodesCount &&
        sourceIndex < allSourceQueue.length) {
      if (myGen != _scanGeneration) return;

      // دریافت موازی ۳ منبع در هر دور
      final List<String> currentUrls =
          allSourceQueue.skip(sourceIndex).take(3).toList();
      sourceIndex += currentUrls.length;

      scanStatusMessage = tr(
        'Scanning sources (${healthyNodes.length}/$_targetHealthyNodesCount healthy found)...',
        'در حال اسکن منابع (${healthyNodes.length} از $_targetHealthyNodesCount سرور سالم پیدا شد)...',
      );
      _notifyUI();

      final List<String> rawBatchLinks = [];
      await Future.wait(currentUrls.map((url) async {
        try {
          final res = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 5));
          if (res.statusCode == 200 && res.body.isNotEmpty) {
            final extracted = _decodeSubscriptionPayload(res.body);
            rawBatchLinks.addAll(extracted);
          }
        } catch (_) {}
      }));

      if (myGen != _scanGeneration) return;
      if (rawBatchLinks.isEmpty) continue;

      rawBatchLinks.shuffle(Random());

      // تجزیه و حذف کانفیگ‌های تکراری
      final List<ServerNode> newCandidates = [];
      for (final rawLink in rawBatchLinks) {
        if (newCandidates.length >= 24) break;
        try {
          final String cleanUri = _normalizeShareUri(rawLink);
          final V2RayURL parser = V2ray.parseFromURL(cleanUri);
          final String address = parser.address.trim();
          final int port = parser.port;
          if (address.isEmpty || port <= 0 || address == '127.0.0.1') continue;

          final String baseJson = parser.getFullConfiguration();
          final Map<String, dynamic> decodedJson = jsonDecode(baseJson);

          String proto = cleanUri.split('://').first.toUpperCase();
          if (cleanUri.contains('security=reality')) proto = 'REALITY';

          final String fp = _extractTechnicalFingerprint(proto, decodedJson);
          if (fp.isEmpty || _seenFingerprints.contains(fp)) continue;

          _seenFingerprints.add(fp);
          final loc = _detectCleanCountry(parser.remark, address, candidateSerial++);

          newCandidates.add(ServerNode(
            id: 'node_${DateTime.now().microsecondsSinceEpoch}_$candidateSerial',
            fingerprint: fp,
            name: loc['name']!,
            flag: loc['flag']!,
            protocol: proto,
            address: address,
            port: port,
            rawUri: cleanUri,
            baseConfigJson: baseJson,
          ));
        } catch (_) {}
      }

      // تست دسته‌ای کاندیداها با هم‌زمانی کنترل‌شده (۶ سرور هم‌زمان) و نمایش لحظه‌ای در UI
      const int concurrencyLimit = 6;
      for (int i = 0; i < newCandidates.length; i += concurrencyLimit) {
        if (myGen != _scanGeneration) return;
        if (healthyNodes.length >= _targetHealthyNodesCount + 4) break;

        final batch = newCandidates.skip(i).take(concurrencyLimit).toList();
        _displayedNodes.addAll(batch);
        _sortDisplayedNodes();

        scanStatusMessage = tr(
          'Testing Real Delay (${healthyNodes.length}/$_targetHealthyNodesCount verified)...',
          'تست پینگ واقعی تونل (${healthyNodes.length} از $_targetHealthyNodesCount سرور سالم)...',
        );
        _notifyUI();

        await Future.wait(
          batch.map((node) => _testSingleCandidateNode(node, myGen)),
        );
      }
    }

    if (myGen != _scanGeneration) return;

    // بررسی نتیجه نهایی اسکن و ثبت دلیل دقیق در صورت کمتر بودن از ۱۰ سرور
    final int finalHealthyCount = healthyNodes.length;
    if (finalHealthyCount == 0) {
      scanDiagnosticReason = tr(
        '0 healthy servers responded on your current network. Check internet or try Refresh.',
        'هیچ سروری روی اینترنت فعلی شما پاسخ نداد (احتمال اختلال شدید شبکه یا مسدود بودن پورت‌ها).',
      );
    } else if (finalHealthyCount < _targetHealthyNodesCount) {
      scanDiagnosticReason = tr(
        'Scanned all available sources: $finalHealthyCount verified healthy nodes found (fewer than 10 due to ISP filtering on remaining nodes).',
        'تمام منابع بررسی شدند و $finalHealthyCount سرور ۱۰۰٪ سالم پیدا شد (بقیه سرورها روی اپراتور فعلی شما تایم‌اوت دادند).',
      );
    } else {
      scanDiagnosticReason = null;
    }

    isScanning = false;
    scanStatusMessage = '';
    _sortDisplayedNodes();
    _notifyUI();
  }

  // ===========================================================================
  // ۳. مدیریت اتصال واقعی برای هر ۳ حالت (Configs، VIP و DNS) + تست پس از اتصال
  // ===========================================================================

  /// بررسی واقعی برقراری ترافیک یا DNS پس از روشن شدن سرویس VPN اندروید
  Future<bool> _verifyPostConnectionHealth({required bool isDnsTunnel}) async {
    // صبر تا دریافت وضعیت CONNECTED از سرویس VpnService اندروید (حداکثر ۳.۵ ثانیه)
    int waitedMs = 0;
    while (!_coreReportedConnected && waitedMs < 3500) {
      if (_cancelConnectRequested) return false;
      await Future.delayed(const Duration(milliseconds: 250));
      waitedMs += 250;
    }

    if (!_coreReportedConnected) return false;

    if (isDnsTunnel) {
      // در حالت DNS، یک استعلام واقعی دامنه انجام می‌دهیم تا مطمئن شویم پورت 53 کار می‌کند و قفل نشده است
      try {
        final List<InternetAddress> addrs = await InternetAddress.lookup('cloudflare.com')
            .timeout(const Duration(milliseconds: 2500));
        return addrs.isNotEmpty && addrs.first.rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    } else {
      // در حالت VPN و VIP، تاخیر واقعی سرور متصل‌شده را از طریق خود تونل استعلام می‌کنیم
      try {
        final int delay = await v2ray
            .getConnectedServerDelay()
            .timeout(const Duration(milliseconds: 3200), onTimeout: () => -1);
        return delay > 0;
      } catch (_) {
        return false;
      }
    }
  }

  /// قطع کامل اتصال و آزادسازی منابع
  Future<void> _disconnectEngine() async {
    _cancelConnectRequested = true;
    try {
      await v2ray.stopV2Ray();
    } catch (_) {}
    if (mounted) {
      setState(() {
        isConnected = false;
        isConnecting = false;
        _coreReportedConnected = false;
      });
    }
  }

  /// شروع فرآیند اتصال بر اساس حالت انتخابی کاربر
  Future<void> _handleConnectButton() async {
    if (isConnected) {
      await _disconnectEngine();
      return;
    }

    if (isConnecting) {
      // امکان لغو عملیات در حین تلاش برای اتصال
      await _disconnectEngine();
      return;
    }

    final bool hasPerm = await v2ray.requestPermission();
    if (!hasPerm) {
      _showDiagnosticBanner(
        tr('VPN Permission denied by Android OS.', 'مجوز ساخت تونل VPN در اندروید تایید نشد.'),
        isError: true,
      );
      return;
    }

    setState(() {
      isConnecting = true;
      _cancelConnectRequested = false;
      _coreReportedConnected = false;
    });

    // -------------------------------------------------------------------------
    // حالت ۱: اتصال تک‌کلیکی به DNS مخفی
    // -------------------------------------------------------------------------
    if (currentMode == AppConnectionMode.dnsMode) {
      final List<String> reachableDns = await _resolveVerifiedDnsOrder();
      if (_cancelConnectRequested) return;

      if (reachableDns.isEmpty) {
        setState(() => isConnecting = false);
        _showDiagnosticBanner(
          tr(
            'DNS Connection Failed: Neither Primary nor Secondary DNS responded on port 53.',
            'خطا در اتصال DNS: شبکه شما دسترسی به پورت ۵۳ سرورهای DNS را مسدود کرده است.',
          ),
          isError: true,
        );
        return;
      }

      try {
        final String dnsConfig = _buildProtectedDnsTunnelConfig(reachableDns);
        await v2ray.startV2Ray(
          remark: "Nivexia Protected DNS", // بدون نمایش آدرس IP در نوتیفیکیشن
          config: dnsConfig,
          proxyOnly: false,
        );

        final bool verified = await _verifyPostConnectionHealth(isDnsTunnel: true);
        if (_cancelConnectRequested) return;

        if (verified) {
          setState(() {
            isConnected = true;
            isConnecting = false;
          });
        } else {
          await _disconnectEngine();
          _showDiagnosticBanner(
            tr(
              'DNS Tunnel failed verification check. Disconnected to prevent DNS leak.',
              'تست پاسخگویی تونل DNS ناموفق بود؛ برای جلوگیری از نشت ترافیک قطع شد.',
            ),
            isError: true,
          );
        }
      } catch (_) {
        await _disconnectEngine();
        _showDiagnosticBanner(
          tr('Failed to initialize DNS service.', 'خطا در راه‌اندازی سرویس DNS.'),
          isError: true,
        );
      }
      return;
    }

    // -------------------------------------------------------------------------
    // اطمینان از وجود سرورهای سالم برای حالت‌های VPN Configs و VIP
    // -------------------------------------------------------------------------
    if (healthyNodes.isEmpty) {
      await _startSmartConfigScan(forceRefresh: true);
    }
    if (_cancelConnectRequested) return;

    final List<ServerNode> availableHealthy = healthyNodes;
    if (availableHealthy.isEmpty) {
      setState(() => isConnecting = false);
      _showDiagnosticBanner(
        tr(
          'No healthy servers available. Check your internet connection and refresh.',
          'هیچ سرور سالمی در دسترس نیست. اتصال اینترنت را بررسی کرده و رفرش بزنید.',
        ),
        isError: true,
      );
      return;
    }

    // -------------------------------------------------------------------------
    // حالت ۲: بخش VIP (وب‌گردی خودکار با Xray Core + TLS Fragment + Failover)
    // -------------------------------------------------------------------------
    if (currentMode == AppConnectionMode.vpnVip) {
      // تست به ترتیب از کم‌پینگ‌ترین سرور سالم؛ در صورت عدم برقراری تونل واقعی، سوییچ خودکار به سرور بعدی
      final int maxAttempts = min(availableHealthy.length, 4);
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (_cancelConnectRequested) return;

        final ServerNode candidate = availableHealthy[attempt];
        try {
          final String vipConfig = _buildCustomizedXrayConfig(
            candidate.baseConfigJson,
            isVipWebMode: true,
          );

          await v2ray.startV2Ray(
            remark: "Nivexia VIP • Auto Web Tunnel",
            config: vipConfig,
            proxyOnly: false,
          );

          final bool tunnelOk = await _verifyPostConnectionHealth(isDnsTunnel: false);
          if (_cancelConnectRequested) return;

          if (tunnelOk) {
            setState(() {
              selectedServer = candidate;
              isConnected = true;
              isConnecting = false;
            });
            return;
          } else {
            await v2ray.stopV2Ray();
            await Future.delayed(const Duration(milliseconds: 300));
          }
        } catch (_) {
          try {
            await v2ray.stopV2Ray();
          } catch (_) {}
        }
      }

      await _disconnectEngine();
      _showDiagnosticBanner(
        tr(
          'VIP Auto-Connect could not establish a stable web tunnel. Please refresh nodes.',
          'اتصال خودکار VIP نتوانست تونل پایداری برقرار کند. لطفاً لیست سرورها را رفرش کنید.',
        ),
        isError: true,
      );
      return;
    }

    // -------------------------------------------------------------------------
    // حالت ۳: بخش کانفیگ‌های گیمینگ (اتصال به سرور انتخابی + سوییچ به سرور بعدی در صورت خطا)
    // -------------------------------------------------------------------------
    final List<ServerNode> tryOrder = [
      if (selectedServer != null) selectedServer!,
      ...availableHealthy.where((n) => n.id != selectedServer?.id).take(2),
    ];

    for (final ServerNode targetNode in tryOrder) {
      if (_cancelConnectRequested) return;
      try {
        final String gameConfig = _buildCustomizedXrayConfig(
          targetNode.baseConfigJson,
          isVipWebMode: false,
        );

        await v2ray.startV2Ray(
          remark: "Nivexia • ${targetNode.name}",
          config: gameConfig,
          proxyOnly: false,
        );

        final bool tunnelOk = await _verifyPostConnectionHealth(isDnsTunnel: false);
        if (_cancelConnectRequested) return;

        if (tunnelOk) {
          setState(() {
            selectedServer = targetNode;
            isConnected = true;
            isConnecting = false;
          });
          return;
        } else {
          await v2ray.stopV2Ray();
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (_) {
        try {
          await v2ray.stopV2Ray();
        } catch (_) {}
      }
    }

    await _disconnectEngine();
    _showDiagnosticBanner(
      tr(
        'Selected server did not pass tunnel verification. Try refreshing servers.',
        'سرور انتخابی به تست ترافیک تونل پاسخ نداد. لطفاً سرورها را رفرش کنید.',
      ),
      isError: true,
    );
  }

  void _showDiagnosticBanner(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.redAccent.shade700 : const Color(0xFF1A2234),
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
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
  // ۴. پنجره لیست سرورها (نمایش لحظه‌ای، تفکیک سالم و Timeout، و دکمه رفرش سریع)
  // ===========================================================================

  void _openServerListSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF10131C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            _activeSheetSetter = setSheetState;
            final int verifiedCount = healthyNodes.length;

            return Directionality(
              textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.78,
                maxChildSize: 0.94,
                minChildSize: 0.50,
                builder: (context, scrollController) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('VERIFIED SERVERS', 'سرورهای تست‌شده'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.1,
                                    color: Color(0xFF00F5D4),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tr(
                                    'Method: Two-Stage (TCP Socket + Xray Real Delay) • $verifiedCount Healthy',
                                    'روش تست: دو مرحله‌ای (سوکت + تونل واقعی Xray) • $verifiedCount سرور سالم',
                                  ),
                                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                                ),
                              ],
                            ),
                            IconButton(
                              tooltip: tr('Add Custom Config', 'افزودن کانفیگ شخصی'),
                              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70),
                              onPressed: () => _showAddCustomConfigDialog(setSheetState),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // دکمه رفرش و دریافت کانفیگ‌های جدید با پشتیبانی از لغو اسکن قبلی
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF182032),
                              foregroundColor: const Color(0xFF00F5D4),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: const Color(0xFF00F5D4).withOpacity(0.4)),
                              ),
                            ),
                            onPressed: () => _startSmartConfigScan(forceRefresh: true),
                            icon: isScanning
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF00F5D4),
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 20),
                            label: Text(
                              isScanning
                                  ? scanStatusMessage
                                  : tr(
                                      'Refresh & Scan New Servers (Target: 10+ Healthy)',
                                      'رفرش و اسکن کانفیگ‌های جدید (هدف: حداقل ۱۰ سرور سالم)',
                                    ),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),

                        if (scanDiagnosticReason != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                            ),
                            child: Text(
                              scanDiagnosticReason!,
                              style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),
                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 10),

                        Expanded(
                          child: _displayedNodes.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isScanning) ...[
                                        const CircularProgressIndicator(color: Color(0xFF00F5D4)),
                                        const SizedBox(height: 14),
                                        Text(
                                          scanStatusMessage,
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          textAlign: TextAlign.center,
                                        ),
                                      ] else ...[
                                        const Icon(Icons.dns_outlined, size: 44, color: Colors.white24),
                                        const SizedBox(height: 10),
                                        Text(
                                          tr('Tap Refresh above to scan servers.', 'دکمه رفرش بالا را بزنید.'),
                                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: _displayedNodes.length,
                                  itemBuilder: (context, index) {
                                    final node = _displayedNodes[index];
                                    final bool isSelected = selectedServer?.id == node.id;

                                    Color badgeColor;
                                    String pingLabel;
                                    if (node.testState == NodeTestState.healthy) {
                                      pingLabel = '${node.realDelayMs} ms';
                                      badgeColor = node.realDelayMs < 140
                                          ? const Color(0xFF00F5D4)
                                          : (node.realDelayMs < 260
                                              ? Colors.amberAccent
                                              : Colors.orangeAccent);
                                    } else if (node.testState == NodeTestState.testing) {
                                      pingLabel = tr('Testing...', 'در حال تست...');
                                      badgeColor = Colors.white54;
                                    } else if (node.testState == NodeTestState.timeout) {
                                      pingLabel = 'Timeout';
                                      badgeColor = Colors.redAccent;
                                    } else {
                                      pingLabel = 'Failed';
                                      badgeColor = Colors.redAccent;
                                    }

                                    return Opacity(
                                      opacity: node.isHealthy ? 1.0 : 0.55,
                                      child: GestureDetector(
                                        onTap: !node.isHealthy
                                            ? null
                                            : () async {
                                                setState(() {
                                                  selectedServer = node;
                                                  currentMode = AppConnectionMode.vpnConfigs;
                                                });
                                                Navigator.pop(context);
                                                if (isConnected) {
                                                  await _disconnectEngine();
                                                  await Future.delayed(
                                                    const Duration(milliseconds: 300),
                                                  );
                                                }
                                                _handleConnectButton();
                                              },
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 10),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF1A2232)
                                                : const Color(0xFF141822),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFF00F5D4)
                                                  : Colors.white10,
                                              width: isSelected ? 1.5 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Text(node.flag, style: const TextStyle(fontSize: 24)),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      node.name,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                        color: Colors.white,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 7,
                                                            vertical: 2,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: Colors.white10,
                                                            borderRadius: BorderRadius.circular(5),
                                                          ),
                                                          child: Text(
                                                            node.protocol,
                                                            style: const TextStyle(
                                                              fontSize: 9,
                                                              color: Color(0xFF00F5D4),
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                        if (node.tcpPingMs > 0) ...[
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            'TCP: ${node.tcpPingMs}ms',
                                                            style: const TextStyle(
                                                              fontSize: 10,
                                                              color: Colors.white38,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: badgeColor.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      node.isHealthy
                                                          ? Icons.signal_cellular_alt_rounded
                                                          : (node.testState == NodeTestState.testing
                                                              ? Icons.hourglass_top_rounded
                                                              : Icons.error_outline_rounded),
                                                      color: badgeColor,
                                                      size: 14,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      pingLabel,
                                                      style: TextStyle(
                                                        color: badgeColor,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
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
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _activeSheetSetter = null;
    });
  }

  /// افزودن کانفیگ دستی با تست واقعی دو مرحله‌ای
  void _showAddCustomConfigDialog(StateSetter setSheetState) {
    final TextEditingController uriCtrl = TextEditingController();
    bool testing = false;
    String? errText;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF151924),
              title: Text(
                tr('Add & Verify Custom Config', 'افزودن و تست واقعی کانفیگ'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: uriCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'vless://, vmess://, trojan://, ss://',
                      filled: true,
                      fillColor: const Color(0xFF090B10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (errText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errText!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Cancel', 'انصراف')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: testing
                      ? null
                      : () async {
                          final String raw = uriCtrl.text.trim();
                          if (raw.isEmpty) return;
                          setDlgState(() {
                            testing = true;
                            errText = null;
                          });

                          try {
                            final String clean = _normalizeShareUri(raw);
                            final V2RayURL parser = V2ray.parseFromURL(clean);
                            final String baseJson = parser.getFullConfiguration();
                            final String fullCfg = _buildCustomizedXrayConfig(
                              baseJson,
                              isVipWebMode: false,
                            );

                            final int delay = await v2ray
                                .getServerDelay(config: fullCfg)
                                .timeout(const Duration(seconds: 4), onTimeout: () => -1);

                            if (delay <= 0) {
                              setDlgState(() {
                                testing = false;
                                errText = tr(
                                  'Verification failed (Timeout). Server is unreachable on your ISP.',
                                  'تست پینگ واقعی ناموفق بود (Timeout). این کانفیگ روی اینترنت شما پاسخ نمی‌دهد.',
                                );
                              });
                              return;
                            }

                            final newNode = ServerNode(
                              id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                              fingerprint: clean,
                              name: parser.remark.isNotEmpty ? parser.remark : 'Custom Verified Node',
                              flag: '⚡',
                              protocol: clean.split('://').first.toUpperCase(),
                              address: parser.address,
                              port: parser.port,
                              rawUri: clean,
                              baseConfigJson: baseJson,
                              realDelayMs: delay,
                              testState: NodeTestState.healthy,
                            );

                            setState(() {
                              _displayedNodes.insert(0, newNode);
                              _cachedHealthyNodes.insert(0, newNode);
                              selectedServer = newNode;
                              currentMode = AppConnectionMode.vpnConfigs;
                            });
                            setSheetState(() {});
                            if (mounted) Navigator.pop(context);
                          } catch (_) {
                            setDlgState(() {
                              testing = false;
                              errText = tr(
                                'Unsupported or invalid config format (Supported: VLESS, VMess, Trojan, SS).',
                                'فرمت کانفیگ نامعتبر است (پروتکل‌های پشتیبانی‌شده: VLESS, VMess, Trojan, SS).',
                              );
                            });
                          }
                        },
                  child: testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(tr('Verify & Add', 'تست و افزودن')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // ۵. پنجره تنظیمات موتور (بدون هیچ‌گونه نمایش آدرس DNS یا ورودی دستی)
  // ===========================================================================

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF10131C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Directionality(
              textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tr('ENGINE SETTINGS', 'تنظیمات موتور شبکه'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00F5D4),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF00F5D4),
                      title: Text(tr('Xray TLS Fragment', 'قطعه قطعه کردن پکت‌ها (TLS Fragment)')),
                      subtitle: Text(
                        tr(
                          'Splits TLS ClientHello (10-50B) to bypass DPI filtering',
                          'عبور از فیلترینگ SNI مخابرات بدون نیاز به نصب گواهی',
                        ),
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      value: enableTlsFragment,
                      onChanged: (v) {
                        setModalState(() => enableTlsFragment = v);
                        setState(() => enableTlsFragment = v);
                      },
                    ),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF00F5D4),
                      title: Text(tr('TCP No-Delay (Gaming Socket)', 'حذف تاخیر سوکت (TCP No-Delay)')),
                      subtitle: Text(
                        tr(
                          'Disables packet buffering for instant gaming response',
                          'ارسال آنی بسته‌های بازی بدون مکث در لایه شبکه',
                        ),
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      value: tcpNoDelay,
                      onChanged: (v) {
                        setModalState(() => tcpNoDelay = v);
                        setState(() => tcpNoDelay = v);
                      },
                    ),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF00F5D4),
                      title: Text(tr('Bypass Domestic Traffic (.ir)', 'عبور مستقیم ترافیک داخلی (.ir)')),
                      subtitle: Text(
                        tr(
                          'Routes domestic domains directly outside the tunnel',
                          'جلوگیری از افزایش پینگ در سایت‌ها و سرویس‌های داخلی',
                        ),
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      value: bypassIran,
                      onChanged: (v) {
                        setModalState(() => bypassIran = v);
                        setState(() => bypassIran = v);
                      },
                    ),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF00F5D4),
                      title: Text(tr('Strict Game-Only Filter (Configs Mode)', 'قفل سخت‌گیرانه وب در حالت گیم')),
                      subtitle: Text(
                        tr(
                          'Blocks TCP 80/443 in Configs Mode (VIP Mode always keeps web open)',
                          'مسدودسازی پورت‌های وب در حالت کانفیگ گیم (در حالت VIP وب همیشه باز است)',
                        ),
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      value: blockWebInGameMode,
                      onChanged: (v) {
                        setModalState(() => blockWebInGameMode = v);
                        setState(() => blockWebInGameMode = v);
                      },
                    ),

                    const Divider(color: Colors.white12),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.language_rounded, color: Color(0xFF00F5D4)),
                      title: Text(tr('App Language', 'زبان برنامه')),
                      trailing: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('EN')),
                          ButtonSegment(value: true, label: Text('فارسی')),
                        ],
                        selected: {isPersian},
                        onSelectionChanged: (val) {
                          setModalState(() => isPersian = val.first);
                          setState(() => isPersian = val.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // ۶. رابط کاربری اصلی (UI)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final Color primaryNeon = isConnected
        ? const Color(0xFF00F5D4)
        : (isConnecting ? Colors.amberAccent : const Color(0xFF7B2CBF));

    final String connectionStateLabel = isConnecting
        ? tr('Connecting', 'در حال اتصال')
        : (isConnected ? tr('Connected', 'متصل') : tr('Disconnected', 'قطع'));

    return Directionality(
      textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
            child: Column(
              children: [
                // ۱. هدر بالا
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NIVEXIA',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3.5,
                            color: Color(0xFF00F5D4),
                          ),
                        ),
                        Text(
                          tr('NETWORK TUNNEL & PING ENGINE', 'موتور تخصصی تونل و کاهش پینگ'),
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.1,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF151924),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: primaryNeon.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: primaryNeon,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                connectionStateLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF151924),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: IconButton(
                            onPressed: _openSettingsSheet,
                            icon: const Icon(Icons.tune_rounded, color: Color(0xFF00F5D4), size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // ۲. تب انتخاب ۳ حالت اصلی: VPN (Configs) | VPN (VIP) | Protected DNS
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131722),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      _buildModeTabButton(
                        mode: AppConnectionMode.vpnConfigs,
                        icon: Icons.sports_esports_rounded,
                        title: tr('Configs', 'کانفیگ گیم'),
                      ),
                      _buildModeTabButton(
                        mode: AppConnectionMode.vpnVip,
                        icon: Icons.workspace_premium_rounded,
                        title: tr('VIP Web', 'VIP وب‌گردی'),
                      ),
                      _buildModeTabButton(
                        mode: AppConnectionMode.dnsMode,
                        icon: Icons.shield_rounded,
                        title: tr('Gaming DNS', 'دی‌ان‌اس'),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ۳. دکمه پاور مرکزی
                GestureDetector(
                  onTap: _handleConnectButton,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final double glowSpread = isConnected
                          ? (6.0 + (_pulseController.value * 10.0))
                          : (2.0 + (_pulseController.value * 4.0));
                      return Container(
                        width: 215,
                        height: 215,
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
                                  ? Icons.close_rounded
                                  : Icons.power_settings_new_rounded,
                              size: 62,
                              color: primaryNeon,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              isConnecting
                                  ? tr('CONNECTING (TAP TO CANCEL)', 'در حال اتصال (لغو)')
                                  : (isConnected
                                      ? tr('CONNECTED', 'متصل شد')
                                      : tr('TAP TO CONNECT', 'شروع اتصال')),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: isConnected ? const Color(0xFF00F5D4) : Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              child: Text(
                                isConnected
                                    ? v2rayStatus.duration
                                    : _buildSubStatusText(),
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const Spacer(),

                // ۴. پنل مانیتورینگ زنده سرعت دانلود و آپلود
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
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
                                Text(
                                  tr('DOWNLOAD', 'دانلود'),
                                  style: const TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 1),
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
                        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
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
                                Text(
                                  tr('UPLOAD', 'آپلود'),
                                  style: const TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 1),
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

                const SizedBox(height: 12),

                // ۵. کارت پایین صفحه متناسب با حالت انتخابی (Configs / VIP / DNS)
                _buildBottomModeCard(),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildSubStatusText() {
    if (currentMode == AppConnectionMode.dnsMode) {
      return tr('Protected Gaming DNS Tunnel', 'تونل محافظت‌شده DNS گیمینگ');
    }
    if (currentMode == AppConnectionMode.vpnVip) {
      return tr('Xray Core + TLS Fragment Auto-Route', 'اتصال خودکار وب‌گردی (Xray + Fragment)');
    }
    if (isScanning && healthyNodes.isEmpty) {
      return tr('Scanning verified nodes...', 'در حال اسکن سرورهای سالم...');
    }
    if (selectedServer != null && selectedServer!.isHealthy) {
      return 'Real Delay: ${selectedServer!.realDelayMs} ms';
    }
    return tr('Tap Server Bar to select node', 'برای انتخاب سرور روی نوار پایین بزنید');
  }

  Widget _buildModeTabButton({
    required AppConnectionMode mode,
    required IconData icon,
    required String title,
  }) {
    final bool active = currentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          if (currentMode == mode) return;
          if (isConnected || isConnecting) {
            await _disconnectEngine();
          }
          setState(() => currentMode = mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1E2638) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: active
                ? Border.all(color: const Color(0xFF00F5D4).withOpacity(0.5))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: active ? const Color(0xFF00F5D4) : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  color: active ? Colors.white : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomModeCard() {
    // ۱. کارت پایین در حالت DNS (بدون نمایش آدرس IP؛ کاملاً مخفی)
    if (currentMode == AppConnectionMode.dnsMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
          color: const Color(0xFF151924),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: Color(0xFF00F5D4), size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Internal Anti-Sanction DNS', 'دی‌ان‌اس ضدتحریم داخلی نیوکسیا'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'One-Tap Connect • Primary & Secondary Protected Routing',
                      'اتصال تک‌کلیکی • مسیردهی خودکار اصلی و پشتیبان با محافظت از نشت DNS',
                    ),
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ۲. کارت پایین در حالت VIP (وب‌گردی خودکار بدون نیاز به انتخاب سرور)
    if (currentMode == AppConnectionMode.vpnVip) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
          color: const Color(0xFF151924),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFF00F5D4), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      'VIP Auto-Tunnel (Xray + TLS Fragment)',
                      'تونل خودکار VIP (مخصوص وب‌گردی بدون سرور دستی)',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'Automatically selects lowest-delay node with anti-DPI fragmentation',
                      'انتخاب خودکار سریع‌ترین سرور سالم با فرگمنت ضد فیلترینگ (${healthyNodes.length} سرور آماده)',
                    ),
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Refresh Pool', 'به‌روزرسانی سرورها'),
              onPressed: () => _startSmartConfigScan(forceRefresh: true),
              icon: isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F5D4)),
                    )
                  : const Icon(Icons.refresh_rounded, color: Color(0xFF00F5D4)),
            ),
          ],
        ),
      );
    }

    // ۳. کارت پایین در حالت کانفیگ‌های گیمینگ (انتخابگر سرور + دکمه رفرش مستقیم)
    return GestureDetector(
      onTap: _openServerListSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF151924),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Text(
              selectedServer?.flag ?? '🌐',
              style: const TextStyle(fontSize: 25),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedServer?.name ??
                        (isScanning
                            ? tr('Scanning Epodonios configs...', 'در حال اسکن کانفیگ‌های جدید...')
                            : tr('Select Gaming Server', 'انتخاب سرور گیمینگ')),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isScanning
                        ? scanStatusMessage
                        : tr(
                            '${healthyNodes.length} healthy nodes ready • Tap to switch',
                            '${healthyNodes.length} سرور سالم آماده • برای تغییر ضربه بزنید',
                          ),
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selectedServer != null && selectedServer!.isHealthy)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${selectedServer!.realDelayMs} ms',
                  style: const TextStyle(
                    color: Color(0xFF00F5D4),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr('Quick Refresh', 'رفرش سریع'),
              onPressed: () => _startSmartConfigScan(forceRefresh: true),
              icon: isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F5D4)),
                    )
                  : const Icon(Icons.refresh_rounded, color: Color(0xFF00F5D4), size: 20),
            ),
            const Icon(Icons.keyboard_arrow_up_rounded, color: Color(0xFF00F5D4)),
          ],
        ),
      ),
    );
  }
}
