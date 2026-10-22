part of 'main.dart';

// ---------------------------------------------------------------------------
// Makine takip (hat makineleri: çalışıyor / duruş nedenleri / kapalı)
// ---------------------------------------------------------------------------

const String kRunKey = 'calisiyor';
const String kOffKey = 'kapali';

class MReason {
  final String key;
  final String label;
  final bool alarm;
  const MReason(this.key, this.label, this.alarm);

  factory MReason.fromMap(dynamic m) {
    final x = (m is Map) ? m : <String, dynamic>{};
    return MReason((x['key'] ?? '').toString(), (x['label'] ?? '').toString(), x['alarm'] == true);
  }

  Map<String, dynamic> toMap() => {'key': key, 'label': label, 'alarm': alarm};
}

const List<MReason> kDefaultMReasons = [
  MReason('uretim_yok', 'Üretim yok', false),
  MReason('ariza', 'Arızalı', true),
  MReason('mola', 'Mola', false),
  MReason('sarf_yok', 'Sarf malzeme yok', true),
  MReason('urun_yok', 'Ürün yok', true),
  MReason('eleman_yok', 'Eleman yok', true),
];

Color mStateColor(String key) {
  if (key == kRunKey) return const Color(0xFF2B8A3E);
  if (key == kOffKey) return const Color(0xFF868E96);
  if (key == 'ariza') return const Color(0xFFC92A2A);
  if (key == 'mola') return const Color(0xFF1D4ED8);
  return const Color(0xFFD9480F);
}

class LineMachine {
  final String id;
  final String name;
  final String line;
  final int order;
  final String state;
  final String stateLabel;
  final DateTime? since;
  final String by;
  final String note;
  final String openLogId;

  LineMachine({
    required this.id,
    required this.name,
    required this.line,
    required this.order,
    required this.state,
    required this.stateLabel,
    required this.since,
    required this.by,
    required this.note,
    required this.openLogId,
  });

  factory LineMachine.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    return LineMachine(
      id: d.id,
      name: (m['name'] ?? '').toString(),
      line: (m['line'] ?? '').toString(),
      order: (m['order'] is num) ? (m['order'] as num).toInt() : 0,
      state: (m['state'] ?? kOffKey).toString(),
      stateLabel: (m['stateLabel'] ?? 'Kapalı').toString(),
      since: tsToDate(m['since']),
      by: (m['by'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      openLogId: (m['openLogId'] ?? '').toString(),
    );
  }

  bool get running => state == kRunKey;
}

class MLog {
  final String id;
  final String machineId;
  final String machineName;
  final String line;
  final String state;
  final String label;
  final DateTime? start;
  final DateTime? end;
  final String by;
  final String note;

  MLog({
    required this.id,
    required this.machineId,
    required this.machineName,
    required this.line,
    required this.state,
    required this.label,
    required this.start,
    required this.end,
    required this.by,
    required this.note,
  });

  factory MLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    return MLog(
      id: d.id,
      machineId: (m['machineId'] ?? '').toString(),
      machineName: (m['machineName'] ?? '').toString(),
      line: (m['line'] ?? '').toString(),
      state: (m['state'] ?? '').toString(),
      label: (m['label'] ?? '').toString(),
      start: tsToDate(m['start']),
      end: tsToDate(m['end']),
      by: (m['by'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
    );
  }

  // Seçilen aralığa düşen süre (saniye)
  int secondsIn(DateTime from, DateTime to, DateTime now) {
    final s = start;
    if (s == null) return 0;
    final e = end ?? now;
    final a = s.isAfter(from) ? s : from;
    final b = e.isBefore(to) ? e : to;
    final d = b.difference(a).inSeconds;
    return d > 0 ? d : 0;
  }
}

class MStat {
  final String id;
  final String name;
  final String line;
  int run = 0;
  int off = 0;
  final Map<String, int> stops = {};
  MStat(this.id, this.name, this.line);

