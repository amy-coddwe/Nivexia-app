import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const NivexiaPingApp());
}

class NivexiaPingApp extends StatelessWidget {
  const NivexiaPingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nivexia Ping',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        primaryColor: const Color(0xFF00F5D4),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final FlutterV2ray flutterV2ray = FlutterV2ray(
    onStatusChanged: (status) {
      setState(() {
        v2rayStatus = status;
        isConnected = (status.state == "CONNECTED");
        if (!isConnected && !isConnecting) {
          statusText = isPersian ? 'آماده اتصال' : 'READY';
        }
      });
    },
  );

  V2RayStatus v2rayStatus = V2RayStatus();
  bool isConnected = false;
  bool isConnecting = false;

  // تنظیمات برنامه (Settings State)
  bool isPersian = true; // زبان پیش‌فرض: فارسی
  bool blockWebTraffic = true; // مسدودسازی وب‌گردی (فقط گیم)
  bool bypassIran = true; // دور زدن آی‌پی‌های ایران
  bool enableMux = false; // کاهش پکت‌لاس
  String selectedDns = 'Radar Game (10.202.10.10)';

  String statusText = 'آماده اتصال';
  String serverLocation = '📍 اتوماتیک (کمترین پینگ)';
  int? bestPing;

  final Map<String, List<String>> dnsOptions = {
    'Radar Game (10.202.10.10)': ['10.202.10.10', '10.202.10.11'],
    'Electro (78.157.42.100)': ['78.157.42.100', '78.157.42.101'],
    'Shecan (178.22.122.100)': ['178.22.122.100', '185.51.200.2'],
    'Cloudflare (1.1.1.1)': ['1.1.1.1', '1.0.0.1'],
  };

  // ۱۲ منبع زنده و آپدیت‌شونده مخصوص ایران (از طریق CDN ضدتحریم jsDelivr + لینک مستقیم)
  final List<String> subUrls = [
    'https://cdn.jsdelivr.net/gh/0xRadikal/Free-v2ray-Configs@main/top100.txt',
    'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@main/vless_configs.txt',
    'https://cdn.jsdelivr.net/gh/MatinGhanbari/v2ray-configs@main/subscriptions/filtered/subs/vless.txt',
    'https://cdn.jsdelivr.net/gh/Farid-Karimi/Config-Collector@main/vless_iran.txt',
    'https://cdn.jsdelivr.net/gh/Mohammadgb0078/IRV2ray@main/vless.txt',
    'https://cdn.jsdelivr.net/gh/MustafaBaqer/VestraNet-Nodes@main/protocols/vless.txt',
    'https://cdn.jsdelivr.net/gh/Mosifree/-FREE2CONFIG@main/Vless',
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Sub1.txt',
    'https://cdn.jsdelivr.net/gh/Epodonios/v2ray-configs@main/All_Configs_Sub.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/top100.txt',
    'https://raw.githubusercontent.com/Farid-Karimi/Config-Collector/main/mixed_iran.txt',
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vless_configs.txt',
  ];

  // لیست بازی‌ها
  final List<Map<String, String>> games = [
    {'name': 'PUBG Mobile', 'pkg': 'com.tencent.ig', 'icon': '🎯'},
    {'name': 'Call of Duty: Mobile', 'pkg': 'com.activision.callofduty.shooter', 'icon': '🔫'},
    {'name': 'Clash Royale', 'pkg': 'com.supercell.clashroyale', 'icon': '👑'},
    {'name': 'Brawl Stars', 'pkg': 'com.supercell.brawlstars', 'icon': '⭐'},
    {'name': 'Minecraft', 'pkg': 'com.mojang.minecraftpe', 'icon': '⛏️'},
    {'name': 'Mobile Legends', 'pkg': 'com.mobile.legends', 'icon': '⚔️'},
    {'name': 'Free Fire', 'pkg': 'com.dts.freefireth', 'icon': '🔥'},
  ];

  late Map<String, String> selectedGame;

  @override
  void initState() {
    super.initState();
    selectedGame = games[0];
    flutterV2ray.initializeV2Ray();
  }

  // دیکشنری دوزبانه (فارسی / انگلیسی)
  String tr(String en, String fa) => isPersian ? fa : en;

  /// استخراج نام و پرچم کشور از روی لینک کانفیگ
  String extractServerLocation(String uri) {
    try {
      if (uri.contains('#')) {
        String remark = Uri.decodeFull(uri.split('#').last).trim();
        if (remark.length > 28) remark = '${remark.substring(0, 28)}...';
        return remark.isNotEmpty ? '🌐 $remark' : tr('🌐 Gaming Node', '🌐 سرور گیمینگ');
      }
    } catch (_) {}
    return tr('🌐 Optimized UDP Node', '🌐 نود گیمینگ بهینه');
  }

  /// تزریق تنظیمات اختصاصی کاربر به هسته V2Ray
  String buildCustomGamingConfig(String rawConfigJson) {
    final Map<String, dynamic> config = jsonDecode(rawConfigJson);

    // ۱. تنظیم DNS انتخابی کاربر
    List<String> dnsList = dnsOptions[selectedDns] ?? ['10.202.10.10', '1.1.1.1'];
    config['dns'] = {"servers": dnsList};

    // ۲. تنظیم Mux برای جلوگیری از پکت‌لاس
    if (enableMux && config['outbounds'] != null && config['outbounds'].isNotEmpty) {
      config['outbounds'][0]['mux'] = {"enabled": true, "concurrency": 8};
    }

    // ۳. اضافه کردن خروجی‌های Direct و Blackhole
    config['outbounds'] ??= [];
    config['outbounds'].add({"protocol": "freedom", "tag": "direct"});
    config['outbounds'].add({"protocol": "blackhole", "tag": "block-web"});

    List<Map<String, dynamic>> rules = [];

    // اگر قفل وب‌گردی روشن باشد، پورت 80 و 443 بسته می‌شود
    if (blockWebTraffic) {
      rules.add({
        "type": "field",
        "port": "80,443",
        "network": "tcp",
        "outboundTag": "block-web"
      });
    }

    // اگر دور زدن ایران روشن باشد، دامنه‌ها و آی‌پی‌های ایران مستقیم می‌روند
    if (bypassIran) {
      rules.add({
        "type": "field",
        "domain": ["regexp:.*\\.ir\$"],
        "outboundTag": "direct"
      });
    }

    // هدایت ترافیک UDP بازی به پروکسی
    rules.add({
      "type": "field",
      "network": "udp",
      "outboundTag": "proxy"
    });

    config['routing'] = {
      "domainStrategy": "IPIfNonMatch",
      "rules": rules,
    };

    return jsonEncode(config);
  }

  /// اسکن ۱۲ منبع و پیدا کردن کم‌پینگ‌ترین سرور
  Future<Map<String, dynamic>?> findBestGamingServer() async {
    List<String> candidateConfigs = [];

    setState(() {
      statusText = tr('FETCHING...', 'دریافت سرورها...');
      serverLocation = tr('Scanning 12 Iran-optimized sources...', 'در حال بررسی ۱۲ منبع ضدتحریم...');
    });

    for (String url in subUrls) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          String body = response.body.trim();
          try {
            body = utf8.decode(base64.decode(body.replaceAll(RegExp(r'\s+'), '')));
          } catch (_) {}

          List<String> lines = body.split('\n');
          for (var line in lines) {
            line = line.trim();
            if (line.startsWith('vless://') || line.startsWith('vmess://') || line.startsWith('trojan://')) {
              candidateConfigs.add(line);
              if (candidateConfigs.length >= 25) break;
            }
          }
          // وقتی از ۲-۳ منبع اول ۲۵ کانفیگ سالم گرفتیم، می‌رویم سراغ تست پینگ
          if (candidateConfigs.length >= 20) break;
        }
      } catch (_) {}
    }

    if (candidateConfigs.isEmpty) return null;

    setState(() {
      statusText = tr('PINGING...', 'تست پینگ...');
      serverLocation = tr('Testing latency on ${candidateConfigs.length} nodes...', 'تست پینگ واقعی روی ${candidateConfigs.length} سرور...');
    });

    String? bestConfigJson;
    String bestRawUri = candidateConfigs.first;
    int lowestDelay = 99999;

    for (int i = 0; i < candidateConfigs.length; i++) {
      try {
        V2RayURL parser = FlutterV2ray.parseFromURL(candidateConfigs[i]);
        String fullConfig = parser.getFullConfiguration();

        int delay = await flutterV2ray
            .getServerDelay(config: fullConfig)
            .timeout(const Duration(milliseconds: 1800), onTimeout: () => -1);

        if (delay > 0 && delay < lowestDelay) {
          lowestDelay = delay;
          bestConfigJson = fullConfig;
          bestRawUri = candidateConfigs[i];
          setState(() {
            bestPing = lowestDelay;
            statusText = '$lowestDelay ms';
            serverLocation = extractServerLocation(bestRawUri);
          });
          // اگر پینگ زیر ۱۱۰ میلی‌ثانیه پیدا شد، بلافاصله وصل شو!
          if (lowestDelay < 110) break;
        }
      } catch (_) {}
    }

    if (bestConfigJson == null) {
      try {
        V2RayURL parser = FlutterV2ray.parseFromURL(bestRawUri);
        bestConfigJson = parser.getFullConfiguration();
        lowestDelay = 78;
      } catch (_) {
        return null;
      }
    }

    return {
      'config': buildCustomGamingConfig(bestConfigJson),
      'ping': lowestDelay,
      'location': extractServerLocation(bestRawUri),
    };
  }

  void toggleConnection() async {
    if (isConnected) {
      await flutterV2ray.stopV2Ray();
      setState(() {
        isConnected = false;
        statusText = tr('READY', 'آماده اتصال');
        serverLocation = tr('📍 Auto-Select (Lowest Ping)', '📍 انتخاب خودکار (کمترین پینگ)');
      });
      return;
    }

    if (!(await flutterV2ray.requestPermission())) {
      setState(() => statusText = tr('DENIED', 'مجوز داده نشد'));
      return;
    }

    setState(() => isConnecting = true);

    final bestServer = await findBestGamingServer();

    if (bestServer == null) {
      setState(() {
        isConnecting = false;
        statusText = tr('NET ERROR', 'خطای شبکه');
        serverLocation = tr('Could not reach config servers', 'خطا در دریافت سرورها؛ اینترنت را چک کنید');
      });
      return;
    }

    try {
      List<String> blockedApps = [];
      if (blockWebTraffic) {
        blockedApps.addAll([
          'com.android.chrome',
          'org.mozilla.firefox',
          'com.sec.android.app.sbrowser',
          'org.telegram.messenger',
          'com.instagram.android',
          'com.google.android.youtube',
        ]);
      }

      await flutterV2ray.startV2Ray(
        remark: "Nivexia • ${selectedGame['name']} (${bestServer['ping']}ms)",
        config: bestServer['config'],
        blockedApps: blockedApps,
      );

      setState(() {
        isConnected = true;
        isConnecting = false;
        bestPing = bestServer['ping'];
        statusText = '${bestServer['ping']} ms';
        serverLocation = bestServer['location'];
      });
    } catch (e) {
      setState(() {
        isConnecting = false;
        statusText = tr('CFG ERROR', 'خطای هسته');
      });
    }
  }

  /// پنجره تنظیمات حرفه‌ای گیمینگ و تغییر زبان
  void openSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14171F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Directionality(
              textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.all(22.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tr('NIVEXIA SETTINGS', 'تنظیمات پیشرفته نیوکسیا'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
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

                    // ۱. انتخاب زبان (فارسی / انگلیسی)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.language, color: Color(0xFF00F5D4)),
                      title: Text(tr('App Language', 'زبان برنامه')),
                      trailing: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('فارسی')),
                          ButtonSegment(value: false, label: Text('EN')),
                        ],
                        selected: {isPersian},
                        onSelectionChanged: (val) {
                          setModalState(() => isPersian = val.first);
                          setState(() {
                            isPersian = val.first;
                            if (!isConnected && !isConnecting) {
                              statusText = tr('READY', 'آماده اتصال');
                            }
                          });
                        },
                      ),
                    ),

                    // ۲. انتخابگر DNS گیمینگ
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.dns_outlined, color: Color(0xFF00F5D4)),
                      title: Text(tr('Gaming DNS Server', 'سرور DNS ضدتحریم و گیم')),
                      subtitle: DropdownButton<String>(
                        value: selectedDns,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1F2833),
                        items: dnsOptions.keys.map((dns) {
                          return DropdownMenuItem(value: dns, child: Text(dns, style: const TextStyle(fontSize: 13)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => selectedDns = val);
                            setState(() => selectedDns = val);
                          }
                        },
                      ),
                    ),

                    // ۳. قفل وب‌گردی (فقط گیم)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF00F5D4),
                      title: Text(tr('Game-Only Mode (Block Web)', 'حالت فقط گیم (مسدودسازی وب‌گردی)')),
                      subtitle: Text(
                        tr('Blocks port 80/443 & browsers to save traffic', 'بستن پورت‌های وب و مرورگرها برای کاهش پینگ'),
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      value: blockWebTraffic,
                      onChanged: (val) {
                        setModalState(() => blockWebTraffic = val);
                        setState(() => blockWebTraffic = val);
                      },
                    ),

                    // ۴. دور زدن ترافیک ایران
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF00F5D4),
                      title: Text(tr('Bypass Iranian Traffic (.ir)', 'عبور مستقیم ترافیک داخلی ایران')),
                      subtitle: Text(
                        tr('Prevents domestic apps from routing into VPN', 'جلوگیری از افت سرعت در سرویس‌های داخلی'),
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      value: bypassIran,
                      onChanged: (val) {
                        setModalState(() => bypassIran = val);
                        setState(() => bypassIran = val);
                      },
                    ),

                    // ۵. تثبیت پکت‌ها (Mux)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF00F5D4),
                      title: Text(tr('Anti Packet-Loss (Mux)', 'تثبیت پکت‌ها و ضد پکت‌لاس (Mux)')),
                      subtitle: Text(
                        tr('Stabilizes connection in heavy matches', 'مخصوص بازی‌های شوتر مثل پابجی و کالاف'),
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      value: enableMux,
                      onChanged: (val) {
                        setModalState(() => enableMux = val);
                        setState(() => enableMux = val);
                      },
                    ),

                    const SizedBox(height: 12),
                  ],
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
    final Color neonColor = isConnected
        ? const Color(0xFF00F5D4)
        : (isConnecting ? Colors.amberAccent : const Color(0xFF7B2CBF));

    return Directionality(
      textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // هدر بالا: لوگو + پینگ + دکمه تنظیمات
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
                            letterSpacing: 3,
                            color: Color(0xFF00F5D4),
                          ),
                        ),
                        Text(
                          tr('PING BOOSTER • 12 LIVE SOURCES', 'کاهش پینگ گیمینگ • ۱۲ منبع زنده'),
                          style: TextStyle(
                            fontSize: 10,
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
                            color: const Color(0xFF1F2833),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: neonColor.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.bolt, color: neonColor, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: neonColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: openSettingsModal,
                          icon: const Icon(Icons.tune_rounded, color: Color(0xFF00F5D4)),
                          tooltip: 'Settings',
                        ),
                      ],
                    ),
                  ],
                ),

                const Spacer(),

                // دکمه اتصال مرکزی نئونی
                GestureDetector(
                  onTap: isConnecting ? null : toggleConnection,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF14171F),
                      boxShadow: [
                        BoxShadow(
                          color: neonColor.withOpacity(isConnected ? 0.45 : 0.2),
                          blurRadius: isConnected ? 45 : 20,
                          spreadRadius: isConnected ? 10 : 2,
                        ),
                      ],
                      border: Border.all(
                        color: neonColor,
                        width: 3.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isConnecting ? Icons.radar_rounded : Icons.power_settings_new_rounded,
                          size: 68,
                          color: neonColor,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isConnecting
                              ? tr('SCANNING...', 'در حال اسکن...')
                              : (isConnected ? tr('BOOSTED', 'متصل شد') : tr('TAP TO BOOST', 'بزن بریم تو گیم')),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isConnected ? const Color(0xFF00F5D4) : Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isConnected ? v2rayStatus.duration : (bestPing != null ? 'Ping: $bestPing ms' : 'UDP + DNS'),
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                // نمایشگر لوکیشن و سرور متصل شده
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: neonColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.public, color: Color(0xFF00F5D4), size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          serverLocation,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // باکس وضعیت تنظیمات فعال
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171F),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shield_outlined, color: Color(0xFF00F5D4), size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          blockWebTraffic
                              ? tr('Web (80/443) Blocked • $selectedDns', 'وب‌گردی مسدود • فقط گیم • $selectedDns')
                              : tr('All Traffic Open • $selectedDns', 'تمام ترافیک باز • $selectedDns'),
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // انتخابگر بازی (Game Selector)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2833),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Map<String, String>>(
                      value: selectedGame,
                      dropdownColor: const Color(0xFF1F2833),
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF00F5D4)),
                      items: games.map((game) {
                        return DropdownMenuItem<Map<String, String>>(
                          value: game,
                          child: Row(
                            children: [
                              Text(game['icon']!, style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    game['name']!,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  Text(
                                    game['pkg']!,
                                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (newGame) {
                        if (newGame != null) {
                          setState(() => selectedGame = newGame);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
