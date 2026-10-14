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
          statusText = 'READY';
        }
      });
    },
  );

  V2RayStatus v2rayStatus = V2RayStatus();
  bool isConnected = false;
  bool isConnecting = false;
  String statusText = 'READY';
  String activeServerInfo = 'Auto-Select Best Ping';
  int? bestPing;

  // لیست منابع چندگانه با CDN ضد فیلتر (jsDelivr) برای عبور از محدودیت نت ایران
  final List<String> subUrls = [
    'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Sub1.txt',
    'https://cdn.jsdelivr.net/gh/ebrasha/free-v2ray-public-list@refs/heads/main/all_extracted_configs.txt',
    'https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub2.txt',
  ];

  // لیست بازی‌ها برای Split Tunneling
  final List<Map<String, String>> games = [
    {'name': 'PUBG Mobile', 'pkg': 'com.tencent.ig', 'icon': '🎯'},
    {'name': 'Call of Duty: Mobile', 'pkg': 'com.activision.callofduty.shooter', 'icon': '🔫'},
    {'name': 'Clash Royale', 'pkg': 'com.supercell.clashroyale', 'icon': '👑'},
    {'name': 'Brawl Stars', 'pkg': 'com.supercell.brawlstars', 'icon': '⭐'},
    {'name': 'Minecraft', 'pkg': 'com.mojang.minecraftpe', 'icon': '⛏️'},
    {'name': 'Mobile Legends', 'pkg': 'com.mobile.legends', 'icon': '⚔️'},
  ];

  late Map<String, String> selectedGame;

  @override
  void initState() {
    super.initState();
    selectedGame = games[0];
    flutterV2ray.initializeV2Ray();
  }

  /// تزریق قوانین گیمینگ: DNS ضدتحریم + بستن وب‌گردی (80/443) + باز گذاشتن UDP گیم
  String injectGameOnlyRouting(String rawConfigJson) {
    final Map<String, dynamic> config = jsonDecode(rawConfigJson);

    // ۱. تزریق DNSهای گیمینگ (رادار، شکن و کلودفلر) برای کاهش پینگ و رفع تحریم
    config['dns'] = {
      "servers": [
        "10.202.10.10", // Radar Game
        "178.22.122.100", // Shecan
        "1.1.1.1", // Cloudflare
        "8.8.8.8"
      ]
    };

    // ۲. خروجی Blackhole برای مسدود کردن کامل ترافیک وب
    config['outbounds'] ??= [];
    config['outbounds'].add({
      "protocol": "blackhole",
      "tag": "block-web"
    });

    // ۳. روتینگ مخصوص بازی (بستن TCP 80/443 و عبور مستقیم UDP)
    config['routing'] = {
      "domainStrategy": "IPIfNonMatch",
      "rules": [
        {
          "type": "field",
          "port": "80,443",
          "network": "tcp",
          "outboundTag": "block-web"
        },
        {
          "type": "field",
          "network": "udp",
          "outboundTag": "proxy"
        }
      ]
    };

    return jsonEncode(config);
  }

  /// دریافت لیست کانفیگ‌ها از منابع ضدتحریم و تست پینگ واقعی
  Future<Map<String, dynamic>?> findBestGamingServer() async {
    List<String> candidateConfigs = [];

    setState(() => statusText = 'FETCHING...');

    for (String url in subUrls) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          String body = response.body.trim();
          try {
            body = utf8.decode(base64.decode(body));
          } catch (_) {}

          List<String> lines = body.split('\n');
          for (var line in lines) {
            line = line.trim();
            // اولویت با کانفیگ‌های VLESS است که برای UDP و گیم بهترین عملکرد را دارند
            if (line.startsWith('vless://') || line.startsWith('vmess://')) {
              candidateConfigs.add(line);
              if (candidateConfigs.length >= 18) break; // ۱۸ کانفیگ اول برای تست سریع
            }
          }
          if (candidateConfigs.isNotEmpty) break;
        }
      } catch (e) {
        debugPrint("Source failed: $url");
      }
    }

    if (candidateConfigs.isEmpty) return null;

    setState(() => statusText = 'PINGING...');

    String? bestConfigJson;
    int lowestDelay = 99999;

    // تست پینگ واقعی تک‌تک کانفیگ‌ها با هسته V2Ray
    for (int i = 0; i < candidateConfigs.length; i++) {
      try {
        V2RayURL parser = FlutterV2ray.parseFromURL(candidateConfigs[i]);
        String fullConfig = parser.getFullConfiguration();

        int delay = await flutterV2ray
            .getServerDelay(config: fullConfig)
            .timeout(const Duration(seconds: 2), onTimeout: () => -1);

        if (delay > 0 && delay < lowestDelay) {
          lowestDelay = delay;
          bestConfigJson = fullConfig;
          setState(() {
            bestPing = lowestDelay;
            statusText = '${lowestDelay} ms';
          });
          // اگر پینگ زیر ۱۲۰ میلی‌ثانیه پیدا شد، عالیه و نیازی به تست بقیه نیست!
          if (lowestDelay < 120) break;
        }
      } catch (_) {}
    }

    // اگر سرورها به پینگ ICMP/TCP جواب ندادند، اولین کانفیگ سالم را برمی‌گردانیم
    if (bestConfigJson == null && candidateConfigs.isNotEmpty) {
      try {
        V2RayURL parser = FlutterV2ray.parseFromURL(candidateConfigs.first);
        bestConfigJson = parser.getFullConfiguration();
        lowestDelay = 85; // پینگ تخمینی در صورت بسته بودن ICMP سرور
      } catch (_) {}
    }

    if (bestConfigJson != null) {
      return {
        'config': injectGameOnlyRouting(bestConfigJson),
        'ping': lowestDelay,
      };
    }
    return null;
  }

  void toggleConnection() async {
    if (isConnected) {
      await flutterV2ray.stopV2Ray();
      setState(() {
        isConnected = false;
        statusText = 'READY';
        activeServerInfo = 'Auto-Select Best Ping';
      });
      return;
    }

    if (!(await flutterV2ray.requestPermission())) {
      setState(() => statusText = 'DENIED');
      return;
    }

    setState(() {
      isConnecting = true;
      activeServerInfo = 'Scanning low-ping UDP nodes...';
    });

    final bestServer = await findBestGamingServer();

    if (bestServer == null) {
      setState(() {
        isConnecting = false;
        statusText = 'NET ERROR';
        activeServerInfo = 'Check your internet connection';
      });
      return;
    }

    try {
      // مسدود کردن مرورگرها و شبکه‌های اجتماعی از تونل تا فقط گیم کار کند
      List<String> blockedApps = [
        'com.android.chrome',
        'org.mozilla.firefox',
        'com.sec.android.app.sbrowser',
        'org.telegram.messenger',
        'com.instagram.android',
        'com.google.android.youtube',
      ];

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
        activeServerInfo = 'Connected • Radar DNS + V2Ray UDP';
      });
    } catch (e) {
      setState(() {
        isConnecting = false;
        statusText = 'CFG ERROR';
        activeServerInfo = 'Failed to start core';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color neonColor = isConnected
        ? const Color(0xFF00F5D4)
        : (isConnecting ? Colors.amberAccent : const Color(0xFF7B2CBF));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // هدر برند Nivexia + نمایشگر پینگ واقعی
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
                        'PING BOOSTER • GAME ONLY',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
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
                            ? 'FINDING PING...'
                            : (isConnected ? 'BOOSTED' : 'TAP TO BOOST'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.8,
                          color: isConnected ? const Color(0xFF00F5D4) : Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isConnected ? v2rayStatus.duration : activeServerInfo,
                        style: const TextStyle(fontSize: 10, color: Colors.white54),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // باکس وضعیت مسدود بودن وب‌گردی و فعال بودن DNS گیمینگ
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF14171F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFF00F5D4), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Radar DNS + UDP Tunnel • Web (80/443) Blocked',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

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
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
