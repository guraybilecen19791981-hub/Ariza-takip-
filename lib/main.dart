import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ---------------------------------------------------------------------------
// Ayarlar
// ---------------------------------------------------------------------------

const String kAdminEmail = 'guraybilecen19791981@gmail.com';

const FirebaseOptions kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyD1W2Y4eH-OfoZH5GK7L1CpzP1SxiAhGEM',
  appId: '1:360683668152:android:80ef3e57f06392c4edaa4d',
  messagingSenderId: '360683668152',
  projectId: 'ariza-takip-3bce3',
  storageBucket: 'ariza-takip-3bce3.firebasestorage.app',
);

const List<String> kDefaultMachines = ['Hakos', 'Bühler', 'Kabuk hattı'];

const Color kDark = Color(0xFF16191D);
const Color kOrange = Color(0xFFC2410C);
const Color kBg = Color(0xFFF2F3F5);
const Color kMuted = Color(0xFF5B636E);
const Color kGreen = Color(0xFF2B8A3E);

const Map<String, String> kRoleLabels = {
  'bekliyor': 'Onay bekliyor',
  'bildiren': 'Bildiren',
  'sef': 'Teknik Müdür',
  'teknisyen': 'Teknisyen',
  'admin': 'Admin',
};

const Map<String, String> kStatusLabels = {
  'acik': 'Açık',
  'basladi': 'Başlandı',
  'parca': 'Parça bekliyor',
  'destek': 'Teknik destek gelecek',
  'giderildi': 'Arıza giderildi',
};

const Map<String, String> kResultLabels = {
  'giderildi': 'Arıza giderildi',
  'parca': 'Parça bekliyor',
  'destek': 'Teknik destek gelecek',
};

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin notif = FlutterLocalNotificationsPlugin();
const MethodChannel keepAlive = MethodChannel('ariza/keepalive');

FirebaseFirestore get db => FirebaseFirestore.instance;
AppUser? currentUser;
String? pendingFaultId;

// ---------------------------------------------------------------------------
// Yardımcılar
// ---------------------------------------------------------------------------

String two(int n) => n.toString().padLeft(2, '0');

String fmtDT(DateTime? d) {
  if (d == null) return '-';
  final now = DateTime.now();
  final hm = '${two(d.hour)}:${two(d.minute)}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return hm;
  return '${two(d.day)}.${two(d.month)}.${d.year} $hm';
}

String fmtFull(DateTime? d) {
  if (d == null) return '';
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

String fmtMin(int m) => m >= 60 ? '${m ~/ 60} sa ${m % 60} dk' : '$m dk';

DateTime? tsToDate(dynamic v) => v is Timestamp ? v.toDate() : null;

Color statusBg(String s) {
  switch (s) {
    case 'acik':
      return const Color(0xFFFFF3BF);
    case 'basladi':
      return const Color(0xFFDBE8FF);
    case 'parca':
    case 'destek':
      return const Color(0xFFFFE3D0);
    case 'giderildi':
      return const Color(0xFFD3F9D8);
  }
  return const Color(0xFFE9ECEF);
}

Color statusFg(String s) {
  switch (s) {
    case 'acik':
      return const Color(0xFF6B4F00);
    case 'basladi':
      return const Color(0xFF1D4ED8);
    case 'parca':
    case 'destek':
      return const Color(0xFF9A3412);
    case 'giderildi':
      return const Color(0xFF1B6B2B);
  }
  return kMuted;
}

void toast(String msg) {
  final ctx = navKey.currentContext;
  if (ctx == null) return;
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
}

Map<String, dynamic> logEntry(String text) => {'t': Timestamp.now(), 't2': DateTime.now().millisecondsSinceEpoch, 'text': text};

// ---------------------------------------------------------------------------
// Modeller
// ---------------------------------------------------------------------------

class AppUser {
  final String uid;
  final String name;
  final String email;
  final String role;
  final bool alarm;

  AppUser({required this.uid, required this.name, required this.email, required this.role, required this.alarm});

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    return AppUser(
      uid: d.id,
      name: (m['name'] ?? '').toString(),
      email: (m['email'] ?? '').toString(),
      role: (m['role'] ?? 'bekliyor').toString(),
      alarm: m['alarm'] == true,
    );
  }

  bool get getsAlarm => role == 'sef' || alarm;
  bool get canManage => role == 'sef' || role == 'admin';
  String get roleLabel => kRoleLabels[role] ?? role;
}

class Fault {
  final String id;
  final String code;
  final String machine;
  final String desc;
  final String reporterUid;
  final String reporterName;
  final DateTime? createdAt;
  final String status;
  final String? assigneeUid;
  final String? assigneeName;
  final DateTime? startedAt;
  final DateTime? firstStartedAt;
  final DateTime? endedAt;
  final int totalMinutes;
  final int photoCount;
  final List<Map<String, dynamic>> log;
  final List<Map<String, dynamic>> works;

