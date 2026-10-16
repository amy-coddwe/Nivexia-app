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

class AppThemePalette {
  final String name;
  final Color bgTop;
  final Color bgBottom;
  final Color card;
  final Color cardBorder;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color connected;

  const AppThemePalette({
    required this.name,
    required this.bgTop,
    required this.bgBottom,
    required this.card,
    required this.cardBorder,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.connected,
  });
}

const List<AppThemePalette> kThemes = [
  AppThemePalette(
    name: 'Royal Indigo',
    bgTop: Color(0xFF0F172A),
    bgBottom: Color(0xFF070A12),
    card: Color(0xFF161F33),
    cardBorder: Color(0xFF26334D),
    surface: Color(0xFF1E293B),
    primary: Color(0xFF6366F1),
    secondary: Color(0xFF8B5CF6),
    connected: Color(0xFF10B981),
  ),
  AppThemePalette(
    name: 'Titanium Blue',
    bgTop: Color(0xFF0B192C),
    bgBottom: Color(0xFF050B14),
    card: Color(0xFF112239),
    cardBorder: Color(0xFF1E375A),
    surface: Color(0xFF172D4A),
    primary: Color(0xFF38BDF8),
    secondary: Color(0xFF0284C7),
    connected: Color(0xFF2DD4BF),
  ),
  AppThemePalette(
    name: 'Midnight Aurora',
    bgTop: Color(0xFF13111C),
    bgBottom: Color(0xFF08070C),
    card: Color(0xFF1C1929),
    cardBorder: Color(0xFF2E2942),
    surface: Color(0xFF252136),
    primary: Color(0xFFA855F7),
    secondary: Color(0xFFEC4899),
    connected: Color(0xFF34D399),
  ),
  AppThemePalette(
    name: 'Amber Obsidian',
    bgTop: Color(0xFF181411),
    bgBottom: Color(0xFF0A0807),
    card: Color(0xFF221C18),
    cardBorder: Color(0xFF382E28),
    surface: Color(0xFF2C241F),
    primary: Color(0xFFF59E0B),
    secondary: Color(0xFFEA580C),
    connected: Color(0xFF10B981),
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
        scaffoldBackgroundColor: kThemes[0].bgBottom,
      ),
      home: const HomeScreen(),
    );
  }
}

