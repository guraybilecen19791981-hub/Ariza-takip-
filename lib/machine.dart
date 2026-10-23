part of 'main.dart';

// ---------------------------------------------------------------------------
// Makine takip (hat makineleri: durum, ürün, personel, üretim, vardiya raporu)
// ---------------------------------------------------------------------------

const String kRunKey = 'calisiyor';
const String kOffKey = 'kapali';
const Map<String, String> kMUnits = {'adet': 'Adet', 'kg': 'Kg'};

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

int _hm(String s) {
  final p = s.split(':');
  final h = int.tryParse(p[0].trim()) ?? 0;
  final m = p.length > 1 ? (int.tryParse(p[1].trim()) ?? 0) : 0;
  return h.clamp(0, 23).toInt() * 60 + m.clamp(0, 59).toInt();
}

String _hmText(int minutes) => '${two(minutes ~/ 60)}:${two(minutes % 60)}';

class MShift {
  final String name;
  final String start;
  final String end;
  const MShift(this.name, this.start, this.end);

  factory MShift.fromMap(dynamic m) {
    final x = (m is Map) ? m : <String, dynamic>{};
    return MShift((x['name'] ?? '').toString(), (x['start'] ?? '08:00').toString(), (x['end'] ?? '08:00').toString());
  }

  Map<String, dynamic> toMap() => {'name': name, 'start': start, 'end': end};
  int get sMin => _hm(start);
  int get eMin => _hm(end);
  String get times => '$start–$end';
  String get label => name.isEmpty ? times : '$name ($times)';
}

const List<MShift> kDefaultShifts = [MShift('Tam gün', '08:00', '08:00')];

class TimeWin {
  final DateTime s;
  final DateTime e;
  final DateTime day;
  const TimeWin(this.s, this.e, this.day);
  bool contains(DateTime t) => !t.isBefore(s) && t.isBefore(e);
}

TimeWin _winFor(DateTime day, MShift sh) {
  final s = DateTime(day.year, day.month, day.day, sh.sMin ~/ 60, sh.sMin % 60);
  var e = DateTime(day.year, day.month, day.day, sh.eMin ~/ 60, sh.eMin % 60);
  if (!e.isAfter(s)) e = DateTime(e.year, e.month, e.day + 1, e.hour, e.minute);
  return TimeWin(s, e, day);
}

List<TimeWin> shiftWindows(DateTime fromDay, DateTime toDay, MShift sh) {
  final out = <TimeWin>[];
  var d = dayStart(fromDay);
  final last = dayStart(toDay);
  while (!d.isAfter(last)) {
    final w = _winFor(d, sh);
    if (w.s.isBefore(DateTime.now())) out.add(w);
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return out;
}

// Şu an içinde bulunulan vardiya penceresi
TimeWin currentWindow(MShift sh) {
  final now = DateTime.now();
  var d = dayStart(now);
  var w = _winFor(d, sh);
  if (now.isBefore(w.s)) {
    d = DateTime(d.year, d.month, d.day - 1);
    w = _winFor(d, sh);
  }
  return w;
}

Color mStateColor(String key) {
  if (key == kRunKey) return const Color(0xFF2B8A3E);
  if (key == kOffKey) return const Color(0xFF868E96);
  if (key == 'ariza') return const Color(0xFFC92A2A);
  if (key == 'mola') return const Color(0xFF1D4ED8);
  return const Color(0xFFD9480F);
}

int _int(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
double _dbl(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? 0);

String fmtQty(double v) {
  final r = (v * 100).round() / 100;
  var t = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2);
  if (t.contains('.')) t = t.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  final parts = t.split('.');
  final buf = StringBuffer();
  final ip = parts[0];
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) buf.write('.');
    buf.write(ip[i]);
  }
  return parts.length > 1 ? '$buf,${parts[1]}' : buf.toString();
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
  final String productCode;
  final String unit;
  final int workers;
  final int daily;
  final String jobId;
  final String orderNo;
  final String jobStatus; // '' | acik | gun_bitti
  final DateTime? jobStartedAt;
  final double jobAdet;
  final double jobKg;

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
    required this.productCode,
    required this.unit,
    required this.workers,
    required this.daily,
    this.jobId = '',
    this.orderNo = '',
    this.jobStatus = '',
    this.jobStartedAt,
    this.jobAdet = 0,
    this.jobKg = 0,
  });

  factory LineMachine.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    return LineMachine(
      id: d.id,
      name: (m['name'] ?? '').toString(),
      line: (m['line'] ?? '').toString(),
      order: _int(m['order']),
      state: (m['state'] ?? kOffKey).toString(),
      stateLabel: (m['stateLabel'] ?? 'Kapalı').toString(),
      since: tsToDate(m['since']),
      by: (m['by'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      openLogId: (m['openLogId'] ?? '').toString(),
      productCode: (m['productCode'] ?? '').toString(),
      unit: kMUnits.containsKey(m['unit']) ? m['unit'].toString() : 'adet',
      workers: _int(m['workers']),
      daily: _int(m['daily']),
      jobId: (m['jobId'] ?? '').toString(),
      orderNo: (m['orderNo'] ?? '').toString(),
      jobStatus: (m['jobStatus'] ?? '').toString(),
      jobStartedAt: tsToDate(m['jobStartedAt']),
      jobAdet: _dbl(m['jobAdet']),
      jobKg: _dbl(m['jobKg']),
    );
  }

  bool get hasJob => jobId.isNotEmpty;
  String get jobQtyText {
    final p = <String>[];
    if (jobAdet > 0) p.add('${fmtQty(jobAdet)} adet');
    if (jobKg > 0) p.add('${fmtQty(jobKg)} kg');
    return p.isEmpty ? '—' : p.join(' · ');
  }

  bool get running => state == kRunKey;
  bool get off => state == kOffKey;
  int get people => workers + daily;
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
  final String productCode;
  final int workers;
  final int daily;
  final String jobId;
  final String orderNo;

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
    this.productCode = '',
    this.workers = 0,
    this.daily = 0,
    this.jobId = '',
    this.orderNo = '',
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
      productCode: (m['productCode'] ?? '').toString(),
      workers: _int(m['workers']),
      daily: _int(m['daily']),
      jobId: (m['jobId'] ?? '').toString(),
      orderNo: (m['orderNo'] ?? '').toString(),
    );
  }

  int secondsIn(DateTime from, DateTime to, DateTime now) {
    final s = start;
    if (s == null) return 0;
    final e0 = end ?? now;
    final e = e0.isAfter(now) ? now : e0;
    final a = s.isAfter(from) ? s : from;
    final b = e.isBefore(to) ? e : to;
    final d = b.difference(a).inSeconds;
    return d > 0 ? d : 0;
  }
}

class MEntry {
  final String id;
  final String machineId;
  final String machineName;
  final String line;
  final String kind; // uretim | bilgi
  final double qty;
  final String unit;
  final String productCode;
  final int workers;
  final int daily;
  final DateTime? t;
  final String by;
  final String text;
  final String jobId;
  final String orderNo;

  MEntry({
    required this.id,
    required this.machineId,
    required this.machineName,
    required this.line,
    required this.kind,
    required this.qty,
    required this.unit,
    required this.productCode,
    required this.workers,
    required this.daily,
    required this.t,
    required this.by,
    required this.text,
    this.jobId = '',
    this.orderNo = '',
  });

  factory MEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    return MEntry(
      id: d.id,
      machineId: (m['machineId'] ?? '').toString(),
      machineName: (m['machineName'] ?? '').toString(),
      line: (m['line'] ?? '').toString(),
      kind: (m['kind'] ?? 'uretim').toString(),
      qty: _dbl(m['qty']),
      unit: (m['unit'] ?? 'adet').toString(),
      productCode: (m['productCode'] ?? '').toString(),
      workers: _int(m['workers']),
      daily: _int(m['daily']),
      t: tsToDate(m['t']),
      by: (m['by'] ?? '').toString(),
      text: (m['text'] ?? '').toString(),
      jobId: (m['jobId'] ?? '').toString(),
      orderNo: (m['orderNo'] ?? '').toString(),
    );
  }

  bool get isProd => kind == 'uretim';
  String get kindLabel => const {
        'uretim': 'Üretim girişi',
        'bilgi': 'Kişi / bilgi güncelleme',
        'is_basla': 'Sipariş başladı',
        'gun_bitti': 'Gün bitti',
        'gun_basla': 'Güne başlandı',
        'is_bitti': 'Sipariş bitti',
      }[kind] ??
      kind;
}

// Makine üzerindeki sipariş / iş (arşiv kaydı)
class MJob {
  final String id;
  final String machineId;
  final String machineName;
  final String line;
  final String orderNo;
  final String productCode;
  final String unit;
  final String status; // acik | gun_bitti | bitti
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String by;
  final String finishNote;
  final double qtyAdet;
  final double qtyKg;
  final int workers;
  final int daily;
  final int runSec;
  final Map<String, int> stops;
  final int dayCount;