  Fault({
    required this.id,
    required this.code,
    required this.machine,
    required this.desc,
    required this.reporterUid,
    required this.reporterName,
    required this.createdAt,
    required this.status,
    required this.assigneeUid,
    required this.assigneeName,
    required this.startedAt,
    required this.firstStartedAt,
    required this.endedAt,
    required this.totalMinutes,
    required this.photoCount,
    required this.log,
    required this.works,
  });

  static List<Map<String, dynamic>> _maps(dynamic v) {
    if (v is! List) return <Map<String, dynamic>>[];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  factory Fault.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final log = _maps(m['log']);
    log.sort((a, b) => ((a['t2'] as num?) ?? 0).compareTo((b['t2'] as num?) ?? 0));
    final works = _maps(m['works']);
    works.sort((a, b) => ((a['t2'] as num?) ?? 0).compareTo((b['t2'] as num?) ?? 0));
    final assignee = m['assigneeUid'];
    return Fault(
      id: d.id,
      code: (m['code'] ?? '').toString(),
      machine: (m['machine'] ?? '').toString(),
      desc: (m['desc'] ?? '').toString(),
      reporterUid: (m['reporterUid'] ?? '').toString(),
      reporterName: (m['reporterName'] ?? '').toString(),
      createdAt: tsToDate(m['createdAt']),
      status: (m['status'] ?? 'acik').toString(),
      assigneeUid: assignee == null ? null : assignee.toString(),
      assigneeName: m['assigneeName']?.toString(),
      startedAt: tsToDate(m['startedAt']),
      firstStartedAt: tsToDate(m['firstStartedAt']),
      endedAt: tsToDate(m['endedAt']),
      totalMinutes: ((m['totalMinutes'] as num?) ?? 0).toInt(),
      photoCount: ((m['photoCount'] as num?) ?? 0).toInt(),
      log: log,
      works: works,
    );
  }

  String get statusLabel {
    if (status == 'acik') return assigneeUid == null ? 'Açık · atanmadı' : 'Açık · atandı';
    return kStatusLabels[status] ?? status;
  }

  bool get isClosed => status == 'giderildi';
  bool get isWaiting => status == 'parca' || status == 'destek';
  String get assigneeLine => assigneeName == null ? 'Henüz atanmadı' : 'Teknisyen: $assigneeName';
  String get lastWork => works.isEmpty ? '' : (works.last['text'] ?? '').toString();
}

int statusOrder(Fault f) {
  if (f.status == 'acik' && f.assigneeUid == null) return 0;
  switch (f.status) {
    case 'basladi':
      return 1;
    case 'acik':
      return 2;
    case 'parca':
    case 'destek':
      return 3;
  }
  return 4;
}

// ---------------------------------------------------------------------------
// Bildirimler ve alarm
// ---------------------------------------------------------------------------

class Notifier {
  static const String alarmChannel = 'ariza_alarm_v1';
  static const String infoChannel = 'ariza_bilgi_v1';

  static Future<void> init() async {
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await notif.initialize(settings, onDidReceiveNotificationResponse: (NotificationResponse r) {
      final id = r.payload;
      if (id != null && id.isNotEmpty) {
        cancel(id);
        openFault(id);
      }
    });
    try {
      final launch = await notif.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) {
        pendingFaultId = launch.notificationResponse?.payload;
      }
    } catch (_) {}
  }

  static Future<void> requestPermissions() async {
    final a = notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (a == null) return;
    try {
      await a.requestNotificationsPermission();
      await a.requestFullScreenIntentPermission();
    } catch (_) {}
  }

  static int idFor(String faultId) => faultId.hashCode & 0x7fffffff;

  static Future<void> alarm(Fault f) async {
    final details = AndroidNotificationDetails(
      alarmChannel,
      'Arıza alarmı',
      channelDescription: 'Yeni arıza bildirildiğinde susturulana kadar çalar',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      sound: UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT: susturulana kadar çalar
      ongoing: true,
      autoCancel: true,
      visibility: NotificationVisibility.public,
    );
    await notif.show(
      idFor(f.id),
      'YENİ ARIZA: ${f.machine}',
      '${f.desc} · ${f.reporterName}',
      NotificationDetails(android: details),
      payload: f.id,
    );
  }

  static Future<void> info(String faultId, String title, String body) async {
    const details = AndroidNotificationDetails(
      infoChannel,
      'Arıza bilgileri',
      channelDescription: 'Size atanan arızalar',
      importance: Importance.high,
      priority: Priority.high,
    );
    await notif.show(idFor(faultId) ^ 0x1000, title, body, const NotificationDetails(android: details), payload: faultId);
  }

  static Future<void> cancel(String faultId) async {
    try {
      await notif.cancel(idFor(faultId));
    } catch (_) {}
  }
}

void openFault(String id) {
  if (currentUser == null) {
    pendingFaultId = id;
    return;
  }
  navKey.currentState?.push(MaterialPageRoute(builder: (_) => FaultDetailPage(faultId: id)));
}

final Set<String> _alarmPagesOpen = <String>{};

void showAlarmPage(String id) {
  if (_alarmPagesOpen.contains(id)) return;
  _alarmPagesOpen.add(id);
  navKey.currentState?.push(MaterialPageRoute(builder: (_) => AlarmPage(faultId: id)));
}

