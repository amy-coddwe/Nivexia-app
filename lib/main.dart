import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
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
  late final FlutterV2ray flutterV2ray = FlutterV2ray(
    onStatusChanged: (status) {
      if (!mounted) return;
      setState(() {
        v2rayStatus = status;
        isConnected = (status.state == "CONNECTED");
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

  // تنظیمات اصلی برنامه
  bool isPersian = false;
  bool isDnsMode = false; // false = VPN Mode | true = DNS Mode

  // تنظیمات پیش‌فرض گیمینگ
  bool gameOnlyLock = true;
  bool tcpNoDelay = true;
  bool bypassIran = true;

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
    'Custom DNS': [],
  };

  final List<String> _sources = [
    'https://cdn.jsdelivr.net/gh/0xRadikal/Free-v2ray-Configs@main/top100.txt',
    'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vless_configs.txt',
    'https://cdn.jsdelivr.net/gh/MatinGhanbari/v2ray-configs@main/subscriptions/filtered/subs/vless.txt',
    'https://cdn.jsdelivr.net/gh/Farid-Karimi/Config-Collector@main/vless_iran.txt',
    'https://cdn.jsdelivr.net/gh/Mohammadgb0078/IRV2ray@main/vless.txt',
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Sub1.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/top100.txt',
    'https://raw.githubusercontent.com/Farid-Karimi/Config-Collector/main/vless_iran.txt',
  ];

  List<ServerNode> servers = [];
  ServerNode? selectedServer;

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
    await flutterV2ray.initializeV2Ray();
    _fetchAndPingServers();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    customDns1Controller.dispose();
    customDns2Controller.dispose();
    super.dispose();
  }

  String tr(String en, String fa) => isPersian ? fa : en;

  List<String> _getActiveDnsPair() {
    if (selectedDnsKey == 'Custom DNS') {
      String d1 = customDns1Controller.text.trim();
      String d2 = customDns2Controller.text.trim();
      return [
        d1.isNotEmpty ? d1 : '1.1.1.1',
        d2.isNotEmpty ? d2 : '8.8.8.8',
      ];
    }
    return dnsPresets[selectedDnsKey] ?? ['10.202.10.10', '1.1.1.1'];
  }

  /// استخراج تمیز پرچم و نام کشور بدون تبلیغات
  Map<String, String> _parseCleanLocation(String rawRemark, int index) {
    String upper = rawRemark.toUpperCase();
    String flag = '🇪🇺';
    String country = 'Europe';

    if (upper.contains('DE') || upper.contains('GERMANY') || rawRemark.contains('🇩🇪') || rawRemark.contains('آلمان')) {
      flag = '🇩🇪';
      country = 'Germany';
    } else if (upper.contains('NL') || upper.contains('NETHERLANDS') || rawRemark.contains('🇳🇱') || rawRemark.contains('هلند')) {
      flag = '🇳🇱';
      country = 'Netherlands';
    } else if (upper.contains('FI') || upper.contains('FINLAND') || rawRemark.contains('🇫🇮') || rawRemark.contains('فنلاند')) {
      flag = '🇫🇮';
      country = 'Finland';
    } else if (upper.contains('TR') || upper.contains('TURKEY') || rawRemark.contains('🇹🇷') || rawRemark.contains('ترکیه')) {
      flag = '🇹🇷';
      country = 'Turkey';
    } else if (upper.contains('GB') || upper.contains('UK') || upper.contains('UNITED KINGDOM') || rawRemark.contains('🇬🇧')) {
      flag = '🇬🇧';
      country = 'United Kingdom';
    } else if (upper.contains('FR') || upper.contains('FRANCE') || rawRemark.contains('🇫🇷') || rawRemark.contains('فرانسه')) {
      flag = '🇫🇷';
      country = 'France';
    } else if (upper.contains('AE') || upper.contains('UAE') || upper.contains('DUBAI') || rawRemark.contains('🇦🇪')) {
      flag = '🇦🇪';
      country = 'UAE (Middle East)';
    } else if (upper.contains('US') || upper.contains('USA') || rawRemark.contains('🇺🇸')) {
      flag = '🇺🇸';
      country = 'United States';
    } else if (upper.contains('SE') || upper.contains('SWEDEN') || rawRemark.contains('🇸🇪')) {
      flag = '🇸🇪';
      country = 'Sweden';
    } else if (upper.contains('PL') || upper.contains('POLAND') || rawRemark.contains('🇵🇱')) {
      flag = '🇵🇱';
      country = 'Poland';
    }

    return {
      'flag': flag,
      'name': '$country • Gaming #${index + 1}',
    };
  }

  /// دریافت موازی سرورها و تست پینگ واقعی
  Future<void> _fetchAndPingServers() async {
    if (isScanningServers) return;
    setState(() => isScanningServers = true);

    List<String> rawLinks = [];

    await Future.wait(_sources.map((url) async {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          String content = res.body.trim();
          try {
            content = utf8.decode(base64.decode(content.replaceAll(RegExp(r'\s+'), '')));
          } catch (_) {}

          for (var line in content.split('\n')) {
            line = line.trim();
            if (line.startsWith('vless://') || line.startsWith('vmess://') || line.startsWith('trojan://')) {
              if (rawLinks.length < 40 && !rawLinks.contains(line)) {
                rawLinks.add(line);
              }
            }
          }
        }
      } catch (_) {}
    }));

    List<ServerNode> parsedNodes = [];
    for (int i = 0; i < rawLinks.length && parsedNodes.length < 22; i++) {
      try {
        String uri = rawLinks[i];
        V2RayURL parser = FlutterV2ray.parseFromURL(uri);
        String fullCfg = parser.getFullConfiguration();
        String proto = uri.split('://').first.toUpperCase();
        if (uri.contains('security=reality')) proto = 'REALITY';

        final loc = _parseCleanLocation(parser.remark, parsedNodes.length);
        parsedNodes.add(ServerNode(
          id: 'node_${parsedNodes.length}',
          name: loc['name']!,
          flag: loc['flag']!,
          protocol: proto,
          rawUri: uri,
          fullConfig: fullCfg,
        ));
      } catch (_) {}
    }

    if (parsedNodes.isNotEmpty && mounted) {
      setState(() {
        servers = parsedNodes;
        selectedServer ??= servers.first;
      });

      await Future.wait(servers.map((node) async {
        try {
          int delay = await flutterV2ray
              .getServerDelay(config: node.fullConfig)
              .timeout(const Duration(milliseconds: 2200), onTimeout: () => -1);
          if (delay > 0 && delay < 3000) {
            node.ping = delay;
          }
        } catch (_) {}
      }));

      if (mounted) {
        setState(() {
          servers.sort((a, b) {
            if (a.ping > 0 && b.ping > 0) return a.ping.compareTo(b.ping);
            if (a.ping > 0) return -1;
            if (b.ping > 0) return 1;
            return 0;
          });
          if (servers.isNotEmpty) {
            selectedServer = servers.first;
          }
          isScanningServers = false;
        });
      }
    } else {
      if (mounted) setState(() => isScanningServers = false);
    }
  }

  /// ساخت کانفیگ استاندارد برای حالت DNS یا حالت VPN
  String _buildEngineConfig({ServerNode? vpnNode}) {
    final List<String> dnsPair = _getActiveDnsPair();

    // ۱. حالت DNS: اتصال مستقیم و فوری بدون سرور خارجی
    if (isDnsMode || vpnNode == null) {
      V2RayURL template = FlutterV2ray.parseFromURL(
        'vless://00000000-0000-0000-0000-000000000000@127.0.0.1:443?security=none&type=tcp#NivexiaDNS',
      );
      Map<String, dynamic> cfg = jsonDecode(template.getFullConfiguration());

      cfg['dns'] = {
        "servers": dnsPair,
      };

      if (cfg['outbounds'] != null && (cfg['outbounds'] as List).isNotEmpty) {
        String primaryTag = cfg['outbounds'][0]['tag'] ?? 'proxy';
        cfg['outbounds'][0] = {
          "tag": primaryTag,
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "UseIP"
          }
        };
      }

      return jsonEncode(cfg);
    }

    // ۲. حالت VPN: تزریق استاندارد DNS و TCP NoDelay بدون دستکاری تگ‌های هسته
    Map<String, dynamic> cfg = jsonDecode(vpnNode.fullConfig);

    cfg['dns'] = {
      "servers": dnsPair,
    };

    if (tcpNoDelay && cfg['outbounds'] != null && (cfg['outbounds'] as List).isNotEmpty) {
      if (cfg['outbounds'][0]['streamSettings'] is Map) {
        cfg['outbounds'][0]['streamSettings']['sockopt'] = {
          "tcpNoDelay": true,
        };
      }
    }

    return jsonEncode(cfg);
  }

  /// اتصال یا قطع اتصال
  Future<void> _toggleConnection() async {
    if (isConnected) {
      await flutterV2ray.stopV2Ray();
      setState(() {
        isConnected = false;
        isConnecting = false;
      });
      return;
    }

    bool hasPerm = await flutterV2ray.requestPermission();
    if (!hasPerm) return;

    setState(() => isConnecting = true);

    try {
      if (!isDnsMode && selectedServer == null) {
        await _fetchAndPingServers();
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

      String finalConfig = _buildEngineConfig(vpnNode: selectedServer);
      String remarkTitle = isDnsMode
          ? "Nivexia DNS • $selectedDnsKey"
          : "Nivexia • ${selectedServer?.name ?? 'Gaming Tunnel'}";

      await flutterV2ray.startV2Ray(
        remark: remarkTitle,
        config: finalConfig,
        blockedApps: blockedApps,
      );

      setState(() {
        isConnected = true;
        isConnecting = false;
      });
    } catch (e) {
      setState(() => isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent.shade700,
            content: Text(tr('Connection failed. Try another server or DNS Mode.', 'خطا در اتصال؛ سرور دیگری انتخاب کنید یا حالت DNS را بزنید.')),
          ),
        );
      }
    }
  }

  String _formatSpeed(dynamic speed) {
    if (speed == null) return '0 KB/s';
    int? val = int.tryParse(speed.toString());
    if (val == null) return speed.toString();
    if (val < 1024) return '$val B/s';
    if (val < 1048576) return '${(val / 1024).toStringAsFixed(1)} KB/s';
    return '${(val / 1048576).toStringAsFixed(1)} MB/s';
  }

  /// لیست سرورها با پرچم، پینگ و سوییچ آنی
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
            return Directionality(
              textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.68,
                maxChildSize: 0.9,
                minChildSize: 0.45,
                builder: (context, scrollController) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tr('GAMING SERVERS', 'سرورهای گیمینگ'),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: Color(0xFF00F5D4),
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: tr('Add Custom Config', 'افزودن کانفیگ شخصی'),
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                                  onPressed: () => _showAddCustomConfigDialog(setSheetState),
                                ),
                                IconButton(
                                  tooltip: tr('Refresh Ping', 'تست مجدد پینگ'),
                                  icon: isScanningServers
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F5D4)),
                                        )
                                      : const Icon(Icons.refresh_rounded, color: Color(0xFF00F5D4)),
                                  onPressed: () async {
                                    setSheetState(() {});
                                    await _fetchAndPingServers();
                                    if (mounted) setSheetState(() {});
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10),
                        Expanded(
                          child: servers.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(color: Color(0xFF00F5D4)),
                                      const SizedBox(height: 14),
                                      Text(
                                        tr('Fetching active gaming nodes...', 'در حال دریافت سرورهای فعال...'),
                                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: servers.length,
                                  itemBuilder: (context, index) {
                                    final node = servers[index];
                                    final bool isSelected = selectedServer?.id == node.id;
                                    final Color pingColor = node.ping <= 0
                                        ? Colors.white38
                                        : (node.ping < 110
                                            ? const Color(0xFF00F5D4)
                                            : (node.ping < 200 ? Colors.amberAccent : Colors.orangeAccent));

                                    return GestureDetector(
                                      onTap: () async {
                                        setState(() {
                                          selectedServer = node;
                                          isDnsMode = false;
                                        });
                                        Navigator.pop(context);
                                        if (isConnected) {
                                          await flutterV2ray.stopV2Ray();
                                          setState(() => isConnected = false);
                                          await Future.delayed(const Duration(milliseconds: 300));
                                          _toggleConnection();
                                        }
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
                                                  ),
                                                  const SizedBox(height: 4),
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
                                                ],
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Icon(Icons.signal_cellular_alt_rounded, color: pingColor, size: 18),
                                                const SizedBox(width: 4),
                                                Text(
                                                  node.ping > 0 ? '${node.ping} ms' : 'Ready',
                                                  style: TextStyle(
                                                    color: pingColor,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
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
    );
  }

  void _showAddCustomConfigDialog(StateSetter setSheetState) {
    final TextEditingController uriController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151924),
          title: Text(tr('Add Custom V2Ray Link', 'افزودن لینک کانفیگ شخصی'), style: const TextStyle(fontSize: 16)),
          content: TextField(
            controller: uriController,
            decoration: InputDecoration(
              hintText: 'vless:// or vmess:// ...',
              filled: true,
              fillColor: const Color(0xFF090B10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Cancel', 'انصراف')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F5D4), foregroundColor: Colors.black),
              onPressed: () async {
                String link = uriController.text.trim();
                try {
                  V2RayURL parser = FlutterV2ray.parseFromURL(link);
                  String fullCfg = parser.getFullConfiguration();
                  int delay = await flutterV2ray.getServerDelay(config: fullCfg).timeout(const Duration(seconds: 2), onTimeout: () => 65);
                  final newNode = ServerNode(
                    id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                    name: parser.remark.isNotEmpty ? parser.remark : 'Custom Gaming Node',
                    flag: '⚡',
                    protocol: 'CUSTOM',
                    rawUri: link,
                    fullConfig: fullCfg,
                    ping: delay > 0 ? delay : 65,
                  );
                  setState(() {
                    servers.insert(0, newNode);
                    selectedServer = newNode;
                  });
                  setSheetState(() {});
                  if (mounted) Navigator.pop(context);
                } catch (_) {}
              },
              child: Text(tr('Add', 'افزودن')),
            ),
          ],
        );
      },
    );
  }

  /// پنجره تنظیمات (VPN / DNS + Custom DNS 1 & 2 + زبان)
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

                      // ۲. انتخابگر DNS + بخش Custom DNS
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

                      // ۳. بهینه‌سازهای پیش‌فرض گیمینگ
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF00F5D4),
                        title: Text(tr('Game-Only Mode', 'حالت اختصاصی گیم (مسدودسازی وب)')),
                        subtitle: Text(
                          tr('Blocks browsers & social media to prevent lag', 'بستن مرورگرها و برنامه‌های پرمصرف در پس‌زمینه'),
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
                          tr('Disables Nagle buffering for instant packet delivery', 'ارسال آنی بسته‌های بازی بدون مکث در شبکه'),
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                        value: tcpNoDelay,
                        onChanged: (v) {
                          setModalState(() => tcpNoDelay = v);
                          setState(() => tcpNoDelay = v);
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

                // ۲. دکمه پاور مرکزی با انیمیشن تنفس نوری
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
                                      ? tr('BOOST ACTIVE', 'متصل و بهینه')
                                      : tr('TAP TO BOOST', 'شروع بهینه‌سازی')),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                                color: isConnected ? const Color(0xFF00F5D4) : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isConnected
                                  ? v2rayStatus.duration
                                  : (isDnsMode
                                      ? '${activeDns.first} • Instant'
                                      : (selectedServer != null && selectedServer!.ping > 0
                                          ? 'Ping: ${selectedServer!.ping} ms'
                                          : tr('Low-Latency Gaming Core', 'هسته کاهش پینگ گیمینگ'))),
                              style: const TextStyle(fontSize: 11, color: Colors.white54),
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
                                  isConnected ? _formatSpeed(v2rayStatus.downloadSpeed) : '0 KB/s',
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
                                  isConnected ? _formatSpeed(v2rayStatus.uploadSpeed) : '0 KB/s',
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
                          isDnsMode ? '⚡' : (selectedServer?.flag ?? '🇩🇪'),
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
                                    : (selectedServer?.name ?? tr('Select Gaming Server', 'انتخاب سرور گیمینگ')),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isDnsMode
                                    ? tr('Tap to change DNS or set Custom DNS', 'برای تغییر DNS یا وارد کردن دستی ضربه بزنید')
                                    : tr('Tap to view servers & live ping', 'مشاهده لیست سرورها و پینگ لحظه‌ای'),
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
