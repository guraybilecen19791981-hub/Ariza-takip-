part of 'main.dart';

// ---------------------------------------------------------------------------
// Makine takip: Sargı makineleri ve Üretim makineleri
// (durum, ürün, personel, üretim, fire, vardiya raporu, sipariş arşivi)
// ---------------------------------------------------------------------------

// Makine grubu: aynı ekranlar iki ayrı panel olarak kullanılır.
// Eski kayıtlarda "group" alanı yoktur; bunlar Sargı makineleri sayılır.
class MGroup {
  final String key;
  final String title;
  final String lineLabel; // Hat / Bölge
  final String perm; // yetki modülü
  final String reasonsDoc; // config belgesi
  final List<String> defaultLines;
  final bool operators; // operatör sayısı girilir
  const MGroup(this.key, this.title, this.lineLabel, this.perm, this.reasonsDoc, this.defaultLines, [this.operators = false]);

  // Kişi metni: "4 çalışan + 1 günlükçü (+ 2 operatör)"
  String peopleText(int w, int d, int o) => operators ? '$w çalışan + $d günlükçü + $o operatör' : '$w çalışan + $d günlükçü';
  String peopleShort(int w, int d, int o) => operators ? '$w+$d+$o' : '$w+$d';

  bool owns(String g) => (g.isEmpty ? 'sargi' : g) == key;
  String get lineLower => lineLabel.toLowerCase();
  String get noLine => '$lineLabel belirtilmemiş';
}

const MGroup kSargi = MGroup('sargi', 'Sargı makineleri', 'Hat', 'hat', 'machineReasons', []);
const MGroup kUretim = MGroup('uretim', 'Üretim makineleri', 'Bölge', 'uretim', 'machineReasonsUretim', ['Zemin kat', '1. kat'], true);
const List<MGroup> kMGroups = [kSargi, kUretim];
MGroup mGroupOf(String key) => key == 'uretim' ? kUretim : kSargi;

// Makine → panel eşlemesi. Eski uygulama sürümleri durum / üretim / sipariş kayıtlarına panel bilgisi
// yazmadığı için kaydın paneli önce makinesinden bulunur; makine bilinmiyorsa kayıttaki alana bakılır.
final Map<String, String> gMachineGroup = {};
void rememberMachineGroups(Iterable<LineMachine> ms) {
  for (final m in ms) {
    gMachineGroup[m.id] = m.group;
  }
}

bool recOwns(MGroup g, String machineId, String recGroup) {
  final mg = gMachineGroup[machineId];
  return g.owns(mg ?? recGroup);
}

// Fire metni: paket fire ve ürün fire (adet / kg)
String fireText(double pA, double pK, double uA, double uK) {
  String q(double a, double k) => [if (a > 0) '${fmtQty(a)} adet', if (k > 0) '${fmtQty(k)} kg'].join(' + ');
  final p = <String>[];
  if (pA > 0 || pK > 0) p.add('paket fire ${q(pA, pK)}');
  if (uA > 0 || uK > 0) p.add('ürün fire ${q(uA, uK)}');
  return p.join(' · ');
}

const String kRunKey = 'calisiyor';
const String kOffKey = 'kapali';
const Map<String, String> kMUnits = {'adet': 'Adet', 'kg': 'Kg'};

class MReason {
  final String key;
  final String label;
  final bool alarm;
  final bool fault; // seçilince arıza kaydı açar (teknik hizmet akışı)
  const MReason(this.key, this.label, this.alarm, [this.fault = false]);

  factory MReason.fromMap(dynamic m) {
    final x = (m is Map) ? m : <String, dynamic>{};
    final key = (x['key'] ?? '').toString();
    return MReason(key, (x['label'] ?? '').toString(), x['alarm'] == true, x.containsKey('fault') ? x['fault'] == true : key == 'ariza');
  }

  Map<String, dynamic> toMap() => {'key': key, 'label': label, 'alarm': alarm, 'fault': fault};
}

// Teknisyen "Bitti" dedikten sonra, arızayı açan onaylayana kadar makinenin durumu
const String kFaultWaitKey = 'ariza_onay';
const String kFaultWaitLabel = 'Arıza onay bekliyor';

const List<MReason> kDefaultMReasons = [
  MReason('uretim_yok', 'Üretim yok', false),
  MReason('ariza', 'Arızalı', true, true),
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
  if (key == kFaultWaitKey) return const Color(0xFF7048E8);
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
  final String group;
  final double jobFpAdet;
  final double jobFpKg;
  final double jobFuAdet;
  final double jobFuKg;
  final int operators;
  final String faultId; // açık arıza kaydı
  final String faultStatus;
  final String faultAssignee;
  final String faultByUid; // arızayı açan (onay verecek kişi)

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
    this.group = 'sargi',
    this.jobFpAdet = 0,
    this.jobFpKg = 0,
    this.jobFuAdet = 0,
    this.jobFuKg = 0,
    this.operators = 0,
    this.faultId = '',
    this.faultStatus = '',
    this.faultAssignee = '',
    this.faultByUid = '',
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
      group: (m['group'] ?? '').toString().isEmpty ? 'sargi' : m['group'].toString(),
      jobFpAdet: _dbl(m['jobFpAdet']),
      jobFpKg: _dbl(m['jobFpKg']),
      jobFuAdet: _dbl(m['jobFuAdet']),
      jobFuKg: _dbl(m['jobFuKg']),
      operators: _int(m['operators']),
      faultId: (m['faultId'] ?? '').toString(),
      faultStatus: (m['faultStatus'] ?? '').toString(),
      faultAssignee: (m['faultAssignee'] ?? '').toString(),
      faultByUid: (m['faultByUid'] ?? '').toString(),
    );
  }

  MGroup get grp => mGroupOf(group);
  bool get hasFault => faultId.isNotEmpty;
  String get peopleText => grp.peopleText(workers, daily, operators);
  String get jobFireText => fireText(jobFpAdet, jobFpKg, jobFuAdet, jobFuKg);
  bool get hasJob => jobId.isNotEmpty;
  String get jobQtyText {
    final p = <String>[];
    if (jobAdet > 0) p.add('${fmtQty(jobAdet)} adet');
    if (jobKg > 0) p.add('${fmtQty(jobKg)} kg');
    return p.isEmpty ? '—' : p.join(' · ');
  }

  bool get running => state == kRunKey;
  bool get off => state == kOffKey;
  int get people => workers + daily + operators;
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
  final String group;
  final int operators;

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
    this.group = '',
    this.operators = 0,
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
      group: (m['group'] ?? '').toString(),
      operators: _int(m['operators']),
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
  final String group;
  final double fp; // paket fire
  final String fpUnit;
  final double fu; // ürün fire
  final String fuUnit;
  final int operators;

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
    this.group = '',
    this.fp = 0,
    this.fpUnit = 'adet',
    this.fu = 0,
    this.fuUnit = 'adet',
    this.operators = 0,
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
      group: (m['group'] ?? '').toString(),
      fp: _dbl(m['fp']),
      fpUnit: (m['fpUnit'] ?? 'adet').toString(),
      fu: _dbl(m['fu']),
      fuUnit: (m['fuUnit'] ?? 'adet').toString(),
      operators: _int(m['operators']),
    );
  }

  bool get isProd => kind == 'uretim';
  String get fireTxt => fireText(fpUnit == 'kg' ? 0 : fp, fpUnit == 'kg' ? fp : 0, fuUnit == 'kg' ? 0 : fu, fuUnit == 'kg' ? fu : 0);
  String get kindLabel => const {
        'uretim': 'Üretim girişi',
        'bilgi': 'Kişi / bilgi güncelleme',
        'is_basla': 'Sipariş başladı',
        'gun_bitti': 'Gün bitti',
        'gun_basla': 'Güne başlandı',
        'is_bitti': 'Sipariş bitti',
        'ariza': 'Arıza',
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
  final int photoCount;
  final String group;
  final double fpAdet;
  final double fpKg;
  final double fuAdet;
  final double fuKg;
  final int operators;

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
    this.photoCount = 0,
    this.group = '',
    this.fpAdet = 0,
    this.fpKg = 0,
    this.fuAdet = 0,
    this.fuKg = 0,
    this.operators = 0,
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
      photoCount: _int(m['photoCount']),
      group: (m['group'] ?? '').toString(),
      fpAdet: _dbl(m['fpAdet']),
      fpKg: _dbl(m['fpKg']),
      fuAdet: _dbl(m['fuAdet']),
      fuKg: _dbl(m['fuKg']),
      operators: _int(m['operators']),
    );
  }

  String get fireTxt => fireText(fpAdet, fpKg, fuAdet, fuKg);
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

// Bir işin çalışma / duruş özetini durum kayıtlarından hesaplar.
// Her kayıt en geç bir sonraki kaydın başladığı anda biter (çakışan / açık kalmış kayıt iki kez sayılmaz).
Map<String, dynamic> jobSummaryFromLogs(List<MLog> logs0, DateTime now) {
  int run = 0;
  final stops = <String, int>{};
  final logs = logs0.where((l) => l.start != null).toList()..sort((a, b) => a.start!.compareTo(b.start!));
  for (var i = 0; i < logs.length; i++) {
    final l = logs[i];
    if (l.state == kOffKey) continue;
    var e = l.end ?? now;
    if (e.isAfter(now)) e = now;
    if (i + 1 < logs.length && logs[i + 1].start!.isBefore(e)) e = logs[i + 1].start!;
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
  int off = 0; // kapalı / vardiya dışı (verime girmez)
  int span = 0; // çalışılan vardiyaların toplam süresi
  int shifts = 0; // çalışılan vardiya sayısı
  int skipped = 0; // baştan sona kapalı (sayılmayan) vardiya sayısı
  final Map<String, int> stops = {};
  double qtyAdet = 0;
  double qtyKg = 0;
  double fpAdet = 0;
  double fpKg = 0;
  double fuAdet = 0;
  double fuKg = 0;
  final Set<String> products = {};
  MStat(this.id, this.name, this.line);

  String get fireTxt => fireText(fpAdet, fpKg, fuAdet, fuKg);
  bool get hasFire => fpAdet > 0 || fpKg > 0 || fuAdet > 0 || fuKg > 0;
  bool get hasData => tracked > 0 || qtyAdet > 0 || qtyKg > 0 || hasFire;
  void addFire(MEntry e) {
    if (e.fpUnit == 'kg') {
      fpKg += e.fp;
    } else {
      fpAdet += e.fp;
    }
    if (e.fuUnit == 'kg') {
      fuKg += e.fu;
    } else {
      fuAdet += e.fu;
    }
  }

  int get stopTotal => stops.values.fold(0, (a, b) => a + b);
  int get tracked => run + stopTotal;
  int get none => math.max(0, span - off - run - stopTotal); // hiç durum girilmemiş süre
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
          operators: m.operators,
          jobId: m.jobId,
          orderNo: m.orderNo,
          group: m.group));
    }
  }
  return all;
}