class Watchers {
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alarmSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _assignSub;
  static String _key = '';
  static final Set<String> _seen = <String>{};

  static Future<void> ensure(AppUser u) async {
    final key = '${u.uid}|${u.role}|${u.alarm}';
    if (key == _key) return;
    await stop();
    _key = key;

    if (u.getsAlarm) {
      final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(seconds: 10)));
      _alarmSub = db.collection('faults').where('createdAt', isGreaterThan: since).snapshots().listen((s) {
        for (final c in s.docChanges) {
          if (c.type != DocumentChangeType.added) continue;
          final f = Fault.fromDoc(c.doc);
          if (f.reporterUid == u.uid) continue;
          if (!_seen.add(f.id)) continue;
          Notifier.alarm(f);
          showAlarmPage(f.id);
        }
      }, onError: (_) {});
    }

    if (u.role == 'teknisyen' || u.role == 'sef' || u.role == 'admin') {
      bool first = true;
      final known = <String>{};
      _assignSub = db.collection('faults').where('assigneeUid', isEqualTo: u.uid).snapshots().listen((s) {
        for (final d in s.docs) {
          final f = Fault.fromDoc(d);
          if (!known.contains(f.id)) {
            known.add(f.id);
            if (!first && !f.isClosed) {
              Notifier.info(f.id, 'Size yeni arıza atandı', '${f.code} · ${f.machine}');
            }
          }
        }
        first = false;
      }, onError: (_) {});
    }

    try {
      if (u.role == 'bildiren' && !u.alarm) {
        await keepAlive.invokeMethod('stop');
      } else {
        await keepAlive.invokeMethod('start');
      }
    } catch (_) {}
  }

  static Future<void> stop() async {
    await _alarmSub?.cancel();
    await _assignSub?.cancel();
    _alarmSub = null;
    _assignSub = null;
    _key = '';
  }
}

// ---------------------------------------------------------------------------
// Uygulama
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: kFirebaseOptions);
  } catch (_) {}
  try {
    await Notifier.init();
  } catch (_) {}
  runApp(const ArizaApp());
}