  int get tracked => run + stops.values.fold(0, (a, b) => a + b);
  double get efficiency => tracked == 0 ? 0 : run * 100 / tracked;
  int get stopTotal => stops.values.fold(0, (a, b) => a + b);
}

Map<String, MStat> computeMStats(List<LineMachine> machines, List<MLog> logs, DateTime from, DateTime to) {
  final now = DateTime.now();
  final out = <String, MStat>{};
  final all = List<MLog>.from(logs);
  final ids = logs.map((l) => l.id).toSet();
  for (final m in machines) {
    out[m.id] = MStat(m.id, m.name, m.line);
    // Okunan aralıktan önce başlamış ve hâlâ süren durum
    if (m.openLogId.isNotEmpty && !ids.contains(m.openLogId) && m.since != null) {
      all.add(MLog(id: m.openLogId, machineId: m.id, machineName: m.name, line: m.line, state: m.state, label: m.stateLabel,
          start: m.since, end: null, by: m.by, note: m.note));
    }
  }
  for (final l in all) {
    final sec = l.secondsIn(from, to, now);
    if (sec <= 0) continue;
    final st = out.putIfAbsent(l.machineId, () => MStat(l.machineId, l.machineName, l.line));
    if (l.state == kRunKey) {
      st.run += sec;
    } else if (l.state == kOffKey) {
      st.off += sec;
    } else {
      final k = l.label.isEmpty ? l.state : l.label;
      st.stops[k] = (st.stops[k] ?? 0) + sec;
    }
  }
  return out;
}

String fmtSec(int s) => fmtMin((s / 60).round());

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

bool canMachineEnter(AppUser? me) => me != null && me.can('hat', 'gir');
bool canMachineManage(AppUser? me) => me != null && (me.isAdmin || me.can('hat', 'yonet'));

class MachineOps {
  static CollectionReference<Map<String, dynamic>> get col => db.collection('lineMachines');
  static CollectionReference<Map<String, dynamic>> get logs => db.collection('machineLogs');
  static DocumentReference<Map<String, dynamic>> get cfg => db.collection('config').doc('machineReasons');

  static List<MReason> _parse(DocumentSnapshot<Map<String, dynamic>> s) {
    final raw = s.data()?['items'];
    if (raw is List && raw.isNotEmpty) return raw.map((e) => MReason.fromMap(e)).where((r) => r.key.isNotEmpty).toList();
    return List<MReason>.from(kDefaultMReasons);
  }

  static Stream<List<MReason>> reasonsStream() => cfg.snapshots().map(_parse);

  static Future<void> saveReasons(List<MReason> list) => cfg.set({'items': list.map((r) => r.toMap()).toList()});

  static Stream<List<LineMachine>> machinesStream() => col.snapshots().map((s) {
        final l = s.docs.map((d) => LineMachine.fromDoc(d)).toList();
        l.sort((a, b) {
          final c = a.line.toLowerCase().compareTo(b.line.toLowerCase());
          if (c != 0) return c;
          final o = a.order.compareTo(b.order);
          return o != 0 ? o : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return l;
      });

  static Stream<List<MLog>> logsSince(DateTime from) => logs
      .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .snapshots()
      .map((s) => s.docs.map((d) => MLog.fromDoc(d)).toList());

  static Future<List<MLog>> logsBetween(DateTime from, DateTime to) async {
    // Aralıktan önce başlayıp aralığa sarkan kayıtlar için 7 gün geriden okunur
    final s = await logs
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from.subtract(const Duration(days: 7))))
        .where('start', isLessThan: Timestamp.fromDate(to))
        .get();
    return s.docs.map((d) => MLog.fromDoc(d)).toList();
  }