// Durum kaydının düzeltilmiş zaman aralığı
class MSeg {
  final MLog l;
  final DateTime s;
  final DateTime e;
  const MSeg(this.l, this.s, this.e);

  int secIn(List<TimeWin> wins) {
    var t = 0;
    for (final w in wins) {
      final a = s.isAfter(w.s) ? s : w.s;
      final b = e.isBefore(w.e) ? e : w.e;
      final d = b.difference(a).inSeconds;
      if (d > 0) t += d;
    }
    return t;
  }
}

// Durum kayıtlarını makine başına zaman çizelgesine çevirir: her kayıt en geç aynı makinedeki
// bir sonraki kaydın başladığı anda biter. Böylece hiçbir süre iki kez sayılmaz; raporlar birbirini tutar.
List<MSeg> normLogs(List<LineMachine> machines, List<MLog> logs, DateTime now) {
  final byId = <String, MLog>{};
  for (final l in _withOpenLogs(machines, logs)) {
    byId[l.id] = l;
  }
  final per = <String, List<MLog>>{};
  for (final l in byId.values) {
    if (l.start == null || l.start!.isAfter(now)) continue;
    per.putIfAbsent(l.machineId, () => <MLog>[]).add(l);
  }
  final out = <MSeg>[];
  for (final arr in per.values) {
    arr.sort((a, b) => a.start!.compareTo(b.start!));
    for (var i = 0; i < arr.length; i++) {
      final l = arr[i];
      var e = l.end ?? now;
      if (e.isAfter(now)) e = now;
      if (i + 1 < arr.length && arr[i + 1].start!.isBefore(e)) e = arr[i + 1].start!;
      if (e.isBefore(l.start!)) e = l.start!;
      out.add(MSeg(l, l.start!, e));
    }
  }
  return out;
}

// from verilirse makinenin ilk kaydından önceki süre sayılmaz (makine sisteme sonradan eklenmiş olabilir)
int winSpanSec(List<TimeWin> wins, DateTime now, [DateTime? from]) {
  var t = 0;
  for (final w in wins) {
    final e = w.e.isBefore(now) ? w.e : now;
    final s = (from != null && from.isAfter(w.s)) ? from : w.s;
    final d = e.difference(s).inSeconds;
    if (d > 0) t += d;
  }
  return t;
}

// Dakikaya yuvarlarken parçaların toplamı hedefi tutsun (en büyük kalan yöntemi)
List<int> lrRound(List<double> vals, int target) {
  final fl = vals.map((v) => v.floor()).toList();
  var rem = target - fl.fold<int>(0, (a, b) => a + b);
  final ord = List<int>.generate(vals.length, (i) => i)..sort((a, b) => (vals[b] - fl[b]).compareTo(vals[a] - fl[a]));
  for (var k = 0; k < ord.length && rem > 0; k++, rem--) {
    fl[ord[k]]++;
  }
  for (var k = ord.length - 1; k >= 0 && rem < 0; k--) {
    if (fl[ord[k]] > 0) {
      fl[ord[k]]--;
      rem++;
    }
  }
  return fl;
}

// Bir makinenin dakikaları: vardiya süresi = kapalı + kayıt yok + çalışma + duruş nedenleri (tam tutar)
class MStatMin {
  final int span, off, none, run, stop;
  final Map<String, int> stops;
  const MStatMin(this.span, this.off, this.none, this.run, this.stop, this.stops);
  int get tracked => run + stop;
}

MStatMin statMin(MStat st) {
  final labels = st.stops.keys.toList();
  final parts = <double>[st.off / 60, st.none / 60, st.run / 60, for (final l in labels) st.stops[l]! / 60];
  final r = lrRound(parts, (st.span / 60).round());
  final stops = <String, int>{};
  for (var i = 0; i < labels.length; i++) {
    stops[labels[i]] = r[3 + i];
  }
  final stop = stops.values.fold<int>(0, (a, b) => a + b);
  return MStatMin((st.span / 60).round(), r[0], r[1], r[2], stop, stops);
}

// Makine istatistikleri. Vardiya vardiya hesaplanır: makinenin baştan sona kapalı olduğu (hiç çalışma / duruş olmayan)
// vardiyalar çalışılmamış sayılır ve hiçbir sütuna girmez (hafta sonu, tatil, çalışılmayan gün).
Map<String, MStat> computeMStats(List<LineMachine> machines, List<MLog> logs, List<MEntry> entries, List<TimeWin> wins) {
  final now = DateTime.now();
  final segs = normLogs(machines, logs, now);
  // Makinenin ilk durum kaydından önceki süre sayılmaz (makine sisteme sonradan eklenmiş olabilir)
  final first = <String, DateTime>{};
  for (final x in segs) {
    final f = first[x.l.machineId];
    if (f == null || x.s.isBefore(f)) first[x.l.machineId] = x.s;
  }
  final out = <String, MStat>{};
  MStat get(String id, String name, String line) => out.putIfAbsent(id, () => MStat(id, name, line));
  for (final m in machines) {
    get(m.id, m.name, m.line);
  }
  // vardiya başına makine kovaları
  final bk = <String, List<MStat>>{};
  for (final x in segs) {
    final l = x.l;
    get(l.machineId, l.machineName, l.line);
    for (var i = 0; i < wins.length; i++) {
      final sec = x.secIn([wins[i]]);
      if (sec <= 0) continue;
      final b = bk.putIfAbsent(l.machineId, () => [for (final _ in wins) MStat('', '', '')])[i];
      if (l.state == kOffKey) {
        b.off += sec;
      } else if (l.state == kRunKey) {
        b.run += sec;
      } else {
        final k = l.label.isEmpty ? l.state : l.label;
        b.stops[k] = (b.stops[k] ?? 0) + sec;
      }
      if (l.productCode.isNotEmpty && l.state != kOffKey) b.products.add(l.productCode);
    }
  }
  for (final st in out.values) {
    final arr = bk[st.id];
    final f = first[st.id];
    if (f == null) continue;
    for (var i = 0; i < wins.length; i++) {
      final w = wins[i];
      final from = f.isAfter(w.s) ? f : w.s;
      final to = w.e.isBefore(now) ? w.e : now;
      final wspan = to.difference(from).inSeconds;
      if (wspan <= 0) continue;
      final b = arr?[i];
      if (b == null || b.run + b.stopTotal <= 0) {
        st.skipped++; // bu vardiyada çalışılmamış
        continue;
      }
      st.shifts++;
      st.span += wspan;
      st.run += b.run;
      st.off += b.off;
      b.stops.forEach((k, v) => st.stops[k] = (st.stops[k] ?? 0) + v);
      st.products.addAll(b.products);
    }
  }
  for (final e in entries) {
    final t = e.t;
    if (t == null || !e.isProd || !wins.any((w) => w.contains(t))) continue;
    final st = get(e.machineId, e.machineName, e.line);
    if (e.unit == 'kg') {
      st.qtyKg += e.qty;
    } else {
      st.qtyAdet += e.qty;
    }
    st.addFire(e);
    if (e.productCode.isNotEmpty) st.products.add(e.productCode);
  }
  for (final st in out.values) {
    final used = st.off + st.run + st.stopTotal;
    if (st.span < used) st.span = used;
  }
  return out;
}

String fmtSec(int s) => fmtMin((s / 60).round());

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

bool canMachineEnter(AppUser? me, MGroup g) => me != null && me.can(g.perm, 'gir');
bool canMachineManage(AppUser? me, MGroup g) => me != null && (me.isAdmin || me.can(g.perm, 'yonet'));

// Kullanıcının görebileceği hatlar / bölgeler: null = tümü.
// Kullanıcıya bu paneldeki hat / bölgelerden hiçbiri atanmamışsa paneldeki tüm makineleri görür.
Set<String>? visibleLines(AppUser? me, MGroup g, Iterable<String> groupLines) {
  if (me == null) return <String>{};
  if (me.isAdmin || me.can(g.perm, 'yonet') || me.lines.isEmpty) return null;
  final gl = groupLines.toSet();
  final mine = me.lines.where(gl.contains).toSet();
  return mine.isEmpty ? null : mine;
}

List<T> filterVisible<T>(AppUser? me, MGroup g, Iterable<T> items, String Function(T) line) {
  final l = items.toList();
  final v = visibleLines(me, g, l.map(line));
  return v == null ? l : l.where((x) => v.contains(line(x))).toList();
}

class MachineOps {
  static CollectionReference<Map<String, dynamic>> get col => db.collection('lineMachines');
  static CollectionReference<Map<String, dynamic>> get logs => db.collection('machineLogs');
  static CollectionReference<Map<String, dynamic>> get entries => db.collection('machineEntries');
  static DocumentReference<Map<String, dynamic>> cfg(MGroup g) => db.collection('config').doc(g.reasonsDoc);
  static DocumentReference<Map<String, dynamic>> get shiftCfg => db.collection('config').doc('machineShifts');

  static Stream<List<MReason>> reasonsStream(MGroup g) => cfg(g).snapshots().map((s) {
        final raw = s.data()?['items'];
        if (raw is List && raw.isNotEmpty) return raw.map((e) => MReason.fromMap(e)).where((r) => r.key.isNotEmpty).toList();
        return List<MReason>.from(kDefaultMReasons);
      });

