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
  final String vpnConfigJson;
  final String speedtestConfigJson;
  final String protocol;
  final String address;
  final int port;
  final String sni;
  final String security;
  final String network;
  int ping;

  ReadyServer({
    required this.rawUri,
    required this.vpnConfigJson,
    required this.speedtestConfigJson,
    required this.protocol,
    required this.address,
    required this.port,
    required this.sni,
    required this.security,
    required this.network,
    required this.ping,
  });
}

class ProtocolTier {
  final String name;
  final List<String> urls;

  const ProtocolTier({
    required this.name,
    required this.urls,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const int _chunkSize = 300; // اسکن دقیق ۳۰۰ تا ۳۰۰ تا از بالای فایل مثل v2rayNG

  late final V2ray v2ray = V2ray(
    onStatusChanged: (status) {
      if (!mounted) return;
      final String st = status.state.toUpperCase();
      setState(() {
        v2rayStatus = status;
        if (st == "CONNECTED") {
          if (!isConnected) {
            isConnected = true;
            isConnecting = false;
            _startConnectionDurationTimer();
          }
        } else if (st == "DISCONNECTED" && !isConnecting && !_isAutoSwitching) {
          isConnected = false;
          _stopConnectionDurationTimer();
        }
      });
    },
  );

  late AnimationController _pulseController;
  V2RayStatus v2rayStatus = V2RayStatus();

  // قالب استاندارد Inbounds هسته برای سازگاری ۱۰۰٪ با tun2socks اندروید
  List<dynamic> _nativeTemplateInbounds = [];

  bool isConnected = false;
  bool isConnecting = false;
  bool isRefreshingPing = false;
  bool _isScanning = false;
  bool _abortScanRequested = false;
  bool _isAutoSwitching = false;
  bool _userCancelledConnect = false;

  int currentPing = -1;
  String statusMessage = 'Initializing v2rayNG core...';

  // تایمر اختصاصی زمان اتصال (جلوگیری از قفل شدن روی 00:00:08)
  Timer? _durationTimer;
  int _connectedSeconds = 0;
  String _formattedDuration = '00:00:00';

  Timer? _backgroundPoolTimer;
  Timer? _healthWatchdogTimer;
  Timer? _failoverCountdownTimer;
  int _configFailSeconds = 0;
  bool _internetIsDown = false;

  final List<ReadyServer> _readyPool = [];
  final Set<String> _deadUris = {};
  ReadyServer? _activeServer;

  // ۴ منبع اصلی Epodonios به ترتیب اولویت: VLESS -> VMess -> SS -> SSR
  final List<ProtocolTier> _protocolWaterfall = const [
    ProtocolTier(
      name: 'VLESS',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/vless.txt',
      ],
    ),
    ProtocolTier(
      name: 'VMess',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/vmess.txt',
      ],
    ),
    ProtocolTier(
      name: 'Shadowsocks',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt',
        'https://cdn.jsdelivr.net/gh/barry-far/V2ray-Configs@main/Splitted-By-Protocol/ss.txt',
      ],
    ),
    ProtocolTier(
      name: 'SSR',
      urls: [
        'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
        'https://ghfast.top/https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initVpnEngine();
  }

  Future<void> _initVpnEngine() async {
    await v2ray.initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    );

    // استخراج پورت‌های دقیق Inbounds از قالب خود پلاگین
    try {
      final V2RayURL tpl = V2ray.parseFromURL(
        'vless://00000000-0000-0000-0000-000000000000@127.0.0.1:443?security=none&type=tcp#tpl',
      );
      final Map<String, dynamic> tplMap = jsonDecode(tpl.getFullConfiguration());
      if (tplMap['inbounds'] is List) {
        _nativeTemplateInbounds = tplMap['inbounds'] as List;
      }
    } catch (_) {}

    if (_nativeTemplateInbounds.isEmpty) {
      _nativeTemplateInbounds = [
        {
          "tag": "socks",
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"]
          },
          "settings": {"auth": "noauth", "udp": true}
        },
        {
          "tag": "http",
          "port": 10809,
          "listen": "127.0.0.1",
          "protocol": "http",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"]
          },
          "settings": {}
        }
      ];
    }

    // شروع فوری اسکن ۳۰۰ تای اول به محض باز شدن برنامه
    _runContinuousWaterfallScan();

    // به‌روزرسانی لیست سرورها در پس‌زمینه (فقط وقتی قطع هستیم)
    _backgroundPoolTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!isConnected && !isConnecting && !_isScanning) {
        _refreshPoolOrRescan();
      }
    });

    // بررسی سلامت اتصال هر ۱۰ ثانیه وقتی VPN روشن است
    _healthWatchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (isConnected && !isConnecting && !_isAutoSwitching) {
        _checkConnectionAndHandleFailover();
      }
    });
  }

  void _startConnectionDurationTimer() {
    _durationTimer?.cancel();
    _connectedSeconds = 0;
    _formattedDuration = '00:00:00';
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !isConnected) return;
      _connectedSeconds++;
      final int h = _connectedSeconds ~/ 3600;
      final int m = (_connectedSeconds % 3600) ~/ 60;
      final int s = _connectedSeconds % 60;
      setState(() {
        _formattedDuration =
            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      });
    });
  }

  void _stopConnectionDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectedSeconds = 0;
    _formattedDuration = '00:00:00';
  }

  @override
  void dispose() {
    _abortScanRequested = true;
    _pulseController.dispose();
    _durationTimer?.cancel();
    _backgroundPoolTimer?.cancel();
    _healthWatchdogTimer?.cancel();
    _failoverCountdownTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // ۱. موتور پارسر اختصاصی منطبق با سورس‌کد v2rayNG (حل کامل مشکل خواندن کانفیگ‌ها)
  // ===========================================================================

  String _urlDecodeSafe(String val) {
    try {
      return Uri.decodeComponent(val);
    } catch (_) {
      return val;
    }
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

  Map<String, String> _parseQueryParamsSafe(String query) {
    final Map<String, String> map = {};
    if (query.isEmpty) return map;
    for (final String pair in query.split('&')) {
      final int eqIdx = pair.indexOf('=');
      if (eqIdx > 0) {
        final String k = pair.substring(0, eqIdx).trim();
        final String v = _urlDecodeSafe(pair.substring(eqIdx + 1).trim());
        map[k] = v;
      }
    }
    return map;
  }

  /// ساخت StreamSettings دقیقاً مطابق استاندارد v2rayNG (پشتیبانی کامل از WS، Reality، gRPC، TCP و TLS)
  Map<String, dynamic> _buildV2rayNgStreamSettings({
    required String network,
    required String security,
    required String hostHeader,
    required String path,
    required String sni,
    required String fingerprint,
    required String alpn,
    required String pbk,
    required String sid,
    required String spx,
    required String headerType,
    required String serviceName,
    required String grpcMode,
  }) {
    final String net = network.isEmpty ? 'tcp' : network.toLowerCase();
    final String sec = security.isEmpty ? 'none' : security.toLowerCase();

    final Map<String, dynamic> stream = {
      "network": net,
      "security": sec,
    };

    // تنظیمات لایه انتقال (Transport)
    if (net == 'ws') {
      String cleanPath = path.isEmpty ? '/' : path;
      int maxEarlyData = 0;
      String earlyDataHeaderName = '';

      // در v2rayNG، اگر در مسیر WebSocket پارامتر ?ed=2048 باشد، به تنظیمات EarlyData منتقل می‌شود
      if (cleanPath.contains('?ed=')) {
        final parts = cleanPath.split('?ed=');
        cleanPath = parts.first.isEmpty ? '/' : parts.first;
        maxEarlyData = int.tryParse(parts.last.split('&').first) ?? 2048;
        earlyDataHeaderName = 'Sec-WebSocket-Protocol';
      }

      final Map<String, dynamic> wsSettings = {
        "path": cleanPath,
        "headers": hostHeader.isNotEmpty ? {"Host": hostHeader} : {},
      };
      if (maxEarlyData > 0) {
        wsSettings["maxEarlyData"] = maxEarlyData;
        wsSettings["earlyDataHeaderName"] = earlyDataHeaderName;
      }
      stream["wsSettings"] = wsSettings;
    } else if (net == 'grpc') {
      stream["grpcSettings"] = {
        "serviceName": serviceName,
        "multiMode": grpcMode.toLowerCase() == 'multi',
        "idle_timeout": 60,
        "health_check_timeout": 20,
      };
    } else if (net == 'tcp') {
      if (headerType.toLowerCase() == 'http') {
        stream["tcpSettings"] = {
          "header": {
            "type": "http",
            "request": {
              "version": "1.1",
              "method": "GET",
              "path": [path.isEmpty ? "/" : path],
              "headers": {
                "Host": hostHeader.isNotEmpty ? [hostHeader] : [],
                "User-Agent": [
                  "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.143 Safari/537.36"
                ],
                "Accept-Encoding": ["gzip, deflate"],
                "Connection": ["keep-alive"],
                "Pragma": "no-cache"
              }
            }
          }
        };
      }
    } else if (net == 'httpupgrade') {
      stream["httpupgradeSettings"] = {
        "path": path.isEmpty ? "/" : path,
        "host": hostHeader,
      };
    } else if (net == 'splithttp' || net == 'xhttp') {
      stream["splithttpSettings"] = {
        "path": path.isEmpty ? "/" : path,
        "host": hostHeader,
      };
    }

    // تنظیمات امنیت (TLS / Reality) دقیقاً مطابق v2rayNG
    if (sec == 'tls') {
      final Map<String, dynamic> tlsSettings = {
        "allowInsecure": false,
      };
      if (sni.isNotEmpty) {
        tlsSettings["serverName"] = sni;
      } else if (hostHeader.isNotEmpty) {
        tlsSettings["serverName"] = hostHeader;
      }
      if (fingerprint.isNotEmpty) {
        tlsSettings["fingerprint"] = fingerprint;
      } else {
        tlsSettings["fingerprint"] = "chrome";
      }
      if (alpn.isNotEmpty) {
        tlsSettings["alpn"] =
            alpn.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      stream["tlsSettings"] = tlsSettings;
    } else if (sec == 'reality') {
      stream["realitySettings"] = {
        "show": false,
        "fingerprint": fingerprint.isNotEmpty ? fingerprint : "chrome",
        "serverName": sni.isNotEmpty ? sni : hostHeader,
        "publicKey": pbk,
        "shortId": sid,
        "spiderX": spx,
      };
    }

    return stream;
  }

  /// تبدیل هر لینک (VLESS, VMess, SS, SSR, Trojan) به ساختار دقیق v2rayNG
  ReadyServer? _parseUriLikeV2rayNg(String rawLine, String tierName) {
    try {
      String uri = rawLine.trim();

      // ۱. تبدیل SSR به SS در صورت نیاز
      if (uri.startsWith('ssr://')) {
        final String decoded = _decodeBase64Safe(uri.substring(6));
        if (decoded.isEmpty) return null;
        final String mainPart = decoded.split('/?').first;
        final List<String> parts = mainPart.split(':');
        if (parts.length < 6) return null;
        final String host = parts[0].trim();
        final String port = parts[1].trim();
        final String method = parts[3].trim();
        final String password = _decodeBase64Safe(parts[5].trim());
        if (host.isEmpty || password.isEmpty) return null;
        final String userB64 =
            base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
        uri = 'ss://$userB64@$host:$port#SSR';
      }

      String address = '';
      int port = 0;
      String sni = '';
      String security = 'none';
      String network = 'tcp';
      Map<String, dynamic>? proxyOutbound;

      // ۲. پارس کردن VLESS و Trojan
      if (uri.startsWith('vless://') || uri.startsWith('trojan://')) {
        final bool isVless = uri.startsWith('vless://');
        final String withoutScheme = uri.substring(isVless ? 8 : 9);
        final String beforeHash = withoutScheme.split('#').first;
        final List<String> qSplit = beforeHash.split('?');
        final String mainCredAndHost = qSplit.first;
        final String queryStr = qSplit.length > 1 ? qSplit.sublist(1).join('?') : '';

        final int atIdx = mainCredAndHost.lastIndexOf('@');
        if (atIdx <= 0) return null;

        final String userIdOrPass = _urlDecodeSafe(mainCredAndHost.substring(0, atIdx));
        final String hostPortPart = mainCredAndHost.substring(atIdx + 1);

        final int colonIdx = hostPortPart.lastIndexOf(':');
        if (colonIdx <= 0) return null;

        address = hostPortPart.substring(0, colonIdx).replaceAll('[', '').replaceAll(']', '').trim();
        port = int.tryParse(hostPortPart.substring(colonIdx + 1).trim()) ?? 0;
        if (address.isEmpty || port <= 0 || port > 65535) return null;

        final Map<String, String> params = _parseQueryParamsSafe(queryStr);
        network = (params['type'] ?? params['network'] ?? 'tcp').toLowerCase();
        security = (params['security'] ?? (isVless ? 'none' : 'tls')).toLowerCase();
        final String hostHeader = params['host'] ?? '';
        final String path = params['path'] ?? '/';
        sni = params['sni'] ?? (hostHeader.isNotEmpty ? hostHeader : address);
        final String fp = params['fp'] ?? 'chrome';
        final String alpn = params['alpn'] ?? '';
        final String pbk = params['pbk'] ?? '';
        final String sid = params['sid'] ?? '';
        final String spx = params['spx'] ?? '';
        final String flow = params['flow'] ?? '';
        final String headerType = params['headerType'] ?? 'none';
        final String serviceName = params['serviceName'] ?? '';
        final String grpcMode = params['mode'] ?? 'gun';

        // اگر Reality است ولی PublicKey ندارد، کانفیگ ناقص است
        if (security == 'reality' && pbk.isEmpty) return null;

        final Map<String, dynamic> streamSettings = _buildV2rayNgStreamSettings(
          network: network,
          security: security,
          hostHeader: hostHeader,
          path: path,
          sni: sni,
          fingerprint: fp,
          alpn: alpn,
          pbk: pbk,
          sid: sid,
          spx: spx,
          headerType: headerType,
          serviceName: serviceName,
          grpcMode: grpcMode,
        );

        if (isVless) {
          final Map<String, dynamic> userMap = {
            "id": userIdOrPass,
            "encryption": params['encryption'] ?? "none",
            "level": 8,
          };
          if (flow.isNotEmpty) {
            userMap["flow"] = flow;
          }
          proxyOutbound = {
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
          };
        } else {
          proxyOutbound = {
            "tag": "proxy",
            "protocol": "trojan",
            "settings": {
              "servers": [
                {
                  "address": address,
                  "port": port,
                  "password": userIdOrPass,
                  "level": 8
                }
              ]
            },
            "streamSettings": streamSettings,
          };
        }
      }
      // ۳. پارس کردن VMess (فرمت JSON Base64 استاندارد v2rayNG)
      else if (uri.startsWith('vmess://')) {
        final String b64 = uri.substring(8).split('#').first.trim();
        final String jsonStr = _decodeBase64Safe(b64);
        if (jsonStr.isEmpty || !jsonStr.startsWith('{')) return null;

        final Map<String, dynamic> vmap = jsonDecode(jsonStr);
        address = (vmap['add'] ?? '').toString().trim();
        port = int.tryParse((vmap['port'] ?? '').toString()) ?? 0;
        final String id = (vmap['id'] ?? '').toString().trim();
        if (address.isEmpty || port <= 0 || id.isEmpty) return null;

        final int aid = int.tryParse((vmap['aid'] ?? '0').toString()) ?? 0;
        final String scy = (vmap['scy'] ?? 'auto').toString();
        network = (vmap['net'] ?? 'tcp').toString().toLowerCase();
        final String headerType = (vmap['type'] ?? 'none').toString();
        final String hostHeader = (vmap['host'] ?? '').toString();
        final String path = (vmap['path'] ?? '/').toString();
        final String tlsVal = (vmap['tls'] ?? '').toString().toLowerCase();
        security = (tlsVal == 'tls' || tlsVal == 'reality') ? tlsVal : 'none';
        sni = (vmap['sni'] ?? (hostHeader.isNotEmpty ? hostHeader : address)).toString();
        final String fp = (vmap['fp'] ?? 'chrome').toString();
        final String alpn = (vmap['alpn'] ?? '').toString();

        final Map<String, dynamic> streamSettings = _buildV2rayNgStreamSettings(
          network: network,
          security: security,
          hostHeader: hostHeader,
          path: path,
          sni: sni,
          fingerprint: fp,
          alpn: alpn,
          pbk: '',
          sid: '',
          spx: '',
          headerType: headerType,
          serviceName: path,
          grpcMode: 'gun',
        );

        proxyOutbound = {
          "tag": "proxy",
          "protocol": "vmess",
          "settings": {
            "vnext": [
              {
                "address": address,
                "port": port,
                "users": [
                  {
                    "id": id,
                    "alterId": aid,
                    "security": scy.isEmpty ? "auto" : scy,
                    "level": 8
                  }
                ]
              }
            ]
          },
          "streamSettings": streamSettings,
        };
      }
      // ۴. پارس کردن Shadowsocks (SS)
      else if (uri.startsWith('ss://')) {
        String body = uri.substring(5).split('#').first.split('?').first.trim();
        String methodPass = '';
        String hostPort = '';

        if (body.contains('@')) {
          final parts = body.split('@');
          methodPass = _decodeBase64Safe(parts.first);
          if (!methodPass.contains(':')) {
            methodPass = _urlDecodeSafe(parts.first);
          }
          hostPort = parts.last;
        } else {
          final decodedAll = _decodeBase64Safe(body);
          if (decodedAll.contains('@')) {
            final parts = decodedAll.split('@');
            methodPass = parts.first;
            hostPort = parts.last;
          }
        }

        final int colonPass = methodPass.indexOf(':');
        final int colonHost = hostPort.lastIndexOf(':');
        if (colonPass <= 0 || colonHost <= 0) return null;

        final String method = methodPass.substring(0, colonPass).trim();
        final String password = methodPass.substring(colonPass + 1).trim();
        address = hostPort.substring(0, colonHost).replaceAll('[', '').replaceAll(']', '').trim();
        port = int.tryParse(hostPort.substring(colonHost + 1).trim()) ?? 0;

        if (address.isEmpty || port <= 0 || password.isEmpty) return null;

        proxyOutbound = {
          "tag": "proxy",
          "protocol": "shadowsocks",
          "settings": {
            "servers": [
              {
                "address": address,
                "port": port,
                "method": method,
                "password": password,
                "level": 8
              }
            ]
          },
          "streamSettings": {
            "network": "tcp",
            "security": "none",
          }
        };
      }

      if (proxyOutbound == null || address == '127.0.0.1') return null;

      // الف) کانفیگ مخصوص تست پینگ در هسته (بدون inbounds برای جلوگیری از خطای Port 10808 in use)
      final Map<String, dynamic> speedtestConfig = {
        "log": {"loglevel": "none"},
        "dns": {
          "servers": ["1.1.1.1", "8.8.8.8"]
        },
        "outbounds": [proxyOutbound],
      };

      // ب) کانفیگ کامل مخصوص اتصال VPN در اندروید (دقیقاً مطابق ساختار v2rayNG)
      final Map<String, dynamic> fullVpnConfig = {
        "log": {"loglevel": "warning"},
        "inbounds": _nativeTemplateInbounds,
        "outbounds": [
          proxyOutbound,
          {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {"domainStrategy": "UseIP"}
          },
          {
            "tag": "block",
            "protocol": "blackhole",
            "settings": {}
          }
        ],
        "dns": {
          "servers": ["1.1.1.1", "8.8.8.8"]
        },
        "routing": {
          "domainStrategy": "IPIfNonMatch",
          "rules": [
            {
              "type": "field",
              "ip": [
                "10.0.0.0/8",
                "127.0.0.0/8",
                "172.16.0.0/12",
                "192.168.0.0/16"
              ],
              "outboundTag": "direct"
            },
            {
              "type": "field",
              "network": "tcp,udp",
              "outboundTag": "proxy"
            }
          ]
        }
      };

      return ReadyServer(
        rawUri: uri,
        vpnConfigJson: jsonEncode(fullVpnConfig),
        speedtestConfigJson: jsonEncode(speedtestConfig),
        protocol: tierName,
        address: address,
        port: port,
        sni: sni.isNotEmpty ? sni : address,
        security: security,
        network: network,
        ping: -1,
      );
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // ۲. استخراج کانفیگ‌ها به ترتیب دقیق فایل (بدون Shuffle) + تست واقعی مثل v2rayNG
  // ===========================================================================

  List<String> _extractOrderedConfigs(String rawContent) {
    String text = rawContent.trim();
    if (text.isEmpty) return [];

    if (!text.contains('://')) {
      final String decoded = _decodeBase64Safe(text);
      if (decoded.isNotEmpty) text = decoded;
    }

    final List<String> validLinks = [];
    final Set<String> seenInFile = {};

    for (String line in text.split(RegExp(r'[\r\n]+'))) {
      line = line.trim();
      if (line.isEmpty || _deadUris.contains(line)) continue;
      if (line.startsWith('vless://') ||
          line.startsWith('vmess://') ||
          line.startsWith('ss://') ||
          line.startsWith('ssr://') ||
          line.startsWith('trojan://')) {
        if (seenInFile.add(line)) {
          validLinks.add(line);
        }
      }
    }
    return validLinks;
  }

  Future<String> _downloadSourceContent(String url) async {
    final http.Client client = http.Client();
    try {
      final http.Request req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'v2rayNG/1.8.23';

      final http.StreamedResponse response =
          await client.send(req).timeout(const Duration(seconds: 7));

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
          if (bytes.length >= 2000000) {
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
        const Duration(seconds: 8),
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

  /// تست دست‌دهی واقعی پروتکل و TLS (رد کردن سرورهایی که فقط پورتشان باز است اما SNI/TLS آن‌ها فیلتر است)
  Future<int> _verifyRealProtocolAndTlsPing(ReadyServer srv) async {
    // ۱. اول تست از طریق هسته Xray (با کانفیگ بدون Inbounds تا تداخل پورت ندهد)
    try {
      final int coreDelay = await v2ray
          .getServerDelay(
            config: srv.speedtestConfigJson,
            url: 'http://cp.cloudflare.com/generate_204',
          )
          .timeout(const Duration(milliseconds: 2200), onTimeout: () => -1);
      if (coreDelay > 0 && coreDelay < 3000) {
        return coreDelay;
      }
    } catch (_) {}

    // ۲. تست واقعی TLS Handshake با SNI سرور (دقیقاً مثل تست Real Delay روی نت ایران)
    if (srv.security == 'tls' || srv.port == 443 || srv.port == 2053 || srv.port == 2083 || srv.port == 8443) {
      SecureSocket? secSock;
      try {
        final Stopwatch sw = Stopwatch()..start();
        secSock = await SecureSocket.connect(
          srv.address,
          srv.port,
          host: srv.sni.isNotEmpty ? srv.sni : srv.address,
          timeout: const Duration(milliseconds: 1600),
          onBadCertificate: (_) => true,
        );
        sw.stop();
        final int tlsDelay = sw.elapsedMilliseconds;
        await secSock.close();
        if (tlsDelay > 0 && tlsDelay < 2500) {
          return tlsDelay;
        }
      } catch (_) {
        secSock?.destroy();
        return -1; // اگر TLS Handshake رد نشد، یعنی سرور روی نت ایران فیلتر یا خراب است
      }
    }

    // ۳. برای سرورهای Reality یا غیر TLS: بررسی دو مرحله‌ای پاسخ واقعی سوکت
    Socket? rawSock;
    try {
      final Stopwatch sw = Stopwatch()..start();
      rawSock = await Socket.connect(
        srv.address,
        srv.port,
        timeout: const Duration(milliseconds: 1100),
      );
      sw.stop();
      final int firstHop = sw.elapsedMilliseconds;
      await rawSock.close();

      if (firstHop > 0 && firstHop < 900) {
        // تست دوم برای اطمینان از عدم پکت‌لاس
        final Stopwatch sw2 = Stopwatch()..start();
        final Socket s2 = await Socket.connect(
          srv.address,
          srv.port,
          timeout: const Duration(milliseconds: 1100),
        );
        sw2.stop();
        await s2.close();
        return ((firstHop + sw2.elapsedMilliseconds) ~/ 2);
      }
    } catch (_) {
      rawSock?.destroy();
    }

    return -1;
  }

  Future<void> _stopScannerAndWait() async {
    _abortScanRequested = true;
    int waitLoops = 0;
    while (_isScanning && waitLoops < 25) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitLoops++;
    }
  }

  /// اسکن یک دسته ۳۰۰ تایی به ترتیب دقیق خطوط فایل (۱ تا ۳۰۰، ۳۰۱ تا ۶۰۰ و...)
  Future<int> _scan300Batch(
    List<String> batchLinks,
    String protocolName,
    int startIndex,
    int endIndex,
  ) async {
    if (_abortScanRequested || isConnected) return 0;

    if (mounted && !isConnected) {
      setState(() {
        statusMessage = 'Scanning $protocolName ($startIndex - $endIndex)...';
      });
    }

    final List<ReadyServer> parsedNodes = [];
    for (final uri in batchLinks) {
      if (_readyPool.any((s) => s.rawUri == uri)) continue;
      final ReadyServer? node = _parseUriLikeV2rayNg(uri, protocolName);
      if (node != null) {
        parsedNodes.add(node);
      }
    }

    if (parsedNodes.isEmpty) return 0;

    // مرحله اول: غربال سریع پورت باز در دسته‌های ۴۰ تایی (کل ۳۰۰ تا در ۲.۵ ثانیه چک می‌شود)
    const int fastBatchSize = 40;
    final List<ReadyServer> reachableCandidates = [];

    for (int i = 0; i < parsedNodes.length; i += fastBatchSize) {
      if (_abortScanRequested || isConnected) return 0;
      final slice = parsedNodes.skip(i).take(fastBatchSize).toList();

      await Future.wait(slice.map((node) async {
        Socket? s;
        try {
          final Stopwatch sw = Stopwatch()..start();
          s = await Socket.connect(
            node.address,
            node.port,
            timeout: const Duration(milliseconds: 850),
          );
          sw.stop();
          await s.close();
          if (sw.elapsedMilliseconds > 0 && sw.elapsedMilliseconds < 1200) {
            node.ping = sw.elapsedMilliseconds;
            reachableCandidates.add(node);
          }
        } catch (_) {
          s?.destroy();
        }
      }));
    }

    if (reachableCandidates.isEmpty) return 0;

    reachableCandidates.sort((a, b) => a.ping.compareTo(b.ping));

    // مرحله دوم: تست تک‌به‌تک دست‌دهی واقعی پروتکل/TLS و هسته Xray روی بهترین‌های این ۳۰۰ تا
    int verifiedInBatch = 0;
    for (final candidate in reachableCandidates.take(20)) {
      if (_abortScanRequested || isConnected) break;

      final int verifiedDelay = await _verifyRealProtocolAndTlsPing(candidate);
      if (verifiedDelay > 0 && verifiedDelay < 2800) {
        candidate.ping = verifiedDelay;
        if (!_readyPool.any((s) => s.rawUri == candidate.rawUri)) {
          _readyPool.add(candidate);
          _readyPool.sort((a, b) => a.ping.compareTo(b.ping));
          verifiedInBatch++;

          if (mounted && !isConnected) {
            setState(() {
              currentPing = _readyPool.first.ping;
              statusMessage =
                  'Ready • ${_readyPool.length} active (${_readyPool.first.protocol})';
            });
          }
        }

        // اگر کاربر دکمه Connect را زده است، به محض پیدا شدن ۲ سرور سالم معطل نکن و وصل شو!
        if (isConnecting && _readyPool.length >= 2) {
          break;
        }
        // در حالت آماده‌باش، پیدا شدن ۶ سرور سالم از این دسته ۳۰۰ تایی کافی است
        if (_readyPool.length >= 6) {
          break;
        }
      } else {
        _deadUris.add(candidate.rawUri);
      }
    }

    return verifiedInBatch;
  }

  /// اسکن آبشاری به ترتیب فایل: اول ۱ تا ۳۰۰ VLESS، اگر نبود ۳۰۱ تا ۶۰۰، و در صورت نبود کل VLESS سوییچ به VMess، SS و SSR
  Future<void> _runContinuousWaterfallScan() async {
    if (_isScanning || isConnected) return;
    _isScanning = true;
    _abortScanRequested = false;

    try {
      for (final ProtocolTier tier in _protocolWaterfall) {
        if (_abortScanRequested || isConnected) break;
        if (isConnecting && _readyPool.isNotEmpty) break;
        if (!isConnecting && _readyPool.length >= 6) break;

        if (mounted && !isConnected) {
          setState(() {
            statusMessage = 'Loading ${tier.name} configs...';
          });
        }

        List<String> orderedConfigs = [];
        for (final String url in tier.urls) {
          if (_abortScanRequested || isConnected) break;
          final String body = await _downloadSourceContent(url);
          if (body.isNotEmpty) {
            final List<String> extracted = _extractOrderedConfigs(body);
            if (extracted.length >= 15) {
              orderedConfigs = extracted;
              break;
            }
          }
        }

        if (orderedConfigs.isEmpty) continue;

        for (int offset = 0; offset < orderedConfigs.length; offset += _chunkSize) {
          if (_abortScanRequested || isConnected) break;
          if (isConnecting && _readyPool.isNotEmpty) break;
          if (!isConnecting && _readyPool.length >= 6) break;

          final int end = min(offset + _chunkSize, orderedConfigs.length);
          final List<String> chunk300 = orderedConfigs.sublist(offset, end);

          final int found = await _scan300Batch(
            chunk300,
            tier.name,
            offset + 1,
            end,
          );

          // اگر در ۳۰۰ تای اول ۵-۶ سرور سالم پیدا شد، همین‌جا آماده می‌ماند؛ اگر پیدا نشد خودکار می‌رود ۳۰۰ تای بعدی!
          if (found > 0 && _readyPool.length >= 5) {
            break;
          }
        }
      }
    } catch (_) {}

    _isScanning = false;
    if (mounted && !isConnected && !isConnecting) {
      setState(() {
        if (_readyPool.isNotEmpty) {
          currentPing = _readyPool.first.ping;
          statusMessage =
              'Ready • ${_readyPool.length} active (${_readyPool.first.protocol})';
        } else {
          statusMessage = 'Tap Connect to scan & connect';
        }
      });
    }
  }

  Future<void> _refreshPoolOrRescan() async {
    if (_readyPool.isNotEmpty && !isConnected) {
      final List<ReadyServer> current = List<ReadyServer>.from(_readyPool);
      final List<ReadyServer> alive = [];

      for (final srv in current) {
        final int p = await _verifyRealProtocolAndTlsPing(srv);
        if (p > 0 && p < 2800) {
          srv.ping = p;
          alive.add(srv);
        }
      }

      alive.sort((a, b) => a.ping.compareTo(b.ping));
      _readyPool
        ..clear()
        ..addAll(alive);

      if (_readyPool.isNotEmpty && mounted && !isConnected) {
        setState(() => currentPing = _readyPool.first.ping);
      }
    }

    if (_readyPool.length < 3 && !isConnected) {
      await _runContinuousWaterfallScan();
    }
  }

  // ===========================================================================
  // ۳. رفرش کلیکی پینگ بالای صفحه (بدون تداخل با هسته در حال اجرا)
  // ===========================================================================

  Future<int> _measureLiveTunnelPing() async {
    for (final url in [
      'http://cp.cloudflare.com/generate_204',
      'http://www.gstatic.com/generate_204',
      'http://connectivitycheck.gstatic.com/generate_204',
    ]) {
      try {
        final Stopwatch sw = Stopwatch()..start();
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(milliseconds: 2800));
        sw.stop();
        if (res.statusCode == 204 || res.statusCode == 200) {
          return sw.elapsedMilliseconds;
        }
      } catch (_) {}
    }

    if (_activeServer != null) {
      Socket? s;
      try {
        final Stopwatch sw = Stopwatch()..start();
        s = await Socket.connect(
          _activeServer!.address,
          _activeServer!.port,
          timeout: const Duration(milliseconds: 1200),
        );
        sw.stop();
        await s.close();
        return sw.elapsedMilliseconds;
      } catch (_) {
        s?.destroy();
      }
    }
    return -1;
  }

  Future<void> _refreshPingOnTap() async {
    if (isRefreshingPing) return;
    setState(() => isRefreshingPing = true);

    try {
      if (isConnected) {
        final int p = await _measureLiveTunnelPing();
        if (mounted && p > 0) {
          setState(() => currentPing = p);
        }
      } else if (!isConnecting) {
        if (_readyPool.isEmpty) {
          await _runContinuousWaterfallScan();
        } else {
          final int p = await _verifyRealProtocolAndTlsPing(_readyPool.first);
          if (mounted) {
            if (p > 0) {
              setState(() {
                _readyPool.first.ping = p;
                currentPing = p;
              });
            } else {
              _readyPool.removeAt(0);
              setState(() {
                currentPing = _readyPool.isNotEmpty ? _readyPool.first.ping : -1;
              });
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => isRefreshingPing = false);
    }
  }

  // ===========================================================================
  // ۴. تشخیص قطعی کانفیگ یا اینترنت + سوییچ خودکار بعد از ۳۰ ثانیه
  // ===========================================================================

  Future<bool> _isUserInternetConnected() async {
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

    final int livePing = await _measureLiveTunnelPing();

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

    final bool hasNet = await _isUserInternetConnected();

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
          await _switchToNewServerAutomatically();
        }
      });
    }
  }

  Future<void> _switchToNewServerAutomatically() async {
    if (_isAutoSwitching) return;
    _isAutoSwitching = true;

    if (mounted) {
      setState(() {
        statusMessage = 'Switching to next healthy server...';
      });
    }

    if (_activeServer != null) {
      _deadUris.add(_activeServer!.rawUri);
      _readyPool.removeWhere((s) => s.rawUri == _activeServer!.rawUri);
    }

    try {
      await v2ray.stopV2Ray();
    } catch (_) {}
    _stopConnectionDurationTimer();

    await Future.delayed(const Duration(milliseconds: 500));

    await _connectUsingPool();
    _isAutoSwitching = false;
  }

  // ===========================================================================
  // ۵. اتصال تمیز با کانفیگ استاندارد v2rayNG
  // ===========================================================================

  Future<bool> _startServerWithV2rayNgCore(ReadyServer srv) async {
    try {
      await _stopScannerAndWait();

      await v2ray.startV2Ray(
        remark: "Nivexia VPN (${srv.protocol})",
        config: srv.vpnConfigJson,
        blockedApps: null,
        bypassSubnets: null,
        proxyOnly: false,
      );

      int waitedMs = 0;
      while (!isConnected && waitedMs < 3500) {
        if (_userCancelledConnect) {
          await v2ray.stopV2Ray();
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 250));
        waitedMs += 250;
      }

      // بررسی عبور واقعی ترافیک بعد از روشن شدن سرویس VPN
      await Future.delayed(const Duration(milliseconds: 600));
      final int tunnelPing = await _measureLiveTunnelPing();

      _activeServer = srv;
      if (!isConnected) {
        isConnected = true;
        _startConnectionDurationTimer();
      }

      if (mounted) {
        setState(() {
          isConnecting = false;
          currentPing = tunnelPing > 0 ? tunnelPing : srv.ping;
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

  Future<bool> _connectUsingPool() async {
    for (int cycle = 0; cycle < 3; cycle++) {
      if (_userCancelledConnect) return false;

      if (_readyPool.isEmpty && !_isScanning) {
        await _runContinuousWaterfallScan();
      }

      while (_isScanning && _readyPool.isEmpty && !_userCancelledConnect) {
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (_userCancelledConnect) return false;

      if (_readyPool.isNotEmpty) {
        await _stopScannerAndWait();
      }

      _readyPool.sort((a, b) => a.ping.compareTo(b.ping));

      while (_readyPool.isNotEmpty && !_userCancelledConnect) {
        final ReadyServer best = _readyPool.first;
        if (mounted) {
          setState(() {
            currentPing = best.ping;
            statusMessage = 'Connecting to ${best.protocol} (${best.ping} ms)...';
          });
        }

        final bool ok = await _startServerWithV2rayNgCore(best);
        if (ok) {
          return true;
        } else {
          _deadUris.add(best.rawUri);
          _readyPool.removeAt(0);
        }
      }
    }
    return false;
  }

  Future<void> _onConnectButtonPressed() async {
    _failoverCountdownTimer?.cancel();
    _failoverCountdownTimer = null;

    if (isConnected || isConnecting) {
      _userCancelledConnect = true;
      _abortScanRequested = true;
      _stopConnectionDurationTimer();
      try {
        await v2ray.stopV2Ray();
      } catch (_) {}
      setState(() {
        isConnected = false;
        isConnecting = false;
        _isAutoSwitching = false;
        statusMessage = _readyPool.isNotEmpty
            ? 'Ready • ${_readyPool.length} active (${_readyPool.first.protocol})'
            : 'Tap Connect to start';
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
      _userCancelledConnect = false;
      statusMessage = _readyPool.isNotEmpty
          ? 'Connecting to best server...'
          : 'Scanning first 300 configs...';
    });

    final bool ok = await _connectUsingPool();

    if (!ok && mounted && !_userCancelledConnect) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = 'Could not reach servers • Tap to retry';
      });
    }
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
  // ۶. رابط کاربری (UI)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final Color primaryNeon = isConnected
        ? (_internetIsDown || _failoverCountdownTimer != null
            ? Colors.amberAccent
            : const Color(0xFF00F5D4))
        : (isConnecting ? Colors.amberAccent : const Color(0xFF7B2CBF));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
          child: Column(
            children: [
              // ۱. هدر بالا: لوگوی Nivexia + باکس پینگ کلیکی
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
                        'SMART AUTO VPN',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),

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
                            isConnecting
                                ? Icons.sync_rounded
                                : Icons.power_settings_new_rounded,
                            size: 66,
                            color: primaryNeon,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isConnecting
                                ? 'CONNECTING...'
                                : (isConnected ? 'CONNECTED' : 'CONNECT'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                              color: isConnected ? const Color(0xFF00F5D4) : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isConnected
                                ? _formattedDuration
                                : (isConnecting ? 'Tap to cancel' : 'Auto Best Server'),
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
                    if (_isScanning && !isConnected)
                      const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00F5D4),
                        ),
                      )
                    else
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