  static Future<void> addMachine(String name, String line, int order) => col.add({
        'name': name,
        'line': line,
        'order': order,
        'state': kOffKey,
        'stateLabel': 'Kapalı',
        'since': Timestamp.now(),
        'by': currentUser?.name ?? '',
        'note': '',
        'openLogId': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

  static Future<void> editMachine(LineMachine m, String name, String line, int order) =>
      col.doc(m.id).update({'name': name, 'line': line, 'order': order});

  static Future<void> deleteMachine(LineMachine m) => col.doc(m.id).delete();

  static Future<void> setState(LineMachine m, String key, String label, bool alarm, String note) async {
    if (m.state == key && m.note == note) return;
    final now = DateTime.now();
    final batch = db.batch();
    if (m.openLogId.isNotEmpty) {
      batch.update(logs.doc(m.openLogId), {'end': Timestamp.fromDate(now), 'endMs': now.millisecondsSinceEpoch});
    }
    final lg = logs.doc();
    batch.set(lg, {
      'machineId': m.id,
      'machineName': m.name,
      'line': m.line,
      'state': key,
      'label': label,
      'start': Timestamp.fromDate(now),
      'startMs': now.millisecondsSinceEpoch,
      'end': null,
      'endMs': null,
      'by': currentUser?.name ?? '',
      'byUid': currentUser?.uid ?? '',
      'note': note,
    });
    batch.update(col.doc(m.id), {
      'state': key,
      'stateLabel': label,
      'since': Timestamp.fromDate(now),
      'by': currentUser?.name ?? '',
      'note': note,
      'openLogId': lg.id,
    });
    if (alarm) {
      batch.set(db.collection('machineAlerts').doc(), {
        'machineId': m.id,
        'machineName': m.name,
        'line': m.line,
        'label': label,
        'note': note,
        'by': currentUser?.name ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

// ---------------------------------------------------------------------------
// Canlı ekran
// ---------------------------------------------------------------------------

class MachineHome extends StatelessWidget {
  final AppUser me;
  final Widget? nav;
  const MachineHome({super.key, required this.me, this.nav});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bind · Makine takip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text('${me.name} · ${me.roleLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Rapor ve Excel',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MachineReportPage())),
          ),
          if (canMachineManage(me))
            IconButton(
              tooltip: 'Makineler ve duruş nedenleri',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MachineSettingsPage())),
            ),
          ...commonActions(me),
        ],
      ),
      bottomNavigationBar: nav,
      body: const MachineLive(),
    );
  }
}

class MachineLive extends StatefulWidget {
  const MachineLive({super.key});

  @override
  State<MachineLive> createState() => _MachineLiveState();
}

class _MachineLiveState extends State<MachineLive> {
  late final DateTime _from = dayStart(DateTime.now()).subtract(const Duration(days: 1));
  late final Stream<List<MLog>> _logs = MachineOps.logsSince(_from);
  late final Stream<List<LineMachine>> _machines = MachineOps.machinesStream();
  late final Stream<List<MReason>> _reasons = MachineOps.reasonsStream();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LineMachine>>(
      stream: _machines,
      builder: (context, ms) {
        if (ms.hasError) return Center(child: Text('Hata: ${ms.error}'));
        if (!ms.hasData) return const Center(child: CircularProgressIndicator());
        final machines = ms.data!;
        if (machines.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                canMachineManage(currentUser)
                    ? 'Henüz makine eklenmedi.\nSağ üstteki ayar simgesinden makineleri ekleyin.'
                    : 'Henüz makine eklenmedi. Admin makineleri eklediğinde burada görünecek.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted, fontSize: 15),
              ),
            ),
          );
        }
        return StreamBuilder<List<MReason>>(
          stream: _reasons,
          builder: (context, rs) {
            final reasons = rs.data ?? kDefaultMReasons;
            return StreamBuilder<List<MLog>>(
              stream: _logs,
              builder: (context, ls) {
                final today = dayStart(DateTime.now());
                final stats = computeMStats(machines, ls.data ?? const [], today, DateTime.now());
                final running = machines.where((m) => m.running).length;
                final stopped = machines.where((m) => !m.running && m.state != kOffKey).length;
                String? lastLine;
                final children = <Widget>[
                  Row(children: [
                    Expanded(child: _kpi('Çalışan', '$running', const Color(0xFF2B8A3E))),
                    const SizedBox(width: 8),
                    Expanded(child: _kpi('Duruşta', '$stopped', const Color(0xFFC92A2A))),
                    const SizedBox(width: 8),
                    Expanded(child: _kpi('Makine', '${machines.length}', kDark)),
                  ]),
                  const SizedBox(height: 12),
                ];
                for (final m in machines) {
                  if (m.line != lastLine) {
                    lastLine = m.line;
                    children.add(Padding(
                      padding: const EdgeInsets.fromLTRB(2, 6, 0, 6),
                      child: Text(m.line.isEmpty ? 'Hat belirtilmemiş' : m.line, style: const TextStyle(fontWeight: FontWeight.w700, color: kMuted)),
                    ));
                  }
                  children.add(Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MachineCard(m: m, stat: stats[m.id], reasons: reasons),
                  ));
                }
                return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: children);
              },
            );
          },
        );
      },
    );
  }

  Widget _kpi(String l, String v, Color c) => _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: const TextStyle(color: kMuted, fontSize: 12)),
        Text(v, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c)),
      ]));
}

