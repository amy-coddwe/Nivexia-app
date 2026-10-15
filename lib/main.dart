import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

class AppThemePalette {
  final String name;
  final Color bg;
  final Color card;
  final Color surface;
  final Color primary;
  final Color secondary;

  const AppThemePalette({
    required this.name,
    required this.bg,
    required this.card,
    required this.surface,
    required this.primary,
    required this.secondary,
  });
}

const List<AppThemePalette> kThemes = [
  AppThemePalette(
    name: 'Cyber Cyan',
    bg: Color(0xFF080B11),
    card: Color(0xFF121722),
    surface: Color(0xFF181F2E),
    primary: Color(0xFF00F5D4),
    secondary: Color(0xFF7B2CBF),
  ),
  AppThemePalette(
    name: 'Emerald Matrix',
    bg: Color(0xFF060E0B),
    card: Color(0xFF0E1B16),
    surface: Color(0xFF152720),
    primary: Color(0xFF10B981),
    secondary: Color(0xFF059669),
  ),
  AppThemePalette(
    name: 'Royal Gold',
    bg: Color(0xFF0E0A08),
    card: Color(0xFF1A1310),
    surface: Color(0xFF261C17),
    primary: Color(0xFFF59E0B),
    secondary: Color(0xFFE11D48),
  ),
  AppThemePalette(
    name: 'Oceanic Blue',
    bg: Color(0xFF070C16),
    card: Color(0xFF101827),
    surface: Color(0xFF1B253B),
    primary: Color(0xFF38BDF8),
    secondary: Color(0xFF6366F1),
  ),
];

const List<String> kDefaultVipConfigs = [
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@104.21.33.59:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@188.244.122.103:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@172.64.34.14:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@104.24.74.9:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@162.158.161.252:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@104.24.74.218:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@188.244.122.116:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@188.114.103.1:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@162.158.172.213:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@104.24.59.192:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@104.24.59.28:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@162.158.172.19:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@162.158.172.55:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@162.158.185.163:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@162.158.164.28:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@104.24.26.199:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@104.24.26.137:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
  'vless://162ab0b0-75c6-4f2e-9da0-750fb0062b6f@162.158.164.20:443?path=%2F%3Fed%3D2048&security=tls&encryption=none&insecure=0&host=hv-hx90g3xn.pages.dev&fp=chrome&ech=cloudflare-ech.com%2Budp%3A%2F%2F1.1.1.1&type=ws&allowInsecure=0&sni=hv-hx90g3xn.pages.dev#VIP%20-%20Nivexia',
];

class NivexiaApp extends StatelessWidget {
  const NivexiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nivexia VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kThemes[0].bg,
      ),
      home: const HomeScreen(),
    );
  }
}

class ServerNode {
  final String rawUri;
  final String name;
  final String configJson;
  final String protocol;
  final String address;
  final int port;
  final int localHttpPort;
  String countryCode;
  String countryName;
  int tcpPing;
  int realPing;

  ServerNode({
    required this.rawUri,
    required this.name,
    required this.configJson,
    required this.protocol,
    required this.address,
    required this.port,
    required this.localHttpPort,
    this.countryCode = 'UN',
    this.countryName = 'Unknown',
    this.tcpPing = -1,
    this.realPing = -1,
  });

  int get displayPing => realPing > 0 ? realPing : tcpPing;

  Map<String, dynamic> toMap() => {
        'rawUri': rawUri,
        'name': name,
        'configJson': configJson,
        'protocol': protocol,
        'address': address,
        'port': port,
        'localHttpPort': localHttpPort,
        'countryCode': countryCode,
        'countryName': countryName,
        'tcpPing': tcpPing,
        'realPing': realPing,
      };