  MJob({
    required this.id,
    required this.machineId,
    required this.machineName,
    required this.line,
    required this.orderNo,
    required this.productCode,
    required this.unit,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.by,
    required this.finishNote,
    required this.qtyAdet,
    required this.qtyKg,
    required this.workers,
    required this.daily,
    required this.runSec,
    required this.stops,
    required this.dayCount,
  });

  factory MJob.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final st = <String, int>{};
    final raw = m['stops'];
    if (raw is Map) raw.forEach((k, v) => st[k.toString()] = _int(v));
    return MJob(
      id: d.id,
      machineId: (m['machineId'] ?? '').toString(),
      machineName: (m['machineName'] ?? '').toString(),
      line: (m['line'] ?? '').toString(),
      orderNo: (m['orderNo'] ?? '').toString(),
      productCode: (m['productCode'] ?? '').toString(),
      unit: (m['unit'] ?? 'adet').toString(),
      status: (m['status'] ?? 'acik').toString(),
      startedAt: tsToDate(m['startedAt']),
      finishedAt: tsToDate(m['finishedAt']),
      by: (m['by'] ?? '').toString(),
      finishNote: (m['finishNote'] ?? '').toString(),
      qtyAdet: _dbl(m['qtyAdet']),
      qtyKg: _dbl(m['qtyKg']),
      workers: _int(m['workers']),
      daily: _int(m['daily']),
      runSec: _int(m['runSec']),
      stops: st,
      dayCount: _int(m['dayCount']),
    );
  }

  bool get finished => status == 'bitti';
  int get stopSec => stops.values.fold(0, (a, b) => a + b);
  double get efficiency => runSec + stopSec == 0 ? 0 : runSec * 100 / (runSec + stopSec);
  String get statusLabel => status == 'bitti' ? 'Bitti' : (status == 'gun_bitti' ? 'Gün bitti' : 'Devam ediyor');
  String get qtyText {
    final p = <String>[];
    if (qtyAdet > 0) p.add('${fmtQty(qtyAdet)} adet');
    if (qtyKg > 0) p.add('${fmtQty(qtyKg)} kg');
    return p.isEmpty ? '—' : p.join(' · ');
  }
}

// Bir işin çalışma / duruş özetini durum kayıtlarından hesaplar
Map<String, dynamic> jobSummaryFromLogs(List<MLog> logs, DateTime now) {
  int run = 0;
  final stops = <String, int>{};
  for (final l in logs) {
    if (l.state == kOffKey || l.start == null) continue;
    final e = l.end ?? now;
    final sec = e.difference(l.start!).inSeconds;
    if (sec <= 0) continue;
    if (l.state == kRunKey) {
      run += sec;
    } else {
      final k = l.label.isEmpty ? l.state : l.label;
      stops[k] = (stops[k] ?? 0) + sec;
    }
  }
  return {'runSec': run, 'stops': stops};
}

class MStat {
  final String id;
  final String name;
  final String line;
  int run = 0;
  final Map<String, int> stops = {};
  double qtyAdet = 0;
  double qtyKg = 0;
  final Set<String> products = {};
  MStat(this.id, this.name, this.line);

  int get stopTotal => stops.values.fold(0, (a, b) => a + b);
  int get tracked => run + stopTotal;
  double get efficiency => tracked == 0 ? 0 : run * 100 / tracked;
  String get qtyText {
    final p = <String>[];
    if (qtyAdet > 0) p.add('${fmtQty(qtyAdet)} adet');
    if (qtyKg > 0) p.add('${fmtQty(qtyKg)} kg');
    return p.isEmpty ? '—' : p.join(' · ');
  }
}

List<MLog> _withOpenLogs(List<LineMachine> machines, List<MLog> logs) {
  final all = List<MLog>.from(logs);
  final ids = logs.map((l) => l.id).toSet();
  for (final m in machines) {
    if (m.openLogId.isNotEmpty && !ids.contains(m.openLogId) && m.since != null) {
      all.add(MLog(
          id: m.openLogId,
          machineId: m.id,
          machineName: m.name,
          line: m.line,
          state: m.state,
          label: m.stateLabel,
          start: m.since,
          end: null,
          by: m.by,
          note: m.note,
          productCode: m.productCode,
          workers: m.workers,
          daily: m.daily,
          jobId: m.jobId,
          orderNo: m.orderNo));
    }
  }
  return all;
}

Map<String, MStat> computeMStats(List<LineMachine> machines, List<MLog> logs, List<MEntry> entries, List<TimeWin> wins) {
  final now = DateTime.now();
  final out = <String, MStat>{};
  for (final m in machines) {
    out[m.id] = MStat(m.id, m.name, m.line);
  }
  for (final l in _withOpenLogs(machines, logs)) {
    if (l.state == kOffKey) continue; // kapalı / vardiya dışı raporlanmaz
    var sec = 0;
    for (final w in wins) {
      sec += l.secondsIn(w.s, w.e, now);
    }
    if (sec <= 0) continue;
    final st = out.putIfAbsent(l.machineId, () => MStat(l.machineId, l.machineName, l.line));
    if (l.state == kRunKey) {
      st.run += sec;
    } else {
      final k = l.label.isEmpty ? l.state : l.label;
      st.stops[k] = (st.stops[k] ?? 0) + sec;
    }
    if (l.productCode.isNotEmpty) st.products.add(l.productCode);
  }
  for (final e in entries) {
    final t = e.t;
    if (t == null || !e.isProd || !wins.any((w) => w.contains(t))) continue;
    final st = out.putIfAbsent(e.machineId, () => MStat(e.machineId, e.machineName, e.line));
    if (e.unit == 'kg') {
      st.qtyKg += e.qty;
    } else {
      st.qtyAdet += e.qty;
    }
    if (e.productCode.isNotEmpty) st.products.add(e.productCode);
  }
  return out;
}

String fmtSec(int s) => fmtMin((s / 60).round());

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

bool canMachineEnter(AppUser? me) => me != null && me.can('hat', 'gir');
bool canMachineManage(AppUser? me) => me != null && (me.isAdmin || me.can('hat', 'yonet'));

// Kullanıcının görebileceği hatlar: null = tüm hatlar
Set<String>? visibleLines(AppUser? me) {
  if (me == null) return <String>{};
  if (me.isAdmin || me.can('hat', 'yonet') || me.lines.isEmpty) return null;
  return me.lines.toSet();
}

bool lineVisible(AppUser? me, String line) {
  final v = visibleLines(me);
  return v == null || v.contains(line);
}

class MachineOps {
  static CollectionReference<Map<String, dynamic>> get col => db.collection('lineMachines');
  static CollectionReference<Map<String, dynamic>> get logs => db.collection('machineLogs');
  static CollectionReference<Map<String, dynamic>> get entries => db.collection('machineEntries');
  static DocumentReference<Map<String, dynamic>> get cfg => db.collection('config').doc('machineReasons');
  static DocumentReference<Map<String, dynamic>> get shiftCfg => db.collection('config').doc('machineShifts');

  static Stream<List<MReason>> reasonsStream() => cfg.snapshots().map((s) {
        final raw = s.data()?['items'];
        if (raw is List && raw.isNotEmpty) return raw.map((e) => MReason.fromMap(e)).where((r) => r.key.isNotEmpty).toList();
        return List<MReason>.from(kDefaultMReasons);
      });

  static Future<void> saveReasons(List<MReason> list) => cfg.set({'items': list.map((r) => r.toMap()).toList()});

  static Stream<List<MShift>> shiftsStream() => shiftCfg.snapshots().map((s) {
        final raw = s.data()?['items'];
        if (raw is List && raw.isNotEmpty) return raw.map((e) => MShift.fromMap(e)).toList();
        return List<MShift>.from(kDefaultShifts);
      });

  static Future<void> saveShifts(List<MShift> list) => shiftCfg.set({'items': list.map((r) => r.toMap()).toList()});

