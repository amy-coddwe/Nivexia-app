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
      });
    },
  );

  V2RayStatus v2rayStatus = V2RayStatus();
  bool isConnected = false;
  bool isConnecting = false;
  String statusText = 'READY';

  // لینک سابسکریپشن کانفیگ‌های رایگان (بعدا لینک اختصاصی خودت رو اینجا می‌ذاریم)
  final String subUrl = 'https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub1.txt';

  // لیست بازی‌ها و پکیج‌نیم‌های رسمی برای تفکیک ترافیک (Split Tunneling)
  final List<Map<String, String>> games = [
    {'name': 'PUBG Mobile', 'pkg': 'com.tencent.ig', 'icon': '🎯'},
    {'name': 'Minecraft', 'pkg': 'com.mojang.minecraftpe', 'icon': '⛏️'},
    {'name': 'Clash Royale', 'pkg': 'com.supercell.clashroyale', 'icon': '👑'},
    {'name': 'Call of Duty: Mobile', 'pkg': 'com.activision.callofduty.shooter', 'icon': '🔫'},
  ];

  late Map<String, String> selectedGame;

  @override
  void initState() {
    super.initState();
    selectedGame = games[0];
    flutterV2ray.initializeV2Ray();
  }

  /// تزریق قوانین روتینگ: بستن وب‌گردی (80/443) و باز گذاشتن پورت‌های گیم
  String injectGameOnlyRouting(String rawConfigJson) {
    final Map<String, dynamic> config = jsonDecode(rawConfigJson);

    config['outbounds'] ??= [];
    config['outbounds'].add({
      "protocol": "blackhole",
      "tag": "block-web"
    });

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

  /// دریافت اتوماتیک کانفیگ از منبع
  Future<String?> fetchBestGameConfig() async {
    try {
      final response = await http.get(Uri.parse(subUrl)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        String body = response.body.trim();
        try {
          body = utf8.decode(base64.decode(body));
        } catch (_) {}
        
        List<String> lines = body.split('\n');
        for (var line in lines) {
          line = line.trim();
          if (line.startsWith('vless://') || line.startsWith('vmess://')) {
            return line;
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching config: $e");
    }
    return null;
  }

  void toggleConnection() async {
    if (isConnected) {
      await flutterV2ray.stopV2Ray();
      setState(() {
        isConnected = false;
        statusText = 'READY';
      });
      return;
    }

    setState(() {
      isConnecting = true;
      statusText = 'FETCHING...';
    });

    if (await flutterV2ray.requestPermission()) {
      String? rawUri = await fetchBestGameConfig();

      if (rawUri == null) {
        setState(() {
          isConnecting = false;
          statusText = 'NET ERROR';
        });
        return;
      }

      try {
        V2RayURL parser = FlutterV2ray.parseFromURL(rawUri);
        String gameOnlyConfig = injectGameOnlyRouting(parser.getFullConfiguration());

        // لیست بقیه بازی‌ها رو مسدود می‌کنیم تا فقط بازی انتخاب‌شده تونل بشه
        List<String> blockedApps = games
            .where((g) => g['pkg'] != selectedGame['pkg'])
            .map((g) => g['pkg']!)
            .toList();

        // مسدود کردن مرورگرهای معروف برای اطمینان ۱۰۰٪ از عدم وب‌گردی
        blockedApps.addAll([
          'com.android.chrome',
          'org.mozilla.firefox',
          'com.sec.android.app.sbrowser',
          'org.telegram.messenger',
          'com.instagram.android',
        ]);

        await flutterV2ray.startV2Ray(
          remark: "Nivexia • ${selectedGame['name']}",
          config: gameOnlyConfig,
          blockedApps: blockedApps,
        );

        setState(() {
          isConnected = true;
          isConnecting = false;
          statusText = 'BOOSTED';
        });
      } catch (e) {
        setState(() {
          isConnecting = false;
          statusText = 'CFG ERROR';
        });
      }
    } else {
      setState(() {
        isConnecting = false;
        statusText = 'DENIED';
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
              // هدر برند Nivexia
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
                  width: 210,
                  height: 210,
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
                        isConnecting ? Icons.sync_rounded : Icons.power_settings_new_rounded,
                        size: 68,
                        color: neonColor,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isConnecting
                            ? 'CONNECTING...'
                            : (isConnected ? 'BOOSTED' : 'TAP TO BOOST'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.8,
                          color: isConnected ? const Color(0xFF00F5D4) : Colors.white70,
                        ),
                      ),
                      if (isConnected) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${v2rayStatus.duration}',
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ]
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // باکس وضعیت مسدود بودن وب‌گردی
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
                      'Web Traffic (80/443) Blocked • Pure Game UDP',
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