  factory ServerNode.fromMap(Map<String, dynamic> map) => ServerNode(
        rawUri: map['rawUri'] ?? '',
        name: map['name'] ?? 'VIP - Nivexia',
        configJson: map['configJson'] ?? '',
        protocol: map['protocol'] ?? 'VLESS',
        address: map['address'] ?? '',
        port: map['port'] ?? 443,
        localHttpPort: map['localHttpPort'] ?? 10809,
        countryCode: map['countryCode'] ?? 'UN',
        countryName: map['countryName'] ?? 'Unknown',
        tcpPing: map['tcpPing'] ?? -1,
        realPing: map['realPing'] ?? -1,
      );
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
          _nativeVpnRunning = true;
          isConnected = true;
          isConnecting = false;
        } else if (st == "DISCONNECTED") {
          _nativeVpnRunning = false;
          if (!isConnecting) {
            isConnected = false;
          }
        }
      });
    },
  );

  late AnimationController _pulseController;
  V2RayStatus v2rayStatus = V2RayStatus();

  int _themeIndex = 0;
  AppThemePalette get _theme => kThemes[_themeIndex % kThemes.length];

  bool _nativeVpnRunning = false;
  bool isConnected = false;
  bool isConnecting = false;
  bool isSyncingSubs = false;
  bool isTestingTcp = false;
  bool isTestingReal = false;
  bool isRefreshingPing = false;
  bool _userCancelled = false;

  int currentPing = -1;
  String statusMessage = 'Ready to connect';

  final List<ServerNode> _servers = [];
  final List<String> _customSubInputs = [];
  final Map<String, Map<String, String>> _geoCache = {};

  ServerNode? _selectedServer;
  ServerNode? _connectedServer;

  final List<String> _githubRemoteFiles = const [
    'https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/irancell.txt',
    'https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/mci.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/irancell.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/mci.txt',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initApp();
  }

  Future<void> _initApp() async {
    await v2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );

    await _loadSavedState();
    if (_servers.isEmpty) {
      _loadBuiltInEighteenServers();
    }
    await _syncAllConfigsFromRemote(silent: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _loadBuiltInEighteenServers() {
    final Set<String> seen = {};
    final List<ServerNode> builtIn = [];
    for (final raw in kDefaultVipConfigs) {
      final String clean = raw.trim();
      if (clean.isEmpty || !seen.add(clean)) continue;
      final ServerNode? node = _parseConfigToNode(clean);
      if (node != null) {
        builtIn.add(node);
      }
    }
    setState(() {
      _servers
        ..clear()
        ..addAll(builtIn);
      if (_servers.isNotEmpty) {
        _selectedServer = _servers.first;
      }
      statusMessage = 'Ready • ${_servers.length} VIP servers loaded';
    });
    _resolveAllServerCountriesInBackground();
  }

  Future<File> _getLocalFile(String name) async {
    final List<String> dirs = [
      '/data/user/0/com.nivexia.nivexia_ping/files',
      '/data/data/com.nivexia.nivexia_ping/files',
      Directory.systemTemp.path,
    ];
    for (final d in dirs) {
      try {
        final dir = Directory(d);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return File('${dir.path}/$name');
      } catch (_) {}
    }
    return File('${Directory.systemTemp.path}/$name');
  }

  Future<void> _loadSavedState() async {
    try {
      final File stateFile = await _getLocalFile('nivexia_ state_v8.json'.replaceAll(' ', ''));
      if (await stateFile.exists()) {
        final Map<String, dynamic> data = jsonDecode(await stateFile.readAsString());
        _themeIndex = data['themeIndex'] ?? 0;

        if (data['customSubs'] is List) {
          _customSubInputs.clear();
          for (final item in data['customSubs']) {
            final String s = item.toString().trim();
            if (s.isNotEmpty && !_customSubInputs.contains(s)) {
              _customSubInputs.add(s);
            }
          }
        }

        if (data['servers'] is List) {
          _servers.clear();
          for (final item in data['servers']) {
            final ServerNode srv = ServerNode.fromMap(Map<String, dynamic>.from(item));
            final ServerNode? rebuilt = _parseConfigToNode(srv.rawUri);
            if (rebuilt != null) {
              rebuilt.countryCode = srv.countryCode;
              rebuilt.countryName = srv.countryName;
              rebuilt.tcpPing = srv.tcpPing;
              rebuilt.realPing = srv.realPing;
              _servers.add(rebuilt);
            }
          }
        }

        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _saveStateToDisk() async {
    try {
      final File stateFile = await _getLocalFile('nivexia_state_v8.json');
      final Map<String, dynamic> data = {
        'themeIndex': _themeIndex,
        'customSubs': _customSubInputs,
        'servers': _servers.map((e) => e.toMap()).toList(),
      };
      await stateFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  String _decodeBase64Flexible(String input) {
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

  Map<String, String> _parseQueryParams(String query) {
    final Map<String, String> result = {};
    for (final part in query.split('&')) {
      if (part.isEmpty) continue;
      final int idx = part.indexOf('=');
      if (idx == -1) {
        result[Uri.decodeComponent(part)] = '';
      } else {
        final String k = Uri.decodeComponent(part.substring(0, idx));
        final String v = Uri.decodeComponent(part.substring(idx + 1));
        result[k] = v;
      }
    }
    return result;
  }

  ServerNode? _buildCustomVlessNode(String rawUri) {
    try {
      final String withoutScheme = rawUri.substring(8);
      final int hashIndex = withoutScheme.indexOf('#');
      final String mainAndQuery =
          hashIndex != -1 ? withoutScheme.substring(0, hashIndex) : withoutScheme;
      final String rawRemark =
          hashIndex != -1 ? withoutScheme.substring(hashIndex + 1) : 'VIP - Nivexia';
      String remark = 'VIP - Nivexia';
      try {
        remark = Uri.decodeComponent(rawRemark).trim();
        if (remark.isEmpty) remark = 'VIP - Nivexia';
      } catch (_) {
        remark = rawRemark.trim();
      }

      final int qIndex = mainAndQuery.indexOf('?');
      final String userAndHost =
          qIndex != -1 ? mainAndQuery.substring(0, qIndex) : mainAndQuery;
      final String queryString =
          qIndex != -1 ? mainAndQuery.substring(qIndex + 1) : '';

      final int atIndex = userAndHost.lastIndexOf('@');
      if (atIndex == -1) return null;

      final String uuid = userAndHost.substring(0, atIndex).trim();
      final String hostPort = userAndHost.substring(atIndex + 1).trim();

      final int colonIndex = hostPort.lastIndexOf(':');
      final String address =
          colonIndex != -1 ? hostPort.substring(0, colonIndex).trim() : hostPort;
      final int port = colonIndex != -1
          ? (int.tryParse(hostPort.substring(colonIndex + 1).trim()) ?? 443)
          : 443;

      if (address.isEmpty || uuid.isEmpty) return null;

      final Map<String, String> params = _parseQueryParams(queryString);
      final String network = (params['type'] ?? 'ws').toLowerCase();
      final String security = (params['security'] ?? 'tls').toLowerCase();
      final String hostHeader = (params['host'] ?? params['sni'] ?? '').trim();
      final String sni = (params['sni'] ?? params['host'] ?? address).trim();
      final String fp = (params['fp'] ?? 'chrome').trim();
      final String rawPath = (params['path'] ?? '/').trim();
      final String encryption = (params['encryption'] ?? 'none').trim();
      final String flow = (params['flow'] ?? '').trim();

      final Map<String, dynamic> userMap = {
        "id": uuid,
        "encryption": encryption.isEmpty ? "none" : encryption,
        "level": 8,
      };
      if (flow.isNotEmpty) {
        userMap["flow"] = flow;
      }

      final Map<String, dynamic> streamSettings = {
        "network": network,
        "security": security,
      };

      if (network == 'ws') {
        streamSettings["wsSettings"] = {
          "path": rawPath.isEmpty ? "/" : rawPath,
          "headers": hostHeader.isNotEmpty ? {"Host": hostHeader} : {},
        };
      } else if (network == 'grpc') {
        streamSettings["grpcSettings"] = {
          "serviceName": params['serviceName'] ?? rawPath,
          "multiMode": params['mode'] == 'multi',
        };
      }

      if (security == 'tls') {
        final Map<String, dynamic> tlsSettings = {
          "allowInsecure": true,
          "serverName": sni,
          "fingerprint": fp.isEmpty ? "chrome" : fp,
          "alpn": network == 'ws' ? ["http/1.1"] : ["h2", "http/1.1"],
        };
        streamSettings["tlsSettings"] = tlsSettings;
      } else if (security == 'reality') {
        streamSettings["realitySettings"] = {
          "serverName": sni,
          "fingerprint": fp.isEmpty ? "chrome" : fp,
          "show": false,
          "publicKey": params['pbk'] ?? '',
          "shortId": params['sid'] ?? '',
          "spiderX": params['spx'] ?? '/',
        };
      }

      streamSettings["sockopt"] = {
        "tcpNoDelay": true,
        "domainStrategy": "UseIPv4",
      };

      final Map<String, dynamic> fullConfig = {
        "log": {"loglevel": "warning"},
        "dns": {
          "hosts": {
            "domain:googleapis.cn": "googleapis.com",
            "dns.google": ["8.8.8.8", "8.8.4.4"],
            "cloudflare-dns.com": ["1.1.1.1", "1.0.0.1"],
          },
          "servers": [
            "https://1.1.1.1/dns-query",
            "1.1.1.1",
            "8.8.8.8",
          ]
        },
        "inbounds": [
          {
            "tag": "socks",
            "port": 10808,
            "listen": "127.0.0.1",
            "protocol": "socks",
            "sniffing": {
              "enabled": true,
              "destOverride": ["http", "tls"],
              "routeOnly": false
            },
            "settings": {"auth": "noauth", "udp": true, "userLevel": 8}
          },
          {
            "tag": "http",
            "port": 10809,
            "listen": "127.0.0.1",
            "protocol": "http",
            "sniffing": {
              "enabled": true,
              "destOverride": ["http", "tls"],
              "routeOnly": false
            },
            "settings": {"userLevel": 8}
          }
        ],
        "outbounds": [
          {
            "tag": "proxy",
            "protocol": "vless",
            "settings": {
              "vnext": [
                {
                  "address": address,
                  "port": port,
                  "users": [userMap]
                }
              ]
            },
            "streamSettings": streamSettings,
            "mux": {"enabled": false, "concurrency": -1}
          },
          {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {"domainStrategy": "UseIP"}
          },
          {
            "tag": "block",
            "protocol": "blackhole",
            "settings": {
              "response": {"type": "none"}
            }
          }
        ],
        "routing": {
          "domainStrategy": "IPIfNonMatch",
          "rules": [
            {
              "type": "field",
              "ip": ["geoip:private"],
              "outboundTag": "direct"
            }
          ]
        }
      };

      final String detectedCode = _guessCountryCodeFromName(remark);

      return ServerNode(
        rawUri: rawUri,
        name: remark,
        configJson: jsonEncode(fullConfig),
        protocol: 'VLESS',
        address: address,
        port: port,
        localHttpPort: 10809,
        countryCode: detectedCode,
        countryName: detectedCode == 'UN' ? address : detectedCode,
      );
    } catch (_) {
      return null;
    }
  }

  String _extractRemarkName(String uri, V2RayURL parser) {
    try {
      if (uri.contains('#')) {
        final String rawFragment = uri.split('#').last.trim();
        final String decoded = Uri.decodeComponent(rawFragment).trim();
        if (decoded.isNotEmpty) return decoded;
      }
      final String parserRemark = parser.remark.trim();
      if (parserRemark.isNotEmpty) return parserRemark;
    } catch (_) {
      if (uri.contains('#')) {
        return uri.split('#').last.trim();
      }
    }
    return 'VIP - Nivexia';
  }

  String? _convertSsrToStandardSs(String ssrUri) {
    try {
      final String b64Part = ssrUri.substring(6).trim();
      final String decoded = _decodeBase64Flexible(b64Part);
      if (decoded.isEmpty) return null;

      final List<String> splitParams = decoded.split('/?');
      final String mainPart = splitParams.first;
      final List<String> parts = mainPart.split(':');
      if (parts.length < 6) return null;

      final String host = parts[0].trim();
      final String port = parts[1].trim();
      final String method = parts[3].trim();
      final String passB64 = parts[5].trim();
      final String password = _decodeBase64Flexible(passB64);

      String remark = 'SSR Server';
      if (splitParams.length > 1) {
        final Uri q = Uri.parse('http://localhost/?${splitParams[1]}');
        if (q.queryParameters['remarks'] != null) {
          final String r = _decodeBase64Flexible(q.queryParameters['remarks']!);
          if (r.isNotEmpty) remark = r;
        }
      }

      if (host.isEmpty || password.isEmpty) return null;
      final String userInfoB64 =
          base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
      return 'ss://$userInfoB64@$host:$port#${Uri.encodeComponent(remark)}';
    } catch (_) {
      return null;
    }
  }

  String _normalizeSsUri(String ssUri) {
    try {
      if (!ssUri.startsWith('ss://')) return ssUri;
      final String withoutPrefix = ssUri.substring(5);
      final List<String> hashParts = withoutPrefix.split('#');
      final String mainPart = hashParts.first;
      final String remarkPart =
          hashParts.length > 1 ? '#${hashParts.sublist(1).join('#')}' : '';
      if (!mainPart.contains('@')) {
        final String decoded = _decodeBase64Flexible(mainPart);
        if (decoded.contains('@')) {
          final List<String> atParts = decoded.split('@');
          final String encodedUser =
              base64Url.encode(utf8.encode(atParts.first)).replaceAll('=', '');
          return 'ss://$encodedUser@${atParts.last}$remarkPart';
        }
      }
    } catch (_) {}
    return ssUri;
  }

  ServerNode? _parseConfigToNode(String rawUri) {
    try {
      String uri = rawUri.trim();
      if (uri.startsWith('vless://')) {
        final ServerNode? customVless = _buildCustomVlessNode(uri);
        if (customVless != null) return customVless;
      }

      if (uri.startsWith('ssr://')) {
        final String? conv = _convertSsrToStandardSs(uri);
        if (conv == null) return null;
        uri = conv;
      } else if (uri.startsWith('ss://')) {
        uri = _normalizeSsUri(uri);
      }

      if (!uri.startsWith('vless://') &&
          !uri.startsWith('vmess://') &&
          !uri.startsWith('ss://') &&
          !uri.startsWith('trojan://')) {
        return null;
      }

      final V2RayURL parser = V2ray.parseFromURL(uri);
      final String host = parser.address.trim();
      final int port = parser.port;
      if (host.isEmpty || port <= 0 || port > 65535) return null;

      if (parser.streamSetting['wsSettings'] is Map) {
        final Map ws = parser.streamSetting['wsSettings'];
        if (ws['path'] is String) {
          String p = ws['path'];
          try {
            p = Uri.decodeComponent(p);
          } catch (_) {}
          ws['path'] = p.isEmpty ? '/' : p;
        }
      }

      if (parser.streamSetting['security'] == 'tls' &&
          parser.streamSetting['tlsSettings'] is Map) {
        parser.streamSetting['tlsSettings']['allowInsecure'] = true;
        parser.streamSetting['tlsSettings']['alpn'] = ['http/1.1'];
      }

      final Map<String, dynamic> fullCfg =
          Map<String, dynamic>.from(jsonDecode(parser.getFullConfiguration()));

      fullCfg['dns'] = {
        "servers": ["1.1.1.1", "8.8.8.8"]
      };

      int httpPort = 10809;
      if (fullCfg['inbounds'] is List) {
        final List inbounds = fullCfg['inbounds'] as List;
        bool hasHttp = false;
        for (final ib in inbounds) {
          if (ib is Map && ib['protocol'] == 'http' && ib['port'] is int) {
            httpPort = ib['port'];
            hasHttp = true;
            break;
          }
        }
        if (!hasHttp) {
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

      final String remarkName = _extractRemarkName(uri, parser);
      final String detectedCode = _guessCountryCodeFromName(remarkName);
      final String proto = uri.split('://').first.toUpperCase();

      return ServerNode(
        rawUri: uri,
        name: remarkName,
        configJson: jsonEncode(fullCfg),
        protocol: proto,
        address: host,
        port: port,
        localHttpPort: httpPort,
        countryCode: detectedCode,
        countryName: detectedCode == 'UN' ? host : detectedCode,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _fetchUrlText(String url) async {
    try {
      final http.Response res = await http.get(
        Uri.parse(url.trim()),
        headers: {'User-Agent': 'v2rayNG/1.8.23'},
      ).timeout(const Duration(seconds: 7));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final String body = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
        if (!body.startsWith('<!DOCTYPE html>') && !body.contains('404: Not Found')) {
          return body;
        }
      }
    } catch (_) {}
    return '';
  }

  Future<List<String>> _extractAllConfigsFromRawOrSub(
    String rawText, {
    int depth = 0,
  }) async {
    String content = rawText.trim();
    if (content.isEmpty) return [];

    if (!content.contains('://')) {
      final String decoded = _decodeBase64Flexible(content);
      if (decoded.isNotEmpty) {
        content = decoded;
      }
    }

    final List<String> finalUris = [];
    final List<String> lines = content.split(RegExp(r'[\r\n]+'));

    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;

      if ((line.startsWith('http://') || line.startsWith('https://')) && depth < 2) {
        final String subBody = await _fetchUrlText(line);
        if (subBody.isNotEmpty) {
          final List<String> subConfigs =
              await _extractAllConfigsFromRawOrSub(subBody, depth: depth + 1);
          finalUris.addAll(subConfigs);
        }
      } else if (line.startsWith('vless://') ||
          line.startsWith('vmess://') ||
          line.startsWith('ss://') ||
          line.startsWith('ssr://') ||
          line.startsWith('trojan://')) {
        finalUris.add(line);
      } else {
        final String decLine = _decodeBase64Flexible(line);
        if (decLine.contains('://')) {
          for (String subLine in decLine.split(RegExp(r'[\r\n]+'))) {
            subLine = subLine.trim();
            if (subLine.startsWith('vless://') ||
                subLine.startsWith('vmess://') ||
                subLine.startsWith('ss://') ||
                subLine.startsWith('ssr://') ||
                subLine.startsWith('trojan://')) {
              finalUris.add(subLine);
            }
          }
        }
      }
    }

    return finalUris;
  }

  Future<void> _syncAllConfigsFromRemote({bool silent = false}) async {
    if (isSyncingSubs) return;
    if (mounted) {
      setState(() {
        isSyncingSubs = true;
        if (!silent) statusMessage = 'Updating server list...';
      });
    }

    try {
      final Map<String, ServerNode> oldByAddress = {};
      for (final s in _servers) {
        oldByAddress['${s.address}:${s.port}'] = s;
      }

      final List<String> collectedUris = [];

      for (final url in _githubRemoteFiles) {
        final String txt = await _fetchUrlText(url);
        if (txt.isNotEmpty) {
          collectedUris.addAll(await _extractAllConfigsFromRawOrSub(txt));
        }
      }

      for (final custom in _customSubInputs) {
        collectedUris.addAll(await _extractAllConfigsFromRawOrSub(custom));
      }

      if (collectedUris.isEmpty) {
        collectedUris.addAll(kDefaultVipConfigs);
      }

      final List<ServerNode> parsedNodes = [];
      final Set<String> seenAddresses = {};

      for (final u in collectedUris) {
        final ServerNode? node = _parseConfigToNode(u);
        if (node != null) {
          final String key = '${node.address}:${node.port}';
          if (!seenAddresses.add(key)) continue;
          if (oldByAddress.containsKey(key)) {
            node.countryCode = oldByAddress[key]!.countryCode;
            node.countryName = oldByAddress[key]!.countryName;
            node.tcpPing = oldByAddress[key]!.tcpPing;
            node.realPing = oldByAddress[key]!.realPing;
          }
          parsedNodes.add(node);
        }
      }

      if (parsedNodes.isNotEmpty) {
        _servers
          ..clear()
          ..addAll(parsedNodes);
        _selectedServer ??= _servers.first;
      }

      await _saveStateToDisk();
      _resolveAllServerCountriesInBackground();
    } catch (_) {}

    if (mounted) {
      setState(() {
        isSyncingSubs = false;
        if (!isConnected) {
          statusMessage = 'Ready • ${_servers.length} servers available';
        }
      });
    }
  }

  String _guessCountryCodeFromName(String text) {
    final String upper = text.toUpperCase();
    final Map<String, String> keywords = {
      'TR': 'TR',
      'TURKEY': 'TR',
      'DE': 'DE',
      'GERMANY': 'DE',
      'NL': 'NL',
      'NETHERLANDS': 'NL',
      'US': 'US',
      'USA': 'US',
      'GB': 'GB',
      'UK': 'GB',
      'FR': 'FR',
      'FRANCE': 'FR',
      'FI': 'FI',
      'SE': 'SE',
      'AE': 'AE',
      'CA': 'CA',
      'SG': 'SG',
      'JP': 'JP',
      'RU': 'RU',
    };

    for (final entry in keywords.entries) {
      if (upper.contains(entry.key)) {
        return entry.value;
      }
    }
    return 'UN';
  }

  Future<void> _resolveSingleServerCountry(ServerNode srv) async {
    final String host = srv.address.trim();
    if (host.isEmpty) return;

    if (_geoCache.containsKey(host)) {
      srv.countryCode = _geoCache[host]!['code'] ?? srv.countryCode;
      srv.countryName = _geoCache[host]!['name'] ?? srv.countryName;
      return;
    }

    String queryTarget = host;
    try {
      final List<InternetAddress> addrs = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      if (addrs.isNotEmpty) {
        queryTarget = addrs.first.address;
      }
    } catch (_) {}

    try {
      final http.Response res = await http
          .get(Uri.parse('http://ip-api.com/json/$queryTarget?fields=status,country,countryCode'))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);
        if (data['status'] == 'success') {
          final String cc = (data['countryCode'] ?? 'UN').toString().toUpperCase();
          final String cn = (data['country'] ?? cc).toString();
          _geoCache[host] = {'code': cc, 'name': cn};
          srv.countryCode = cc;
          srv.countryName = cn;
          if (mounted) setState(() {});
          return;
        }
      }
    } catch (_) {}

    try {
      final http.Response res2 = await http
          .get(Uri.parse('https://ipwho.is/$queryTarget'))
          .timeout(const Duration(seconds: 4));
      if (res2.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res2.body);
        if (data['success'] == true) {
          final String cc = (data['country_code'] ?? 'UN').toString().toUpperCase();
          final String cn = (data['country'] ?? cc).toString();
          _geoCache[host] = {'code': cc, 'name': cn};
          srv.countryCode = cc;
          srv.countryName = cn;
          if (mounted) setState(() {});
        }
      }
    } catch (_) {}
  }

  Future<void> _resolveAllServerCountriesInBackground() async {
    for (final srv in _servers) {
      await _resolveSingleServerCountry(srv);
    }
    await _saveStateToDisk();
  }

  String _countryCodeToEmoji(String code) {
    final String clean = code.trim().toUpperCase();
    if (clean.length != 2 || clean == 'UN') return '🌐';
    final int first = clean.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int second = clean.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }

  Widget _buildHighQualityFlag(String countryCode, {double size = 28}) {
    final String cc = countryCode.trim().toLowerCase();
    if (cc.length != 2 || cc == 'un') {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _theme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
        ),
        child: Text('🌐', style: TextStyle(fontSize: size * 0.58)),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 4,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.network(
          'https://flagcdn.com/w160/$cc.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: _theme.surface,
              alignment: Alignment.center,
              child: Text(
                _countryCodeToEmoji(cc),
                style: TextStyle(fontSize: size * 0.6),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<int> _measureTcpPing(String host, int port) async {
    Socket? socket;
    try {
      final Stopwatch sw = Stopwatch()..start();
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 1200),
      );
      sw.stop();
      await socket.close();
      return sw.elapsedMilliseconds;
    } catch (_) {
      socket?.destroy();
      return -1;
    }
  }

  Future<int> _measureRealCorePing(ServerNode srv) async {
    final int tcp = await _measureTcpPing(srv.address, srv.port);
    if (tcp <= 0) return -1;
    srv.tcpPing = tcp;

    try {
      final int delay = await v2ray
          .getServerDelay(
            config: srv.configJson,
            url: 'http://cp.cloudflare.com/generate_204',
          )
          .timeout(const Duration(milliseconds: 3200), onTimeout: () => -1);

      if (delay > 0 && delay < 4000) {
        return delay;
      }
    } catch (_) {}

    return tcp;
  }

  Future<void> _runTcpPingAll() async {
    if (isTestingTcp || isTestingReal || _servers.isEmpty) return;

    setState(() {
      isTestingTcp = true;
      statusMessage = 'Running TCP Ping test...';
    });

    await Future.wait(_servers.map((srv) async {
      final int ms = await _measureTcpPing(srv.address, srv.port);
      srv.tcpPing = ms;
      if (mounted) setState(() {});
    }));

    await _saveStateToDisk();
    if (mounted) {
      setState(() {
        isTestingTcp = false;
        statusMessage = 'TCP Ping test completed';
      });
    }
  }

  Future<void> _runRealTestAll() async {
    if (isTestingReal || isTestingTcp || _servers.isEmpty) return;

    setState(() {
      isTestingReal = true;
      statusMessage = 'Running Real Config test...';
    });

    for (final srv in _servers) {
      if (!mounted) break;
      final int realMs = await _measureRealCorePing(srv);
      srv.realPing = realMs;
      setState(() {});
    }

    await _saveStateToDisk();
    if (mounted) {
      setState(() {
        isTestingReal = false;
        statusMessage = 'Real Config test completed';
      });
    }
  }

  Future<void> _refreshSingleServerPing(ServerNode srv) async {
    if (isRefreshingPing) return;
    setState(() => isRefreshingPing = true);

    try {
      int p = -1;
      if (isConnected && _connectedServer?.address == srv.address) {
        try {
          p = await v2ray
              .getConnectedServerDelay()
              .timeout(const Duration(milliseconds: 2500), onTimeout: () => -1);
        } catch (_) {}
      }
      if (p <= 0) {
        p = await _measureRealCorePing(srv);
      }

      if (mounted) {
        setState(() {
          if (p > 0) {
            srv.realPing = p;
            srv.tcpPing = p;
            currentPing = p;
          }
        });
      }
      await _resolveSingleServerCountry(srv);
    } catch (_) {}

    if (mounted) {
      setState(() => isRefreshingPing = false);
    }
  }

  Future<void> _triggerTunnelTrafficWarmup() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      client.findProxy = (uri) => "PROXY 127.0.0.1:10809";
      final req = await client
          .getUrl(Uri.parse('http://cp.cloudflare.com/generate_204'))
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain();
      client.close(force: true);
    } catch (_) {
      client?.close(force: true);
    }
  }

  Future<bool> _startVpnWithNode(ServerNode node) async {
    try {
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 350));

      _nativeVpnRunning = false;
      await v2ray.startV2Ray(
        remark: node.name,
        config: node.configJson,
        blockedApps: null,
        bypassSubnets: null,
        proxyOnly: false,
      );

      int waited = 0;
      while (!_nativeVpnRunning && waited < 3500) {
        if (_userCancelled) {
          await v2ray.stopV2Ray();
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 150));
        waited += 150;
      }

      if (!_nativeVpnRunning) {
        await v2ray.stopV2Ray();
        return false;
      }

      _connectedServer = node;
      _selectedServer = node;

      _resolveSingleServerCountry(node);
      _triggerTunnelTrafficWarmup();

      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
          currentPing = node.displayPing;
          statusMessage = 'Connected • ${node.name}';
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

  Future<void> _onConnectButtonPressed({ServerNode? specificServer}) async {
    if ((isConnected || isConnecting) && specificServer == null) {
      _userCancelled = true;
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
        _nativeVpnRunning = false;
        statusMessage = 'Disconnected';
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
      isConnected = false;
      _userCancelled = false;
      statusMessage = 'Testing & connecting...';
    });

    if (_servers.isEmpty) {
      _loadBuiltInEighteenServers();
    }

    if (specificServer != null) {
      final int ping = await _measureRealCorePing(specificServer);
      if (ping > 0) specificServer.realPing = ping;
      final bool ok = await _startVpnWithNode(specificServer);
      if (!ok && mounted) {
        setState(() {
          isConnecting = false;
          statusMessage = 'Failed to connect to ${specificServer.name}';
        });
      }
      return;
    }

    final List<ServerNode> alive = [];
    await Future.wait(_servers.map((srv) async {
      final int tcp = await _measureTcpPing(srv.address, srv.port);
      if (tcp > 0) {
        srv.tcpPing = tcp;
        alive.add(srv);
      }
    }));

    if (alive.isEmpty || _userCancelled) {
      if (mounted) {
        setState(() {
          isConnecting = false;
          statusMessage = 'No server responded to ping test';
        });
      }
      return;
    }

    alive.sort((a, b) => a.tcpPing.compareTo(b.tcpPing));

    for (final candidate in alive) {
      if (_userCancelled) break;
      if (mounted) {
        setState(() {
          statusMessage = 'Connecting to ${candidate.name} (${candidate.tcpPing} ms)...';
        });
      }

      final int realMs = await _measureRealCorePing(candidate);
      if (realMs > 0) {
        candidate.realPing = realMs;
        final bool connected = await _startVpnWithNode(candidate);
        if (connected) return;
      }
    }

    if (mounted && !_userCancelled) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'Could not establish connection';
      });
    }
  }

  void _openAddCustomSubSheet() {
    final TextEditingController inputCtrl = TextEditingController();
    bool isAdding = false;
    String feedbackText = '';

    showModalBottomSheet(
      context: context,
      backgroundColor: _theme.card,
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
                      Text(
                        'ADD SUBSCRIPTION / CONFIGS',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _theme.primary,
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
                    'Paste a Subscription URL (https://...) or configs (vless://, vmess://, ss://, trojan://):',
                    style: TextStyle(fontSize: 11.5, color: Colors.white60),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: inputCtrl,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'https://sub-link... or vless://...#Name',
                      filled: true,
                      fillColor: _theme.bg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (feedbackText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        feedbackText,
                        style: TextStyle(
                          fontSize: 12,
                          color: _theme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _theme.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isAdding
                          ? null
                          : () async {
                              final String raw = inputCtrl.text.trim();
                              if (raw.isEmpty) return;

                              setModalState(() {
                                isAdding = true;
                                feedbackText = 'Reading & extracting configs...';
                              });

                              final List<String> extractedUris =
                                  await _extractAllConfigsFromRawOrSub(raw);

                              int addedCount = 0;
                              for (final u in extractedUris) {
                                final ServerNode? node = _parseConfigToNode(u);
                                if (node != null &&
                                    !_servers.any(
                                        (s) => s.address == node.address && s.port == node.port)) {
                                  _servers.add(node);
                                  addedCount++;
                                }
                              }

                              if (extractedUris.isNotEmpty && !_customSubInputs.contains(raw)) {
                                _customSubInputs.add(raw);
                                await _saveStateToDisk();
                                _resolveAllServerCountriesInBackground();
                              }

                              setModalState(() {
                                isAdding = false;
                                feedbackText = extractedUris.isEmpty
                                    ? 'No valid configs found in input!'
                                    : 'Added $addedCount new config(s)!';
                              });
                              inputCtrl.clear();
                              if (mounted) setState(() {});
                            },
                      icon: isAdding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: Text(
                        isAdding ? 'Extracting...' : 'Fetch & Add Configs',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final Color activeColor = isConnected
        ? _theme.primary
        : (isConnecting ? Colors.amberAccent : _theme.secondary);

    return Scaffold(
      backgroundColor: _theme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
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
                          Text(
                            'NIVEXIA',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3.0,
                              color: _theme.primary,
                            ),
                          ),
                          Text(
                            _theme.name.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              letterSpacing: 1.5,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Change Theme',
                        onPressed: () {
                          setState(() {
                            _themeIndex = (_themeIndex + 1) % kThemes.length;
                          });
                          _saveStateToDisk();
                        },
                        icon: Icon(Icons.palette_outlined, color: _theme.primary, size: 20),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Add Custom Sub / Config',
                        onPressed: _openAddCustomSubSheet,
                        icon: Icon(Icons.add_circle_outline_rounded, color: _theme.primary, size: 21),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Sync GitHub Configs',
                        onPressed: () => _syncAllConfigsFromRemote(silent: false),
                        icon: isSyncingSubs
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _theme.primary,
                                ),
                              )
                            : const Icon(Icons.sync_rounded, color: Colors.white70, size: 20),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      final ServerNode? target = _connectedServer ??
                          _selectedServer ??
                          (_servers.isNotEmpty ? _servers.first : null);
                      if (target != null) {
                        _refreshSingleServerPing(target);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _theme.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: activeColor.withOpacity(0.55)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isRefreshingPing)
                            SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _theme.primary,
                              ),
                            )
                          else
                            Icon(Icons.bolt_rounded, color: activeColor, size: 16),
                          const SizedBox(width: 5),
                          Text(
                            currentPing > 0 ? '$currentPing ms' : '-- ms',
                            style: TextStyle(
                              color: activeColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.refresh_rounded, color: Colors.white54, size: 13),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _onConnectButtonPressed(),
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final double spread = isConnected
                            ? (4.0 + (_pulseController.value * 7.0))
                            : (1.5 + (_pulseController.value * 3.0));
                        return Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _theme.card,
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withOpacity(isConnected ? 0.35 : 0.16),
                                blurRadius: isConnected ? 30 : 18,
                                spreadRadius: spread,
                              ),
                            ],
                            border: Border.all(color: activeColor, width: 2.8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isConnecting
                                    ? Icons.sync_rounded
                                    : Icons.power_settings_new_rounded,
                                size: 42,
                                color: activeColor,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isConnecting
                                    ? 'WAIT...'
                                    : (isConnected ? 'CONNECTED' : 'CONNECT'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.3,
                                  color: isConnected ? _theme.primary : Colors.white,
                                ),
                              ),
                              if (isConnected) ...[
                                const SizedBox(height: 3),
                                Text(
                                  v2rayStatus.duration,
                                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (_connectedServer != null) {
                              _refreshSingleServerPing(_connectedServer!);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _theme.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: activeColor.withOpacity(0.35)),
                            ),
                            child: Row(
                              children: [
                                _buildHighQualityFlag(
                                  _connectedServer?.countryCode ??
                                      _selectedServer?.countryCode ??
                                      'UN',
                                  size: 26,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isConnected && _connectedServer != null
                                            ? _connectedServer!.name
                                            : statusMessage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isConnected && _connectedServer != null
                                            ? '${_connectedServer!.countryName} • ${currentPing > 0 ? "$currentPing ms" : "Tap to ping"}'
                                            : '${_servers.length} VIP Servers Ready',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: _theme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: _theme.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.south_rounded, color: _theme.primary, size: 13),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'DOWNLOAD',
                                          style: TextStyle(fontSize: 8.5, color: Colors.white54),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isConnected ? _formatSpeed(v2rayStatus.downloadSpeed) : '0 B/s',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: _theme.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.north_rounded, color: _theme.secondary, size: 13),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'UPLOAD',
                                          style: TextStyle(fontSize: 8.5, color: Colors.white54),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isConnected ? _formatSpeed(v2rayStatus.uploadSpeed) : '0 B/s',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SERVERS (${_servers.length})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: _runTcpPingAll,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _theme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _theme.primary.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              if (isTestingTcp)
                                SizedBox(
                                  width: 11,
                                  height: 11,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: _theme.primary,
                                  ),
                                )
                              else
                                Icon(Icons.speed_rounded, size: 13, color: _theme.primary),
                              const SizedBox(width: 5),
                              Text(
                                'TCP Ping',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: _theme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _runRealTestAll,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _theme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _theme.secondary.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              if (isTestingReal)
                                const SizedBox(
                                  width: 11,
                                  height: 11,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: Colors.amberAccent,
                                  ),
                                )
                              else
                                const Icon(Icons.verified_outlined, size: 13, color: Colors.amberAccent),
                              const SizedBox(width: 5),
                              const Text(
                                'Real Test',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amberAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: _servers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final ServerNode srv = _servers[index];
                    final bool isThisConnected =
                        isConnected && _connectedServer?.address == srv.address;
                    final bool isThisSelected =
                        _selectedServer?.address == srv.address;

                    final int pingVal = srv.displayPing;
                    final Color pingColor = pingVal <= 0
                        ? Colors.white38
                        : (pingVal < 250
                            ? Colors.greenAccent
                            : (pingVal < 600 ? Colors.amberAccent : Colors.redAccent));

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedServer = srv;
                          if (srv.displayPing > 0) {
                            currentPing = srv.displayPing;
                          }
                        });
                        _onConnectButtonPressed(specificServer: srv);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isThisConnected
                              ? _theme.primary.withOpacity(0.12)
                              : _theme.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isThisConnected
                                ? _theme.primary
                                : (isThisSelected
                                    ? _theme.primary.withOpacity(0.45)
                                    : Colors.white10),
                            width: isThisConnected ? 1.8 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildHighQualityFlag(srv.countryCode, size: 34),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    srv.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: isThisConnected
                                          ? _theme.primary
                                          : Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    srv.countryCode != 'UN'
                                        ? '${srv.countryName} (${srv.address})'
                                        : srv.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _refreshSingleServerPing(srv),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _theme.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: pingColor.withOpacity(0.4),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.bolt_rounded,
                                      size: 14,
                                      color: pingColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      pingVal > 0 ? '$pingVal ms' : 'Ping',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: pingColor,
                                      ),
                                    ),
                                  ],
                                ),
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
        ),
      ),
    );
  }
}