class _MachineCard extends StatelessWidget {
  final LineMachine m;
  final MStat? stat;
  final List<MReason> reasons;
  const _MachineCard({required this.m, required this.stat, required this.reasons});

  @override
  Widget build(BuildContext context) {
    final c = mStateColor(m.state);
    final st = stat;
    final enter = canMachineEnter(currentUser);
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enter ? () => showMachineStateSheet(context, m, reasons) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(m.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              if (m.since != null) Elapsed(start: m.since!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c)),
            ]),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(999)),
              child: Text(m.stateLabel.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            if (m.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.note, style: const TextStyle(fontStyle: FontStyle.italic))),
            const SizedBox(height: 6),
            Text(
              'Bugün: verim %${(st?.efficiency ?? 0).toStringAsFixed(0)} · çalışma ${fmtSec(st?.run ?? 0)} · duruş ${fmtSec(st?.stopTotal ?? 0)}',
              style: const TextStyle(color: kMuted, fontSize: 13),
            ),
            Text('${m.by.isEmpty ? '' : '${m.by} · '}${fmtDT(m.since)}${enter ? ' · değiştirmek için dokunun' : ''}',
                style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

Future<void> showMachineStateSheet(BuildContext context, LineMachine m, List<MReason> reasons) async {
  final note = TextEditingController();
  final picked = await showModalBottomSheet<MReason>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(m.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text('Şu an: ${m.stateLabel}', style: const TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            _stateBtn(c, const MReason(kRunKey, 'Çalışıyor', false), m.state),
            const SizedBox(height: 8),
            for (final r in reasons) ...[
              _stateBtn(c, r, m.state),
              const SizedBox(height: 8),
            ],
            _stateBtn(c, const MReason(kOffKey, 'Kapalı / vardiya dışı', false), m.state),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', isDense: true)),
          ]),
        ),
      ),
    ),
  );
  if (picked == null) return;
  try {
    await MachineOps.setState(m, picked.key, picked.label, picked.alarm, note.text.trim());
    toast('${m.name}: ${picked.label}${picked.alarm ? ' · alarm gönderildi' : ''}');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Widget _stateBtn(BuildContext c, MReason r, String current) {
  final col = mStateColor(r.key);
  final on = r.key == current;
  return FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: on ? col : col.withOpacity(0.12),
      foregroundColor: on ? Colors.white : col,
      minimumSize: const Size.fromHeight(52),
      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
    onPressed: () => Navigator.pop(c, r),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(r.label),
      if (r.alarm) ...[const SizedBox(width: 8), const Icon(Icons.notifications_active, size: 18)],
    ]),
  );
}

// ---------------------------------------------------------------------------
// Rapor ve Excel
// ---------------------------------------------------------------------------

class MachineReportPage extends StatefulWidget {
  const MachineReportPage({super.key});

  @override
  State<MachineReportPage> createState() => _MachineReportPageState();
}