class ServerNode {
  final String rawUri;
  final String name;
  String configJson;
  final String protocol;
  final String address;
  final int port;
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
    this.countryCode = 'UN',
    this.countryName = 'Detecting...',
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
        'countryCode': countryCode,
        'countryName': countryName,
        'tcpPing': tcpPing,
        'realPing': realPing,
      };
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
  bool _cancelRealTest = false;

  // Auto mode is selected by default when the user opens the app
  bool _isAutoMode = true;

  int currentPing = -1;
  String statusMessage = 'Ready • Auto Mode Selected';

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
      duration: const Duration(milliseconds: 1800),
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
    setState(() {
      _isAutoMode = true;
      _selectedServer = null;
    });
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
      if (clean.isEmpty) continue;
      final ServerNode? node = _parseConfigToNode(clean);
      if (node != null && seen.add('${node.address}:${node.port}')) {
        builtIn.add(node);
      }
    }
    setState(() {
      _servers
        ..clear()
        ..addAll(builtIn);
      _isAutoMode = true;
      _selectedServer = null;
      statusMessage = 'Auto Mode • ${_servers.length} VIP servers ready';
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
      final File stateFile = await _getLocalFile('nivexia_state_v10.json');
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
            final Map<String, dynamic> m = Map<String, dynamic>.from(item);
            final String rawUri = (m['rawUri'] ?? '').toString();
            final ServerNode? rebuilt = _parseConfigToNode(rawUri);
            if (rebuilt != null) {
              rebuilt.countryCode = (m['countryCode'] ?? 'UN').toString();
              rebuilt.countryName = (m['countryName'] ?? rebuilt.address).toString();
              rebuilt.tcpPing = (m['tcpPing'] is int) ? m['tcpPing'] : -1;
              rebuilt.realPing = (m['realPing'] is int) ? m['realPing'] : -1;
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
      final File stateFile = await _getLocalFile('nivexia_state_v10.json');
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
        try {
          result[Uri.decodeComponent(part)] = '';
        } catch (_) {
          result[part] = '';
        }
      } else {
        final String rawK = part.substring(0, idx);
        final String rawV = part.substring(idx + 1);
        String k = rawK;
        String v = rawV;
        try {
          k = Uri.decodeComponent(rawK);
        } catch (_) {}
        try {
          v = Uri.decodeComponent(rawV);
        } catch (_) {}
        result[k] = v;
      }
    }
    return result;
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

      Map<String, String> queryParams = {};
      if (uri.contains('?')) {
        final String qPart = uri.split('?').sublist(1).join('?').split('#').first;
        queryParams = _parseQueryParams(qPart);
      }

      final String hostHeader =
          (queryParams['host'] ?? queryParams['sni'] ?? '').trim();
      final String sniHeader =
          (queryParams['sni'] ?? queryParams['host'] ?? host).trim();
      final String fpHeader = (queryParams['fp'] ?? 'chrome').trim();
      final String echParam = (queryParams['ech'] ?? '').trim();
      final String pathParam = (queryParams['path'] ?? '').trim();
      final bool allowInsecureParam =
          queryParams['allowInsecure'] == '1' || queryParams['insecure'] == '1';

      final Map<String, dynamic> baseCfg =
          Map<String, dynamic>.from(jsonDecode(parser.getFullConfiguration()));

      baseCfg['dns'] = {
        "servers": ["8.8.8.8", "1.1.1.1"]
      };

      if (baseCfg['inbounds'] is List) {
        for (final ib in (baseCfg['inbounds'] as List)) {
          if (ib is Map) {
            ib['sniffing'] = {
              "enabled": true,
              "destOverride": ["http", "tls"]
            };
            if (ib['protocol'] == 'socks' && ib['settings'] is Map) {
              ib['settings']['udp'] = true;
            }
          }
        }
      }

      if (baseCfg['outbounds'] is List && (baseCfg['outbounds'] as List).isNotEmpty) {
        final Map<String, dynamic> mainOutbound =
            Map<String, dynamic>.from((baseCfg['outbounds'] as List).first);
        mainOutbound['tag'] = 'proxy';

        if (mainOutbound['streamSettings'] is Map) {
          final Map<String, dynamic> stream =
              Map<String, dynamic>.from(mainOutbound['streamSettings']);
          final String net = (stream['network'] ?? 'tcp').toString().toLowerCase();

          if (net == 'ws') {
            final Map<String, dynamic> ws = stream['wsSettings'] is Map
                ? Map<String, dynamic>.from(stream['wsSettings'])
                : <String, dynamic>{};

            String cleanPath = pathParam.isNotEmpty
                ? pathParam
                : (ws['path'] ?? '/').toString();
            try {
              cleanPath = Uri.decodeComponent(cleanPath);
            } catch (_) {}
            if (cleanPath.isEmpty) cleanPath = '/';

            ws['path'] = cleanPath;
            if (hostHeader.isNotEmpty) {
              ws['host'] = hostHeader;
              ws['headers'] = {'Host': hostHeader};
            }
            stream['wsSettings'] = ws;
          }

          if (stream['security'] == 'tls') {
            final Map<String, dynamic> tls = stream['tlsSettings'] is Map
                ? Map<String, dynamic>.from(stream['tlsSettings'])
                : <String, dynamic>{};

            tls['allowInsecure'] = allowInsecureParam;
            if (sniHeader.isNotEmpty) {
              tls['serverName'] = sniHeader;
            }
            tls['fingerprint'] = fpHeader.isEmpty ? 'chrome' : fpHeader;
            if (net == 'ws') {
              tls['alpn'] = ['http/1.1'];
            }
            if (echParam.isNotEmpty) {
              tls['echConfigList'] = echParam;
            }
            stream['tlsSettings'] = tls;
          }

          mainOutbound['streamSettings'] = stream;
        }

        (baseCfg['outbounds'] as List)[0] = mainOutbound;
      }

      final String remarkName = _extractRemarkName(uri, parser);
      final String detectedCode = _guessCountryCodeFromName(remarkName);
      final String proto = uri.split('://').first.toUpperCase();

      return ServerNode(
        rawUri: uri,
        name: remarkName,
        configJson: jsonEncode(baseCfg),
        protocol: proto,
        address: host,
        port: port,
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
        if (!silent) statusMessage = 'Syncing servers...';
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
      }

      await _saveStateToDisk();
      _resolveAllServerCountriesInBackground();
    } catch (_) {}

    if (mounted) {
      setState(() {
        isSyncingSubs = false;
        if (!isConnected) {
          statusMessage = _isAutoMode
              ? 'Auto Mode • ${_servers.length} servers ready'
              : '${_selectedServer?.countryName ?? "Server"} selected';
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

  Widget _buildHighQualityFlag(String countryCode, {double size = 32, bool isAuto = false}) {
    if (isAuto) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_theme.primary, _theme.secondary],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _theme.primary.withOpacity(0.35),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(
          Icons.hdr_auto_rounded,
          color: Colors.white,
          size: size * 0.62,
        ),
      );
    }

    final String cc = countryCode.trim().toLowerCase();
    if (cc.length != 2 || cc == 'un') {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _theme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: _theme.cardBorder),
        ),
        child: Text('🌐', style: TextStyle(fontSize: size * 0.55)),
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
            blurRadius: 6,
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
                style: TextStyle(fontSize: size * 0.58),
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
        timeout: const Duration(milliseconds: 900),
      );
      sw.stop();
      await socket.close();
      final int ms = sw.elapsedMilliseconds;
      if (ms < 20) return -1;
      return ms;
    } catch (_) {
      socket?.destroy();
      return -1;
    }
  }

  Future<int> _measureRealCorePing(ServerNode srv) async {
    final int tcp = await _measureTcpPing(srv.address, srv.port);
    if (tcp < 20) {
      srv.tcpPing = -1;
      srv.realPing = -1;
      return -1;
    }
    srv.tcpPing = tcp;

    try {
      final int delay = await v2ray
          .getServerDelay(
            config: srv.configJson,
            url: 'http://cp.cloudflare.com/generate_204',
          )
          .timeout(const Duration(milliseconds: 2200), onTimeout: () => -1);

      if (delay >= 20 && delay < 4000) {
        srv.realPing = delay;
        return delay;
      }
    } catch (_) {}

    return -1;
  }

  Future<void> _runTcpPingAll() async {
    if (isTestingTcp || _servers.isEmpty) return;

    setState(() {
      isTestingTcp = true;
      statusMessage = 'Measuring TCP latency...';
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
        statusMessage = 'TCP Ping test finished';
      });
    }
  }

  // Fast parallel Real Test with toggle-off support when tapped a second time
  Future<void> _runRealTestAll() async {
    if (_servers.isEmpty) return;

    // If already running, tapping again stops the scan immediately
    if (isTestingReal) {
      setState(() {
        _cancelRealTest = true;
        isTestingReal = false;
        statusMessage = 'Real test stopped';
      });
      return;
    }

    setState(() {
      isTestingReal = true;
      _cancelRealTest = false;
      statusMessage = 'Running fast real test...';
    });

    const int batchSize = 5;
    for (int i = 0; i < _servers.length; i += batchSize) {
      if (_cancelRealTest || !mounted) break;
      final int end = min(i + batchSize, _servers.length);
      final List<ServerNode> batch = _servers.sublist(i, end);

      await Future.wait(batch.map((srv) async {
        if (_cancelRealTest) return;
        final int realMs = await _measureRealCorePing(srv);
        if (!_cancelRealTest && mounted) {
          setState(() {
            srv.realPing = realMs;
          });
        }
      }));
    }

    await _saveStateToDisk();
    if (mounted) {
      setState(() {
        isTestingReal = false;
        statusMessage = _cancelRealTest ? 'Real test stopped' : 'Real test completed';
        _cancelRealTest = false;
      });
    }
  }

  Future<void> _refreshSingleServerPing(ServerNode? srv) async {
    if (isRefreshingPing) return;
    final ServerNode? target = srv ??
        _connectedServer ??
        _selectedServer ??
        (_servers.isNotEmpty ? _servers.first : null);
    if (target == null) return;

    setState(() => isRefreshingPing = true);

    try {
      int p = -1;
      if (isConnected && _connectedServer?.address == target.address) {
        try {
          p = await v2ray
              .getConnectedServerDelay()
              .timeout(const Duration(milliseconds: 2200), onTimeout: () => -1);
        } catch (_) {}
      }
      if (p < 20) {
        p = await _measureRealCorePing(target);
      }
      if (p < 20) {
        p = await _measureTcpPing(target.address, target.port);
      }

      if (mounted) {
        setState(() {
          if (p >= 20) {
            target.realPing = p;
            target.tcpPing = p;
            currentPing = p;
          }
        });
      }
      await _resolveSingleServerCountry(target);
    } catch (_) {}

    if (mounted) {
      setState(() => isRefreshingPing = false);
    }
  }

  // Direct 1-shot connection without any multi-variant loop
  Future<bool> _startVpnWithNode(ServerNode node) async {
    try {
      if (_nativeVpnRunning || isConnected) {
        try {
          await v2ray.stopV2Ray();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _nativeVpnRunning = false;
      await v2ray.startV2Ray(
        remark: node.name,
        config: node.configJson,
        blockedApps: null,
        bypassSubnets: null,
        proxyOnly: false,
      );

      int waited = 0;
      while (!_nativeVpnRunning && waited < 3000) {
        if (_userCancelled) {
          await v2ray.stopV2Ray();
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 100));
        waited += 100;
      }

      if (!_nativeVpnRunning) {
        await v2ray.stopV2Ray();
        return false;
      }

      _connectedServer = node;
      _resolveSingleServerCountry(node);

      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
          currentPing = node.displayPing;
          statusMessage = 'Connected • ${node.countryName}';
        });
      }

      // Update live ping in the background without interrupting the tunnel
      Future.delayed(const Duration(milliseconds: 600), () async {
        if (!mounted || !isConnected || _connectedServer?.address != node.address) return;
        try {
          int delay = await v2ray
              .getConnectedServerDelay()
              .timeout(const Duration(milliseconds: 2500), onTimeout: () => -1);
          if (delay < 20) {
            delay = await _measureTcpPing(node.address, node.port);
          }
          if (delay >= 20 && mounted) {
            setState(() {
              node.realPing = delay;
              currentPing = delay;
            });
          }
        } catch (_) {}
      });

      return true;
    } catch (_) {
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      return false;
    }
  }

  // Instant server switch when already connected, or simple selection when disconnected
  Future<void> _onServerItemTapped(ServerNode? srv, {required bool isAutoItem}) async {
    if (isAutoItem) {
      setState(() {
        _isAutoMode = true;
        _selectedServer = null;
        if (!isConnected) {
          statusMessage = 'Auto Mode • Tap START to connect';
        }
      });
      if (isConnected) {
        await _connectAutoBestServer();
      }
      return;
    }

    if (srv == null) return;

    setState(() {
      _isAutoMode = false;
      _selectedServer = srv;
      if (srv.displayPing > 0) {
        currentPing = srv.displayPing;
      }
      if (!isConnected) {
        statusMessage = 'Selected ${srv.countryName} • Tap START';
      }
    });

    // If already connected to another server, switch immediately in 1 shot
    if (isConnected && _connectedServer?.address != srv.address) {
      setState(() {
        isConnecting = true;
        _userCancelled = false;
        statusMessage = 'Switching to ${srv.countryName}...';
      });
      final bool ok = await _startVpnWithNode(srv);
      if (!ok && mounted) {
        setState(() {
          isConnecting = false;
          statusMessage = 'Failed to switch to ${srv.countryName}';
        });
      }
    }
  }

  Future<void> _connectAutoBestServer() async {
    setState(() {
      isConnecting = true;
      _userCancelled = false;
      statusMessage = 'Auto Mode • Finding fastest server...';
    });

    if (_servers.isEmpty) {
      _loadBuiltInEighteenServers();
    }

    final List<ServerNode> alive = [];
    await Future.wait(_servers.map((srv) async {
      final int tcp = await _measureTcpPing(srv.address, srv.port);
      if (tcp >= 20) {
        srv.tcpPing = tcp;
        alive.add(srv);
      }
    }));

    if (alive.isEmpty || _userCancelled) {
      if (mounted) {
        setState(() {
          isConnecting = false;
          statusMessage = 'No active servers responded';
        });
      }
      return;
    }

    alive.sort((a, b) => a.displayPing.compareTo(b.displayPing));

    for (final candidate in alive) {
      if (_userCancelled) break;
      if (mounted) {
        setState(() {
          statusMessage = 'Connecting to ${candidate.countryName} (${candidate.tcpPing} ms)...';
        });
      }
      final bool connected = await _startVpnWithNode(candidate);
      if (connected) return;
    }

    if (mounted && !_userCancelled) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'Could not establish connection';
      });
    }
  }

  Future<void> _onConnectButtonPressed() async {
    if (isConnected || isConnecting) {
      _userCancelled = true;
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
        _nativeVpnRunning = false;
        statusMessage = _isAutoMode
            ? 'Disconnected • Auto Mode'
            : 'Disconnected • ${_selectedServer?.countryName ?? "Ready"}';
      });
      return;
    }

    final bool hasPerm = await v2ray.requestPermission();
    if (!hasPerm) {
      setState(() => statusMessage = 'VPN Permission Required');
      return;
    }

    if (_servers.isEmpty) {
      _loadBuiltInEighteenServers();
    }

    // If Auto is selected, scan and connect to the best server
    if (_isAutoMode || _selectedServer == null) {
      await _connectAutoBestServer();
      return;
    }

    // If a specific server is selected, connect to it directly in 1 shot
    final ServerNode target = _selectedServer!;
    setState(() {
      isConnecting = true;
      isConnected = false;
      _userCancelled = false;
      statusMessage = 'Connecting to ${target.countryName}...';
    });

    final bool ok = await _startVpnWithNode(target);
    if (!ok && mounted && !_userCancelled) {
      setState(() {
        isConnecting = false;
        statusMessage = 'Server unreachable • Try Auto or another node';
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Import Configs / Subscription',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _theme.primary,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Paste a Subscription link (https://...) or VLESS / VMess / Trojan / Shadowsocks configs:',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: inputCtrl,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: 'https://... or vless://...',
                      filled: true,
                      fillColor: _theme.bgBottom,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _theme.cardBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (feedbackText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Text(
                        feedbackText,
                        style: TextStyle(
                          fontSize: 12,
                          color: _theme.connected,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _theme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: isAdding
                          ? null
                          : () async {
                              final String raw = inputCtrl.text.trim();
                              if (raw.isEmpty) return;

                              setModalState(() {
                                isAdding = true;
                                feedbackText = 'Parsing & importing...';
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
                                    ? 'No valid configs found!'
                                    : 'Imported $addedCount new server(s) successfully!';
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
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_task_rounded, size: 18),
                      label: Text(
                        isAdding ? 'Importing...' : 'Import Now',
                        style: const TextStyle(fontWeight: FontWeight.w800),
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
    return '${(val / 1048576).toStringAsFixed(2)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    final Color statusAccent = isConnected
        ? _theme.connected
        : (isConnecting ? Colors.amberAccent : _theme.primary);

    final ServerNode? activeDisplayNode =
        isConnected ? _connectedServer : _selectedServer;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_theme.bgTop, _theme.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
            child: Column(
              children: [
                // Top App Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_theme.primary, _theme.secondary],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            color: Colors.white,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'NIVEXIA',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.2,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              _theme.name,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: _theme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildTopIconButton(
                          icon: Icons.palette_outlined,
                          onTap: () {
                            setState(() {
                              _themeIndex = (_themeIndex + 1) % kThemes.length;
                            });
                            _saveStateToDisk();
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildTopIconButton(
                          icon: Icons.add_rounded,
                          onTap: _openAddCustomSubSheet,
                        ),
                        const SizedBox(width: 8),
                        _buildTopIconButton(
                          icon: Icons.sync_rounded,
                          isLoading: isSyncingSubs,
                          onTap: () => _syncAllConfigsFromRemote(silent: false),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Hero Dashboard Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _theme.card,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: isConnected
                          ? _theme.connected.withOpacity(0.45)
                          : _theme.cardBorder,
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: statusAccent.withOpacity(0.10),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Animated Power Orb
                          GestureDetector(
                            onTap: _onConnectButtonPressed,
                            child: AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                final double pulse = _pulseController.value;
                                return Container(
                                  width: 104,
                                  height: 104,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: isConnected
                                          ? [
                                              _theme.connected,
                                              _theme.connected.withOpacity(0.7)
                                            ]
                                          : (isConnecting
                                              ? [Colors.amber, Colors.orangeAccent]
                                              : [_theme.primary, _theme.secondary]),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: statusAccent.withOpacity(
                                            0.28 + (pulse * 0.18)),
                                        blurRadius: 20 + (pulse * 10),
                                        spreadRadius: 2 + (pulse * 4),
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.all(3.2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _theme.bgBottom.withOpacity(0.82),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isConnecting
                                              ? Icons.autorenew_rounded
                                              : Icons.power_settings_new_rounded,
                                          size: 35,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          isConnecting
                                              ? 'WAIT'
                                              : (isConnected ? 'STOP' : 'START'),
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.4,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Connection Info & Active Node + Clickable Ping Badge
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusAccent.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: statusAccent,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isConnected
                                                ? 'PROTECTED • ${v2rayStatus.duration}'
                                                : (isConnecting
                                                    ? 'CONNECTING...'
                                                    : 'DISCONNECTED'),
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              color: statusAccent,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Clickable Ping Pill right next to connection status
                                    GestureDetector(
                                      onTap: () => _refreshSingleServerPing(activeDisplayNode),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _theme.surface,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.amberAccent.withOpacity(0.4),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isRefreshingPing)
                                              const SizedBox(
                                                width: 10,
                                                height: 10,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 1.6,
                                                  color: Colors.amberAccent,
                                                ),
                                              )
                                            else
                                              const Icon(
                                                Icons.bolt_rounded,
                                                size: 12,
                                                color: Colors.amberAccent,
                                              ),
                                            const SizedBox(width: 3),
                                            Text(
                                              currentPing > 0 ? '$currentPing ms' : 'Ping',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.amberAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    _buildHighQualityFlag(
                                      activeDisplayNode?.countryCode ?? 'UN',
                                      size: 28,
                                      isAuto: !isConnected && _isAutoMode,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            !isConnected && _isAutoMode
                                                ? 'Auto (Best Server)'
                                                : (activeDisplayNode?.countryName ??
                                                    'Auto (Best Server)'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            statusMessage,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white60,
                                            ),
                                          ),
                                        ],
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

                      // 3-Column Metrics Bar (Download | Upload | Clickable Latency)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: _theme.surface.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildMetricItem(
                                icon: Icons.arrow_downward_rounded,
                                color: _theme.connected,
                                label: 'DOWNLOAD',
                                value: isConnected
                                    ? _formatSpeed(v2rayStatus.downloadSpeed)
                                    : '0 B/s',
                              ),
                            ),
                            Container(width: 1, height: 28, color: Colors.white12),
                            Expanded(
                              child: _buildMetricItem(
                                icon: Icons.arrow_upward_rounded,
                                color: _theme.primary,
                                label: 'UPLOAD',
                                value: isConnected
                                    ? _formatSpeed(v2rayStatus.uploadSpeed)
                                    : '0 B/s',
                              ),
                            ),
                            Container(width: 1, height: 28, color: Colors.white12),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _refreshSingleServerPing(activeDisplayNode),
                                child: _buildMetricItem(
                                  icon: Icons.bolt_rounded,
                                  color: Colors.amberAccent,
                                  label: 'LATENCY ↻',
                                  isLoading: isRefreshingPing,
                                  value: currentPing > 0 ? '$currentPing ms' : 'Tap to test',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Section Header & Test Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SERVERS (AUTO + ${_servers.length})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Colors.white70,
                      ),
                    ),
                    Row(
                      children: [
                        _buildActionPill(
                          label: 'TCP Ping',
                          icon: Icons.speed_rounded,
                          isLoading: isTestingTcp,
                          color: _theme.primary,
                          onTap: _runTcpPingAll,
                        ),
                        const SizedBox(width: 8),
                        _buildActionPill(
                          label: isTestingReal ? 'Stop Test' : 'Real Test',
                          icon: isTestingReal
                              ? Icons.stop_circle_outlined
                              : Icons.verified_rounded,
                          isLoading: isTestingReal,
                          color: isTestingReal ? Colors.redAccent : _theme.connected,
                          onTap: _runRealTestAll,
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Server List (Index 0 is always "Auto", followed by all servers)
                Expanded(
                  child: ListView.separated(
                    itemCount: _servers.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, listIndex) {
                      if (listIndex == 0) {
                        return _buildAutoServerTile();
                      }

                      final int index = listIndex - 1;
                      final ServerNode srv = _servers[index];
                      final bool isThisConnected =
                          isConnected && _connectedServer?.address == srv.address;
                      final bool isThisSelected =
                          !_isAutoMode && _selectedServer?.address == srv.address;

                      final int pingVal = srv.displayPing;
                      final Color pingColor = pingVal <= 0
                          ? Colors.white38
                          : (pingVal < 220
                              ? _theme.connected
                              : (pingVal < 500
                                  ? Colors.amberAccent
                                  : Colors.redAccent));

                      return GestureDetector(
                        onTap: () => _onServerItemTapped(srv, isAutoItem: false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isThisConnected
                                ? _theme.connected.withOpacity(0.12)
                                : (isThisSelected
                                    ? _theme.primary.withOpacity(0.10)
                                    : _theme.card),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isThisConnected
                                  ? _theme.connected
                                  : (isThisSelected
                                      ? _theme.primary
                                      : _theme.cardBorder),
                              width: (isThisConnected || isThisSelected) ? 1.6 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildHighQualityFlag(srv.countryCode, size: 36),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _theme.primary.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '#${index + 1}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: _theme.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Expanded(
                                          child: Text(
                                            srv.countryCode != 'UN'
                                                ? '${srv.countryName} • ${srv.name}'
                                                : srv.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                              color: isThisConnected
                                                  ? _theme.connected
                                                  : Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${srv.address}:${srv.port}  •  ${srv.protocol}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
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
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: pingColor.withOpacity(0.35),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.bolt_rounded,
                                        size: 13,
                                        color: pingColor,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        pingVal > 0 ? '$pingVal ms' : 'Test',
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
      ),
    );
  }

  Widget _buildAutoServerTile() {
    final bool isAutoActive = _isAutoMode;
    return GestureDetector(
      onTap: () => _onServerItemTapped(null, isAutoItem: true),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isAutoActive
              ? _theme.primary.withOpacity(0.14)
              : _theme.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isAutoActive ? _theme.primary : _theme.cardBorder,
            width: isAutoActive ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            _buildHighQualityFlag('UN', size: 36, isAuto: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _theme.connected.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'SMART',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: _theme.connected,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Auto',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: isAutoActive ? Colors.white : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Automatically tests & connects to the fastest server',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isAutoActive
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isAutoActive ? _theme.primary : Colors.white30,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _theme.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _theme.cardBorder),
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _theme.primary,
                  ),
                )
              : Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool isLoading = false,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: color,
                ),
              )
            else
              Icon(icon, color: color, size: 13),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildActionPill({
    required String label,
    required IconData icon,
    required bool isLoading,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: _theme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            if (isLoading)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: color,
                ),
              )
            else
              Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
