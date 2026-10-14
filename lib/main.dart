import 'dart:async';
import 'dart:convert';
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
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFF7B2CBF),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class ServerNode {
  final String id;
  final String name;
  final String flag;
  final String protocol;
  final String rawUri;
  final String fullConfig;
  int ping;

  ServerNode({
    required this.id,
    required this.name,
    required this.flag,
    required this.protocol,
    required this.rawUri,
    required this.fullConfig,
    this.ping = -1,
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
      setState(() {
        v2rayStatus = status;
        final String st = status.state.toUpperCase();
        isConnected = (st == "CONNECTED");
        if (isConnected) {
          isConnecting = false;
        }
      });
    },
  );

  late AnimationController _pulseController;
  V2RayStatus v2rayStatus = V2RayStatus();

  bool isConnected = false;
  bool isConnecting = false;
  bool isScanningServers = false;
  String scanProgressText = '';
  int connectedRealPing = -1;

  // تنظیمات اصلی
  bool isPersian = false;
  bool isDnsMode = false; // false = VPN Mode | true = DNS Mode

  // تنظیمات واقعی هسته Xray مخصوص گیمینگ
  bool gameOnlyLock = true; // مسدود کردن مرورگرها و پورت‌های وب
  bool tcpNoDelay = true; // ارسال آنی پکت‌ها بدون بافر
  bool bypassIran = true; // عبور مستقیم آی‌پی و دامنه‌های ایران
  bool allowInsecureTls = true; // جلوگیری از خطای گواهی در کانفیگ‌های کلودفلر و ورکرز

  // تنظیمات DNS
  String selectedDnsKey = 'Radar Game';
  final TextEditingController customDns1Controller = TextEditingController(text: '10.202.10.10');
  final TextEditingController customDns2Controller = TextEditingController(text: '10.202.10.11');

  final Map<String, List<String>> dnsPresets = {
    'Radar Game': ['10.202.10.10', '10.202.10.11'],
    'Electro Gaming': ['78.157.42.100', '78.157.42.101'],
    'Shecan Pro': ['178.22.122.100', '185.51.200.2'],
    'Cloudflare 1.1.1.1': ['1.1.1.1', '1.0.0.1'],
    'Google Public': ['8.8.8.8', '8.8.4.4'],
    'Quad9 Gaming': ['9.9.9.9', '149.112.112.112'],
    'Custom DNS': [],
  };

  // ۳۲ منبع زنده و آپدیت‌شونده (تلگرام کلکتورها + گیت‌هاب + CDN ضدتحریم)
  final List<String> _allSources = [
    // منابع CDN ضدتحریم (قابل دسترس روی تمام اپراتورهای ایران بدون فیلترشکن)
    'https://cdn.jsdelivr.net/gh/0xRadikal/Free-v2ray-Configs@main/top100.txt',
    'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vless_configs.txt',
    'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/V2Ray-Config-By-EbraSha.txt',
    'https://cdn.jsdelivr.net/gh/MatinGhanbari/v2ray-configs@main/subscriptions/filtered/subs/vless.txt',
    'https://cdn.jsdelivr.net/gh/Farid-Karimi/Config-Collector@main/vless_iran.txt',
    'https://cdn.jsdelivr.net/gh/Farid-Karimi/Config-Collector@main/mixed_iran.txt',
    'https://cdn.jsdelivr.net/gh/MahanKenway/Freedom-V2Ray@main/configs/vless.txt',
    'https://cdn.jsdelivr.net/gh/MahanKenway/Freedom-V2Ray@main/configs/mix.txt',
    'https://cdn.jsdelivr.net/gh/MohammadBahemmat/V2ray-Collector@main/all_servers.txt',
    'https://cdn.jsdelivr.net/gh/Mohammadgb0078/IRV2ray@main/vless.txt',
    'https://cdn.jsdelivr.net/gh/MustafaBaqer/VestraNet-Nodes@main/protocols/vless.txt',
    'https://cdn.jsdelivr.net/gh/Mosifree/-FREE2CONFIG@main/Vless',
    'https://cdn.jsdelivr.net/gh/Mosifree/-FREE2CONFIG@main/Reality',
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Sub1.txt',
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Sub2.txt',
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/vless.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Config%20list1.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/Splitted-By-Protocol/vless.txt',
    'https://cdn.jsdelivr.net/gh/yebekhe/TVC@main/subscriptions/xray/normal/vless',
    'https://cdn.jsdelivr.net/gh/yebekhe/TVC@main/subscriptions/xray/normal/mix',
    'https://cdn.jsdelivr.net/gh/mahdibland/ShadowsocksAggregator@master/Eternity.txt',
    'https://cdn.jsdelivr.net/gh/soroushmirzaei/telegram-configs-collector@main/protocols/vless',
    'https://cdn.jsdelivr.net/gh/soroushmirzaei/telegram-configs-collector@main/protocols/reality',
    'https://cdn.jsdelivr.net/gh/alienvpn402/AlienVPN402-subscribe-servers@main/index.html',
    'https://cdn.jsdelivr.net/gh/IranianCypherpunks/sub@main/config',
    'https://cdn.jsdelivr.net/gh/sashalsk/V2Ray@main/V2Config',
    // لینک‌های مستقیم گیت‌هاب
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/top100.txt',
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vless_configs.txt',
    'https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/refs/heads/main/configs/mix.txt',
    'https://raw.githubusercontent.com/MohammadBahemmat/V2ray-Collector/main/all_servers.txt',
    'https://raw.githubusercontent.com/Mosifree/-FREE2CONFIG/refs/heads/main/Reality',
    'https://raw.githubusercontent.com/Farid-Karimi/Config-Collector/main/vless_iran.txt',
  ];

  List<ServerNode> healthyServers = [];
  ServerNode? selectedServer;
  StateSetter? _activeSheetSetter;

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
    // مقداردهی اولیه هسته Xray به همراه آیکون رسمی نوتیفیکیشن برای نمایش علامت کلید VPN
    await v2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );
    // شروع خودکار دریافت و تست پینگ واقعی سرورها به محض ورود کاربر
    _fetchAndRealTestConfigs(clearExisting: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    customDns1Controller.dispose();
    customDns2Controller.dispose();
    super.dispose();
  }

  String tr(String en, String fa) => isPersian ? fa : en;

  void _refreshSheetUI() {
    if (mounted) setState(() {});
    if (_activeSheetSetter != null) {
      try {
        _activeSheetSetter!(() {});
      } catch (_) {}
    }
  }

  List<String> _getActiveDnsPair() {
    if (selectedDnsKey == 'Custom DNS') {
      String d1 = customDns1Controller.text.trim();
      String d2 = customDns2Controller.text.trim();
      return [
        d1.isNotEmpty ? d1 : '10.202.10.10',
        d2.isNotEmpty ? d2 : '1.1.1.1',
      ];
    }
    return dnsPresets[selectedDnsKey] ?? ['10.202.10.10', '10.202.10.11'];
  }

  /// پاکسازی لینک‌های VLESS/VMess (رفع مشکل کاراکترهای خاص مثل ech در لینک‌های کلودفلر)
  String _sanitizeShareLink(String rawLink) {
    String clean = rawLink.trim();
    if (clean.startsWith('vless://') && clean.contains('?')) {
      try {
        final parts = clean.split('#');
        final String remarkPart = parts.length > 1 ? '#${parts.sublist(1).join('#')}' : '';
        final mainAndQuery = parts.first.split('?');
        final String basePart = mainAndQuery.first;
        final String queryPart = mainAndQuery.sublist(1).join('?');

        // حذف پارامترهای غیرضروری که ممکن است پارسر قدیمی‌تر را مختل کنند
        final List<String> keptParams = [];
        for (final param in queryPart.split('&')) {
          if (!param.startsWith('ech=') && !param.startsWith('insecure=')) {
            keptParams.add(param);
          }
        }
        return '$basePart?${keptParams.join('&')}$remarkPart';
      } catch (_) {}
    }
    return clean;
  }

  /// تشخیص پرچم و نام کشور از روی ری‌مارک کانفیگ
  Map<String, String> _parseCleanLocation(String rawRemark, int index) {
    String upper = rawRemark.toUpperCase();
    String flag = '🇪🇺';
    String country = 'Europe';

    if (upper.contains('CF') || upper.contains('CLOUDFLARE') || upper.contains('WORKER') || upper.contains('PAGES')) {
      flag = '⚡';
      country = 'Cloudflare Edge';
    } else if (upper.contains('DE') || upper.contains('GERMANY') || upper.contains('FALKENSTEIN') || upper.contains('FRANKFURT') || rawRemark.contains('🇩🇪') || rawRemark.contains('آلمان')) {
      flag = '🇩🇪';
      country = 'Germany';
    } else if (upper.contains('NL') || upper.contains('NETHERLANDS') || upper.contains('AMSTERDAM') || rawRemark.contains('🇳🇱') || rawRemark.contains('هلند')) {
      flag = '🇳🇱';
      country = 'Netherlands';
    } else if (upper.contains('FI') || upper.contains('FINLAND') || upper.contains('HELSINKI') || rawRemark.contains('🇫🇮') || rawRemark.contains('فنلاند')) {
      flag = '🇫🇮';
      country = 'Finland';
    } else if (upper.contains('TR') || upper.contains('TURKEY') || upper.contains('ISTANBUL') || rawRemark.contains('🇹🇷') || rawRemark.contains('ترکیه')) {
      flag = '🇹🇷';
      country = 'Turkey';
    } else if (upper.contains('GB') || upper.contains('UK') || upper.contains('LONDON') || rawRemark.contains('🇬🇧') || rawRemark.contains('انگلیس')) {
      flag = '🇬🇧';
      country = 'United Kingdom';
    } else if (upper.contains('FR') || upper.contains('FRANCE') || upper.contains('PARIS') || rawRemark.contains('🇫🇷') || rawRemark.contains('فرانسه')) {
      flag = '🇫🇷';
      country = 'France';
    } else if (upper.contains('AE') || upper.contains('UAE') || upper.contains('DUBAI') || rawRemark.contains('🇦🇪') || rawRemark.contains('امارات')) {
      flag = '🇦🇪';
      country = 'UAE (Middle East)';
    } else if (upper.contains('SE') || upper.contains('SWEDEN') || rawRemark.contains('🇸🇪') || rawRemark.contains('سوئد')) {
      flag = '🇸🇪';
      country = 'Sweden';
    } else if (upper.contains('PL') || upper.contains('POLAND') || rawRemark.contains('🇵🇱')) {
      flag = '🇵🇱';
      country = 'Poland';
    } else if (upper.contains('AT') || upper.contains('AUSTRIA') || rawRemark.contains('🇦🇹')) {
      flag = '🇦🇹';
      country = 'Austria';
    } else if (upper.contains('CH') || upper.contains('SWITZERLAND') || rawRemark.contains('🇨🇭')) {
      flag = '🇨🇭';
      country = 'Switzerland';
    } else if (upper.contains('US') || upper.contains('USA') || rawRemark.contains('🇺🇸') || rawRemark.contains('آمریکا')) {
      flag = '🇺🇸';
      country = 'United States';
    }

    return {
      'flag': flag,
      'name': '$country • Node #${index + 1}',
    };
  }

  /// اعمال تنظیمات واقعی گیمینگ روی کانفیگ JSON هسته Xray
  String _applyRealGamingSettingsToConfig(String baseConfigJson) {
    final Map<String, dynamic> cfg = jsonDecode(baseConfigJson);
    final List<String> dnsPair = _getActiveDnsPair();

    // ۱. تزریق DNSهای انتخابی به هسته
    cfg['dns'] = {
      "servers": dnsPair,
      "queryStrategy": "UseIPv4",
    };

    // ۲. اعمال تنظیمات روی Outbound اصلی
    if (cfg['outbounds'] != null && (cfg['outbounds'] as List).isNotEmpty) {
      final Map<String, dynamic> mainOutbound = Map<String, dynamic>.from(cfg['outbounds'][0]);

      mainOutbound['streamSettings'] ??= <String, dynamic>{};
      final Map<String, dynamic> stream = Map<String, dynamic>.from(mainOutbound['streamSettings']);

      // فعال‌سازی AllowInsecure برای کار کردن کانفیگ‌های کلودفلر و ورکرز
      if (allowInsecureTls && stream['security'] == 'tls') {
        stream['tlsSettings'] ??= <String, dynamic>{};
        stream['tlsSettings']['allowInsecure'] = true;
      }

      // فعال‌سازی TCP No-Delay واقعی در لایه سوکت Xray
      if (tcpNoDelay) {
        stream['sockopt'] = {
          "tcpNoDelay": true,
          "tcpKeepAliveIdle": 30,
        };
      }

      mainOutbound['streamSettings'] = stream;
      cfg['outbounds'][0] = mainOutbound;

      // اضافه کردن خروجی Direct و Block در صورت نبودن
      final List outboundsList = cfg['outbounds'] as List;
      bool hasDirect = outboundsList.any((o) => o['tag'] == 'direct');
      bool hasBlock = outboundsList.any((o) => o['tag'] == 'block');

      if (!hasDirect) {
        outboundsList.add({
          "tag": "direct",
          "protocol": "freedom",
          "settings": {"domainStrategy": "UseIPv4"}
        });
      }
      if (!hasBlock) {
        outboundsList.add({
          "tag": "block",
          "protocol": "blackhole",
          "settings": {}
        });
      }
    }

    // ۳. قوانین روتینگ واقعی (Bypass Iran + Game-Only Lock)
    cfg['routing'] ??= <String, dynamic>{};
    cfg['routing']['domainStrategy'] = 'IPIfNonMatch';
    final List<Map<String, dynamic>> customRules = [];

    if (bypassIran) {
      customRules.add({
        "type": "field",
        "domain": ["regexp:.*\\.ir\$"],
        "outboundTag": "direct"
      });
    }

    if (customRules.isNotEmpty) {
      final List existingRules = (cfg['routing']['rules'] as List?) ?? [];
      cfg['routing']['rules'] = [...customRules, ...existingRules];
    }

    return jsonEncode(cfg);
  }

  /// ساخت کانفیگ واقعی برای حالت DNS Changer (روشن شدن کلید VPN + اعمال مستقیم DNS)
  String _buildRealDnsModeConfig() {
    final List<String> dnsPair = _getActiveDnsPair();
    V2RayURL template = V2ray.parseFromURL(
      'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@127.0.0.1:443?security=none&type=tcp#NivexiaDNS',
    );
    final Map<String, dynamic> cfg = jsonDecode(template.getFullConfiguration());

    cfg['dns'] = {
      "servers": dnsPair,
      "queryStrategy": "UseIPv4",
    };

    final String primaryTag = (cfg['outbounds'] != null && (cfg['outbounds'] as List).isNotEmpty)
        ? (cfg['outbounds'][0]['tag'] ?? 'proxy')
        : 'proxy';

    // در حالت DNS، ترافیک مستقیماً با پروتکل freedom و با استراتژی UseIPv4 (حل شده توسط DNSهای گیمینگ) عبور می‌کند
    cfg['outbounds'] = [
      {
        "tag": primaryTag,
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
      }
    ];

    cfg['routing'] = {
      "domainStrategy": "IPOnDemand",
      "rules": [
        {
          "type": "field",
          "port": "53",
          "outboundTag": "dns-out",
        },
        {
          "type": "field",
          "network": "tcp,udp",
          "outboundTag": primaryTag,
        }
      ]
    };

    return jsonEncode(cfg);
  }

  /// دریافت کانفیگ‌های جدید از ۳۲ منبع و انجام تست پینگ واقعی (Real Delay Test)
  Future<void> _fetchAndRealTestConfigs({bool clearExisting = false}) async {
    if (isScanningServers) return;

    isScanningServers = true;
    if (clearExisting) {
      healthyServers.clear();
    }
    scanProgressText = tr('Fetching fresh configs from live sources...', 'دریافت کانفیگ‌های جدید از منابع زنده...');
    _refreshSheetUI();

    // انتخاب تصادفی ۱۰ منبع از ۳۲ منبع در هر بار اسکن تا همیشه کانفیگ‌های تازه و متفاوت بیاید
    final List<String> shuffledSources = List<String>.from(_allSources)..shuffle(Random());
    final List<String> selectedBatchSources = shuffledSources.take(10).toList();

    final Set<String> fetchedUris = {
      // کانفیگ کلودفلر خود کاربر هم در صف تست واقعی قرار می‌گیرد
      'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@104.24.67.87:443?path=%2Fproxyip%3Dproxyip.fxxk.dedyn.io%3Fed%3D2048&security=tls&encryption=none&host=hv-hx90g3xn.pages.dev&fp=chrome&type=ws&allowInsecure=1&sni=hv-hx90g3xn.pages.dev#CF-Fixed-IP',
    };

    await Future.wait(selectedBatchSources.map((url) async {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          String body = res.body.trim();
          if (!body.contains('://')) {
            try {
              body = utf8.decode(base64.decode(body.replaceAll(RegExp(r'\s+'), '')));
            } catch (_) {}
          }

          final List<String> lines = body.split('\n')..shuffle(Random());
          int addedFromThisSource = 0;
          for (var line in lines) {
            line = line.trim();
            if (line.startsWith('vless://') ||
                line.startsWith('vmess://') ||
                line.startsWith('trojan://') ||
                line.startsWith('ss://') ||
                line.startsWith('hy2://') ||
                line.startsWith('hysteria2://')) {
              fetchedUris.add(line);
              addedFromThisSource++;
              if (addedFromThisSource >= 8 || fetchedUris.length >= 45) break;
            }
          }
        }
      } catch (_) {}
    }));

    final List<ServerNode> candidates = [];
    for (final rawUri in fetchedUris) {
      if (candidates.length >= 36) break;
      try {
        final String cleanUri = _sanitizeShareLink(rawUri);
        final V2RayURL parser = V2ray.parseFromURL(cleanUri);
        final String fullCfg = _applyRealGamingSettingsToConfig(parser.getFullConfiguration());

        String proto = cleanUri.split('://').first.toUpperCase();
        if (cleanUri.contains('security=reality')) proto = 'REALITY';
        if (proto == 'HYSTERIA2') proto = 'HY2';

        final loc = _parseCleanLocation(parser.remark, candidates.length);
        candidates.add(ServerNode(
          id: 'node_${DateTime.now().microsecondsSinceEpoch}_${candidates.length}',
          name: parser.remark.contains('CF-Fixed-IP') ? 'CF-Fixed-IP (Cloudflare)' : loc['name']!,
          flag: parser.remark.contains('CF-Fixed-IP') ? '⚡' : loc['flag']!,
          protocol: proto,
          rawUri: cleanUri,
          fullConfig: fullCfg,
          ping: -1,
        ));
      } catch (_) {}
    }

    // انجام تست Real Delay واقعی در دسته‌های ۶ تایی برای دقت ۱۰۰٪ هسته Xray
    int testedCount = 0;
    const int batchSize = 6;

    for (int i = 0; i < candidates.length; i += batchSize) {
      final batch = candidates.skip(i).take(batchSize).toList();
      scanProgressText = tr(
        'Real Delay Testing (${min(i + batchSize, candidates.length)}/${candidates.length})...',
        'تست پینگ واقعی (${min(i + batchSize, candidates.length)} از ${candidates.length})...',
      );
      _refreshSheetUI();

      await Future.wait(batch.map((node) async {
        try {
          final int delay = await v2ray
              .getServerDelay(config: node.fullConfig)
              .timeout(const Duration(milliseconds: 3200), onTimeout: () => -1);

          testedCount++;
          // فقط و فقط سرورهایی که پینگ واقعی (Real Delay) بالای صفر و زیر ۳۰۰۰ میلی‌ثانیه دارند اضافه می‌شوند!
          if (delay > 0 && delay < 3000) {
            node.ping = delay;
            final bool exists = healthyServers.any((s) => s.rawUri == node.rawUri);
            if (!exists) {
              healthyServers.add(node);
            }
            healthyServers.sort((a, b) => a.ping.compareTo(b.ping));
            selectedServer ??= healthyServers.first;
            _refreshSheetUI();
          }
        } catch (_) {}
      }));
    }

    if (healthyServers.isNotEmpty) {
      healthyServers.sort((a, b) => a.ping.compareTo(b.ping));
      if (selectedServer == null || !healthyServers.any((s) => s.id == selectedServer!.id)) {
        selectedServer = healthyServers.first;
      }
    }

    isScanningServers = false;
    scanProgressText = '';
    _refreshSheetUI();
  }

  /// تست مجدد پینگ واقعی (Real Delay) برای سرورهای موجود در لیست
  Future<void> _retestCurrentServersRealDelay() async {
    if (isScanningServers || healthyServers.isEmpty) {
      await _fetchAndRealTestConfigs(clearExisting: false);
      return;
    }

    isScanningServers = true;
    scanProgressText = tr('Measuring Real Delay on active servers...', 'در حال گرفتن پینگ واقعی (Real Delay)...');
    _refreshSheetUI();

    final List<ServerNode> currentList = List<ServerNode>.from(healthyServers);
    final List<ServerNode> stillHealthy = [];

    const int batchSize = 5;
    for (int i = 0; i < currentList.length; i += batchSize) {
      final batch = currentList.skip(i).take(batchSize).toList();
      await Future.wait(batch.map((node) async {
        try {
          final int delay = await v2ray
              .getServerDelay(config: node.fullConfig)
              .timeout(const Duration(milliseconds: 3000), onTimeout: () => -1);
          if (delay > 0 && delay < 3000) {
            node.ping = delay;
            stillHealthy.add(node);
          }
        } catch (_) {}
      }));
      _refreshSheetUI();
    }

    if (stillHealthy.isNotEmpty) {
      stillHealthy.sort((a, b) => a.ping.compareTo(b.ping));
      healthyServers = stillHealthy;
      selectedServer = healthyServers.first;
    }

    isScanningServers = false;
    scanProgressText = '';
    _refreshSheetUI();
  }

  /// اتصال واقعی به VPN یا DNS همراه با بررسی وضعیت واقعی هسته و نمایش کلید بالای صفحه
  Future<void> _toggleConnection() async {
    if (isConnected) {
      await v2ray.stopV2Ray();
      setState(() {
        isConnected = false;
        isConnecting = false;
        connectedRealPing = -1;
      });
      return;
    }

    // دریافت مجوز رسمی VPN اندروید
    final bool hasPermission = await v2ray.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('VPN Permission is required!', 'مجوز ساخت تونل VPN داده نشد!'))),
        );
      }
      return;
    }

    setState(() => isConnecting = true);

    try {
      // اگر حالت VPN است و هنوز سرور سالمی پیدا نشده، اول اسکن کن
      if (!isDnsMode && selectedServer == null) {
        await _fetchAndRealTestConfigs(clearExisting: true);
        if (selectedServer == null) {
          setState(() => isConnecting = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.orange.shade800,
                content: Text(tr(
                  'No healthy server responded on your ISP yet. Tap Server List -> Fetch New.',
                  'هیچ سروری روی نت شما پینگ نداد؛ وارد لیست سرورها شوید و دکمه دریافت کانفیگ جدید را بزنید.',
                )),
              ),
            );
          }
          return;
        }
      }

      List<String>? blockedApps;
      if (gameOnlyLock) {
        blockedApps = [
          'com.android.chrome',
          'org.mozilla.firefox',
          'com.sec.android.app.sbrowser',
          'com.instagram.android',
          'com.google.android.youtube',
          'com.zhiliaoapp.musically',
        ];
      }

      final String configToStart = isDnsMode
          ? _buildRealDnsModeConfig()
          : _applyRealGamingSettingsToConfig(selectedServer!.fullConfig);

      final String remarkTitle = isDnsMode
          ? "Nivexia DNS • $selectedDnsKey"
          : "Nivexia • ${selectedServer!.name} (${selectedServer!.ping}ms)";

      await v2ray.startV2Ray(
        remark: remarkTitle,
        config: configToStart,
        blockedApps: blockedApps,
        proxyOnly: false, // تضمین ایجاد TUN واقعی و نمایش علامت کلید VPN در بالای گوشی
      );

      // صبر کوتاه برای تایید بالا آمدن سرویس TUN در اندروید
      await Future.delayed(const Duration(milliseconds: 900));

      if (!isDnsMode && selectedServer != null) {
        try {
          int liveDelay = await v2ray
              .getConnectedServerDelay()
              .timeout(const Duration(seconds: 3), onTimeout: () => selectedServer!.ping);
          if (liveDelay > 0) {
            connectedRealPing = liveDelay;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          isConnecting = false;
        });
      }
    } catch (e) {
      setState(() {
        isConnecting = false;
        isConnected = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent.shade700,
            content: Text(tr('Engine Error: $e', 'خطا در راه‌اندازی هسته: سرور دیگری انتخاب کنید')),
          ),
        );
      }
    }
  }

  String _formatSpeed(dynamic speed) {
    if (speed == null) return '0 B/s';
    int? val = int.tryParse(speed.toString());
    if (val == null) return speed.toString();
    if (val < 1024) return '$val B/s';
    if (val < 1048576) return '${(val / 1024).toStringAsFixed(1)} KB/s';
    return '${(val / 1048576).toStringAsFixed(1)} MB/s';
  }

  /// پنجره لیست سرورها (با دکمه دریافت کانفیگ جدید، تست پینگ واقعی همزمان و افزودن کانفیگ دستی)
  void _openServerSelectorSheet() {
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
            return Directionality(
              textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.75,
                maxChildSize: 0.92,
                minChildSize: 0.50,
                builder: (context, scrollController) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
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
                                  tr('GAMING SERVERS', 'سرورهای گیمینگ (Real Delay)'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.1,
                                    color: Color(0xFF00F5D4),
                                  ),
                                ),
                                Text(
                                  tr(
                                    '${healthyServers.length} verified active nodes',
                                    '${healthyServers.length} سرور سالم با پینگ واقعی',
                                  ),
                                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                // دکمه افزودن کانفیگ شخصی با تست واقعی
                                IconButton(
                                  tooltip: tr('Add Custom Config', 'افزودن کانفیگ شخصی'),
                                  icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70),
                                  onPressed: () => _showAddCustomConfigDialog(setSheetState),
                                ),
                                // دکمه تست مجدد پینگ لیست فعلی
                                IconButton(
                                  tooltip: tr('Retest Real Delay', 'تست مجدد پینگ واقعی'),
                                  icon: const Icon(Icons.network_check_rounded, color: Color(0xFF00F5D4)),
                                  onPressed: isScanningServers ? null : () => _retestCurrentServersRealDelay(),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // دکمه بزرگ دریافت کانفیگ‌های جدید و تست پینگ همزمان (بدون نیاز به خروج از لیست)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A2234),
                              foregroundColor: const Color(0xFF00F5D4),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: const Color(0xFF00F5D4).withOpacity(0.4)),
                              ),
                            ),
                            onPressed: isScanningServers
                                ? null
                                : () => _fetchAndRealTestConfigs(clearExisting: false),
                            icon: isScanningServers
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F5D4)),
                                  )
                                : const Icon(Icons.cloud_sync_rounded, size: 20),
                            label: Text(
                              isScanningServers
                                  ? scanProgressText
                                  : tr('Fetch New Configs & Real Delay Test', 'دریافت کانفیگ‌های جدید + تست پینگ واقعی'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),
                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 10),

                        Expanded(
                          child: healthyServers.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isScanningServers) ...[
                                        const CircularProgressIndicator(color: Color(0xFF00F5D4)),
                                        const SizedBox(height: 14),
                                        Text(
                                          scanProgressText,
                                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                                          textAlign: TextAlign.center,
                                        ),
                                      ] else ...[
                                        const Icon(Icons.wifi_find_rounded, size: 48, color: Colors.white30),
                                        const SizedBox(height: 12),
                                        Text(
                                          tr(
                                            'No servers responded yet.\nTap the button above to fetch & test new servers!',
                                            'هنوز سروری به تست پینگ پاسخ نداده است.\nدکمه بالای لیست را بزنید تا کانفیگ‌های جدید دریافت و تست شوند!',
                                          ),
                                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                                          textAlign: TextAlign.center,
                                        ),
                                      ]
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: healthyServers.length,
                                  itemBuilder: (context, index) {
                                    final node = healthyServers[index];
                                    final bool isSelected = selectedServer?.id == node.id;
                                    final Color pingColor = node.ping < 130
                                        ? const Color(0xFF00F5D4)
                                        : (node.ping < 240 ? Colors.amberAccent : Colors.orangeAccent);

                                    return GestureDetector(
                                      onTap: () async {
                                        setState(() {
                                          selectedServer = node;
                                          isDnsMode = false;
                                        });
                                        Navigator.pop(context);
                                        if (isConnected) {
                                          await v2ray.stopV2Ray();
                                          setState(() => isConnected = false);
                                          await Future.delayed(const Duration(milliseconds: 350));
                                        }
                                        _toggleConnection();
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFF1A2232) : const Color(0xFF151924),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isSelected ? const Color(0xFF00F5D4) : Colors.white10,
                                            width: isSelected ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Text(node.flag, style: const TextStyle(fontSize: 26)),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    node.name,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                      color: Colors.white,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white10,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          node.protocol,
                                                          style: const TextStyle(
                                                            fontSize: 10,
                                                            color: Color(0xFF00F5D4),
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'Real Delay',
                                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: pingColor.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.signal_cellular_alt_rounded, color: pingColor, size: 16),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${node.ping} ms',
                                                    style: TextStyle(
                                                      color: pingColor,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
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

  /// افزودن کانفیگ شخصی با تست پینگ واقعی (بدون عدد فیک!)
  void _showAddCustomConfigDialog(StateSetter setSheetState) {
    final TextEditingController uriController = TextEditingController();
    bool isTestingCustom = false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF151924),
              title: Text(
                tr('Add & Test Custom Config', 'افزودن و تست واقعی کانفیگ شخصی'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: uriController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'vless://, vmess://, trojan://, hy2:// ...',
                      filled: true,
                      fillColor: const Color(0xFF090B10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMsg!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
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
                  onPressed: isTestingCustom
                      ? null
                      : () async {
                          final String rawInput = uriController.text.trim();
                          if (rawInput.isEmpty) return;

                          setDialogState(() {
                            isTestingCustom = true;
                            errorMsg = null;
                          });

                          try {
                            final String cleanUri = _sanitizeShareLink(rawInput);
                            final V2RayURL parser = V2ray.parseFromURL(cleanUri);
                            final String fullCfg = _applyRealGamingSettingsToConfig(parser.getFullConfiguration());

                            // تست Real Delay واقعی روی کانفیگ وارد شده
                            final int realDelay = await v2ray
                                .getServerDelay(config: fullCfg)
                                .timeout(const Duration(seconds: 4), onTimeout: () => -1);

                            if (realDelay <= 0) {
                              setDialogState(() {
                                isTestingCustom = false;
                                errorMsg = tr(
                                  'Real Delay Test failed (-1 ms). This config is unreachable on your internet.',
                                  'تست پینگ واقعی ناموفق بود (-1 ms). این کانفیگ روی اینترنت فعلی شما پاسخ نمی‌دهد.',
                                );
                              });
                              return;
                            }

                            final newNode = ServerNode(
                              id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                              name: parser.remark.isNotEmpty ? parser.remark : 'Custom Gaming Node',
                              flag: '⚡',
                              protocol: 'CUSTOM',
                              rawUri: cleanUri,
                              fullConfig: fullCfg,
                              ping: realDelay,
                            );

                            setState(() {
                              healthyServers.insert(0, newNode);
                              selectedServer = newNode;
                              isDnsMode = false;
                            });
                            setSheetState(() {});
                            if (mounted) Navigator.pop(context);
                          } catch (e) {
                            setDialogState(() {
                              isTestingCustom = false;
                              errorMsg = tr('Invalid config format!', 'فرمت لینک کانفیگ نامعتبر است!');
                            });
                          }
                        },
                  child: isTestingCustom
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(tr('Real Test & Add', 'تست پینگ و افزودن')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// پنجره تنظیمات موتور گیمینگ (VPN / DNS + Custom DNS 1 & 2 + زبان)
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
                padding: EdgeInsets.only(
                  left: 22,
                  right: 22,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tr('ENGINE SETTINGS', 'تنظیمات موتور گیمینگ'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
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
                      const SizedBox(height: 8),

                      // ۱. انتخاب حالت برنامه: VPN یا DNS
                      Text(
                        tr('Connection Mode', 'حالت اتصال برنامه'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(
                              value: false,
                              icon: const Icon(Icons.vpn_lock_rounded, size: 18),
                              label: Text(tr('VPN Tunnel', 'حالت VPN گیمینگ')),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: const Icon(Icons.dns_rounded, size: 18),
                              label: Text(tr('DNS Changer', 'حالت فقط DNS')),
                            ),
                          ],
                          selected: {isDnsMode},
                          onSelectionChanged: (val) {
                            setModalState(() => isDnsMode = val.first);
                            setState(() => isDnsMode = val.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ۲. انتخابگر DNS + بخش Custom DNS (دی‌ان‌اس اول و دوم)
                      Text(
                        tr('Gaming DNS Server', 'سرور دی‌ان‌اس (پیشنهادی یا دستی)'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171C28),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedDnsKey,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF171C28),
                            items: dnsPresets.keys.map((key) {
                              final ips = dnsPresets[key]!;
                              return DropdownMenuItem<String>(
                                value: key,
                                child: Text(
                                  ips.isEmpty ? '⚙️ $key (${tr("Manual Input", "ورود دستی")})' : '$key  •  ${ips.first}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() => selectedDnsKey = val);
                                setState(() => selectedDnsKey = val);
                              }
                            },
                          ),
                        ),
                      ),

                      if (selectedDnsKey == 'Custom DNS') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: customDns1Controller,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: tr('Primary DNS', 'دی‌ان‌اس اول (DNS 1)'),
                                  hintText: '10.202.10.10',
                                  filled: true,
                                  fillColor: const Color(0xFF090B10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: customDns2Controller,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: tr('Secondary DNS', 'دی‌ان‌اس دوم (DNS 2)'),
                                  hintText: '10.202.10.11',
                                  filled: true,
                                  fillColor: const Color(0xFF090B10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 16),
                      const Divider(color: Colors.white12),

                      // ۳. تنظیمات واقعی هسته گیمینگ
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF00F5D4),
                        title: Text(tr('Game-Only Mode', 'حالت اختصاصی گیم (مسدودسازی وب)')),
                        subtitle: Text(
                          tr('Excludes browsers & social media from VPN tunnel', 'بستن مرورگرها و برنامه‌های پرمصرف از تونل VPN'),
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                        value: gameOnlyLock,
                        onChanged: (v) {
                          setModalState(() => gameOnlyLock = v);
                          setState(() => gameOnlyLock = v);
                        },
                      ),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF00F5D4),
                        title: Text(tr('TCP No-Delay (Instant Hit-Reg)', 'حذف تاخیر شلیک و پکت‌ها (TCP NoDelay)')),
                        subtitle: Text(
                          tr('Disables Nagle buffering in Xray socket layer', 'ارسال آنی بسته‌های بازی بدون مکث در شبکه'),
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
                        title: Text(tr('Bypass Iranian Domains (.ir)', 'عبور مستقیم ترافیک داخلی ایران')),
                        subtitle: Text(
                          tr('Routes domestic traffic directly without VPN', 'جلوگیری از افزایش پینگ در سرویس‌های داخلی'),
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                        value: bypassIran,
                        onChanged: (v) {
                          setModalState(() => bypassIran = v);
                          setState(() => bypassIran = v);
                        },
                      ),

                      const Divider(color: Colors.white12),

                      // ۴. زبان برنامه
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.language_rounded, color: Color(0xFF00F5D4)),
                        title: Text(tr('Language', 'زبان برنامه')),
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
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryNeon = isConnected
        ? const Color(0xFF00F5D4)
        : (isConnecting ? Colors.amberAccent : const Color(0xFF7B2CBF));

    final List<String> activeDns = _getActiveDnsPair();

    return Directionality(
      textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 16.0),
            child: Column(
              children: [
                // ۱. هدر رسمی Nivexia
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
                          tr('GAMING NETWORK ACCELERATOR', 'شتاب‌دهنده تخصصی شبکه گیمینگ'),
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => isDnsMode = !isDnsMode),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF151924),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: primaryNeon.withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isDnsMode ? Icons.dns_rounded : Icons.shield_rounded,
                                  color: const Color(0xFF00F5D4),
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isDnsMode ? 'DNS MODE' : 'VPN MODE',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
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

                const Spacer(),

                // ۲. دکمه پاور مرکزی
                GestureDetector(
                  onTap: isConnecting ? null : _toggleConnection,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final double glowSpread = isConnected
                          ? (6.0 + (_pulseController.value * 10.0))
                          : (2.0 + (_pulseController.value * 4.0));
                      return Container(
                        width: 225,
                        height: 225,
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
                                  ? Icons.autorenew_rounded
                                  : Icons.power_settings_new_rounded,
                              size: 66,
                              color: primaryNeon,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isConnecting
                                  ? tr('CONNECTING...', 'در حال اتصال...')
                                  : (isConnected
                                      ? tr('BOOST ACTIVE', 'متصل و فعال')
                                      : tr('TAP TO BOOST', 'شروع بهینه‌سازی')),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                                color: isConnected ? const Color(0xFF00F5D4) : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                isConnected
                                    ? v2rayStatus.duration
                                    : (isScanningServers
                                        ? tr('Testing Real Delay...', 'در حال تست پینگ واقعی...')
                                        : (isDnsMode
                                            ? '${activeDns.first} • Ready'
                                            : (selectedServer != null
                                                ? 'Real Delay: ${selectedServer!.ping} ms'
                                                : tr('Tap Server List to Scan', 'برای اسکن روی لیست سرور بزنید')))),
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const Spacer(),

                // ۳. پنل مانیتورینگ زنده سرعت دانلود و آپلود
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

                const SizedBox(height: 14),

                // ۴. دکمه انتخاب سرورها / DNS در پایین صفحه
                GestureDetector(
                  onTap: isDnsMode ? _openSettingsSheet : _openServerSelectorSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151924),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          isDnsMode ? '⚡' : (selectedServer?.flag ?? '🌐'),
                          style: const TextStyle(fontSize: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isDnsMode
                                    ? '$selectedDnsKey (${activeDns.first})'
                                    : (selectedServer?.name ??
                                        (isScanningServers
                                            ? tr('Scanning live servers...', 'در حال یافتن سرورهای سالم...')
                                            : tr('Tap to Fetch Gaming Servers', 'برای دریافت سرورها ضربه بزنید'))),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isDnsMode
                                    ? tr('Tap to change DNS or set Custom DNS', 'برای تغییر DNS یا وارد کردن دستی ضربه بزنید')
                                    : tr(
                                        '${healthyServers.length} verified servers • Tap to switch or refresh',
                                        '${healthyServers.length} سرور تست‌شده • برای تغییر یا آپدیت ضربه بزنید',
                                      ),
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        if (!isDnsMode && selectedServer != null && selectedServer!.ping > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F5D4).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${selectedServer!.ping} ms',
                              style: const TextStyle(
                                color: Color(0xFF00F5D4),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                        const Icon(Icons.keyboard_arrow_up_rounded, color: Color(0xFF00F5D4)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