class ArizaApp extends StatelessWidget {
  const ArizaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      title: 'Arıza Takip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kOrange, primary: kOrange),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(backgroundColor: kDark, foregroundColor: Colors.white),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const LoadingPage();
        final user = snap.data;
        if (user == null) return const LoginPage();
        return UserGate(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

Map<String, dynamic> newUserData(String email, String name) {
  final e = email.trim().toLowerCase();
  final isAdmin = e == kAdminEmail;
  return {
    'name': name.trim().isEmpty ? e.split('@').first : name.trim(),
    'email': e,
    'role': isAdmin ? 'admin' : 'bekliyor',
    'alarm': isAdmin,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

// ---------------------------------------------------------------------------
// Giriş / kayıt
// ---------------------------------------------------------------------------

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  String _msg(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'E-posta adresi geçersiz.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-posta ya da şifre hatalı.';
      case 'email-already-in-use':
        return 'Bu e-posta ile zaten bir hesap var. Giriş yapın.';
      case 'weak-password':
        return 'Şifre en az 6 karakter olmalı.';
      case 'network-request-failed':
        return 'İnternet bağlantısı yok.';
    }
    return 'Hata: ${e.message ?? e.code}';
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final pass = _pass.text;
      if (_register) {
        if (_name.text.trim().isEmpty) {
          setState(() => _error = 'Lütfen adınızı yazın.');
          return;
        }
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
        await cred.user?.updateDisplayName(_name.text.trim());
        await db.collection('users').doc(cred.user!.uid).set(newUserData(email, _name.text));
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } catch (e) {
      if (mounted) setState(() => _error = 'Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: kOrange, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.notifications_active, color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(height: 16),
            const Center(child: Text('Arıza Takip', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
            const SizedBox(height: 32),
            if (_register) ...[
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Adınız Soyadınız')),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-posta'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre')),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFC92A2A))),
              ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Lütfen bekleyin…' : (_register ? 'Hesap oluştur' : 'Giriş yap')),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _register = !_register),
              child: Text(_register ? 'Hesabım var, giriş yap' : 'Hesabım yok, yeni hesap oluştur'),
            ),
          ],
        ),
      ),
    );
  }
}

class UserGate extends StatefulWidget {
  final User user;
  const UserGate({super.key, required this.user});

  @override
  State<UserGate> createState() => _UserGateState();
}

class _UserGateState extends State<UserGate> {
  bool _creating = false;

  Future<void> _ensureDoc() async {
    if (_creating) return;
    _creating = true;
    await Future<void>.delayed(const Duration(seconds: 2));
    final ref = db.collection('users').doc(widget.user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set(newUserData(widget.user.email ?? '', widget.user.displayName ?? ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(widget.user.uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return SimpleMessagePage(
            title: 'Bağlantı hatası',
            text: 'Veritabanına erişilemedi. Firestore kurallarının yayınlandığından emin olun.\n\n${snap.error}',
          );
        }
        if (!snap.hasData) return const LoadingPage();
        final doc = snap.data!;
        if (!doc.exists) {
          _ensureDoc();
          return const LoadingPage();
        }
        final me = AppUser.fromDoc(doc);
        if (me.role == 'bekliyor') {
          currentUser = null;
          return SimpleMessagePage(
            title: 'Hesabınız onay bekliyor',
            text: 'Merhaba ${me.name}. Admin hesabınıza bir rol verdiğinde uygulama otomatik açılacak.',
          );
        }
        return HomePage(me: me);
      },
    );
  }
}

Future<void> signOut() async {
  await Watchers.stop();
  try {
    await keepAlive.invokeMethod('stop');
  } catch (_) {}
  currentUser = null;
  await FirebaseAuth.instance.signOut();
}

class SimpleMessagePage extends StatelessWidget {
  final String title;
  final String text;
  const SimpleMessagePage({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arıza Takip'), actions: [
        IconButton(onPressed: signOut, icon: const Icon(Icons.logout), tooltip: 'Çıkış'),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_top, size: 56, color: kMuted),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ana sayfa
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  final AppUser me;
  const HomePage({super.key, required this.me});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _askedPermissions = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setup();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _setup();
  }

  void _setup() {
    currentUser = widget.me;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_askedPermissions) {
        _askedPermissions = true;
        await Notifier.requestPermissions();
        if (widget.me.role == 'admin') await ensureMachines();
      }
      await Watchers.ensure(widget.me);
      final p = pendingFaultId;
      if (p != null) {
        pendingFaultId = null;
        openFault(p);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final List<Tab> tabs;
    final List<Widget> views;
    switch (me.role) {
      case 'sef':
        tabs = const [Tab(text: 'Açık'), Tab(text: 'Arşiv')];
        views = [
          FaultList(filter: (f) => !f.isClosed, sortOpen: true, empty: 'Açık arıza yok.'),
          FaultList(filter: (f) => f.isClosed, empty: 'Arşiv boş.'),
        ];
        break;
      case 'admin':
        tabs = const [Tab(text: 'Özet'), Tab(text: 'Arızalar'), Tab(text: 'Kullanıcılar'), Tab(text: 'Makineler')];
        views = [
          const SummaryView(),
          FaultList(filter: (f) => true, sortOpen: true, empty: 'Henüz arıza yok.'),
          const UsersView(),
          const MachinesView(),
        ];
        break;
      case 'teknisyen':
        tabs = const [Tab(text: 'İşlerim'), Tab(text: 'Giderdiklerim')];
        views = [
          FaultList(filter: (f) => f.assigneeUid == me.uid && !f.isClosed, sortOpen: true, empty: 'Size atanmış açık arıza yok.'),
          FaultList(filter: (f) => f.assigneeUid == me.uid && f.isClosed, empty: 'Henüz giderilen arıza yok.'),
        ];
        break;
      default:
        tabs = const [Tab(text: 'Bildirdiklerim')];
        views = [
          FaultList(filter: (f) => f.reporterUid == me.uid, empty: 'Henüz arıza bildirmediniz.'),
        ];
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Arıza Takip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Text('${me.name} · ${me.roleLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
            ],
          ),
          actions: [
            if (me.getsAlarm)
              IconButton(
                tooltip: 'Alarm için pil ayarı',
                icon: const Icon(Icons.battery_alert),
                onPressed: () => keepAlive.invokeMethod('batterySettings').catchError((_) => null),
              ),
            IconButton(onPressed: signOut, icon: const Icon(Icons.logout), tooltip: 'Çıkış'),
          ],
          bottom: tabs.length > 1
              ? TabBar(
                  tabs: tabs,
                  isScrollable: tabs.length > 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFFADB5BD),
                  indicatorColor: kOrange,
                )
              : null,
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: kOrange,
          foregroundColor: Colors.white,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewFaultPage(me: me))),
          icon: const Icon(Icons.add),
          label: const Text('Arıza Bildir'),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}

Stream<List<Fault>> faultsStream() {
  return db
      .collection('faults')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map((d) => Fault.fromDoc(d)).toList());
}

class FaultList extends StatelessWidget {
  final bool Function(Fault) filter;
  final bool sortOpen;
  final String empty;
  const FaultList({super.key, required this.filter, required this.empty, this.sortOpen = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Fault>>(
      stream: faultsStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!.where(filter).toList();
        if (sortOpen) {
          list.sort((a, b) {
            final o = statusOrder(a).compareTo(statusOrder(b));
            if (o != 0) return o;
            return (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now());
          });
        }
        if (list.isEmpty) {
          return Center(child: Text(empty, style: const TextStyle(color: kMuted, fontSize: 15)));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => FaultCard(f: list[i]),
        );
      },
    );
  }
}

