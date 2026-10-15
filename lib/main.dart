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
  final String group;
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
    required this.group,
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
        'group': group,
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
        name: map['name'] ?? 'Server',
        group: map['group'] ?? 'irancell',
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

class CustomSubEntry {
  final String input;
  final String group;

  CustomSubEntry({required this.input, required this.group});

  Map<String, dynamic> toMap() => {'input': input, 'group': group};

  factory CustomSubEntry.fromMap(Map<String, dynamic> map) => CustomSubEntry(
        input: map['input'] ?? '',
        group: map['group'] ?? 'irancell',
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

  String _selectedTab = 'auto';

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

  final List<ServerNode> _irancellServers = [];
  final List<ServerNode> _mciServers = [];
  final List<CustomSubEntry> _customSubEntries = [];
  final Map<String, Map<String, String>> _geoCache = {};

  ServerNode? _selectedServer;
  ServerNode? _connectedServer;

  final List<String> _githubIrancellUrls = const [
    'https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/irancell.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/irancell.txt',
    'https://cdn.jsdelivr.net/gh/amy-coddwe/Nivexia-app@main/irancell.txt',
  ];

  final List<String> _githubMciUrls = const [
    'https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/mci.txt',
    'https://ghfast.top/https://raw.githubusercontent.com/amy-coddwe/Nivexia-app/main/mci.txt',
    'https://cdn.jsdelivr.net/gh/amy-coddwe/Nivexia-app@main/mci.txt',
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
    await _syncAllConfigsFromRemote(silent: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
      final File stateFile = await _getLocalFile('nivexia_manager_v7.json');
      if (await stateFile.exists()) {
        final Map<String, dynamic> data = jsonDecode(await stateFile.readAsString());
        _themeIndex = data['themeIndex'] ?? 0;
        _selectedTab = data['selectedTab'] ?? 'auto';

        if (data['customSubs'] is List) {
          _customSubEntries.clear();
          for (final item in data['customSubs']) {
            _customSubEntries.add(
              CustomSubEntry.fromMap(Map<String, dynamic>.from(item)),
            );
          }
        }

        if (data['irancellServers'] is List) {
          _irancellServers.clear();
          for (final item in data['irancellServers']) {
            _irancellServers.add(
              ServerNode.fromMap(Map<String, dynamic>.from(item)),
            );
          }
        }

        if (data['mciServers'] is List) {
          _mciServers.clear();
          for (final item in data['mciServers']) {
            _mciServers.add(
              ServerNode.fromMap(Map<String, dynamic>.from(item)),
            );
          }
        }

        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _saveStateToDisk() async {
    try {
      final File stateFile = await _getLocalFile('nivexia_manager_v7.json');
      final Map<String, dynamic> data = {
        'themeIndex': _themeIndex,
        'selectedTab': _selectedTab,
        'customSubs': _customSubEntries.map((e) => e.toMap()).toList(),
        'irancellServers': _irancellServers.map((e) => e.toMap()).toList(),
        'mciServers': _mciServers.map((e) => e.toMap()).toList(),
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
    return '${uri.split('://').first.toUpperCase()} Server';
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

  ServerNode? _parseConfigToNode(String rawUri, String group) {
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

      if (parser.streamSetting['realitySettings'] is Map) {
        final Map rl = parser.streamSetting['realitySettings'];
        if (rl['spiderX'] is String) {
          try {
            rl['spiderX'] = Uri.decodeComponent(rl['spiderX']);
          } catch (_) {}
        }
      }

      if (parser.streamSetting['security'] == 'tls' &&
          parser.streamSetting['tlsSettings'] is Map) {
        parser.streamSetting['tlsSettings']['allowInsecure'] = true;
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

      String proto = uri.split('://').first.toUpperCase();
      if (uri.contains('security=reality')) proto = 'REALITY';

      return ServerNode(
        rawUri: uri,
        name: remarkName,
        group: group,
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
      ).timeout(const Duration(seconds: 8));

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
        if (!silent) statusMessage = 'Updating Irancell & MCI configs...';
      });
    }

    try {
      final Map<String, ServerNode> oldByUri = {};
      for (final s in _irancellServers) {
        oldByUri[s.rawUri] = s;
      }
      for (final s in _mciServers) {
        oldByUri[s.rawUri] = s;
      }

      String irancellRaw = '';
      for (final url in _githubIrancellUrls) {
        final String txt = await _fetchUrlText(url);
        if (txt.isNotEmpty) {
          irancellRaw = txt;
          break;
        }
      }

      String mciRaw = '';
      for (final url in _githubMciUrls) {
        final String txt = await _fetchUrlText(url);
        if (txt.isNotEmpty) {
          mciRaw = txt;
          break;
        }
      }

      final List<String> newIrancellUris = [];
      final List<String> newMciUris = [];

      if (irancellRaw.isNotEmpty) {
        newIrancellUris.addAll(await _extractAllConfigsFromRawOrSub(irancellRaw));
      }
      if (mciRaw.isNotEmpty) {
        newMciUris.addAll(await _extractAllConfigsFromRawOrSub(mciRaw));
      }

      for (final entry in _customSubEntries) {
        final List<String> extracted = await _extractAllConfigsFromRawOrSub(entry.input);
        if (entry.group == 'mci') {
          newMciUris.addAll(extracted);
        } else {
          newIrancellUris.addAll(extracted);
        }
      }

      if (newIrancellUris.isNotEmpty) {
        final List<ServerNode> parsedIrancell = [];
        final Set<String> seen = {};
        for (final u in newIrancellUris) {
          if (!seen.add(u)) continue;
          final ServerNode? node = _parseConfigToNode(u, 'irancell');
          if (node != null) {
            if (oldByUri.containsKey(u)) {
              node.countryCode = oldByUri[u]!.countryCode;
              node.countryName = oldByUri[u]!.countryName;
              node.tcpPing = oldByUri[u]!.tcpPing;
              node.realPing = oldByUri[u]!.realPing;
            }
            parsedIrancell.add(node);
          }
        }
        _irancellServers
          ..clear()
          ..addAll(parsedIrancell);
      }

      if (newMciUris.isNotEmpty) {
        final List<ServerNode> parsedMci = [];
        final Set<String> seen = {};
        for (final u in newMciUris) {
          if (!seen.add(u)) continue;
          final ServerNode? node = _parseConfigToNode(u, 'mci');
          if (node != null) {
            if (oldByUri.containsKey(u)) {
              node.countryCode = oldByUri[u]!.countryCode;
              node.countryName = oldByUri[u]!.countryName;
              node.tcpPing = oldByUri[u]!.tcpPing;
              node.realPing = oldByUri[u]!.realPing;
            }
            parsedMci.add(node);
          }
        }
        _mciServers
          ..clear()
          ..addAll(parsedMci);
      }

      await _saveStateToDisk();
      _resolveAllServerCountriesInBackground();
    } catch (_) {}

    if (mounted) {
      setState(() {
        isSyncingSubs = false;
        final int total = _irancellServers.length + _mciServers.length;
        if (!isConnected) {
          statusMessage = total > 0
              ? 'Ready • $total servers loaded'
              : 'No servers yet • Add in GitHub or tap +';
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
      'AMERICA': 'US',
      'GB': 'GB',
      'UK': 'GB',
      'ENGLAND': 'GB',
      'FR': 'FR',
      'FRANCE': 'FR',
      'FI': 'FI',
      'FINLAND': 'FI',
      'SE': 'SE',
      'SWEDEN': 'SE',
      'AE': 'AE',
      'UAE': 'AE',
      'DUBAI': 'AE',
      'CA': 'CA',
      'CANADA': 'CA',
      'SG': 'SG',
      'SINGAPORE': 'SG',
      'JP': 'JP',
      'JAPAN': 'JP',
      'RU': 'RU',
      'RUSSIA': 'RU',
      'PL': 'PL',
      'POLAND': 'PL',
      'AT': 'AT',
      'AUSTRIA': 'AT',
      'CH': 'CH',
      'SWISS': 'CH',
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
    final List<ServerNode> all = [..._irancellServers, ..._mciServers];
    for (final srv in all) {
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
          .timeout(const Duration(milliseconds: 3000), onTimeout: () => -1);

      if (delay > 0 && delay < 3500) {
        return delay;
      }
    } catch (_) {}

    return tcp;
  }

  List<ServerNode> _getCurrentTabServers() {
    if (_selectedTab == 'irancell') return _irancellServers;
    if (_selectedTab == 'mci') return _mciServers;
    return [..._irancellServers, ..._mciServers];
  }

  Future<void> _runTcpPingForCurrentTab() async {
    if (isTestingTcp || isTestingReal) return;
    final List<ServerNode> list = _getCurrentTabServers();
    if (list.isEmpty) return;

    setState(() {
      isTestingTcp = true;
      statusMessage = 'Running TCP Ping test...';
    });

    await Future.wait(list.map((srv) async {
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

  Future<void> _runRealTestForCurrentTab() async {
    if (isTestingReal || isTestingTcp) return;
    final List<ServerNode> list = _getCurrentTabServers();
    if (list.isEmpty) return;

    setState(() {
      isTestingReal = true;
      statusMessage = 'Running Real Config test...';
    });

    for (final srv in list) {
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
      if (isConnected && _connectedServer?.rawUri == srv.rawUri) {
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
            if (_connectedServer?.rawUri == srv.rawUri ||
                _selectedServer?.rawUri == srv.rawUri) {
              currentPing = p;
            }
          }
        });
      }
      await _resolveSingleServerCountry(srv);
    } catch (_) {}

    if (mounted) {
      setState(() => isRefreshingPing = false);
    }
  }

  Future<bool> _startVpnWithNode(ServerNode node) async {
    try {
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));

      _nativeVpnRunning = false;
      await v2ray.startV2Ray(
        remark: node.name,
        config: node.configJson,
        blockedApps: null,
        bypassSubnets: null,
        proxyOnly: false,
      );

      int waited = 0;
      while (!_nativeVpnRunning && waited < 3200) {
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
      statusMessage = 'Testing configs & connecting...';
    });

    if (_irancellServers.isEmpty && _mciServers.isEmpty) {
      await _syncAllConfigsFromRemote(silent: true);
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

    final List<ServerNode> candidates = _selectedTab == 'auto'
        ? [..._irancellServers, ..._mciServers]
        : (_selectedServer != null ? [_selectedServer!] : _getCurrentTabServers());

    if (candidates.isEmpty) {
      setState(() {
        isConnecting = false;
        statusMessage = 'No configs found! Add configs via + or GitHub.';
      });
      return;
    }

    final List<ServerNode> alive = [];
    await Future.wait(candidates.map((srv) async {
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
          statusMessage = 'Testing ${candidate.name} (${candidate.tcpPing} ms)...';
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
    String targetGroup = _selectedTab == 'mci' ? 'mci' : 'irancell';
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
                    'Paste a Subscription URL (https://...) or configs (vless://, vmess://, ss://, trojan://) and select its operator group:',
                    style: TextStyle(fontSize: 11.5, color: Colors.white60),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'Target Group: ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Irancell'),
                        selected: targetGroup == 'irancell',
                        selectedColor: _theme.primary.withOpacity(0.25),
                        onSelected: (_) => setModalState(() => targetGroup = 'irancell'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('MCI'),
                        selected: targetGroup == 'mci',
                        selectedColor: _theme.primary.withOpacity(0.25),
                        onSelected: (_) => setModalState(() => targetGroup = 'mci'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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
                              final List<ServerNode> targetList =
                                  targetGroup == 'mci' ? _mciServers : _irancellServers;

                              for (final u in extractedUris) {
                                if (targetList.any((s) => s.rawUri == u)) continue;
                                final ServerNode? node = _parseConfigToNode(u, targetGroup);
                                if (node != null) {
                                  targetList.add(node);
                                  addedCount++;
                                }
                              }

                              if (extractedUris.isNotEmpty) {
                                _customSubEntries.add(
                                  CustomSubEntry(input: raw, group: targetGroup),
                                );
                                await _saveStateToDisk();
                                _resolveAllServerCountriesInBackground();
                              }

                              setModalState(() {
                                isAdding = false;
                                feedbackText = extractedUris.isEmpty
                                    ? 'No valid configs found in input!'
                                    : 'Added $addedCount config(s) to ${targetGroup.toUpperCase()}!';
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

    final List<ServerNode> visibleServers = _getCurrentTabServers();

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
                          (visibleServers.isNotEmpty ? visibleServers.first : null);
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
                                            : 'Mode: ${_selectedTab.toUpperCase()}',
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
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _theme.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    _buildGroupTabButton(
                      id: 'auto',
                      title: 'AUTO (${_irancellServers.length + _mciServers.length})',
                      icon: Icons.auto_awesome_rounded,
                    ),
                    _buildGroupTabButton(
                      id: 'irancell',
                      title: 'IRANCELL (${_irancellServers.length})',
                      icon: Icons.sim_card_rounded,
                    ),
                    _buildGroupTabButton(
                      id: 'mci',
                      title: 'MCI (${_mciServers.length})',
                      icon: Icons.network_cell_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SERVERS LIST',
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
                        onTap: _runTcpPingForCurrentTab,
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
                        onTap: _runRealTestForCurrentTab,
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
                child: visibleServers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.dns_outlined, size: 42, color: Colors.grey.shade700),
                            const SizedBox(height: 10),
                            Text(
                              'No configs in ${_selectedTab.toUpperCase()} group yet',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Add configs to irancell.txt / mci.txt in GitHub or tap + above',
                              style: TextStyle(fontSize: 11, color: Colors.white38),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: visibleServers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final ServerNode srv = visibleServers[index];
                          final bool isThisConnected =
                              isConnected && _connectedServer?.rawUri == srv.rawUri;
                          final bool isThisSelected =
                              _selectedServer?.rawUri == srv.rawUri;

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
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 1.5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _theme.surface,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                srv.group.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: _theme.primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                srv.countryCode != 'UN'
                                                    ? srv.countryName
                                                    : 'Tap ping to detect',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Colors.white54,
                                                ),
                                              ),
                                            ),
                                          ],
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

  Widget _buildGroupTabButton({
    required String id,
    required String title,
    required IconData icon,
  }) {
    final bool selected = _selectedTab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTab = id);
          _saveStateToDisk();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _theme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.black : Colors.white70,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.black : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