  static List<LineMachine> _sorted(Iterable<LineMachine> l) {
    final x = l.toList();
    x.sort((a, b) {
      final c = a.line.toLowerCase().compareTo(b.line.toLowerCase());
      if (c != 0) return c;
      final o = a.order.compareTo(b.order);
      return o != 0 ? o : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return x;
  }

  static Stream<List<LineMachine>> machinesStream({bool all = false}) => col.snapshots().map((s) {
        final l = s.docs.map((d) => LineMachine.fromDoc(d));
        return _sorted(all ? l : l.where((m) => lineVisible(currentUser, m.line)));
      });

  static Stream<List<MLog>> logsSince(DateTime from) => logs
      .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .snapshots()
      .map((s) => s.docs.map((d) => MLog.fromDoc(d)).toList());

  static Stream<List<MEntry>> entriesSince(DateTime from) => entries
      .where('t', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .snapshots()
      .map((s) => s.docs.map((d) => MEntry.fromDoc(d)).toList());

  static Future<List<MLog>> logsBetween(DateTime from, DateTime to) async {
    final s = await logs
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from.subtract(const Duration(days: 7))))
        .where('start', isLessThan: Timestamp.fromDate(to))
        .get();
    return s.docs.map((d) => MLog.fromDoc(d)).toList();
  }

  static Future<List<MEntry>> entriesBetween(DateTime from, DateTime to) async {
    final s = await entries.where('t', isGreaterThanOrEqualTo: Timestamp.fromDate(from)).where('t', isLessThan: Timestamp.fromDate(to)).get();
    return s.docs.map((d) => MEntry.fromDoc(d)).toList();
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
        'productCode': '',
        'unit': 'adet',
        'workers': 0,
        'daily': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

  static Future<void> editMachine(LineMachine m, String name, String line, int order) =>
      col.doc(m.id).update({'name': name, 'line': line, 'order': order});

  static Future<void> deleteMachine(LineMachine m) => col.doc(m.id).delete();

  static CollectionReference<Map<String, dynamic>> get jobs => db.collection('machineJobs');

  static Map<String, dynamic> _logData(LineMachine m, String key, String label, String note, DateTime now, String jobId, String orderNo, String productCode, int workers, int daily) => {
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
        'productCode': productCode,
        'workers': workers,
        'daily': daily,
        'jobId': jobId,
        'orderNo': orderNo,
      };

  static Map<String, dynamic> _entryData(LineMachine m, String kind, DateTime now, {double qty = 0, String? unit, String text = '', String? jobId, String? orderNo, String? productCode, int? workers, int? daily}) => {
        'machineId': m.id,
        'machineName': m.name,
        'line': m.line,
        'kind': kind,
        'qty': qty,
        'unit': unit ?? m.unit,
        'productCode': productCode ?? m.productCode,
        'workers': workers ?? m.workers,
        'daily': daily ?? m.daily,
        'jobId': jobId ?? m.jobId,
        'orderNo': orderNo ?? m.orderNo,
        't': Timestamp.fromDate(now),
        'tMs': now.millisecondsSinceEpoch,
        'by': currentUser?.name ?? '',
        'byUid': currentUser?.uid ?? '',
        'text': text,
      };

  // Açık durum kaydını kapatır, yenisini açar; makine belgesine yazılacak alanları döndürür
  static Map<String, dynamic> _switchLog(WriteBatch batch, LineMachine m, DateTime now, String key, String label, String note,
      {required String jobId, required String orderNo, required String productCode, required int workers, required int daily}) {
    if (m.openLogId.isNotEmpty) {
      batch.update(logs.doc(m.openLogId), {'end': Timestamp.fromDate(now), 'endMs': now.millisecondsSinceEpoch});
    }
    final lg = logs.doc();
    batch.set(lg, _logData(m, key, label, note, now, jobId, orderNo, productCode, workers, daily));
    return {
      'state': key,
      'stateLabel': label,
      'since': Timestamp.fromDate(now),
      'by': currentUser?.name ?? '',
      'note': note,
      'openLogId': lg.id,
    };
  }

  static Future<void> setState(LineMachine m, String key, String label, bool alarm, String note) async {
    if (m.state == key && m.note == note) return;
    final now = DateTime.now();
    final batch = db.batch();
    final upd = _switchLog(batch, m, now, key, label, note,
        jobId: m.jobId, orderNo: m.orderNo, productCode: m.productCode, workers: m.workers, daily: m.daily);
    // Gün bitmiş bir işte makine yeniden çalıştırılırsa gün otomatik başlar
    if (m.jobStatus == 'gun_bitti' && key != kOffKey && m.hasJob) {
      upd['jobStatus'] = 'acik';
      batch.update(jobs.doc(m.jobId), {'status': 'acik', 'dayCount': FieldValue.increment(1)});
      batch.set(entries.doc(), _entryData(m, 'gun_basla', now, text: 'Güne başlandı (durum değişikliğiyle)'));
    }
    batch.update(col.doc(m.id), upd);
    if (alarm) {
      batch.set(db.collection('machineAlerts').doc(), {
        'machineId': m.id,
        'machineName': m.name,
        'line': m.line,
        'label': label,
        'note': note,
        'orderNo': m.orderNo,
        'by': currentUser?.name ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // Yeni sipariş / iş başlat (makine çalışıyor durumuna geçer)
  static Future<void> startJob(LineMachine m, String orderNo, String productCode, String unit, int workers, int daily) async {
    final now = DateTime.now();
    final batch = db.batch();
    final job = jobs.doc();
    batch.set(job, {
      'machineId': m.id,
      'machineName': m.name,
      'line': m.line,
      'orderNo': orderNo,
      'productCode': productCode,
      'unit': unit,
      'status': 'acik',
      'startedAt': Timestamp.fromDate(now),
      'finishedAt': null,
      'by': currentUser?.name ?? '',
      'byUid': currentUser?.uid ?? '',
      'finishNote': '',
      'qtyAdet': 0,
      'qtyKg': 0,
      'workers': workers,
      'daily': daily,
      'runSec': 0,
      'stops': <String, int>{},
      'dayCount': 1,
    });
    final upd = _switchLog(batch, m, now, kRunKey, 'Çalışıyor', '', jobId: job.id, orderNo: orderNo, productCode: productCode, workers: workers, daily: daily);
    upd.addAll({
      'jobId': job.id,
      'orderNo': orderNo,
      'productCode': productCode,
      'unit': unit,
      'workers': workers,
      'daily': daily,
      'jobStatus': 'acik',
      'jobStartedAt': Timestamp.fromDate(now),
      'jobAdet': 0,
      'jobKg': 0,
    });
    batch.update(col.doc(m.id), upd);
    batch.set(entries.doc(),
        _entryData(m, 'is_basla', now, jobId: job.id, orderNo: orderNo, productCode: productCode, unit: unit, workers: workers, daily: daily,
            text: 'Sipariş $orderNo · $productCode · $workers çalışan + $daily günlükçü'));
    await batch.commit();
  }

  static Future<Map<String, dynamic>> _summary(String jobId, DateTime now) async {
    final s = await logs.where('jobId', isEqualTo: jobId).get();
    return jobSummaryFromLogs(s.docs.map((d) => MLog.fromDoc(d)).toList(), now);
  }

  static Future<Map<String, dynamic>> liveSummary(String jobId) => _summary(jobId, DateTime.now());

  // Günü bitir: makine kapalıya alınır, sipariş açık kalır
  static Future<void> endDay(LineMachine m) async {
    if (!m.hasJob) return;
    final now = DateTime.now();
    final sum = await _summary(m.jobId, now);
    final batch = db.batch();
    final upd = _switchLog(batch, m, now, kOffKey, 'Kapalı', 'Gün bitti',
        jobId: m.jobId, orderNo: m.orderNo, productCode: m.productCode, workers: m.workers, daily: m.daily);
    upd['jobStatus'] = 'gun_bitti';
    batch.update(col.doc(m.id), upd);
    batch.update(jobs.doc(m.jobId), {'status': 'gun_bitti', 'dayEndedAt': Timestamp.fromDate(now), ...sum});
    batch.set(entries.doc(), _entryData(m, 'gun_bitti', now, text: 'Gün bitti · bu sipariş: ${m.jobQtyText}'));
    await batch.commit();
  }

  // Güne başla: kişi sayıları sorulur, makine çalışıyor olur
  static Future<void> startDay(LineMachine m, int workers, int daily) async {
    if (!m.hasJob) return;
    final now = DateTime.now();
    final batch = db.batch();
    final upd = _switchLog(batch, m, now, kRunKey, 'Çalışıyor', '',
        jobId: m.jobId, orderNo: m.orderNo, productCode: m.productCode, workers: workers, daily: daily);
    upd.addAll({'jobStatus': 'acik', 'workers': workers, 'daily': daily});
    batch.update(col.doc(m.id), upd);
    batch.update(jobs.doc(m.jobId), {'status': 'acik', 'workers': workers, 'daily': daily, 'dayCount': FieldValue.increment(1)});
    batch.set(entries.doc(), _entryData(m, 'gun_basla', now, workers: workers, daily: daily, text: 'Güne başlandı · $workers çalışan + $daily günlükçü'));
    await batch.commit();
  }

  // Siparişi bitir: iş arşive kapanır, makine kapalıya alınır
  static Future<void> finishJob(LineMachine m, String note) async {
    if (!m.hasJob) return;
    final now = DateTime.now();
    final sum = await _summary(m.jobId, now);
    final batch = db.batch();
    final upd = _switchLog(batch, m, now, kOffKey, 'Kapalı', 'Sipariş bitti', jobId: '', orderNo: '', productCode: '', workers: 0, daily: 0);
    upd.addAll({'jobId': '', 'orderNo': '', 'productCode': '', 'jobStatus': '', 'jobStartedAt': null, 'jobAdet': 0, 'jobKg': 0, 'workers': 0, 'daily': 0});
    batch.update(col.doc(m.id), upd);
    batch.update(jobs.doc(m.jobId), {'status': 'bitti', 'finishedAt': Timestamp.fromDate(now), 'finishNote': note, ...sum});
    batch.set(entries.doc(), _entryData(m, 'is_bitti', now, text: 'Sipariş bitti · ${m.jobQtyText}${note.isEmpty ? '' : ' · Not: $note'}'));
    await batch.commit();
  }

  // Sipariş no / ürün kodu / birim düzeltme
  static Future<void> editJob(LineMachine m, String orderNo, String productCode, String unit) async {
    if (!m.hasJob) return;
    final ch = <String>[];
    if (orderNo != m.orderNo) ch.add('Sipariş: ${m.orderNo} → $orderNo');
    if (productCode != m.productCode) ch.add('Ürün: ${m.productCode} → $productCode');
    if (unit != m.unit) ch.add('Birim: ${kMUnits[unit]}');
    if (ch.isEmpty) return;
    final now = DateTime.now();
    final batch = db.batch();
    batch.update(col.doc(m.id), {'orderNo': orderNo, 'productCode': productCode, 'unit': unit});
    batch.update(jobs.doc(m.jobId), {'orderNo': orderNo, 'productCode': productCode, 'unit': unit});
    if (m.openLogId.isNotEmpty) batch.update(logs.doc(m.openLogId), {'orderNo': orderNo, 'productCode': productCode});
    batch.set(entries.doc(), _entryData(m, 'bilgi', now, orderNo: orderNo, productCode: productCode, unit: unit, text: ch.join(' · ')));
    await batch.commit();
  }

  // Çalışan / günlükçü sayısı güncelleme
  static Future<void> setPeople(LineMachine m, int workers, int daily) async {
    if (workers == m.workers && daily == m.daily) return;
    final now = DateTime.now();
    final batch = db.batch();
    final upd = _switchLog(batch, m, now, m.state, m.stateLabel, m.note,
        jobId: m.jobId, orderNo: m.orderNo, productCode: m.productCode, workers: workers, daily: daily);
    upd.addAll({'workers': workers, 'daily': daily});
    upd.remove('since'); // durum süresi sıfırlanmasın
    upd.remove('by');
    batch.update(col.doc(m.id), upd);
    if (m.hasJob) batch.update(jobs.doc(m.jobId), {'workers': workers, 'daily': daily});
    batch.set(entries.doc(), _entryData(m, 'bilgi', now, workers: workers, daily: daily, text: 'Kişi: ${m.workers}+${m.daily} → $workers+$daily'));
    await batch.commit();
  }

  static Future<void> addProduction(LineMachine m, double qty, String unit, String note) async {
    final now = DateTime.now();
    final batch = db.batch();
    batch.set(entries.doc(), _entryData(m, 'uretim', now, qty: qty, unit: unit, text: note));
    final f = unit == 'kg' ? 'Kg' : 'Adet';
    batch.update(col.doc(m.id), {'job$f': FieldValue.increment(qty), if (unit != m.unit) 'unit': unit});
    if (m.hasJob) batch.update(jobs.doc(m.jobId), {'qty$f': FieldValue.increment(qty)});
    await batch.commit();
  }

  static Stream<List<MJob>> jobsStream() => jobs.orderBy('startedAt', descending: true).limit(500).snapshots().map((s) => s.docs.map((d) => MJob.fromDoc(d)).toList());

  static Future<List<MJob>> jobsActiveBetween(DateTime from, DateTime to) async {
    final s = await jobs.where('startedAt', isLessThan: Timestamp.fromDate(to)).orderBy('startedAt', descending: true).limit(500).get();
    return s.docs.map((d) => MJob.fromDoc(d)).where((j) => j.finishedAt == null || j.finishedAt!.isAfter(from)).toList();
  }

  static Future<void> deleteEntry(MEntry e) => entries.doc(e.id).delete();
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
            tooltip: 'Sipariş arşivi',
            icon: const Icon(Icons.inventory_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MachineJobsPage())),
          ),
          IconButton(
            tooltip: 'Rapor ve Excel',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MachineReportPage())),
          ),
          if (canMachineManage(me))
            IconButton(
              tooltip: 'Makineler, nedenler, vardiyalar',
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
  late final DateTime _from = dayStart(DateTime.now()).subtract(const Duration(days: 2));
  late final Stream<List<MLog>> _logs = MachineOps.logsSince(_from);
  late final Stream<List<MEntry>> _entries = MachineOps.entriesSince(_from);
  late final Stream<List<LineMachine>> _machines = MachineOps.machinesStream();
  late final Stream<List<MReason>> _reasons = MachineOps.reasonsStream();
  late final Stream<List<MShift>> _shifts = MachineOps.shiftsStream();
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
                    : 'Size atanmış hatta makine yok. Admin size hat atadığında makineler burada görünecek.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted, fontSize: 15),
              ),
            ),
          );
        }
        return StreamBuilder<List<MShift>>(
          stream: _shifts,
          builder: (context, ss) {
            final shift = (ss.data == null || ss.data!.isEmpty) ? kDefaultShifts.first : ss.data!.first;
            final win = currentWindow(shift);
            return StreamBuilder<List<MReason>>(
              stream: _reasons,
              builder: (context, rs) {
                final reasons = rs.data ?? kDefaultMReasons;
                return StreamBuilder<List<MEntry>>(
                  stream: _entries,
                  builder: (context, es) {
                    return StreamBuilder<List<MLog>>(
                      stream: _logs,
                      builder: (context, ls) {
                        final stats = computeMStats(machines, ls.data ?? const [], es.data ?? const [], [win]);
                        final running = machines.where((m) => m.running).length;
                        final off = machines.where((m) => m.off).length;
                        String? lastLine;
                        final children = <Widget>[
                          Row(children: [
                            Expanded(child: _kpi('Çalışan', '$running', const Color(0xFF2B8A3E))),
                            const SizedBox(width: 8),
                            Expanded(child: _kpi('Duruşta', '${machines.length - running - off}', const Color(0xFFC92A2A))),
                            const SizedBox(width: 8),
                            Expanded(child: _kpi('Kapalı', '$off', kMuted)),
                          ]),
                          const SizedBox(height: 6),
                          Text('Vardiya: ${shift.label} · ${fmtDT(win.s)} başladı', style: const TextStyle(color: kMuted, fontSize: 12)),
                          const SizedBox(height: 8),
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
      color: m.off ? const Color(0xFFF8F9FA) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enter ? () => showMachineSheet(context, m, reasons) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(m.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              if (!m.off && m.since != null) Elapsed(start: m.since!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c)),
            ]),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(999)),
              child: Text(m.stateLabel.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            if (m.note.isNotEmpty && !m.off) Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.note, style: const TextStyle(fontStyle: FontStyle.italic))),
            const SizedBox(height: 6),
            if (m.hasJob) ...[
              Text('Sipariş ${m.orderNo} · ${m.productCode}${m.jobStatus == 'gun_bitti' ? ' · gün bitti' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${m.workers} çalışan + ${m.daily} günlükçü · bu sipariş: ${m.jobQtyText}', style: const TextStyle(fontSize: 13)),
            ] else
              const Text('Aktif sipariş yok', style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
            if (!m.off || (st?.tracked ?? 0) > 0)
              Text(
                'Bu vardiya: verim %${(st?.efficiency ?? 0).toStringAsFixed(0)} · çalışma ${fmtSec(st?.run ?? 0)} · duruş ${fmtSec(st?.stopTotal ?? 0)} · üretim ${st?.qtyText ?? '—'}',
                style: const TextStyle(color: kMuted, fontSize: 13),
              ),
            Text(m.off ? 'Kapalı · ${fmtDT(m.since)}' : '${m.by.isEmpty ? '' : '${m.by} · '}${fmtDT(m.since)}${enter ? ' · dokunun' : ''}',
                style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

Widget _actBtn(BuildContext c, String key, String label, IconData icon, Color color) => FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(48)),
      onPressed: () => Navigator.pop(c, key),
      icon: Icon(icon, size: 20),
      label: Text(label),
    );

Future<void> showMachineSheet(BuildContext context, LineMachine m, List<MReason> reasons) async {
  final note = TextEditingController();
  final picked = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(m.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(
              m.hasJob
                  ? 'Sipariş ${m.orderNo} · ${m.productCode} · ${m.workers}+${m.daily} kişi · ${m.jobQtyText}'
                  : 'Şu an: ${m.stateLabel} · aktif sipariş yok',
              style: const TextStyle(color: kMuted),
            ),
            const SizedBox(height: 12),
            const Text('Sipariş', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (!m.hasJob) _actBtn(c, 'yeni', 'Yeni sipariş başlat', Icons.play_arrow, kGreen),
            if (m.hasJob && m.jobStatus != 'gun_bitti') ...[
              Row(children: [
                Expanded(child: _actBtn(c, 'uretim', 'Üretim gir', Icons.add, kOrange)),
                const SizedBox(width: 8),
                Expanded(child: _actBtn(c, 'kisi', 'Kişi sayısı', Icons.groups, kDark)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _actBtn(c, 'gunbitir', 'Günü bitir', Icons.nightlight_round, const Color(0xFF495057))),
                const SizedBox(width: 8),
                Expanded(child: _actBtn(c, 'bitir', 'Siparişi bitir', Icons.flag, const Color(0xFFC92A2A))),
              ]),
            ],
            if (m.hasJob && m.jobStatus == 'gun_bitti')
              Row(children: [
                Expanded(child: _actBtn(c, 'gunbasla', 'Güne başla', Icons.wb_sunny, kGreen)),
                const SizedBox(width: 8),
                Expanded(child: _actBtn(c, 'bitir', 'Siparişi bitir', Icons.flag, const Color(0xFFC92A2A))),
              ]),
            if (m.hasJob)
              TextButton.icon(onPressed: () => Navigator.pop(c, 'duzenle'), icon: const Icon(Icons.edit, size: 18), label: const Text('Sipariş no / ürün kodu düzelt')),
            const SizedBox(height: 10),
            const Text('Durum', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _stateBtn(c, const MReason(kRunKey, 'Çalışıyor', false), m.state),
            const SizedBox(height: 8),
            for (final r in reasons) ...[
              _stateBtn(c, r, m.state),
              const SizedBox(height: 8),
            ],
            _stateBtn(c, const MReason(kOffKey, 'Kapalı / vardiya dışı', false), m.state),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Durum notu (isteğe bağlı)', isDense: true)),
          ]),
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  Future<void> run(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (ok.isNotEmpty) toast(ok);
    } catch (e) {
      toast('Kaydedilemedi: $e');
    }
  }

  switch (picked) {
    case 'yeni':
      return askStartJob(context, m);
    case 'uretim':
      return askProduction(context, m);
    case 'kisi':
      {
        final v = await askPeople(context, m, 'Kişi sayısını güncelle');
        if (v != null) await run(() => MachineOps.setPeople(m, v[0], v[1]), 'Kişi sayısı güncellendi');
        return;
      }
    case 'gunbitir':
      {
        if (await confirm(context, 'Gün bitirilsin mi?', '${m.name} kapalıya alınır. Sipariş ${m.orderNo} açık kalır; yarın "Güne başla" ile devam edilir.', 'Günü bitir')) {
          await run(() => MachineOps.endDay(m), 'Gün bitti');
        }
        return;
      }
    case 'gunbasla':
      {
        final v = await askPeople(context, m, 'Bugün kaç kişi çalışıyor?');
        if (v != null) await run(() => MachineOps.startDay(m, v[0], v[1]), 'Güne başlandı');
        return;
      }
    case 'bitir':
      {
        if (!context.mounted) return;
        final fn = await askText(context, 'Sipariş ${m.orderNo} bitirilsin mi?', 'Bitiş notu (isteğe bağlı)', ok: 'Siparişi bitir');
        if (fn != null) await run(() => MachineOps.finishJob(m, fn), 'Sipariş bitti, arşive kaydedildi');
        return;
      }
    case 'duzenle':
      return askEditJob(context, m);
  }
  if (picked is MReason) {
    if (!m.hasJob && picked.key == kRunKey) toast('Not: aktif sipariş yok. Üretim takibi için "Yeni sipariş başlat" kullanın.');
    await run(() => MachineOps.setState(m, picked.key, picked.label, picked.alarm, note.text.trim()),
        '${m.name}: ${picked.label}${picked.alarm ? ' · alarm gönderildi' : ''}');
  }
}

Widget _stateBtn(BuildContext c, MReason r, String current) {
  final col = mStateColor(r.key);
  final on = r.key == current;
  return FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: on ? col : col.withOpacity(0.12),
      foregroundColor: on ? Colors.white : col,
      minimumSize: const Size.fromHeight(50),
      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
    onPressed: () => Navigator.pop(c, r),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(r.label),
      if (r.alarm) ...[const SizedBox(width: 8), const Icon(Icons.notifications_active, size: 18)],
    ]),
  );
}

Future<List<int>?> askPeople(BuildContext context, LineMachine m, String title) async {
  final w = TextEditingController(text: '${m.workers}');
  final dl = TextEditingController(text: '${m.daily}');
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Row(children: [
        Expanded(child: TextField(controller: w, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Çalışan'))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: dl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Günlükçü'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
      ],
    ),
  );
  if (ok != true) return null;
  final wi = int.tryParse(w.text.trim().isEmpty ? '0' : w.text.trim());
  final di = int.tryParse(dl.text.trim().isEmpty ? '0' : dl.text.trim());
  if (wi == null || di == null) {
    toast('Kişi sayılarını rakamla girin.');
    return null;
  }
  return [wi, di];
}

Future<void> askStartJob(BuildContext context, LineMachine m) async {
  final order = TextEditingController();
  final code = TextEditingController();
  final w = TextEditingController(text: m.workers > 0 ? '${m.workers}' : '');
  final dl = TextEditingController(text: '${m.daily}');
  String unit = m.unit;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('Yeni sipariş · ${m.name}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: order, autofocus: true, decoration: const InputDecoration(labelText: 'Sipariş numarası')),
            const SizedBox(height: 10),
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Ürün kodu')),
            const SizedBox(height: 10),
            const Text('Üretim birimi', style: TextStyle(fontSize: 13, color: kMuted)),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: [for (final e in kMUnits.entries) ButtonSegment<String>(value: e.key, label: Text(e.value))],
              selected: {unit},
              onSelectionChanged: (v) => setS(() => unit = v.first),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: w, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Çalışan'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: dl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Günlükçü'))),
            ]),
            const SizedBox(height: 6),
            const Text('Başlatınca makine "Çalışıyor" durumuna geçer.', style: TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Başlat')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final wi = int.tryParse(w.text.trim().isEmpty ? '0' : w.text.trim());
  final di = int.tryParse(dl.text.trim().isEmpty ? '0' : dl.text.trim());
  if (order.text.trim().isEmpty || code.text.trim().isEmpty) {
    toast('Sipariş numarası ve ürün kodu gerekli.');
    return;
  }
  if (wi == null || di == null) {
    toast('Kişi sayılarını rakamla girin.');
    return;
  }
  try {
    await MachineOps.startJob(m, order.text.trim(), code.text.trim(), unit, wi, di);
    toast('Sipariş ${order.text.trim()} başladı');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> askEditJob(BuildContext context, LineMachine m) async {
  final order = TextEditingController(text: m.orderNo);
  final code = TextEditingController(text: m.productCode);
  String unit = m.unit;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: const Text('Siparişi düzelt'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: order, decoration: const InputDecoration(labelText: 'Sipariş numarası')),
          const SizedBox(height: 10),
          TextField(controller: code, decoration: const InputDecoration(labelText: 'Ürün kodu')),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: [for (final e in kMUnits.entries) ButtonSegment<String>(value: e.key, label: Text(e.value))],
            selected: {unit},
            onSelectionChanged: (v) => setS(() => unit = v.first),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
        ],
      ),
    ),
  );
  if (ok != true || order.text.trim().isEmpty || code.text.trim().isEmpty) return;
  try {
    await MachineOps.editJob(m, order.text.trim(), code.text.trim(), unit);
    toast('Kaydedildi');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> askProduction(BuildContext context, LineMachine m) async {
  final qty = TextEditingController();
  final note = TextEditingController();
  String unit = m.unit;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('Üretim gir · ${m.name}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sipariş ${m.orderNo} · ${m.productCode} · şu ana kadar: ${m.jobQtyText}', style: const TextStyle(color: kMuted)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [for (final e in kMUnits.entries) ButtonSegment<String>(value: e.key, label: Text(e.value))],
              selected: {unit},
              onSelectionChanged: (v) => setS(() => unit = v.first),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Eklenen miktar (${kMUnits[unit]})'),
            ),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Ekle')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final v = double.tryParse(qty.text.trim().replaceAll(',', '.'));
  if (v == null || v <= 0) {
    toast('Miktarı rakamla girin.');
    return;
  }
  try {
    await MachineOps.addProduction(m, v, unit, note.text.trim());
    toast('${m.name}: +${fmtQty(v)} ${unit == 'kg' ? 'kg' : 'adet'}');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
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
  List<MShift> _shifts = List<MShift>.from(kDefaultShifts);
  int _shiftIdx = 0; // _shifts.length = özel
  MShift _custom = const MShift('Özel', '08:00', '16:00');
  String _line = '';
  List<MLog>? _logs;
  List<MEntry> _entries = [];
  List<LineMachine> _machines = [];
  bool _loading = false;

  MShift get _shift => _shiftIdx < _shifts.length ? _shifts[_shiftIdx] : _custom;
  List<TimeWin> get _wins => shiftWindows(_from, _to, _shift);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final s = await MachineOps.shiftCfg.get();
      final raw = s.data()?['items'];
      if (raw is List && raw.isNotEmpty) _shifts = raw.map((e) => MShift.fromMap(e)).toList();
    } catch (_) {}
    await _load();
  }

  List<LineMachine> get _visibleMachines => _machines.where((m) => _line.isEmpty || m.line == _line).toList();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ms = await MachineOps.col.get();
      _machines = MachineOps._sorted(ms.docs.map((d) => LineMachine.fromDoc(d)).where((m) => lineVisible(currentUser, m.line)));
      final w = _wins;
      if (w.isEmpty) {
        _logs = [];
        _entries = [];
      } else {
        final end = w.last.e.isAfter(DateTime.now()) ? DateTime.now().add(const Duration(minutes: 1)) : w.last.e;
        _logs = await MachineOps.logsBetween(w.first.s, end);
        _entries = await MachineOps.entriesBetween(w.first.s, end);
      }
    } catch (e) {
      toast('Rapor yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MLog> get _fLogs {
    final ids = _visibleMachines.map((m) => m.id).toSet();
    return (_logs ?? const <MLog>[]).where((l) => ids.contains(l.machineId)).toList();
  }

  List<MEntry> get _fEntries {
    final ids = _visibleMachines.map((m) => m.id).toSet();
    return _entries.where((e) => ids.contains(e.machineId)).toList();
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

  Future<void> _pickTime(bool start) async {
    final cur = start ? _custom.sMin : _custom.eMin;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60), helpText: start ? 'Vardiya başlangıcı' : 'Vardiya bitişi');
    if (t == null) return;
    final v = _hmText(t.hour * 60 + t.minute);
    setState(() => _custom = start ? MShift('Özel', v, _custom.end) : MShift('Özel', _custom.start, v));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final wins = _wins;
    final stats = _logs == null ? <String, MStat>{} : computeMStats(_visibleMachines, _fLogs, _fEntries, wins);
    final list = stats.values.where((s) => s.tracked > 0 || s.qtyAdet > 0 || s.qtyKg > 0).toList()..sort((a, b) => '${a.line}${a.name}'.compareTo('${b.line}${b.name}'));
    final lines = _machines.map((m) => m.line).toSet().toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Makine raporu'), actions: [
        IconButton(
          tooltip: "Excel'e aktar",
          icon: const Icon(Icons.download),
          onPressed: _logs == null ? null : () => exportMachineExcel(_visibleMachines, _fLogs, _fEntries, wins, _shift),
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
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: _shiftIdx,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Vardiya / saat aralığı', isDense: true),
          items: [
            for (var i = 0; i < _shifts.length; i++) DropdownMenuItem<int>(value: i, child: Text(_shifts[i].label)),
            DropdownMenuItem<int>(value: _shifts.length, child: const Text('Özel saat aralığı')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _shiftIdx = v);
            _load();
          },
        ),
        if (_shiftIdx >= _shifts.length) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _pickTime(true), icon: const Icon(Icons.schedule, size: 18), label: Text('Başlangıç ${_custom.start}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _pickTime(false), icon: const Icon(Icons.schedule, size: 18), label: Text('Bitiş ${_custom.end}'))),
          ]),
        ],
        if (lines.length > 1) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _line,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Hat', isDense: true),
            items: [
              const DropdownMenuItem<String>(value: '', child: Text('Tüm hatlar')),
              for (final l in lines) DropdownMenuItem<String>(value: l, child: Text(l.isEmpty ? 'Hat belirtilmemiş' : l)),
            ],
            onChanged: (v) => setState(() => _line = v ?? ''),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Her gün için ${_shift.times} aralığı raporlanır (${wins.length} vardiya). Verimlilik = çalışma ÷ (çalışma + duruş). Kapalı / vardiya dışı süreler raporlanmaz.',
          style: const TextStyle(color: kMuted, fontSize: 12),
        ),
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
                Text('Çalışma ${fmtSec(s.run)} · Duruş ${fmtSec(s.stopTotal)} · Üretim ${s.qtyText}', style: const TextStyle(color: kMuted, fontSize: 13)),
                if (s.products.isNotEmpty) Text('Ürünler: ${s.products.join(', ')}', style: const TextStyle(color: kMuted, fontSize: 13)),
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