class StatusChip extends StatelessWidget {
  final Fault f;
  const StatusChip({super.key, required this.f});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: statusBg(f.status), borderRadius: BorderRadius.circular(999)),
      child: Text(f.statusLabel, style: TextStyle(color: statusFg(f.status), fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class FaultCard extends StatelessWidget {
  final Fault f;
  const FaultCard({super.key, required this.f});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE3E6EA))),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openFault(f.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${f.code} · ${fmtDT(f.createdAt)}', style: const TextStyle(color: kMuted, fontSize: 12)),
                  ),
                  StatusChip(f: f),
                ],
              ),
              const SizedBox(height: 6),
              Text(f.machine, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(f.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted)),
              const SizedBox(height: 4),
              Text(
                f.isClosed ? '${f.assigneeName ?? ''} · Süre: ${fmtMin(f.totalMinutes)}' : f.assigneeLine,
                style: const TextStyle(color: kMuted, fontSize: 13),
              ),
              if (f.status == 'basladi' && f.startedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    const Text('Süre: ', style: TextStyle(color: kMuted, fontSize: 13)),
                    Elapsed(start: f.startedAt!, style: const TextStyle(color: kMuted, fontSize: 13)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class Elapsed extends StatefulWidget {
  final DateTime start;
  final TextStyle? style;
  const Elapsed({super.key, required this.start, this.style});

  @override
  State<Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<Elapsed> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var d = DateTime.now().difference(widget.start);
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final text = h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
    return Text(text, style: widget.style);
  }
}

// ---------------------------------------------------------------------------
// Yeni arıza
// ---------------------------------------------------------------------------

class NewFaultPage extends StatefulWidget {
  final AppUser me;
  const NewFaultPage({super.key, required this.me});

  @override
  State<NewFaultPage> createState() => _NewFaultPageState();
}

class _NewFaultPageState extends State<NewFaultPage> {
  String? _machine;
  final _desc = TextEditingController();
  final List<Uint8List> _photos = <Uint8List>[];
  bool _busy = false;

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Fotoğraf çek'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 60);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 700000) {
        toast('Fotoğraf çok büyük, lütfen tekrar deneyin.');
        return;
      }
      setState(() => _photos.add(bytes));
    } catch (e) {
      toast('Fotoğraf alınamadı: $e');
    }
  }

  Future<void> _submit() async {
    if (_machine == null) {
      toast('Lütfen makineyi seçin.');
      return;
    }
    if (_desc.text.trim().isEmpty) {
      toast('Lütfen arıza detayını yazın.');
      return;
    }
    setState(() => _busy = true);
    try {
      final me = widget.me;
      final counterRef = db.collection('counters').doc('faults');
      final faultRef = db.collection('faults').doc();
      String code = '';
      await db.runTransaction((tx) async {
        final c = await tx.get(counterRef);
        final n = ((c.data()?['next'] as num?) ?? 1).toInt();
        code = 'A-${n.toString().padLeft(4, '0')}';
        tx.set(counterRef, {'next': n + 1});
        tx.set(faultRef, {
          'no': n,
          'code': code,
          'machine': _machine,
          'desc': _desc.text.trim(),
          'reporterUid': me.uid,
          'reporterName': me.name,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'acik',
          'assigneeUid': null,
          'assigneeName': null,
          'totalMinutes': 0,
          'photoCount': _photos.length,
          'log': [logEntry('Bildirildi · ${me.name}')],
          'works': <Map<String, dynamic>>[],
        });
      });
      for (var i = 0; i < _photos.length; i++) {
        await faultRef.collection('photos').doc('$i').set({'i': i, 'data': base64Encode(_photos[i])});
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      toast('$code numarasıyla bildirildi. Teknik müdüre alarm gitti.');
    } catch (e) {
      toast('Gönderilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni arıza bildir')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('machines').orderBy('name').snapshots(),
        builder: (context, snap) {
          final machines = snap.hasData ? snap.data!.docs.map((d) => (d.data()['name'] ?? '').toString()).toList() : <String>[];
          if (_machine != null && !machines.contains(_machine)) machines.add(_machine!);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Makine adı', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _machine,
                hint: const Text('Makine seçin'),
                items: machines.map((m) => DropdownMenuItem<String>(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _machine = v),
              ),
              const SizedBox(height: 16),
              const Text('Arıza detayı', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _desc,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'Ne oldu? Ses, koku, hata kodu…'),
              ),
              const SizedBox(height: 16),
              const Text('Fotoğraf (varsa, en fazla 3)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_photos[i], width: 90, height: 90, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton(
                            style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _photos.removeAt(i)),
                          ),
                        ),
                      ],
                    ),
                  if (_photos.length < 3)
                    InkWell(
                      onTap: _addPhoto,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF868E96)),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Icon(Icons.photo_camera), SizedBox(height: 4), Text('Ekle', style: TextStyle(fontSize: 12))],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Gönderiliyor…' : 'Arızayı Gönder'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Arıza detayı
// ---------------------------------------------------------------------------

class FaultDetailPage extends StatelessWidget {
  final String faultId;
  const FaultDetailPage({super.key, required this.faultId});

  DocumentReference<Map<String, dynamic>> get ref => db.collection('faults').doc(faultId);