  static Future<void> saveReasons(MGroup g, List<MReason> list) => cfg(g).set({'items': list.map((r) => r.toMap()).toList()});

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

  static Stream<List<LineMachine>> machinesStream(MGroup g, {bool all = false}) => col.snapshots().map((s) {
        final allM = s.docs.map((d) => LineMachine.fromDoc(d)).toList();
        rememberMachineGroups(allM);
        final l = allM.where((m) => g.owns(m.group));
        return _sorted(all ? l : filterVisible<LineMachine>(currentUser, g, l, (m) => m.line));
      });

  static Stream<List<MLog>> logsSince(MGroup g, DateTime from) => logs
      .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .snapshots()
      .map((s) => s.docs.map((d) => MLog.fromDoc(d)).where((l) => recOwns(g, l.machineId, l.group)).toList());

  static Stream<List<MEntry>> entriesSince(MGroup g, DateTime from) => entries
      .where('t', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .snapshots()
      .map((s) => s.docs.map((d) => MEntry.fromDoc(d)).where((e) => recOwns(g, e.machineId, e.group)).toList());

  static Future<List<MLog>> logsBetween(MGroup g, DateTime from, DateTime to) async {
    final s = await logs
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from.subtract(const Duration(days: 7))))
        .where('start', isLessThan: Timestamp.fromDate(to))
        .get();
    return s.docs.map((d) => MLog.fromDoc(d)).where((l) => recOwns(g, l.machineId, l.group)).toList();
  }

  static Future<List<MEntry>> entriesBetween(MGroup g, DateTime from, DateTime to) async {
    final s = await entries.where('t', isGreaterThanOrEqualTo: Timestamp.fromDate(from)).where('t', isLessThan: Timestamp.fromDate(to)).get();
    return s.docs.map((d) => MEntry.fromDoc(d)).where((e) => recOwns(g, e.machineId, e.group)).toList();
  }

  static Future<void> addMachine(MGroup g, String name, String line, int order) => col.add({
        'group': g.key,
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
        'operators': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

  static Future<void> editMachine(LineMachine m, String name, String line, int order) =>
      col.doc(m.id).update({'name': name, 'line': line, 'order': order});

  static Future<void> deleteMachine(LineMachine m) => col.doc(m.id).delete();

  static CollectionReference<Map<String, dynamic>> get jobs => db.collection('machineJobs');

  static Map<String, dynamic> _logData(LineMachine m, String key, String label, String note, DateTime now, String jobId, String orderNo, String productCode, int workers, int daily, int operators) => {
        'group': m.group,
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
        'operators': operators,
        'jobId': jobId,
        'orderNo': orderNo,
      };

  static Map<String, dynamic> _entryData(LineMachine m, String kind, DateTime now, {double qty = 0, String? unit, String text = '', String? jobId, String? orderNo, String? productCode, int? workers, int? daily, int? operators}) => {
        'group': m.group,
        'machineId': m.id,
        'machineName': m.name,
        'line': m.line,
        'kind': kind,
        'qty': qty,
        'unit': unit ?? m.unit,
        'productCode': productCode ?? m.productCode,
        'workers': workers ?? m.workers,
        'daily': daily ?? m.daily,
        'operators': operators ?? m.operators,
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
      {required String jobId, required String orderNo, required String productCode, required int workers, required int daily, int? operators}) {
    if (m.openLogId.isNotEmpty) {
      batch.update(logs.doc(m.openLogId), {'end': Timestamp.fromDate(now), 'endMs': now.millisecondsSinceEpoch});
    }
    final lg = logs.doc();
    batch.set(lg, _logData(m, key, label, note, now, jobId, orderNo, productCode, workers, daily, operators ?? m.operators));
    return {
      'state': key,
      'stateLabel': label,
      'since': Timestamp.fromDate(now),
      'by': currentUser?.name ?? '',
      'note': note,
      'openLogId': lg.id,
    };
  }

  // extraMachine: makine belgesine ek alanlar; extraWrites: aynı toplu yazmaya eklenecek diğer kayıtlar
  static Future<void> setState(LineMachine m, String key, String label, bool alarm, String note,
      {Map<String, dynamic>? extraMachine, void Function(WriteBatch b)? extraWrites, bool force = false, bool fault = false}) async {
    if (!force && m.state == key && m.note == note) return;
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
    if (extraMachine != null) upd.addAll(extraMachine);
    batch.update(col.doc(m.id), upd);
    if (extraWrites != null) extraWrites(batch);
    if (alarm) {
      batch.set(db.collection('machineAlerts').doc(), {
        'group': m.group,
        'machineId': m.id,
        'machineName': m.name,
        'line': m.line,
        'label': label,
        'note': note,
        'orderNo': m.orderNo,
        'fault': fault,
        'by': currentUser?.name ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // Yeni sipariş / iş başlat (makine çalışıyor durumuna geçer)
  static Future<void> startJob(LineMachine m, String orderNo, String productCode, String unit, int workers, int daily, [int operators = 0]) async {
    final now = DateTime.now();
    final batch = db.batch();
    final job = jobs.doc();
    batch.set(job, {
      'group': m.group,
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
      'fpAdet': 0,
      'fpKg': 0,
      'fuAdet': 0,
      'fuKg': 0,
      'workers': workers,
      'daily': daily,
      'operators': operators,
      'runSec': 0,
      'stops': <String, int>{},
      'dayCount': 1,
    });
    final upd = _switchLog(batch, m, now, kRunKey, 'Çalışıyor', '', jobId: job.id, orderNo: orderNo, productCode: productCode, workers: workers, daily: daily, operators: operators);
    upd.addAll({
      'jobId': job.id,
      'orderNo': orderNo,
      'productCode': productCode,
      'unit': unit,
      'workers': workers,
      'daily': daily,
      'operators': operators,
      'jobStatus': 'acik',
      'jobStartedAt': Timestamp.fromDate(now),
      'jobAdet': 0,
      'jobKg': 0,
      'jobFpAdet': 0,
      'jobFpKg': 0,
      'jobFuAdet': 0,
      'jobFuKg': 0,
    });
    batch.update(col.doc(m.id), upd);
    batch.set(entries.doc(),
        _entryData(m, 'is_basla', now, jobId: job.id, orderNo: orderNo, productCode: productCode, unit: unit, workers: workers, daily: daily, operators: operators,
            text: 'Sipariş $orderNo · $productCode · ${m.grp.peopleText(workers, daily, operators)}'));
    await batch.commit();
  }

  static Future<Map<String, dynamic>> _summary(String jobId, DateTime now) async {
    final s = await logs.where('jobId', isEqualTo: jobId).get();
    return jobSummaryFromLogs(s.docs.map((d) => MLog.fromDoc(d)).toList(), now);
  }

  static Future<Map<String, dynamic>> liveSummary(String jobId) => _summary(jobId, DateTime.now());
  // Arşiv: durum kayıtlarından her seferinde yeniden hesaplanır (biten sipariş bitiş anına kadar)
  static Future<Map<String, dynamic>> summaryAt(String jobId, DateTime at) => _summary(jobId, at);

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
  static Future<void> startDay(LineMachine m, int workers, int daily, [int operators = 0]) async {
    if (!m.hasJob) return;
    final now = DateTime.now();
    final batch = db.batch();
    final upd = _switchLog(batch, m, now, kRunKey, 'Çalışıyor', '',
        jobId: m.jobId, orderNo: m.orderNo, productCode: m.productCode, workers: workers, daily: daily, operators: operators);
    upd.addAll({'jobStatus': 'acik', 'workers': workers, 'daily': daily, 'operators': operators});
    batch.update(col.doc(m.id), upd);
    batch.update(jobs.doc(m.jobId), {'status': 'acik', 'workers': workers, 'daily': daily, 'operators': operators, 'dayCount': FieldValue.increment(1)});
    batch.set(entries.doc(),
        _entryData(m, 'gun_basla', now, workers: workers, daily: daily, operators: operators, text: 'Güne başlandı · ${m.grp.peopleText(workers, daily, operators)}'));
    await batch.commit();
  }

  // Siparişi bitir: iş arşive kapanır, makine kapalıya alınır
  static Future<void> finishJob(LineMachine m, String note) async {
    if (!m.hasJob) return;
    final now = DateTime.now();
    final sum = await _summary(m.jobId, now);
    final batch = db.batch();
    final upd = _switchLog(batch, m, now, kOffKey, 'Kapalı', 'Sipariş bitti', jobId: '', orderNo: '', productCode: '', workers: 0, daily: 0, operators: 0);
    upd.addAll({'jobId': '', 'orderNo': '', 'productCode': '', 'jobStatus': '', 'jobStartedAt': null, 'jobAdet': 0, 'jobKg': 0,
      'jobFpAdet': 0, 'jobFpKg': 0, 'jobFuAdet': 0, 'jobFuKg': 0, 'workers': 0, 'daily': 0, 'operators': 0});
    batch.update(col.doc(m.id), upd);
    batch.update(jobs.doc(m.jobId), {'status': 'bitti', 'finishedAt': Timestamp.fromDate(now), 'finishNote': note, ...sum});
    final fire = m.jobFireText;
    batch.set(entries.doc(), _entryData(m, 'is_bitti', now, text: 'Sipariş bitti · ${m.jobQtyText}${fire.isEmpty ? '' : ' · $fire'}${note.isEmpty ? '' : ' · Not: $note'}'));
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
  static Future<void> setPeople(LineMachine m, int workers, int daily, [int operators = 0]) async {
    if (workers == m.workers && daily == m.daily && operators == m.operators) return;
    final now = DateTime.now();
    final batch = db.batch();
    final upd = _switchLog(batch, m, now, m.state, m.stateLabel, m.note,
        jobId: m.jobId, orderNo: m.orderNo, productCode: m.productCode, workers: workers, daily: daily, operators: operators);
    upd.addAll({'workers': workers, 'daily': daily, 'operators': operators});
    upd.remove('since'); // durum süresi sıfırlanmasın
    upd.remove('by');
    batch.update(col.doc(m.id), upd);
    if (m.hasJob) batch.update(jobs.doc(m.jobId), {'workers': workers, 'daily': daily, 'operators': operators});
    batch.set(entries.doc(),
        _entryData(m, 'bilgi', now, workers: workers, daily: daily, operators: operators,
            text: 'Kişi: ${m.grp.peopleShort(m.workers, m.daily, m.operators)} → ${m.grp.peopleShort(workers, daily, operators)}'));
    await batch.commit();
  }

  // Üretim girişi: miktar ve / veya paket fire, ürün fire (her biri adet ya da kg)
  static Future<void> addProduction(LineMachine m, double qty, String unit, String note,
      {double fp = 0, String fpUnit = 'adet', double fu = 0, String fuUnit = 'adet'}) async {
    final now = DateTime.now();
    final batch = db.batch();
    final data = _entryData(m, 'uretim', now, qty: qty, unit: unit, text: note);
    data.addAll({'fp': fp, 'fpUnit': fpUnit, 'fu': fu, 'fuUnit': fuUnit});
    batch.set(entries.doc(), data);
    final f = unit == 'kg' ? 'Kg' : 'Adet';
    final mu = <String, dynamic>{if (unit != m.unit && qty > 0) 'unit': unit};
    final ju = <String, dynamic>{};
    if (qty > 0) {
      mu['job$f'] = FieldValue.increment(qty);
      ju['qty$f'] = FieldValue.increment(qty);
    }
    if (fp > 0) {
      final k = fpUnit == 'kg' ? 'Kg' : 'Adet';
      mu['jobFp$k'] = FieldValue.increment(fp);
      ju['fp$k'] = FieldValue.increment(fp);
    }
    if (fu > 0) {
      final k = fuUnit == 'kg' ? 'Kg' : 'Adet';
      mu['jobFu$k'] = FieldValue.increment(fu);
      ju['fu$k'] = FieldValue.increment(fu);
    }
    if (mu.isNotEmpty) batch.update(col.doc(m.id), mu);
    if (m.hasJob && ju.isNotEmpty) batch.update(jobs.doc(m.jobId), ju);
    await batch.commit();
  }

  // Devam eden işler canlı; bitenler seçili geçmiş aralığından
  static Stream<List<MJob>> jobsStream(MGroup g) {
    List<MJob> conv(QuerySnapshot<Map<String, dynamic>> s) => s.docs.map((d) => MJob.fromDoc(d)).where((j) => recOwns(g, j.machineId, j.group)).toList();
    final active = jobs.where('status', whereIn: ['acik', 'gun_bitti']).snapshots().map(conv);
    final done = jobs.where('finishedAt', isGreaterThanOrEqualTo: histFrom()).snapshots().map((s) => conv(s).where((j) => j.finished).toList());
    return mergeLists<MJob>([active, done], (j) => j.id).map((l) {
      l.sort((a, b) => (b.startedAt ?? DateTime(2000)).compareTo(a.startedAt ?? DateTime(2000)));
      return l;
    });
  }

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
  final MGroup group;
  const MachineHome({super.key, required this.me, this.nav, required this.group});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bind · ${group.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text('${me.name} · ${me.roleLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Arızalar',
            icon: const Icon(Icons.build_circle_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MFaultsPage(group: group))),
          ),
          IconButton(
            tooltip: 'Sipariş arşivi',
            icon: const Icon(Icons.inventory_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MachineJobsPage(group: group))),
          ),
          IconButton(
            tooltip: 'Rapor ve Excel',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MachineReportPage(group: group))),
          ),
          if (canMachineManage(me, group))
            IconButton(
              tooltip: 'Makineler, nedenler, vardiyalar',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MachineSettingsPage(group: group))),
            ),
          ...commonActions(me),
        ],
      ),
      bottomNavigationBar: nav,
      body: MachineLive(key: ValueKey('live-${group.key}'), group: group),
    );
  }
}