Future<void> exportMachineExcel(List<LineMachine> machines, List<MLog> logs, List<MEntry> entries, List<TimeWin> wins, MShift shift) async {
  try {
    if (wins.isEmpty) {
      toast('Seçilen aralıkta vardiya yok.');
      return;
    }
    toast('Makine raporu hazırlanıyor…');
    final now = DateTime.now();
    final stats = computeMStats(machines, logs, entries, wins);
    final list = stats.values.where((s) => s.tracked > 0 || s.qtyAdet > 0 || s.qtyKg > 0).toList()..sort((a, b) => '${a.line}${a.name}'.compareTo('${b.line}${b.name}'));
    final labels = <String>{};
    for (final s in list) {
      labels.addAll(s.stops.keys);
    }
    final lab = labels.toList()..sort();
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Özet');
    final xl.Sheet sh = excel['Özet'];
    final xl.Sheet byShift = excel['Vardiya bazlı'];
    final xl.Sheet prod = excel['Üretim ve personel'];
    final xl.Sheet det = excel['Durum hareketleri'];
    xl.CellValue t(String v) => xl.TextCellValue(v);
    xl.CellValue n(int v) => xl.IntCellValue(v);
    xl.CellValue dbl(double v) => xl.DoubleCellValue((v * 10).round() / 10);
    int mins(int s) => (s / 60).round();

    sh.appendRow(<xl.CellValue?>[t('Makine raporu'), t('${fmtDay(wins.first.day)} – ${fmtDay(wins.last.day)}'), t('Vardiya: ${shift.label}')]);
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[
      t('Makine'), t('Hat'), t('İzlenen süre (dk)'), t('Çalışma (dk)'), t('Toplam duruş (dk)'), t('Verimlilik %'),
      for (final l in lab) t('$l (dk)'),
      t('Üretim (adet)'), t('Üretim (kg)'), t('Ürünler'),
    ]);
    for (final s in list) {
      sh.appendRow(<xl.CellValue?>[
        t(s.name), t(s.line), n(mins(s.tracked)), n(mins(s.run)), n(mins(s.stopTotal)), dbl(s.efficiency),
        for (final l in lab) n(mins(s.stops[l] ?? 0)),
        dbl(s.qtyAdet), dbl(s.qtyKg), t(s.products.join(', ')),
      ]);
    }
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[t('Verimlilik = çalışma ÷ (çalışma + duruş). Kapalı / vardiya dışı süreler raporlanmaz.')]);

    byShift.appendRow(<xl.CellValue?>[
      t('Tarih'), t('Vardiya'), t('Makine'), t('Hat'), t('Çalışma (dk)'), t('Duruş (dk)'), t('Verimlilik %'), t('Üretim (adet)'), t('Üretim (kg)'), t('En çok duruş nedeni'),
    ]);
    for (final w in wins) {
      final st = computeMStats(machines, logs, entries, [w]);
      for (final s in st.values.toList()..sort((a, b) => '${a.line}${a.name}'.compareTo('${b.line}${b.name}'))) {
        if (s.tracked == 0 && s.qtyAdet == 0 && s.qtyKg == 0) continue;
        final top = s.stops.entries.isEmpty ? null : (s.stops.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
        byShift.appendRow(<xl.CellValue?>[
          t(fmtDay(w.day)), t('${_hmText(w.s.hour * 60 + w.s.minute)}–${_hmText(w.e.hour * 60 + w.e.minute)}'), t(s.name), t(s.line),
          n(mins(s.run)), n(mins(s.stopTotal)), dbl(s.efficiency), dbl(s.qtyAdet), dbl(s.qtyKg),
          t(top == null ? '' : '${top.key} (${mins(top.value)} dk)'),
        ]);
      }
    }

    prod.appendRow(<xl.CellValue?>[
      t('Makine'), t('Hat'), t('Tarih saat'), t('İşlem'), t('Sipariş no'), t('Ürün kodu'), t('Miktar'), t('Birim'), t('Çalışan'), t('Günlükçü'), t('Toplam kişi'), t('Giren'), t('Not / değişiklik'),
    ]);
    final es = entries.where((e) => e.t != null && wins.any((w) => w.contains(e.t!))).toList()
      ..sort((a, b) {
        final c = '${a.line}${a.machineName}'.compareTo('${b.line}${b.machineName}');
        return c != 0 ? c : a.t!.compareTo(b.t!);
      });
    for (final e in es) {
      prod.appendRow(<xl.CellValue?>[
        t(e.machineName), t(e.line), t(fmtFull(e.t)), t(e.kindLabel), t(e.orderNo), t(e.productCode),
        e.isProd ? dbl(e.qty) : null, t(e.isProd ? (kMUnits[e.unit] ?? e.unit) : ''), n(e.workers), n(e.daily), n(e.workers + e.daily), t(e.by), t(e.text),
      ]);
    }

    det.appendRow(<xl.CellValue?>[
      t('Makine'), t('Hat'), t('Durum'), t('Başlangıç'), t('Bitiş'), t('Süre (dk)'), t('Sipariş no'), t('Ürün kodu'), t('Çalışan'), t('Günlükçü'), t('Giren'), t('Not'),
    ]);
    final ls = _withOpenLogs(machines, logs).where((l) => l.state != kOffKey).map((l) {
      var sec = 0;
      for (final w in wins) {
        sec += l.secondsIn(w.s, w.e, now);
      }
      return MapEntry(l, sec);
    }).where((x) => x.value > 0).toList()
      ..sort((a, b) {
        final c = '${a.key.line}${a.key.machineName}'.compareTo('${b.key.line}${b.key.machineName}');
        return c != 0 ? c : (a.key.start ?? DateTime(2000)).compareTo(b.key.start ?? DateTime(2000));
      });
    for (final x in ls) {
      final l = x.key;
      det.appendRow(<xl.CellValue?>[
        t(l.machineName), t(l.line), t(l.label), t(fmtFull(l.start)), t(l.end == null ? 'devam ediyor' : fmtFull(l.end)), n(mins(x.value)),
        t(l.orderNo), t(l.productCode), n(l.workers), n(l.daily), t(l.by), t(l.note),
      ]);
    }

    // Sipariş bazlı (seçilen aralıkta)
    final xl.Sheet byJob = excel['Sipariş bazlı'];
    byJob.appendRow(<xl.CellValue?>[
      t('Makine'), t('Hat'), t('Sipariş no'), t('Ürün kodu'), t('Çalışma (dk)'), t('Duruş (dk)'), t('Verimlilik %'), t('Üretim (adet)'), t('Üretim (kg)'),
      t('Kişi (son)'), t('En çok duruş nedeni'),
    ]);
    final jobKeys = <String, List<Object>>{};
    for (final x in ls) {
      final l = x.key;
      if (l.jobId.isEmpty) continue;
      final k = jobKeys.putIfAbsent(l.jobId, () => <Object>[l, 0, <String, int>{}, 0.0, 0.0, l.workers + l.daily]);
      if (l.state == kRunKey) {
        k[1] = (k[1] as int) + x.value;
      } else {
        final mp = k[2] as Map<String, int>;
        mp[l.label] = (mp[l.label] ?? 0) + x.value;
      }
      k[5] = l.workers + l.daily;
    }
    for (final e in es) {
      if (!e.isProd || e.jobId.isEmpty) continue;
      final k = jobKeys[e.jobId];
      if (k == null) continue;
      if (e.unit == 'kg') {
        k[4] = (k[4] as double) + e.qty;
      } else {
        k[3] = (k[3] as double) + e.qty;
      }
    }
    for (final k in jobKeys.values) {
      final l = k[0] as MLog;
      final run = k[1] as int;
      final mp = k[2] as Map<String, int>;
      final stop = mp.values.fold(0, (a, b) => a + b);
      final top = mp.entries.isEmpty ? null : (mp.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
      byJob.appendRow(<xl.CellValue?>[
        t(l.machineName), t(l.line), t(l.orderNo), t(l.productCode), n(mins(run)), n(mins(stop)), dbl(run + stop == 0 ? 0 : run * 100 / (run + stop)),
        dbl(k[3] as double), dbl(k[4] as double), n(k[5] as int), t(top == null ? '' : '${top.key} (${mins(top.value)} dk)'),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final d0 = wins.first.day;
    final file = File('${dir.path}/makine_raporu_${d0.year}${two(d0.month)}${two(d0.day)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Makine raporu');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}

// ---------------------------------------------------------------------------
// Ayarlar: makineler, duruş nedenleri, vardiyalar
// ---------------------------------------------------------------------------

class MachineSettingsPage extends StatelessWidget {
  const MachineSettingsPage({super.key});

  Future<void> _machineDialog(BuildContext context, LineMachine? m, int nextOrder, List<String> lines) async {
    final name = TextEditingController(text: m?.name ?? '');
    final line = TextEditingController(text: m?.line ?? '');
    final order = TextEditingController(text: '${m?.order ?? nextOrder}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(m == null ? 'Makine ekle' : 'Makineyi düzenle'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Makine adı')),
            const SizedBox(height: 10),
            TextField(controller: line, decoration: const InputDecoration(labelText: 'Hat (ör. Zemin kat, Draje paket hattı)')),
            if (lines.isNotEmpty)
              Wrap(spacing: 6, children: [
                for (final l in lines.where((x) => x.isNotEmpty)) ActionChip(label: Text(l), onPressed: () => line.text = l),
              ]),
            const SizedBox(height: 10),
            TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sıra')),
          ]),
        ),
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

  Future<void> _shiftDialog(BuildContext context, List<MShift> list, int? index) async {
    final s = index == null ? null : list[index];
    final name = TextEditingController(text: s?.name ?? '');
    int start = s?.sMin ?? 8 * 60;
    int end = s?.eMin ?? 16 * 60;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text(s == null ? 'Vardiya ekle' : 'Vardiyayı düzenle'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad (ör. 1. vardiya)')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: d, initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60));
                    if (t != null) setS(() => start = t.hour * 60 + t.minute);
                  },
                  child: Text('Başlangıç ${_hmText(start)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: d, initialTime: TimeOfDay(hour: end ~/ 60, minute: end % 60));
                    if (t != null) setS(() => end = t.hour * 60 + t.minute);
                  },
                  child: Text('Bitiş ${_hmText(end)}'),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Bitiş başlangıçtan önce ya da eşitse ertesi gün sayılır (ör. 08:00–08:00 = 24 saat).',
                style: TextStyle(color: kMuted, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final nl = List<MShift>.from(list);
    final ns = MShift(name.text.trim(), _hmText(start), _hmText(end));
    if (s == null) {
      nl.add(ns);
    } else {
      nl[index!] = ns;
    }
    try {
      await MachineOps.saveShifts(nl);
    } catch (e) {
      toast('Kaydedilemedi: $e');
    }
  }

  Widget _title(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (sub != null) Text(sub, style: const TextStyle(color: kMuted, fontSize: 13)),
        ]),
      );

  Widget _row({required Widget title, Widget? leading, String? subtitle, required VoidCallback onEdit, required VoidCallback onDelete}) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: Colors.white,
        elevation: 0,
        child: ListTile(
          leading: leading,
          title: title,
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Düzenle', onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete_outline, color: Color(0xFFC92A2A)), tooltip: 'Sil', onPressed: onDelete),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Makine takip ayarları')),
      body: StreamBuilder<List<LineMachine>>(
        stream: MachineOps.machinesStream(all: true),
        builder: (context, ms) {
          final machines = ms.data ?? const <LineMachine>[];
          final lines = machines.map((m) => m.line).toSet().toList()..sort();
          return StreamBuilder<List<MReason>>(
            stream: MachineOps.reasonsStream(),
            builder: (context, rs) {
              final reasons = rs.data ?? kDefaultMReasons;
              return StreamBuilder<List<MShift>>(
                stream: MachineOps.shiftsStream(),
                builder: (context, ss) {
                  final shifts = ss.data ?? kDefaultShifts;
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    _title('Makineler', 'Kullanıcıların hangi hatları göreceğini Kullanıcılar sayfasından atayın.'),
                    for (final m in machines)
                      _row(
                        title: Text(m.name),
                        subtitle: '${m.line.isEmpty ? 'Hat yok' : m.line} · sıra ${m.order}',
                        onEdit: () => _machineDialog(context, m, m.order, lines),
                        onDelete: () async {
                          if (!await confirm(context, 'Makine silinsin mi?', '${m.name} listeden kalkar. Geçmiş kayıtları raporlarda kalır.', 'Sil')) return;
                          try {
                            await MachineOps.deleteMachine(m);
                          } catch (e) {
                            toast('Silinemedi: $e');
                          }
                        },
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _machineDialog(context, null, machines.length + 1, lines),
                      icon: const Icon(Icons.add),
                      label: const Text('Makine ekle'),
                    ),
                    const SizedBox(height: 24),
                    _title('Vardiyalar', 'İlk sıradaki vardiya canlı ekranda kullanılır. Raporda istediğinizi seçebilirsiniz.'),
                    for (var i = 0; i < shifts.length; i++)
                      _row(
                        leading: Icon(Icons.schedule, color: i == 0 ? kOrange : kMuted),
                        title: Text(shifts[i].label),
                        subtitle: i == 0 ? 'Canlı ekran vardiyası' : null,
                        onEdit: () => _shiftDialog(context, shifts, i),
                        onDelete: () async {
                          if (shifts.length <= 1) {
                            toast('En az bir vardiya kalmalı.');
                            return;
                          }
                          if (!await confirm(context, 'Vardiya silinsin mi?', shifts[i].label, 'Sil')) return;
                          final nl = List<MShift>.from(shifts)..removeAt(i);
                          try {
                            await MachineOps.saveShifts(nl);
                          } catch (e) {
                            toast('Silinemedi: $e');
                          }
                        },
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _shiftDialog(context, shifts, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Vardiya ekle'),
                    ),
                    const SizedBox(height: 24),
                    _title('Duruş nedenleri', '"Çalışıyor" ve "Kapalı / vardiya dışı" sabittir. Zil simgesi olanlar alarm gönderir.'),
                    for (var i = 0; i < reasons.length; i++)
                      _row(
                        leading: Icon(reasons[i].alarm ? Icons.notifications_active : Icons.notifications_off_outlined,
                            color: reasons[i].alarm ? const Color(0xFFC92A2A) : kMuted),
                        title: Text(reasons[i].label),
                        subtitle: reasons[i].alarm ? 'Alarm gönderir' : 'Alarm yok',
                        onEdit: () => _reasonDialog(context, reasons, i),
                        onDelete: () async {
                          if (!await confirm(context, 'Neden silinsin mi?', '"${reasons[i].label}" listeden kalkar. Geçmiş kayıtlar raporda kalır.', 'Sil')) return;
                          final nl = List<MReason>.from(reasons)..removeAt(i);
                          try {
                            await MachineOps.saveReasons(nl);
                          } catch (e) {
                            toast('Silinemedi: $e');
                          }
                        },
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
          );
        },
      ),
    );
  }
}

// Kullanıcılar sayfasından: kullanıcının göreceği hatları seç
Future<void> pickUserLines(BuildContext context, AppUser u) async {
  List<String> all;
  try {
    final s = await MachineOps.col.get();
    all = s.docs.map((d) => (d.data()['line'] ?? '').toString()).toSet().toList()..sort();
  } catch (e) {
    toast('Hatlar okunamadı: $e');
    return;
  }
  if (all.isEmpty) {
    toast('Önce Makine takip ayarlarından makine ve hat ekleyin.');
    return;
  }
  if (!context.mounted) return;
  final sel = u.lines.toSet();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('${u.name} · görebileceği hatlar'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hiçbiri seçilmezse tüm hatları görür. Admin ve "yönetir" yetkisi olanlar her zaman tümünü görür.',
                style: TextStyle(color: kMuted, fontSize: 12)),
            for (final l in all)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: sel.contains(l),
                title: Text(l.isEmpty ? 'Hat belirtilmemiş' : l),
                onChanged: (v) => setS(() => v == true ? sel.add(l) : sel.remove(l)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await db.collection('users').doc(u.uid).update({'lines': sel.toList()..sort()});
    toast('Kaydedildi');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}


// ---------------------------------------------------------------------------
// Sipariş arşivi (makine bazlı işler)
// ---------------------------------------------------------------------------

class MachineJobsPage extends StatefulWidget {
  const MachineJobsPage({super.key});

  @override
  State<MachineJobsPage> createState() => _MachineJobsPageState();
}

class _MachineJobsPageState extends State<MachineJobsPage> {
  String _q = '';
  int _filter = 0; // 0 tümü, 1 devam eden, 2 biten
  List<MJob> _last = const [];

  List<MJob> _apply(List<MJob> all) {
    final q = _q.trim().toLowerCase();
    return all.where((j) => lineVisible(currentUser, j.line)).where((j) => _filter == 0 || (_filter == 1 ? !j.finished : j.finished)).where((j) {
      if (q.isEmpty) return true;
      return '${j.orderNo} ${j.productCode} ${j.machineName} ${j.line} ${j.finishNote}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sipariş arşivi'), actions: [
        IconButton(tooltip: "Excel'e aktar", icon: const Icon(Icons.download), onPressed: () => exportJobsExcel(_last)),
      ]),
      body: StreamBuilder<List<MJob>>(
        stream: MachineOps.jobsStream(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = _apply(snap.data!);
          _last = list;
          return ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Sipariş no, ürün kodu, makine ara'),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(value: 0, label: Text('Tümü')),
                ButtonSegment<int>(value: 1, label: Text('Devam eden')),
                ButtonSegment<int>(value: 2, label: Text('Biten')),
              ],
              selected: {_filter},
              onSelectionChanged: (v) => setState(() => _filter = v.first),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty) const Padding(padding: EdgeInsets.only(top: 30), child: Center(child: Text('Kayıt yok.', style: TextStyle(color: kMuted)))),
            for (final j in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => showJobDetail(context, j),
                  child: _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('Sipariş ${j.orderNo}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                            color: j.finished ? const Color(0xFFE9ECEF) : const Color(0xFFD3F9D8), borderRadius: BorderRadius.circular(999)),
                        child: Text(j.statusLabel,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: j.finished ? kMuted : const Color(0xFF1B6B2B))),
                      ),
                    ]),
                    Text('${j.productCode} · ${j.machineName}${j.line.isEmpty ? '' : ' · ${j.line}'}', style: const TextStyle(color: kMuted)),
                    Text('${fmtDT(j.startedAt)} → ${j.finished ? fmtDT(j.finishedAt) : 'devam ediyor'} · ${j.dayCount} gün',
                        style: const TextStyle(color: kMuted, fontSize: 13)),
                    Text('Üretim: ${j.qtyText}${j.finished || j.runSec > 0 ? ' · verim %${j.efficiency.toStringAsFixed(0)}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ])),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

Future<void> showJobDetail(BuildContext context, MJob j) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, dynamic>>(
          future: j.finished ? Future.value(<String, dynamic>{'runSec': j.runSec, 'stops': j.stops}) : MachineOps.liveSummary(j.id),
          builder: (c, snap) {
            final run = (snap.data?['runSec'] as int?) ?? j.runSec;
            final stops = (snap.data?['stops'] as Map<String, int>?) ?? j.stops;
            final stop = stops.values.fold(0, (a, b) => a + b);
            final eff = run + stop == 0 ? 0.0 : run * 100 / (run + stop);
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Sipariş ${j.orderNo}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text('${j.productCode} · ${j.machineName}${j.line.isEmpty ? '' : ' · ${j.line}'} · ${j.statusLabel}', style: const TextStyle(color: kMuted)),
                const SizedBox(height: 8),
                Text('Başlangıç: ${fmtFull(j.startedAt)}'),
                Text('Bitiş: ${j.finished ? fmtFull(j.finishedAt) : 'devam ediyor'} · ${j.dayCount} gün'),
                Text('Başlatan: ${j.by} · son kişi sayısı ${j.workers}+${j.daily}'),
                if (j.finishNote.isNotEmpty) Text('Bitiş notu: ${j.finishNote}', style: const TextStyle(fontStyle: FontStyle.italic)),
                const Divider(height: 20),
                Text('Üretim: ${j.qtyText}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('Verimlilik: %${eff.toStringAsFixed(1)} · çalışma ${fmtSec(run)} · duruş ${fmtSec(stop)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (snap.connectionState == ConnectionState.waiting) const LinearProgressIndicator(),
                for (final e in (stops.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [Expanded(child: Text(e.key)), Text(fmtSec(e.value), style: const TextStyle(fontWeight: FontWeight.w600))]),
                  ),
                if (canMachineManage(currentUser)) ...[
                  const SizedBox(height: 12),
                  if (j.finished)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC92A2A)),
                      onPressed: () async {
                        if (!await confirm(c, 'Arşiv kaydı silinsin mi?', 'Sipariş ${j.orderNo} arşivden kalkar. Makinenin durum ve üretim kayıtları raporlarda kalır.', 'Sil')) {
                          return;
                        }
                        try {
                          await MachineOps.jobs.doc(j.id).delete();
                          if (c.mounted) Navigator.pop(c);
                          toast('Silindi');
                        } catch (e) {
                          toast('Silinemedi: $e');
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Arşivden sil'),
                    ),
                ],
              ]),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> exportJobsExcel(List<MJob> jobs) async {
  try {
    if (jobs.isEmpty) {
      toast('Aktarılacak sipariş yok.');
      return;
    }
    toast('Sipariş arşivi hazırlanıyor…');
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Sipariş arşivi');
    final xl.Sheet sh = excel['Sipariş arşivi'];
    xl.CellValue t(String v) => xl.TextCellValue(v);
    xl.CellValue n(int v) => xl.IntCellValue(v);
    xl.CellValue dbl(double v) => xl.DoubleCellValue((v * 10).round() / 10);
    int mins(int s) => (s / 60).round();
    final labels = <String>{};
    final sums = <String, Map<String, dynamic>>{};
    for (final j in jobs) {
      final Map<String, dynamic> sm = j.finished ? <String, dynamic>{'runSec': j.runSec, 'stops': j.stops} : await MachineOps.liveSummary(j.id);
      sums[j.id] = sm;
      labels.addAll((sm['stops'] as Map<String, int>).keys);
    }
    final lab = labels.toList()..sort();
    sh.appendRow(<xl.CellValue?>[
      t('Sipariş no'), t('Ürün kodu'), t('Makine'), t('Hat'), t('Durum'), t('Başlangıç'), t('Bitiş'), t('Gün sayısı'), t('Üretim (adet)'), t('Üretim (kg)'),
      t('Çalışma (dk)'), t('Duruş (dk)'), t('Verimlilik %'), for (final l in lab) t('$l (dk)'), t('Son çalışan'), t('Son günlükçü'), t('Başlatan'), t('Bitiş notu'),
    ]);
    for (final j in jobs) {
      final sm = sums[j.id]!;
      final run = sm['runSec'] as int;
      final st = sm['stops'] as Map<String, int>;
      final stop = st.values.fold(0, (a, b) => a + b);
      sh.appendRow(<xl.CellValue?>[
        t(j.orderNo), t(j.productCode), t(j.machineName), t(j.line), t(j.statusLabel), t(fmtFull(j.startedAt)), t(j.finished ? fmtFull(j.finishedAt) : ''),
        n(j.dayCount), dbl(j.qtyAdet), dbl(j.qtyKg), n(mins(run)), n(mins(stop)), dbl(run + stop == 0 ? 0 : run * 100 / (run + stop)),
        for (final l in lab) n(mins(st[l] ?? 0)), n(j.workers), n(j.daily), t(j.by), t(j.finishNote),
      ]);
    }
    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final file = File('${dir.path}/siparis_arsivi_${now.year}${two(now.month)}${two(now.day)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Makine sipariş arşivi');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}