  Future<void> _assign(BuildContext context, Fault f) async {
    final snap = await db.collection('users').where('role', isEqualTo: 'teknisyen').get();
    final techs = snap.docs.map((d) => AppUser.fromDoc(d)).toList();
    if (!context.mounted) return;
    if (techs.isEmpty) {
      toast('Teknisyen rolünde kullanıcı yok. Admin, Kullanıcılar sekmesinden rol verebilir.');
      return;
    }
    final picked = await showModalBottomSheet<AppUser>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Teknisyen seçin', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final t in techs)
              ListTile(
                leading: CircleAvatar(child: Text(t.name.isEmpty ? '?' : t.name.substring(0, 1).toUpperCase())),
                title: Text(t.name),
                subtitle: Text(t.email),
                onTap: () => Navigator.pop(c, t),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ref.update({
      'assigneeUid': picked.uid,
      'assigneeName': picked.name,
      'log': FieldValue.arrayUnion([logEntry('Atandı · ${picked.name}')]),
    });
    toast('${f.code} atandı: ${picked.name}');
  }

  Future<void> _start(Fault f) async {
    final now = Timestamp.now();
    final data = <String, dynamic>{
      'status': 'basladi',
      'startedAt': now,
      'log': FieldValue.arrayUnion([logEntry(f.works.isEmpty ? 'Arızaya başlandı' : 'Arızaya tekrar başlandı')]),
    };
    if (f.firstStartedAt == null) data['firstStartedAt'] = now;
    await ref.update(data);
  }

  @override
  Widget build(BuildContext context) {
    final me = currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Arıza detayı')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (!snap.data!.exists) return const Center(child: Text('Arıza bulunamadı.'));
          final f = Fault.fromDoc(snap.data!);
          final canAssign = me != null && me.canManage && !f.isClosed && f.status != 'basladi';
          final isMine = me != null && f.assigneeUid == me.uid;
          final canStart = isMine && (f.status == 'acik' || f.isWaiting);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _box(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text('${f.code} · ${fmtDT(f.createdAt)}', style: const TextStyle(color: kMuted, fontSize: 12))),
                    StatusChip(f: f),
                  ]),
                  const SizedBox(height: 8),
                  Text(f.machine, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  Text('Bildiren: ${f.reporterName}', style: const TextStyle(color: kMuted)),
                  const SizedBox(height: 8),
                  Text(f.desc, style: const TextStyle(fontSize: 15, height: 1.4)),
                  if (f.photoCount > 0) ...[
                    const SizedBox(height: 12),
                    PhotoStrip(faultId: f.id),
                  ],
                ],
              )),
              const SizedBox(height: 12),
              if (canAssign)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: f.assigneeUid == null
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: kDark),
                          onPressed: () => _assign(context, f),
                          icon: const Icon(Icons.person_add),
                          label: const Text('Teknisyene ata'),
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: () => _assign(context, f),
                          icon: const Icon(Icons.swap_horiz),
                          label: Text('Atanan: ${f.assigneeName} · Değiştir'),
                        ),
                ),
              if (canStart)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kGreen),
                    onPressed: () => _start(f),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(f.isWaiting ? 'Arızaya Tekrar Başla' : 'Arızaya Başla'),
                  ),
                ),
              if (f.status == 'basladi' && f.startedAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _box(Column(
                    children: [
                      const Text('Arızaya başlandı', style: TextStyle(color: kMuted)),
                      Elapsed(start: f.startedAt!, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w600)),
                      Text('Başlangıç: ${fmtDT(f.startedAt)} · ${f.assigneeName ?? ''}', style: const TextStyle(color: kMuted)),
                    ],
                  )),
                ),
              if (isMine && f.status == 'basladi')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kDark),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FinishPage(fault: f))),
                    child: const Text('İşi Bitir'),
                  ),
                ),
              if (f.works.isNotEmpty) ...[
                _box(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Yapılan işlemler', style: TextStyle(fontWeight: FontWeight.w600)),
                    for (final w in f.works) ...[
                      const Divider(),
                      Text(
                        '${fmtDT(tsToDate(w['t']))} · ${w['by'] ?? ''} · ${w['result'] ?? ''} · ${fmtMin(((w['minutes'] as num?) ?? 0).toInt())}',
                        style: const TextStyle(color: kMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text((w['text'] ?? '').toString(), style: const TextStyle(fontSize: 15)),
                    ],
                  ],
                )),
                const SizedBox(height: 12),
              ],
              _box(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Süreç', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  for (final l in f.log)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 120, child: Text(fmtDT(tsToDate(l['t'])), style: const TextStyle(color: kMuted, fontSize: 13))),
                          Expanded(child: Text((l['text'] ?? '').toString(), style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                ],
              )),
            ],
          );
        },
      ),
    );
  }
}

Widget _box(Widget child) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE3E6EA)),
    ),
    child: child,
  );
}