class _MachineReportPageState extends State<MachineReportPage> {
  DateTime _from = dayStart(DateTime.now());
  DateTime _to = dayStart(DateTime.now());
  List<MLog>? _logs;
  List<LineMachine> _machines = [];
  bool _loading = false;

  DateTime get _toEnd => _to.add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ms = await MachineOps.col.get();
      _machines = ms.docs.map((d) => LineMachine.fromDoc(d)).toList()..sort((a, b) => '${a.line}${a.name}'.compareTo('${b.line}${b.name}'));
      final end = _toEnd.isAfter(DateTime.now()) ? DateTime.now() : _toEnd;
      _logs = await MachineOps.logsBetween(_from, end);
    } catch (e) {
      toast('Rapor yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _preset(int daysBack, {bool yesterday = false}) {
    final t = dayStart(DateTime.now());
    setState(() {
      if (yesterday) {
        _from = t.subtract(const Duration(days: 1));
        _to = _from;
      } else {
        _from = t.subtract(Duration(days: daysBack));
        _to = t;
      }
    });
    _load();
  }

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(context: context, initialDate: from ? _from : _to, firstDate: DateTime(2024), lastDate: DateTime(2100));
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = d;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final end = _toEnd.isAfter(DateTime.now()) ? DateTime.now() : _toEnd;
    final stats = _logs == null ? <String, MStat>{} : computeMStats(_machines, _logs!, _from, end);
    final list = stats.values.toList()..sort((a, b) => '${a.line}${a.name}'.compareTo('${b.line}${b.name}'));
    return Scaffold(
      appBar: AppBar(title: const Text('Makine raporu'), actions: [
        IconButton(
          tooltip: "Excel'e aktar",
          icon: const Icon(Icons.download),
          onPressed: _logs == null ? null : () => exportMachineExcel(_machines, _logs!, _from, end),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: () => _preset(0), child: const Text('Bugün')),
          OutlinedButton(onPressed: () => _preset(0, yesterday: true), child: const Text('Dün')),
          OutlinedButton(onPressed: () => _preset(6), child: const Text('Son 7 gün')),
          OutlinedButton(onPressed: () => _preset(29), child: const Text('Son 30 gün')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.calendar_today, size: 18), label: Text(fmtDay(_from)))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
          Expanded(child: OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.calendar_today, size: 18), label: Text(fmtDay(_to)))),
        ]),
        const SizedBox(height: 6),
        const Text('Verimlilik = çalışma süresi ÷ izlenen süre. "Kapalı / vardiya dışı" süreler hesaba katılmaz; mola dahil tüm duruşlar verimliliği düşürür.',
            style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 12),
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (!_loading && list.isEmpty) const Text('Kayıt yok.', style: TextStyle(color: kMuted)),
        if (!_loading)
          for (final s in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text('${s.name}${s.line.isEmpty ? '' : ' · ${s.line}'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Text('%${s.efficiency.toStringAsFixed(1)}',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: s.efficiency >= 80 ? const Color(0xFF2B8A3E) : (s.efficiency >= 60 ? const Color(0xFFD9480F) : const Color(0xFFC92A2A)))),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: s.tracked == 0 ? 0 : s.run / s.tracked,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFFFE3E3),
                    color: const Color(0xFF2B8A3E),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Çalışma ${fmtSec(s.run)} · Duruş ${fmtSec(s.stopTotal)} · Kapalı ${fmtSec(s.off)}', style: const TextStyle(color: kMuted, fontSize: 13)),
                for (final e in (s.stops.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      Expanded(child: Text(e.key)),
                      Text(fmtSec(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(
                        width: 56,
                        child: Text(' %${s.tracked == 0 ? 0 : (e.value * 100 / s.tracked).toStringAsFixed(0)}',
                            textAlign: TextAlign.right, style: const TextStyle(color: kMuted)),
                      ),
                    ]),
                  ),
              ])),
            ),
      ]),
    );
  }
}