class MachineLive extends StatefulWidget {
  final MGroup group;
  const MachineLive({super.key, required this.group});

  @override
  State<MachineLive> createState() => _MachineLiveState();
}

// Canlı ekran filtreleri (web paneldeki gibi tek tuş)
const Map<String, String> kLiveFilters = {'tumu': 'Tümü', 'ariza': 'Arızalı', 'durus': 'Duruşta', 'calisan': 'Çalışan', 'kapali': 'Kapalı'};
bool liveFilterOk(String f, LineMachine m) {
  switch (f) {
    case 'ariza':
      return m.hasFault || m.state == 'ariza' || m.state == kFaultWaitKey;
    case 'durus':
      return !m.running && !m.off;
    case 'calisan':
      return m.running;
    case 'kapali':
      return m.off;
  }
  return true;
}

class _MachineLiveState extends State<MachineLive> {
  String _filter = 'tumu';
  late final DateTime _from = dayStart(DateTime.now()).subtract(const Duration(days: 2));
  MGroup get g => widget.group;
  late final Stream<List<MLog>> _logs = MachineOps.logsSince(g, _from);
  late final Stream<List<MEntry>> _entries = MachineOps.entriesSince(g, _from);
  late final Stream<List<LineMachine>> _machines = MachineOps.machinesStream(g);
  late final Stream<List<MReason>> _reasons = MachineOps.reasonsStream(g);
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
                canMachineManage(currentUser, g)
                    ? 'Henüz makine eklenmedi.\nSağ üstteki ayar simgesinden makineleri ekleyin.'
                    : 'Size atanmış ${g.lineLower} içinde makine yok. Admin size ${g.lineLower} atadığında makineler burada görünecek.',
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
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final e in kLiveFilters.entries)
                              ChoiceChip(
                                label: Text('${e.value} (${machines.where((x) => liveFilterOk(e.key, x)).length})'),
                                selected: _filter == e.key,
                                showCheckmark: false,
                                selectedColor: e.key == 'ariza' ? const Color(0xFFC92A2A) : kDark,
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _filter == e.key ? Colors.white : (e.key == 'ariza' ? const Color(0xFFC92A2A) : kDark),
                                ),
                                side: BorderSide(color: e.key == 'ariza' ? const Color(0xFFC92A2A) : const Color(0xFFCED4DA)),
                                onSelected: (_) => setState(() => _filter = e.key),
                              ),
                          ]),
                          const SizedBox(height: 4),
                        ];
                        final shown = machines.where((x) => liveFilterOk(_filter, x)).toList();
                        if (shown.isEmpty) {
                          children.add(Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_filter == 'ariza' ? 'Şu an arızalı makine yok.' : 'Bu filtrede makine yok.',
                                textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 15)),
                          ));
                        }
                        for (final m in shown) {
                          if (m.line != lastLine) {
                            lastLine = m.line;
                            children.add(Padding(
                              padding: const EdgeInsets.fromLTRB(2, 6, 0, 6),
                              child: Text(m.line.isEmpty ? g.noLine : m.line, style: const TextStyle(fontWeight: FontWeight.w700, color: kMuted)),
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
    final enter = canMachineEnter(currentUser, m.grp);
    final tech = m.hasFault && canTechSee(currentUser);
    return Card(
      margin: EdgeInsets.zero,
      color: m.off ? const Color(0xFFF8F9FA) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enter
            ? () => showMachineSheet(context, m, reasons)
            : (tech ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MFaultDetailPage(faultId: m.faultId))) : null),
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
            if (m.hasFault)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFFFF5F5), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFFC9C9))),
                child: Row(children: [
                  const Icon(Icons.build_circle, color: Color(0xFFC92A2A), size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Arıza: ${kMFaultStatus[m.faultStatus] ?? m.faultStatus}${m.faultAssignee.isEmpty ? '' : ' · ${m.faultAssignee}'}',
                        style: const TextStyle(color: Color(0xFFC92A2A), fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            const SizedBox(height: 6),
            if (m.hasJob) ...[
              Text('Sipariş ${m.orderNo} · ${m.productCode}${m.jobStatus == 'gun_bitti' ? ' · gün bitti' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${m.peopleText} · bu sipariş: ${m.jobQtyText}', style: const TextStyle(fontSize: 13)),
              if (m.jobFireText.isNotEmpty)
                Text('Fire: ${m.jobFireText}', style: const TextStyle(fontSize: 13, color: Color(0xFFC92A2A))),
            ] else
              const Text('Aktif sipariş yok', style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
            if (!m.off || (st?.tracked ?? 0) > 0)
              Text(
                'Bu vardiya: verim %${(st?.efficiency ?? 0).toStringAsFixed(0)} · çalışma ${fmtSec(st?.run ?? 0)} · duruş ${fmtSec(st?.stopTotal ?? 0)} · üretim ${st?.qtyText ?? '—'}${(st?.hasFire ?? false) ? ' · ${st!.fireTxt}' : ''}',
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
                  ? 'Sipariş ${m.orderNo} · ${m.productCode} · ${m.peopleText} · ${m.jobQtyText}${m.jobFireText.isEmpty ? '' : ' · ${m.jobFireText}'}'
                  : 'Şu an: ${m.stateLabel} · aktif sipariş yok',
              style: const TextStyle(color: kMuted),
            ),
            if (m.hasFault) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFFF5F5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFC9C9))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Açık arıza: ${kMFaultStatus[m.faultStatus] ?? m.faultStatus}${m.faultAssignee.isEmpty ? '' : ' · ${m.faultAssignee}'}',
                      style: const TextStyle(color: Color(0xFFC92A2A), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (m.faultStatus == 'onay' && canApproveFault(currentUser, m.grp, m.faultByUid)) ...[
                    Row(children: [
                      Expanded(child: _actBtn(c, 'f_onay', 'Onayla, makine çalışsın', Icons.check_circle, kGreen)),
                      const SizedBox(width: 8),
                      Expanded(child: _actBtn(c, 'f_red', 'Giderilmedi', Icons.cancel, const Color(0xFFC92A2A))),
                    ]),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(c, 'f_detay'),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Arıza detayı ve yorumlar'),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Sipariş', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (!m.hasJob) _actBtn(c, 'yeni', 'Yeni sipariş başlat', Icons.play_arrow, kGreen),
            if (m.hasJob && m.jobStatus != 'gun_bitti') ...[
              Row(children: [
                Expanded(child: _actBtn(c, 'uretim', 'Üretim / fire gir', Icons.add, kOrange)),
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
              Row(children: [
                Expanded(
                  child: TextButton.icon(
                      onPressed: () => Navigator.pop(c, 'duzenle'), icon: const Icon(Icons.edit, size: 18), label: const Text('Sipariş no / ürün kodu düzelt')),
                ),
                Expanded(
                  child: TextButton.icon(
                      onPressed: () => Navigator.pop(c, 'gorsel'), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('Sipariş görselleri')),
                ),
              ]),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(c, 'notlar'),
              icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
              label: Text(m.hasJob ? 'Notlar · siparişe not ekle' : 'Notlar · makineye not ekle'),
            ),
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
        if (v != null) await run(() => MachineOps.setPeople(m, v[0], v[1], v[2]), 'Kişi sayısı güncellendi');
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
        if (v != null) await run(() => MachineOps.startDay(m, v[0], v[1], v[2]), 'Güne başlandı');
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
    case 'notlar':
      {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotesPage(ref: NoteRef.machine(m))));
        return;
      }
    case 'gorsel':
      {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => JobPhotosPage(jobId: m.jobId, orderNo: m.orderNo, group: m.grp)));
        return;
      }
    case 'f_detay':
      {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MFaultDetailPage(faultId: m.faultId)));
        return;
      }
    case 'f_onay':
    case 'f_red':
      {
        final f = await MFaultOps.load(m.faultId);
        if (f == null || !context.mounted) return;
        if (picked == 'f_onay') {
          await approveFaultFlow(context, f);
        } else {
          await rejectFaultFlow(context, f);
        }
        return;
      }
  }
  if (picked is MReason) {
    if (picked.fault && !m.hasFault) {
      await reportFaultFlow(context, m, picked, note.text.trim());
      return;
    }
    if (picked.key == kRunKey && m.hasFault) {
      if (!context.mounted) return;
      final go = await confirm(context, 'Açık arıza kaydı var',
          'Makine "Çalışıyor" yapılırsa arıza kaydı açık kalır. Arıza giderildiyse teknisyenin "Bitti" demesi ve arızayı açanın onaylaması gerekir. Yine de çalışıyor yapılsın mı?',
          'Evet, çalışıyor');
      if (!go) return;
    }
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

// Kişi sayıları: [çalışan, günlükçü, operatör] (operatör yalnız Üretim makinelerinde sorulur)
Future<List<int>?> askPeople(BuildContext context, LineMachine m, String title) async {
  final w = TextEditingController(text: '${m.workers}');
  final dl = TextEditingController(text: '${m.daily}');
  final op = TextEditingController(text: '${m.operators}');
  final ops = m.grp.operators;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Row(children: [
        Expanded(child: TextField(controller: w, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Çalışan'))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: dl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Günlükçü'))),
        if (ops) ...[
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: op, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Operatör'))),
        ],
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
  final oi = ops ? int.tryParse(op.text.trim().isEmpty ? '0' : op.text.trim()) : 0;
  if (wi == null || di == null || oi == null) {
    toast('Kişi sayılarını rakamla girin.');
    return null;
  }
  return [wi, di, oi];
}

Future<void> askStartJob(BuildContext context, LineMachine m) async {
  final order = TextEditingController();
  final code = TextEditingController();
  final w = TextEditingController(text: m.workers > 0 ? '${m.workers}' : '');
  final dl = TextEditingController(text: '${m.daily}');
  final op = TextEditingController(text: '${m.operators}');
  final ops = m.grp.operators;
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
              if (ops) ...[
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: op, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Operatör'))),
              ],
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
  final oi = ops ? int.tryParse(op.text.trim().isEmpty ? '0' : op.text.trim()) : 0;
  if (order.text.trim().isEmpty || code.text.trim().isEmpty) {
    toast('Sipariş numarası ve ürün kodu gerekli.');
    return;
  }
  if (wi == null || di == null || oi == null) {
    toast('Kişi sayılarını rakamla girin.');
    return;
  }
  try {
    await MachineOps.startJob(m, order.text.trim(), code.text.trim(), unit, wi, di, oi);
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
  final fpC = TextEditingController();
  final fuC = TextEditingController();
  final note = TextEditingController();
  String unit = m.unit;
  String fpUnit = m.unit;
  String fuUnit = m.unit;
  Widget unitSel(String v, void Function(String) on) => SegmentedButton<String>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [for (final e in kMUnits.entries) ButtonSegment<String>(value: e.key, label: Text(e.value))],
        selected: {v},
        onSelectionChanged: (x) => on(x.first),
      );
  Widget qtyRow(TextEditingController c, String label, String u, void Function(String) on, {bool focus = false}) => Row(children: [
        Expanded(
          child: TextField(
            controller: c,
            autofocus: focus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        unitSel(u, on),
      ]);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('Üretim / fire gir · ${m.name}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sipariş ${m.orderNo} · ${m.productCode} · şu ana kadar: ${m.jobQtyText}${m.jobFireText.isEmpty ? '' : ' · ${m.jobFireText}'}',
                style: const TextStyle(color: kMuted)),
            const SizedBox(height: 12),
            qtyRow(qty, 'Üretim miktarı', unit, (v) => setS(() => unit = v), focus: true),
            const SizedBox(height: 12),
            qtyRow(fpC, 'Paket fire', fpUnit, (v) => setS(() => fpUnit = v)),
            const SizedBox(height: 12),
            qtyRow(fuC, 'Ürün fire', fuUnit, (v) => setS(() => fuUnit = v)),
            const SizedBox(height: 6),
            const Text('Sadece doldurduğunuz alanlar kaydedilir. Yalnız fire de girebilirsiniz.', style: TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', isDense: true)),
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
  double? parseQ(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    final v = double.tryParse(t);
    return (v == null || v < 0) ? null : v;
  }

  final v = parseQ(qty), fp = parseQ(fpC), fu = parseQ(fuC);
  if (v == null || fp == null || fu == null) {
    toast('Miktarları rakamla girin.');
    return;
  }
  if (v == 0 && fp == 0 && fu == 0) {
    toast('Üretim ya da fire miktarı girin.');
    return;
  }
  try {
    await MachineOps.addProduction(m, v, unit, note.text.trim(), fp: fp, fpUnit: fpUnit, fu: fu, fuUnit: fuUnit);
    final parts = <String>[
      if (v > 0) '+${fmtQty(v)} ${unit == 'kg' ? 'kg' : 'adet'}',
      if (fp > 0) 'paket fire ${fmtQty(fp)} ${fpUnit == 'kg' ? 'kg' : 'adet'}',
      if (fu > 0) 'ürün fire ${fmtQty(fu)} ${fuUnit == 'kg' ? 'kg' : 'adet'}',
    ];
    toast('${m.name}: ${parts.join(' · ')}');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

// ---------------------------------------------------------------------------
// Rapor ve Excel
// ---------------------------------------------------------------------------

class MachineReportPage extends StatefulWidget {
  final MGroup group;
  const MachineReportPage({super.key, required this.group});

  @override
  State<MachineReportPage> createState() => _MachineReportPageState();
}

class _MachineReportPageState extends State<MachineReportPage> {
  MGroup get g => widget.group;
  DateTime _from = dayStart(DateTime.now());
  DateTime _to = dayStart(DateTime.now());
  List<MShift> _shifts = List<MShift>.from(kDefaultShifts);
  int _shiftIdx = 0; // _shifts.length = özel
  MShift _custom = const MShift('Özel', '08:00', '16:00');
  String _line = '';
  List<MLog>? _logs;
  List<MEntry> _entries = [];
  List<MFault> _faults = [];
  List<MNote> _notes = [];
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
      final allM = ms.docs.map((d) => LineMachine.fromDoc(d)).toList();
      rememberMachineGroups(allM);
      _machines = MachineOps._sorted(filterVisible<LineMachine>(currentUser, g, allM.where((m) => g.owns(m.group)), (m) => m.line));
      final w = _wins;
      if (w.isEmpty) {
        _logs = [];
        _entries = [];
      } else {
        final end = w.last.e.isAfter(DateTime.now()) ? DateTime.now().add(const Duration(minutes: 1)) : w.last.e;
        _logs = await MachineOps.logsBetween(g, w.first.s, end);
        _entries = await MachineOps.entriesBetween(g, w.first.s, end);
        try {
          _faults = await MFaultOps.between(g, w.first.s, end);
        } catch (_) {
          _faults = [];
        }
        try {
          _notes = await NotesOps.between(g.key, w.first.s, end);
        } catch (_) {
          _notes = [];
        }
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
    final list = stats.values.where((s) => s.hasData).toList()..sort((a, b) => '${a.line}${a.name}'.compareTo('${b.line}${b.name}'));
    final lines = _machines.map((m) => m.line).toSet().toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text('${g.title} · rapor'), actions: [
        IconButton(
          tooltip: "Excel'e aktar",
          icon: const Icon(Icons.download),
          onPressed: _logs == null
              ? null
              : () {
                  final ids = _visibleMachines.map((m) => m.id).toSet();
                  exportMachineExcel(g, _visibleMachines, _fLogs, _fEntries, wins, _shift,
                      faults: _faults.where((x) => ids.contains(x.machineId)).toList(), notes: _notes.where((x) => ids.contains(x.machineId)).toList());
                },
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
            decoration: InputDecoration(labelText: g.lineLabel, isDense: true),
            items: [
              DropdownMenuItem<String>(value: '', child: Text(g == kUretim ? 'Tüm bölgeler' : 'Tüm hatlar')),
              for (final l in lines) DropdownMenuItem<String>(value: l, child: Text(l.isEmpty ? g.noLine : l)),
            ],
            onChanged: (v) => setState(() => _line = v ?? ''),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Her gün için ${_shift.times} aralığı raporlanır (${wins.length} vardiya). Toplam duruş = duruş nedenlerinin toplamı. '
          'Verimlilik = çalışma ÷ (çalışma + toplam duruş); kapalı süre verime girmez. Her durum kaydı bir sonraki kaydın başladığı anda biter, hiçbir süre iki kez sayılmaz.',
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
                Text('Çalışılan süre ${fmtMin(statMin(s).tracked)} = çalışma ${fmtMin(statMin(s).run)} + toplam duruş ${fmtMin(statMin(s).stop)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('Üretim ${s.qtyText}', style: const TextStyle(fontSize: 13)),
                Text(
                    '${s.shifts} vardiya çalışıldı${s.skipped > 0 ? ' (${s.skipped} kapalı vardiya sayılmadı)' : ''} · vardiya süresi ${fmtMin(statMin(s).span)}'
                    '${statMin(s).off > 0 ? ' · ara kapalı ${fmtMin(statMin(s).off)}' : ''}${statMin(s).none > 0 ? ' · kayıt yok ${fmtMin(statMin(s).none)}' : ''}',
                    style: const TextStyle(color: kMuted, fontSize: 12)),
                if (s.hasFire) Text('Fire: ${s.fireTxt}', style: const TextStyle(color: Color(0xFFC92A2A), fontSize: 13, fontWeight: FontWeight.w600)),
                if (s.products.isNotEmpty) Text('Ürünler: ${s.products.join(', ')}', style: const TextStyle(color: kMuted, fontSize: 13)),
                for (final e in (s.stops.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      Expanded(child: Text(e.key)),
                      Text(fmtMin(statMin(s).stops[e.key] ?? 0), style: const TextStyle(fontWeight: FontWeight.w600)),
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

// Sipariş bazlı satır (makine + sipariş; sipariş boşsa "siparişsiz")
class _JobAgg {
  final String machineId;
  final String jobId;
  final String orderNo;
  final String productCode;
  final MStat st;
  int ppl = 0;
  _JobAgg(this.machineId, this.jobId, this.orderNo, this.productCode) : st = MStat(jobId, '', '');
}

Future<void> exportMachineExcel(MGroup g, List<LineMachine> machines, List<MLog> logs, List<MEntry> entries, List<TimeWin> wins, MShift shift,
    {List<MFault> faults = const [], List<MNote> notes = const []}) async {
  try {
    if (wins.isEmpty) {
      toast('Seçilen aralıkta vardiya yok.');
      return;
    }
    toast('Makine raporu hazırlanıyor…');
    final now = DateTime.now();
    final stats = computeMStats(machines, logs, entries, wins);
    final list = stats.values.where((s) => s.hasData).toList()..sort((a, b) => '${a.line}${a.name}'.compareTo('${b.line}${b.name}'));
    final hl = g.lineLabel;
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
    final fireHead = [t('Paket fire (adet)'), t('Paket fire (kg)'), t('Ürün fire (adet)'), t('Ürün fire (kg)')];
    List<xl.CellValue?> fireCells(MStat s) => [dbl(s.fpAdet), dbl(s.fpKg), dbl(s.fuAdet), dbl(s.fuKg)];

    final mm = <String, MStatMin>{for (final s in list) s.id: statMin(s)};
    sh.appendRow(<xl.CellValue?>[t('${g.title} raporu'), t('${fmtDay(wins.first.day)} – ${fmtDay(wins.last.day)}'), t('Vardiya: ${shift.label}')]);
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[
      t('Makine'), t(hl), t('Verimlilik %'), t('Çalışılan süre (dk)'), t('Çalışma (dk)'), t('Toplam duruş (dk)'),
      for (final l in lab) t('$l (dk)'),
      t('Üretim (adet)'), t('Üretim (kg)'), ...fireHead, t('Ürünler'),
      t('Çalışılan vardiya'), t('Kapalı vardiya (sayılmadı)'), t('Vardiya süresi (dk)'), t('Ara kapalı (dk)'), t('Kayıt yok (dk)'),
    ]);
    for (final s in list) {
      final m = mm[s.id]!;
      sh.appendRow(<xl.CellValue?>[
        t(s.name), t(s.line), dbl(s.efficiency), n(m.tracked), n(m.run), n(m.stop),
        for (final l in lab) n(m.stops[l] ?? 0),
        dbl(s.qtyAdet), dbl(s.qtyKg), ...fireCells(s), t(s.products.join(', ')),
        n(s.shifts), n(s.skipped), n(m.span), n(m.off), n(m.none),
      ]);
    }
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[
      t('Çalışılan süre = Çalışma + Toplam duruş. Toplam duruş = kapalı hariç tüm duruş nedenlerinin toplamı. Verimlilik = Çalışma ÷ Çalışılan süre.')
    ]);
    sh.appendRow(<xl.CellValue?>[
      t('Makinenin baştan sona kapalı olduğu vardiyalar (hafta sonu, çalışılmayan gün) hiç sayılmaz. Çalışılan vardiyalarda: Vardiya süresi = Çalışılan süre + Ara kapalı + Kayıt yok.')
    ]);
    sh.appendRow(<xl.CellValue?>[
      t('Her durum kaydı en geç aynı makinedeki bir sonraki kaydın başladığı anda biter; hiçbir süre iki kez sayılmaz. Vardiya bazlı ve Sipariş bazlı sayfaların toplamı bu sayfayla aynıdır.')
    ]);

    // Vardiya bazlı: her makinenin vardiya satırları toplamı Özet ile aynı
    byShift.appendRow(<xl.CellValue?>[
      t('Tarih'), t('Vardiya'), t('Makine'), t(hl), t('Ara kapalı (dk)'), t('Çalışma (dk)'), t('Toplam duruş (dk)'), t('Verimlilik %'), t('Üretim (adet)'), t('Üretim (kg)'),
      ...fireHead, t('En çok duruş nedeni'),
    ]);
    final perWin = [for (final w in wins) computeMStats(machines, logs, entries, [w])];
    for (final s in list) {
      final m = mm[s.id]!;
      final rows = <int>[];
      for (var i = 0; i < wins.length; i++) {
        final x = perWin[i][s.id];
        if (x != null && (x.hasData || x.off > 0)) rows.add(i);
      }
      final runR = lrRound([for (final i in rows) perWin[i][s.id]!.run / 60], m.run);
      final stopR = lrRound([for (final i in rows) perWin[i][s.id]!.stopTotal / 60], m.stop);
      final offR = lrRound([for (final i in rows) perWin[i][s.id]!.off / 60], m.off);
      for (var k = 0; k < rows.length; k++) {
        final w = wins[rows[k]];
        final x = perWin[rows[k]][s.id]!;
        final top = x.stops.entries.isEmpty ? null : (x.stops.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
        byShift.appendRow(<xl.CellValue?>[
          t(fmtDay(w.day)), t('${_hmText(w.s.hour * 60 + w.s.minute)}–${_hmText(w.e.hour * 60 + w.e.minute)}'), t(s.name), t(s.line),
          n(offR[k]), n(runR[k]), n(stopR[k]), dbl(x.efficiency), dbl(x.qtyAdet), dbl(x.qtyKg), ...fireCells(x),
          t(top == null ? '' : '${top.key} (${mins(top.value)} dk)'),
        ]);
      }
    }

    prod.appendRow(<xl.CellValue?>[
      t('Makine'), t(hl), t('Tarih saat'), t('İşlem'), t('Sipariş no'), t('Ürün kodu'), t('Miktar'), t('Birim'), t('Paket fire'), t('Birim'), t('Ürün fire'), t('Birim'),
      t('Çalışan'), t('Günlükçü'), if (g.operators) t('Operatör'), t('Toplam kişi'), t('Giren'), t('Not / değişiklik'),
    ]);
    final es = entries.where((e) => e.t != null && wins.any((w) => w.contains(e.t!))).toList()
      ..sort((a, b) {
        final c = '${a.line}${a.machineName}'.compareTo('${b.line}${b.machineName}');
        return c != 0 ? c : a.t!.compareTo(b.t!);
      });
    for (final e in es) {
      prod.appendRow(<xl.CellValue?>[
        t(e.machineName), t(e.line), t(fmtFull(e.t)), t(e.kindLabel), t(e.orderNo), t(e.productCode),
        e.isProd && e.qty > 0 ? dbl(e.qty) : null, t(e.isProd && e.qty > 0 ? (kMUnits[e.unit] ?? e.unit) : ''),
        e.fp > 0 ? dbl(e.fp) : null, t(e.fp > 0 ? (kMUnits[e.fpUnit] ?? e.fpUnit) : ''),
        e.fu > 0 ? dbl(e.fu) : null, t(e.fu > 0 ? (kMUnits[e.fuUnit] ?? e.fuUnit) : ''),
        n(e.workers), n(e.daily), if (g.operators) n(e.operators), n(e.workers + e.daily + e.operators), t(e.by), t(e.text),
      ]);
    }

    // Durum hareketleri: vardiya içindeki düzeltilmiş süreleriyle (kapalı dahil)
    det.appendRow(<xl.CellValue?>[
      t('Makine'), t(hl), t('Durum'), t('Başlangıç'), t('Bitiş'), t('Vardiya içindeki süre (dk)'), t('Sipariş no'), t('Ürün kodu'), t('Çalışan'), t('Günlükçü'),
      if (g.operators) t('Operatör'), t('Giren'), t('Not'),
    ]);
    final segs = normLogs(machines, logs, now).map((x) => MapEntry(x, x.secIn(wins))).where((x) => x.value > 0).toList()
      ..sort((a, b) {
        final c = '${a.key.l.line}${a.key.l.machineName}'.compareTo('${b.key.l.line}${b.key.l.machineName}');
        return c != 0 ? c : a.key.s.compareTo(b.key.s);
      });
    for (final x in segs) {
      final l = x.key.l;
      final open = l.end == null && !x.key.e.isBefore(now.subtract(const Duration(seconds: 1)));
      det.appendRow(<xl.CellValue?>[
        t(l.machineName), t(l.line), t(l.label.isEmpty ? l.state : l.label), t(fmtFull(x.key.s)), t(open ? 'devam ediyor' : fmtFull(x.key.e)), dbl(x.value / 60),
        t(l.orderNo), t(l.productCode), n(l.workers), n(l.daily), if (g.operators) n(l.operators), t(l.by), t(l.note),
      ]);
    }

    // Sipariş bazlı: siparişsiz süreler de ayrı satırda; her makinenin satır toplamı Özet ile aynı
    final xl.Sheet byJob = excel['Sipariş bazlı'];
    byJob.appendRow(<xl.CellValue?>[
      t('Makine'), t(hl), t('Sipariş no'), t('Ürün kodu'), t('Çalışma (dk)'), t('Toplam duruş (dk)'), t('Verimlilik %'), t('Üretim (adet)'), t('Üretim (kg)'), ...fireHead,
      t('Kişi (son)'), t('En çok duruş nedeni'),
    ]);
    final jobs = <String, _JobAgg>{};
    for (final x in segs) {
      final l = x.key.l;
      if (l.state == kOffKey) continue;
      final k = jobs.putIfAbsent('${l.machineId}|${l.jobId}', () => _JobAgg(l.machineId, l.jobId, l.orderNo, l.productCode));
      if (l.state == kRunKey) {
        k.st.run += x.value;
      } else {
        final lb = l.label.isEmpty ? l.state : l.label;
        k.st.stops[lb] = (k.st.stops[lb] ?? 0) + x.value;
      }
      if (l.jobId.isNotEmpty) k.ppl = l.workers + l.daily + l.operators;
    }
    for (final e in es) {
      if (!e.isProd) continue;
      final k = jobs.putIfAbsent('${e.machineId}|${e.jobId}', () => _JobAgg(e.machineId, e.jobId, e.orderNo, e.productCode));
      if (e.unit == 'kg') {
        k.st.qtyKg += e.qty;
      } else {
        k.st.qtyAdet += e.qty;
      }
      k.st.addFire(e);
    }
    for (final s in list) {
      final m = mm[s.id]!;
      final rows = jobs.values.where((k) => k.machineId == s.id).toList()..sort((a, b) => (a.jobId.isEmpty ? 1 : 0).compareTo(b.jobId.isEmpty ? 1 : 0));
      final runR = lrRound([for (final k in rows) k.st.run / 60], m.run);
      final stopR = lrRound([for (final k in rows) k.st.stopTotal / 60], m.stop);
      for (var i = 0; i < rows.length; i++) {
        final k = rows[i];
        final top = k.st.stops.entries.isEmpty ? null : (k.st.stops.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
        byJob.appendRow(<xl.CellValue?>[
          t(s.name), t(s.line), t(k.jobId.isEmpty ? '(siparişsiz)' : k.orderNo), t(k.jobId.isEmpty ? '' : k.productCode), n(runR[i]), n(stopR[i]), dbl(k.st.efficiency),
          dbl(k.st.qtyAdet), dbl(k.st.qtyKg), ...fireCells(k.st), k.jobId.isEmpty ? null : n(k.ppl), t(top == null ? '' : '${top.key} (${mins(top.value)} dk)'),
        ]);
      }
    }

    // Arızalar (seçilen aralıkta bildirilenler)
    final xl.Sheet fs = excel['Arızalar'];
    fs.appendRow(<xl.CellValue?>[for (final h in kFaultExcelHead(hl)) t(h)]);
    for (final f in faults.toList()..sort((a, b) => (a.createdAt ?? DateTime(2000)).compareTo(b.createdAt ?? DateTime(2000)))) {
      fs.appendRow(faultExcelRow(f));
    }

    // Notlar (seçilen aralıkta yazılanlar)
    final xl.Sheet ns = excel['Notlar'];
    ns.appendRow(<xl.CellValue?>[t('Tarih saat'), t('Makine'), t(hl), t('Sipariş no'), t('Ürün kodu'), t('Not'), t('Yazan')]);
    for (final x in notes) {
      ns.appendRow(<xl.CellValue?>[t(fmtFull(x.t)), t(x.machineName), t(x.line), t(x.orderNo), t(x.productCode), t(x.text), t(x.by)]);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final d0 = wins.first.day;
    await shareBytes(bytes, '${g == kUretim ? 'uretim_makineleri' : 'sargi_makineleri'}_raporu_${d0.year}${two(d0.month)}${two(d0.day)}.xlsx', '${g.title} raporu');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}

// ---------------------------------------------------------------------------
// Ayarlar: makineler, duruş nedenleri, vardiyalar
// ---------------------------------------------------------------------------

class MachineSettingsPage extends StatelessWidget {
  final MGroup group;
  const MachineSettingsPage({super.key, required this.group});

  Future<void> _machineDialog(BuildContext context, LineMachine? m, int nextOrder, List<String> lines) async {
    final name = TextEditingController(text: m?.name ?? '');
    final line = TextEditingController(text: m?.line ?? (group.defaultLines.isNotEmpty ? group.defaultLines.first : ''));
    final chips = <String>{...group.defaultLines, ...lines.where((x) => x.isNotEmpty)}.toList();
    final order = TextEditingController(text: '${m?.order ?? nextOrder}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(m == null ? 'Makine ekle' : 'Makineyi düzenle'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Makine adı')),
            const SizedBox(height: 10),
            TextField(
                controller: line,
                decoration: InputDecoration(labelText: group == kUretim ? 'Bölge (ör. Zemin kat, 1. kat)' : 'Hat (ör. Draje paket hattı)')),
            if (chips.isNotEmpty)
              Wrap(spacing: 6, children: [
                for (final l in chips) ActionChip(label: Text(l), onPressed: () => line.text = l),
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
        await MachineOps.addMachine(group, name.text.trim(), line.text.trim(), o);
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
    bool fault = r?.fault ?? false;
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Arıza kaydı açar'),
              subtitle: const Text('Seçilince açıklama istenir; teknik hizmet atama, başlama, bitiş ve onay akışı başlar'),
              value: fault,
              onChanged: (v) => setS(() => fault = v),
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
      nl.add(MReason('n${DateTime.now().millisecondsSinceEpoch}', c.text.trim(), alarm, fault));
    } else {
      nl[index!] = MReason(r.key, c.text.trim(), alarm, fault);
    }
    try {
      await MachineOps.saveReasons(group, nl);
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
      appBar: AppBar(title: Text('${group.title} · ayarlar')),
      body: StreamBuilder<List<LineMachine>>(
        stream: MachineOps.machinesStream(group, all: true),
        builder: (context, ms) {
          final machines = ms.data ?? const <LineMachine>[];
          final lines = machines.map((m) => m.line).toSet().toList()..sort();
          return StreamBuilder<List<MReason>>(
            stream: MachineOps.reasonsStream(group),
            builder: (context, rs) {
              final reasons = rs.data ?? kDefaultMReasons;
              return StreamBuilder<List<MShift>>(
                stream: MachineOps.shiftsStream(),
                builder: (context, ss) {
                  final shifts = ss.data ?? kDefaultShifts;
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    _title('Makineler', 'Kullanıcıların hangi ${group.lineLower} bilgilerini göreceğini Kullanıcılar sayfasından atayın.'),
                    for (final m in machines)
                      _row(
                        title: Text(m.name),
                        subtitle: '${m.line.isEmpty ? group.noLine : m.line} · sıra ${m.order}',
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
                    _title('Vardiyalar', 'Vardiyalar Sargı ve Üretim makinelerinde ortaktır. İlk sıradaki vardiya canlı ekranda kullanılır.'),
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
                    _title('Duruş nedenleri (${group.title})', '"Çalışıyor" ve "Kapalı / vardiya dışı" sabittir. Zil simgesi olanlar alarm gönderir.'),
                    for (var i = 0; i < reasons.length; i++)
                      _row(
                        leading: Icon(reasons[i].alarm ? Icons.notifications_active : Icons.notifications_off_outlined,
                            color: reasons[i].alarm ? const Color(0xFFC92A2A) : kMuted),
                        title: Text(reasons[i].label),
                        subtitle: '${reasons[i].alarm ? 'Alarm gönderir' : 'Alarm yok'}${reasons[i].fault ? ' · arıza kaydı açar' : ''}',
                        onEdit: () => _reasonDialog(context, reasons, i),
                        onDelete: () async {
                          if (!await confirm(context, 'Neden silinsin mi?', '"${reasons[i].label}" listeden kalkar. Geçmiş kayıtlar raporda kalır.', 'Sil')) return;
                          final nl = List<MReason>.from(reasons)..removeAt(i);
                          try {
                            await MachineOps.saveReasons(group, nl);
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
  final where = <String, Set<String>>{}; // hat / bölge -> hangi panel
  try {
    final s = await MachineOps.col.get();
    for (final d in s.docs) {
      final m = LineMachine.fromDoc(d);
      where.putIfAbsent(m.line, () => <String>{}).add(m.grp.title);
    }
    all = where.keys.toList()..sort();
  } catch (e) {
    toast('Hatlar okunamadı: $e');
    return;
  }
  if (all.isEmpty) {
    toast('Önce makine ayarlarından makine ve hat / bölge ekleyin.');
    return;
  }
  if (!context.mounted) return;
  final sel = u.lines.toSet();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('${u.name} · görebileceği hat / bölgeler'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hiçbiri seçilmezse tümünü görür. Admin ve "yönetir" yetkisi olanlar her zaman tümünü görür.',
                style: TextStyle(color: kMuted, fontSize: 12)),
            for (final l in all)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: sel.contains(l),
                title: Text(l.isEmpty ? 'Belirtilmemiş' : l),
                subtitle: Text(where[l]!.join(', '), style: const TextStyle(fontSize: 12)),
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
  final MGroup group;
  const MachineJobsPage({super.key, required this.group});

  @override
  State<MachineJobsPage> createState() => _MachineJobsPageState();
}

class _MachineJobsPageState extends State<MachineJobsPage> {
  MGroup get g => widget.group;
  String _q = '';
  int _filter = 0; // 0 tümü, 1 devam eden, 2 biten
  List<MJob> _last = const [];
  Stream<List<MJob>>? _s;
  int _sd = -1;
  final List<MJob> _extra = [];

  Stream<List<MJob>> get _stream {
    if (_s == null || _sd != gHistDays.value) {
      _sd = gHistDays.value;
      _s = MachineOps.jobsStream(g);
    }
    return _s!;
  }

  Future<void> _find() async {
    if (_q.trim().isEmpty) {
      toast('Önce arama kutusuna sipariş numarasını yazın.');
      return;
    }
    try {
      final r = await findInHistory('machineJobs', 'orderNo', _q);
      setState(() {
        _extra.removeWhere((x) => r.any((d) => d.id == x.id));
        _extra.addAll(r.map((d) => MJob.fromDoc(d)).where((j) => recOwns(g, j.machineId, j.group)));
      });
      toast(r.isEmpty ? 'Tüm geçmişte bu numarayla sipariş yok.' : '${r.length} kayıt bulundu');
    } catch (e) {
      toast('Arama yapılamadı: $e');
    }
  }

  List<MJob> _apply(List<MJob> all) {
    final q = _q.trim().toLowerCase();
    return filterVisible<MJob>(currentUser, g, all, (j) => j.line).where((j) => _filter == 0 || (_filter == 1 ? !j.finished : j.finished)).where((j) {
      if (q.isEmpty) return true;
      return '${j.orderNo} ${j.productCode} ${j.machineName} ${j.line} ${j.finishNote}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${g.title} · sipariş arşivi'), actions: [
        IconButton(tooltip: "Excel'e aktar", icon: const Icon(Icons.download), onPressed: () => exportJobsExcel(g, _last)),
      ]),
      body: ValueListenableBuilder<int>(
        valueListenable: gHistDays,
        builder: (context, _, __) => StreamBuilder<List<MJob>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final ids = snap.data!.map((j) => j.id).toSet();
          final list = _apply([...snap.data!, ..._extra.where((x) => !ids.contains(x.id))]);
          _last = list;
          return ListView(padding: const EdgeInsets.all(16), children: [
            HistBar(onFind: _find),
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
                      if (j.photoCount > 0) ...[
                        const Icon(Icons.photo_camera_outlined, size: 16, color: kMuted),
                        Text(' ${j.photoCount}  ', style: const TextStyle(color: kMuted, fontSize: 12)),
                      ],
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
                    if (j.fireTxt.isNotEmpty) Text('Fire: ${j.fireTxt}', style: const TextStyle(color: Color(0xFFC92A2A), fontSize: 13)),
                  ])),
                ),
              ),
          ]);
        },
      ),
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
          future: MachineOps.summaryAt(j.id, j.finished ? (j.finishedAt ?? DateTime.now()) : DateTime.now()),
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
                Text('Başlatan: ${j.by} · son kişi sayısı ${mGroupOf(j.group).peopleShort(j.workers, j.daily, j.operators)}'),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => JobPhotosPage(jobId: j.id, orderNo: j.orderNo, group: mGroupOf(j.group)))),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text('Sipariş görselleri (${j.photoCount})'),
                ),
                const SizedBox(height: 6),
                NotesButton(noteRef: NoteRef.job(j)),
                if (j.finishNote.isNotEmpty) Text('Bitiş notu: ${j.finishNote}', style: const TextStyle(fontStyle: FontStyle.italic)),
                const Divider(height: 20),
                Text('Üretim: ${j.qtyText}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (j.fireTxt.isNotEmpty) Text('Fire: ${j.fireTxt}', style: const TextStyle(color: Color(0xFFC92A2A), fontWeight: FontWeight.w600)),
                Text('Verimlilik: %${eff.toStringAsFixed(1)} · çalışma ${fmtSec(run)} · duruş ${fmtSec(stop)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (snap.connectionState == ConnectionState.waiting) const LinearProgressIndicator(),
                for (final e in (stops.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [Expanded(child: Text(e.key)), Text(fmtSec(e.value), style: const TextStyle(fontWeight: FontWeight.w600))]),
                  ),
                if (canMachineManage(currentUser, mGroupOf(j.group))) ...[
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

Future<void> exportJobsExcel(MGroup g, List<MJob> jobs) async {
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
      final Map<String, dynamic> sm = await MachineOps.summaryAt(j.id, j.finished ? (j.finishedAt ?? DateTime.now()) : DateTime.now());
      sums[j.id] = sm;
      labels.addAll((sm['stops'] as Map<String, int>).keys);
    }
    final lab = labels.toList()..sort();
    Map<String, List<MNote>> notes = {};
    try {
      notes = await NotesOps.byModule(g.key);
    } catch (_) {}
    sh.appendRow(<xl.CellValue?>[
      t('Sipariş no'), t('Ürün kodu'), t('Makine'), t(g.lineLabel), t('Durum'), t('Başlangıç'), t('Bitiş'), t('Gün sayısı'), t('Üretim (adet)'), t('Üretim (kg)'),
      t('Paket fire (adet)'), t('Paket fire (kg)'), t('Ürün fire (adet)'), t('Ürün fire (kg)'),
      t('Çalışma (dk)'), t('Duruş (dk)'), t('Verimlilik %'), for (final l in lab) t('$l (dk)'), t('Son çalışan'), t('Son günlükçü'), if (g.operators) t('Son operatör'), t('Başlatan'), t('Bitiş notu'), t('Notlar'),
    ]);
    for (final j in jobs) {
      final sm = sums[j.id]!;
      final run = sm['runSec'] as int;
      final st = sm['stops'] as Map<String, int>;
      final stop = st.values.fold(0, (a, b) => a + b);
      sh.appendRow(<xl.CellValue?>[
        t(j.orderNo), t(j.productCode), t(j.machineName), t(j.line), t(j.statusLabel), t(fmtFull(j.startedAt)), t(j.finished ? fmtFull(j.finishedAt) : ''),
        n(j.dayCount), dbl(j.qtyAdet), dbl(j.qtyKg), dbl(j.fpAdet), dbl(j.fpKg), dbl(j.fuAdet), dbl(j.fuKg), n(mins(run)), n(mins(stop)), dbl(run + stop == 0 ? 0 : run * 100 / (run + stop)),
        for (final l in lab) n(mins(st[l] ?? 0)), n(j.workers), n(j.daily), if (g.operators) n(j.operators), t(j.by), t(j.finishNote), t(NotesOps.joined(notes[j.id])),
      ]);
    }
    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final now = DateTime.now();
    await shareBytes(bytes, '${g == kUretim ? 'uretim' : 'sargi'}_siparis_arsivi_${now.year}${two(now.month)}${two(now.day)}.xlsx', '${g.title} sipariş arşivi');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}


// ---------------------------------------------------------------------------
// Sipariş görselleri (ürün görseli vb., sipariş başına en fazla kMaxPhotos)
// ---------------------------------------------------------------------------

class JobPhotosPage extends StatefulWidget {
  final String jobId;
  final String orderNo;
  final MGroup group;
  const JobPhotosPage({super.key, required this.jobId, required this.orderNo, required this.group});

  @override
  State<JobPhotosPage> createState() => _JobPhotosPageState();
}

class _JobPhotosPageState extends State<JobPhotosPage> {
  bool _busy = false;

  CollectionReference<Map<String, dynamic>> get _col => MachineOps.jobs.doc(widget.jobId).collection('photos');

  Future<void> _add(int count) async {
    if (count >= kMaxPhotos) {
      toast('En fazla $kMaxPhotos görsel eklenebilir.');
      return;
    }
    final b = await pickPhotoBytes(context);
    if (b == null) return;
    setState(() => _busy = true);
    try {
      final fields = await photoFields('machineJobs/${widget.jobId}', b);
      await _col.add({'i': DateTime.now().millisecondsSinceEpoch, ...fields, 'by': currentUser?.name ?? '', 't': Timestamp.now()});
      await MachineOps.jobs.doc(widget.jobId).update({'photoCount': FieldValue.increment(1)});
      toast('Görsel eklendi');
    } catch (e) {
      toast('Görsel eklenemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    if (!await confirm(context, 'Görsel silinsin mi?', 'Bu görsel siparişten kaldırılır.', 'Sil')) return;
    try {
      await d.reference.delete();
      await deleteStoredPhoto(d.data()['path']);
      await MachineOps.jobs.doc(widget.jobId).update({'photoCount': FieldValue.increment(-1)});
    } catch (e) {
      toast('Silinemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = canMachineEnter(currentUser, widget.group);
    final canDel = canMachineManage(currentUser, widget.group);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _col.orderBy('t').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return Scaffold(
          appBar: AppBar(title: Text('Sipariş ${widget.orderNo} · görseller (${docs.length}/$kMaxPhotos)')),
          floatingActionButton: canAdd && docs.length < kMaxPhotos
              ? FloatingActionButton.extended(
                  backgroundColor: kOrange,
                  foregroundColor: Colors.white,
                  onPressed: _busy ? null : () => _add(docs.length),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_a_photo),
                  label: const Text('Görsel ekle'),
                )
              : null,
          body: snap.hasError
              ? Center(child: Text('Hata: ${snap.error}'))
              : !snap.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : docs.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Henüz görsel yok. Ürün görseli, etiket, numune gibi fotoğrafları "Görsel ekle" ile ekleyin.',
                                textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, mainAxisSpacing: 8, crossAxisSpacing: 8),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final m = docs[i].data();
                            final url = (m['url'] ?? '').toString();
                            final data = (m['data'] ?? '').toString();
                            return GestureDetector(
                              onTap: () => openStoredImage(context, url, data),
                              onLongPress: canDel ? () => _delete(docs[i]) : null,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(fit: StackFit.expand, children: [
                                  storedImage(url, data),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      color: Colors.black45,
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Text('${m['by'] ?? ''} · ${fmtDT(tsToDate(m['t']))}',
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    ),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
        );
      },
    );
  }
}