class PhotoStrip extends StatelessWidget {
  final String faultId;
  const PhotoStrip({super.key, required this.faultId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: db.collection('faults').doc(faultId).collection('photos').orderBy('i').get(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()));
        final images = <Uint8List>[];
        for (final d in snap.data!.docs) {
          try {
            images.add(base64Decode((d.data()['data'] ?? '').toString()));
          } catch (_) {}
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final img in images)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(backgroundColor: Colors.black),
                    body: Center(child: InteractiveViewer(child: Image.memory(img))),
                  ),
                )),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(img, width: 96, height: 96, fit: BoxFit.cover),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// İşi bitir
// ---------------------------------------------------------------------------

class FinishPage extends StatefulWidget {
  final Fault fault;
  const FinishPage({super.key, required this.fault});

  @override
  State<FinishPage> createState() => _FinishPageState();
}

class _FinishPageState extends State<FinishPage> {
  final _note = TextEditingController();
  String? _result;
  bool _busy = false;

  Future<void> _save() async {
    if (_note.text.trim().isEmpty) {
      toast('Lütfen yapılan işlemleri yazın.');
      return;
    }
    if (_result == null) {
      toast('Lütfen arıza durumunu seçin.');
      return;
    }
    setState(() => _busy = true);
    try {
      final f = widget.fault;
      final me = currentUser;
      final now = DateTime.now();
      final mins = math.max(1, now.difference(f.startedAt ?? now).inMinutes);
      final label = kResultLabels[_result!]!;
      await db.collection('faults').doc(f.id).update({
        'status': _result,
        'endedAt': Timestamp.fromDate(now),
        'totalMinutes': FieldValue.increment(mins),
        'works': FieldValue.arrayUnion([
          {
            't': Timestamp.fromDate(now),
            't2': now.millisecondsSinceEpoch,
            'by': me?.name ?? '',
            'text': _note.text.trim(),
            'result': label,
            'minutes': mins,
          }
        ]),
        'log': FieldValue.arrayUnion([logEntry('$label · ${fmtMin(mins)}')]),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(_result == 'giderildi' ? '${f.code} giderildi, arşive eklendi.' : '${f.code} açık kaldı: $label');
    } catch (e) {
      toast('Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fault;
    return Scaffold(
      appBar: AppBar(title: const Text('İşi bitir')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${f.code} · ${f.machine}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const Text('Yapılan işlemler', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _note,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'Arızanın nedeni ve yapılan müdahale'),
          ),
          const SizedBox(height: 16),
          const Text('Arıza durumu', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final e in kResultLabels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _result == e.key ? kDark : const Color(0xFFCED4DA), width: _result == e.key ? 2 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _result = e.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    child: Row(
                      children: [
                        Icon(_result == e.key ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: _result == e.key ? kDark : kMuted),
                        const SizedBox(width: 12),
                        Text(e.value, style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kGreen),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Kaydediliyor…' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alarm ekranı
// ---------------------------------------------------------------------------

class AlarmPage extends StatefulWidget {
  final String faultId;
  const AlarmPage({super.key, required this.faultId});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    _alarmPagesOpen.remove(widget.faultId);
    super.dispose();
  }

  void _ack() {
    Notifier.cancel(widget.faultId);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => FaultDetailPage(faultId: widget.faultId)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Scaffold(
        backgroundColor: Color.lerp(const Color(0xFFC92A2A), const Color(0xFF8F0D0D), _c.value),
        body: child,
      ),
      child: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('faults').doc(widget.faultId).snapshots(),
          builder: (context, snap) {
            final f = (snap.hasData && snap.data!.exists) ? Fault.fromDoc(snap.data!) : null;
            return Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_active, color: Colors.white, size: 84),
                  const SizedBox(height: 12),
                  const Text('YENİ ARIZA', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  Text(f?.machine ?? '', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(f == null ? '' : 'Bildiren: ${f.reporterName}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 10),
                  Text(f?.desc ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  const SizedBox(height: 32),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFA51111)),
                    onPressed: _ack,
                    child: const Text('Alarmı Sustur ve Görüntüle'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin: özet, kullanıcılar, makineler, Excel
// ---------------------------------------------------------------------------

Future<void> ensureMachines() async {
  try {
    final s = await db.collection('machines').limit(1).get();
    if (s.docs.isEmpty) {
      for (final m in kDefaultMachines) {
        await db.collection('machines').add({'name': m});
      }
    }
  } catch (_) {}
}

class SummaryView extends StatelessWidget {
  const SummaryView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Fault>>(
      stream: faultsStream(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        int count(bool Function(Fault) t) => all.where(t).length;
        final tiles = <List<String>>[
          ['Atama bekleyen', '${count((f) => f.status == 'acik' && f.assigneeUid == null)}'],
          ['Açık (atandı)', '${count((f) => f.status == 'acik' && f.assigneeUid != null)}'],
          ['Başlandı', '${count((f) => f.status == 'basladi')}'],
          ['Parça / destek bekliyor', '${count((f) => f.isWaiting)}'],
          ['Giderildi', '${count((f) => f.isClosed)}'],
          ['Toplam', '${all.length}'],
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.8,
              children: [
                for (final t in tiles)
                  _box(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t[0], style: const TextStyle(color: kMuted, fontSize: 13)),
                      Text(t[1], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
                    ],
                  )),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kDark),
              onPressed: () => exportExcel(),
              icon: const Icon(Icons.download),
              label: const Text("Tüm arızaları Excel'e aktar"),
            ),
            const SizedBox(height: 12),
            const Text(
              'Alarm alacak kişileri Kullanıcılar sekmesinden seçebilirsiniz. Teknik Müdür her zaman alarm alır.',
              style: TextStyle(color: kMuted),
            ),
          ],
        );
      },
    );
  }
}

Future<void> exportExcel() async {
  try {
    toast('Excel dosyası hazırlanıyor…');
    final snap = await db.collection('faults').orderBy('createdAt').get();
    final excel = xl.Excel.createExcel();
    final xl.Sheet sheet = excel['Sheet1'];
    final headers = [
      'No', 'Makine', 'Arıza detayı', 'Bildiren', 'Bildirim', 'Teknisyen', 'İlk başlama', 'Bitiş',
      'Süre (dk)', 'Durum', 'Yapılan işlemler',
    ];
    sheet.appendRow(headers.map<xl.CellValue?>((h) => xl.TextCellValue(h)).toList());
    for (final d in snap.docs) {
      final f = Fault.fromDoc(d);
      final works = f.works.map((w) => '${fmtFull(tsToDate(w['t']))} ${w['by'] ?? ''}: ${w['text'] ?? ''} (${w['result'] ?? ''})').join(' | ');
      sheet.appendRow(<xl.CellValue?>[
        xl.TextCellValue(f.code),
        xl.TextCellValue(f.machine),
        xl.TextCellValue(f.desc),
        xl.TextCellValue(f.reporterName),
        xl.TextCellValue(fmtFull(f.createdAt)),
        xl.TextCellValue(f.assigneeName ?? ''),
        xl.TextCellValue(fmtFull(f.firstStartedAt)),
        xl.TextCellValue(f.works.isEmpty ? '' : fmtFull(f.endedAt)),
        xl.IntCellValue(f.totalMinutes),
        xl.TextCellValue(kStatusLabels[f.status] ?? f.status),
        xl.TextCellValue(works),
      ]);
    }
    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final file = File('${dir.path}/ariza_takip_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Arıza Takip kayıtları');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}

class UsersView extends StatelessWidget {
  const UsersView({super.key});

  Future<void> _rename(BuildContext context, AppUser u) async {
    final c = TextEditingController(text: u.name);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('İsim'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await db.collection('users').doc(u.uid).update({'name': name});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = snap.data!.docs.map((d) => AppUser.fromDoc(d)).toList();
        users.sort((a, b) {
          final p = (a.role == 'bekliyor' ? 0 : 1).compareTo(b.role == 'bekliyor' ? 0 : 1);
          return p != 0 ? p : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const Text(
              'Yeni kullanıcılar telefonlarında uygulamayı açıp "Yeni hesap oluştur" ile kayıt olur. '
              'Burada onlara rol verin. Alarm anahtarı açık olanların telefonunda yeni arızada alarm çalar.',
              style: TextStyle(color: kMuted),
            ),
            const SizedBox(height: 12),
            for (final u in users)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _box(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              Text(u.email, style: const TextStyle(color: kMuted, fontSize: 13)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => _rename(context, u), icon: const Icon(Icons.edit), tooltip: 'İsmi düzenle'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: kRoleLabels.containsKey(u.role) ? u.role : 'bekliyor',
                            decoration: const InputDecoration(labelText: 'Rol', isDense: true),
                            items: kRoleLabels.entries
                                .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              if (u.uid == currentUser?.uid && v != 'admin') {
                                toast('Kendi admin rolünüzü kaldıramazsınız.');
                                return;
                              }
                              db.collection('users').doc(u.uid).update({'role': v});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          children: [
                            const Text('Alarm', style: TextStyle(fontSize: 12, color: kMuted)),
                            Switch(
                              value: u.role == 'sef' ? true : u.alarm,
                              onChanged: u.role == 'sef' ? null : (v) => db.collection('users').doc(u.uid).update({'alarm': v}),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                )),
              ),
          ],
        );
      },
    );
  }
}

class MachinesView extends StatelessWidget {
  const MachinesView({super.key});

  Future<void> _add(BuildContext context) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Makine ekle'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Makine adı')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Ekle')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await db.collection('machines').add({'name': name});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('machines').orderBy('name').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => _add(context),
              icon: const Icon(Icons.add),
              label: const Text('Makine ekle'),
            ),
            const SizedBox(height: 12),
            for (final d in docs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _box(Row(
                  children: [
                    Expanded(child: Text((d.data()['name'] ?? '').toString(), style: const TextStyle(fontSize: 16))),
                    IconButton(
                      tooltip: 'Sil',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Makine silinsin mi?'),
                            content: Text((d.data()['name'] ?? '').toString()),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
                            ],
                          ),
                        );
                        if (ok == true) await d.reference.delete();
                      },
                    ),
                  ],
                )),
              ),
          ],
        );
      },
    );
  }
}