String fmtDay(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';

Future<void> exportMachineExcel(List<LineMachine> machines, List<MLog> logs, DateTime from, DateTime to) async {
  try {
    toast('Makine raporu hazırlanıyor…');
    final stats = computeMStats(machines, logs, from, to);
    final list = stats.values.toList()..sort((a, b) => '${a.line}${a.name}'.compareTo('${b.line}${b.name}'));
    final labels = <String>{};
    for (final s in list) {
      labels.addAll(s.stops.keys);
    }
    final lab = labels.toList()..sort();
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Özet');
    final xl.Sheet sh = excel['Özet'];
    final xl.Sheet det = excel['Hareketler'];
    xl.CellValue t(String v) => xl.TextCellValue(v);
    xl.CellValue n(int v) => xl.IntCellValue(v);
    xl.CellValue dbl(double v) => xl.DoubleCellValue(double.parse(v.toStringAsFixed(1)));
    int mins(int s) => (s / 60).round();
    sh.appendRow(<xl.CellValue?>[t('Makine raporu'), t('${fmtFull(from)} – ${fmtFull(to)}')]);
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[
      t('Makine'), t('Hat'), t('İzlenen süre (dk)'), t('Çalışma (dk)'), t('Toplam duruş (dk)'), t('Verimlilik %'),
      for (final l in lab) t('$l (dk)'),
      t('Kapalı / vardiya dışı (dk)'),
    ]);
    for (final s in list) {
      sh.appendRow(<xl.CellValue?>[
        t(s.name), t(s.line), n(mins(s.tracked)), n(mins(s.run)), n(mins(s.stopTotal)), dbl(s.efficiency),
        for (final l in lab) n(mins(s.stops[l] ?? 0)),
        n(mins(s.off)),
      ]);
    }
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[t('Verimlilik = çalışma ÷ izlenen süre (kapalı süreler hariç, mola dahil tüm duruşlar düşürür).')]);

    det.appendRow(<xl.CellValue?>[t('Makine'), t('Hat'), t('Durum'), t('Başlangıç'), t('Bitiş'), t('Süre (dk)'), t('Giren'), t('Not')]);
    final sorted = logs.where((l) => l.secondsIn(from, to, DateTime.now()) > 0).toList()
      ..sort((a, b) {
        final c = '${a.line}${a.machineName}'.compareTo('${b.line}${b.machineName}');
        return c != 0 ? c : (a.start ?? DateTime(2000)).compareTo(b.start ?? DateTime(2000));
      });
    for (final l in sorted) {
      det.appendRow(<xl.CellValue?>[
        t(l.machineName), t(l.line), t(l.label), t(fmtFull(l.start)), t(l.end == null ? 'devam ediyor' : fmtFull(l.end)),
        n(mins(l.secondsIn(from, to, DateTime.now()))), t(l.by), t(l.note),
      ]);
    }
    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/makine_raporu_${from.year}${two(from.month)}${two(from.day)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Makine raporu');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}

// ---------------------------------------------------------------------------
// Ayarlar: makineler ve duruş nedenleri
// ---------------------------------------------------------------------------

class MachineSettingsPage extends StatelessWidget {
  const MachineSettingsPage({super.key});

  Future<void> _machineDialog(BuildContext context, LineMachine? m, int nextOrder) async {
    final name = TextEditingController(text: m?.name ?? '');
    final line = TextEditingController(text: m?.line ?? '');
    final order = TextEditingController(text: '${m?.order ?? nextOrder}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(m == null ? 'Makine ekle' : 'Makineyi düzenle'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Makine adı')),
          const SizedBox(height: 10),
          TextField(controller: line, decoration: const InputDecoration(labelText: 'Hat (ör. Paketleme hattı 1)')),
          const SizedBox(height: 10),
          TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sıra')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final o = int.tryParse(order.text.trim()) ?? nextOrder;
      if (m == null) {
        await MachineOps.addMachine(name.text.trim(), line.text.trim(), o);
      } else {
        await MachineOps.editMachine(m, name.text.trim(), line.text.trim(), o);
      }
    } catch (e) {
      toast('Kaydedilemedi: $e');
    }
  }

  Future<void> _reasonDialog(BuildContext context, List<MReason> list, int? index) async {
    final r = index == null ? null : list[index];
    final c = TextEditingController(text: r?.label ?? '');
    bool alarm = r?.alarm ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text(r == null ? 'Duruş nedeni ekle' : 'Duruş nedenini düzenle'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Neden (ör. Bant koptu)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alarm gönder'),
              subtitle: const Text('Bu nedenle durunca makine alarmı açık kişilere bildirim gider'),
              value: alarm,
              onChanged: (v) => setS(() => alarm = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (ok != true || c.text.trim().isEmpty) return;
    final nl = List<MReason>.from(list);
    if (r == null) {
      nl.add(MReason('n${DateTime.now().millisecondsSinceEpoch}', c.text.trim(), alarm));
    } else {
      nl[index!] = MReason(r.key, c.text.trim(), alarm);
    }
    try {
      await MachineOps.saveReasons(nl);
    } catch (e) {
      toast('Kaydedilemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Makineler ve duruş nedenleri')),
      body: StreamBuilder<List<LineMachine>>(
        stream: MachineOps.machinesStream(),
        builder: (context, ms) {
          final machines = ms.data ?? const <LineMachine>[];
          return StreamBuilder<List<MReason>>(
            stream: MachineOps.reasonsStream(),
            builder: (context, rs) {
              final reasons = rs.data ?? kDefaultMReasons;
              return ListView(padding: const EdgeInsets.all(16), children: [
                const Text('Makineler', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final m in machines)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.white,
                    elevation: 0,
                    child: ListTile(
                      title: Text(m.name),
                      subtitle: Text('${m.line.isEmpty ? 'Hat yok' : m.line} · sıra ${m.order}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit), tooltip: 'Düzenle', onPressed: () => _machineDialog(context, m, m.order)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFC92A2A)),
                          tooltip: 'Sil',
                          onPressed: () async {
                            if (!await confirm(context, 'Makine silinsin mi?', '${m.name} listeden kalkar. Geçmiş kayıtları raporlarda kalır.', 'Sil')) return;
                            try {
                              await MachineOps.deleteMachine(m);
                            } catch (e) {
                              toast('Silinemedi: $e');
                            }
                          },
                        ),
                      ]),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _machineDialog(context, null, machines.length + 1),
                  icon: const Icon(Icons.add),
                  label: const Text('Makine ekle'),
                ),
                const SizedBox(height: 24),
                const Text('Duruş nedenleri', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const Text('"Çalışıyor" ve "Kapalı / vardiya dışı" sabittir. Zil simgesi olanlar alarm gönderir.',
                    style: TextStyle(color: kMuted, fontSize: 13)),
                const SizedBox(height: 8),
                for (var i = 0; i < reasons.length; i++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.white,
                    elevation: 0,
                    child: ListTile(
                      leading: Icon(reasons[i].alarm ? Icons.notifications_active : Icons.notifications_off_outlined,
                          color: reasons[i].alarm ? const Color(0xFFC92A2A) : kMuted),
                      title: Text(reasons[i].label),
                      subtitle: Text(reasons[i].alarm ? 'Alarm gönderir' : 'Alarm yok'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit), tooltip: 'Düzenle', onPressed: () => _reasonDialog(context, reasons, i)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFC92A2A)),
                          tooltip: 'Sil',
                          onPressed: () async {
                            if (!await confirm(context, 'Neden silinsin mi?', '"${reasons[i].label}" listeden kalkar. Geçmiş kayıtlar raporda kalır.', 'Sil')) return;
                            final nl = List<MReason>.from(reasons)..removeAt(i);
                            try {
                              await MachineOps.saveReasons(nl);
                            } catch (e) {
                              toast('Silinemedi: $e');
                            }
                          },
                        ),
                      ]),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _reasonDialog(context, reasons, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Duruş nedeni ekle'),
                ),
              ]);
            },
          );
        },
      ),
    );
  }
}
