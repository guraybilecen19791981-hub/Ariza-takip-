part of 'main.dart';

// ---------------------------------------------------------------------------
// Arıza ekibi performans panosu (Sargı, Üretim makineleri ve Tesis ekipmanları)
// Zamanında atama %, zamanında varış %, ilk seferde çözüm %, makine kullanılabilirlik %
// Ekip performansı = zamanında atama, zamanında varış ve ilk seferde çözüm yüzdelerinin ortalaması.
// Parça bekleme süresi teknisyenin net onarım süresinden düşülür.
// ---------------------------------------------------------------------------

class FaultTargets {
  final int assignMin; // bildirimden atamaya hedef (dk)
  final int arriveMin; // atamadan "Başladım"a hedef (dk)
  const FaultTargets(this.assignMin, this.arriveMin);
  static DocumentReference<Map<String, dynamic>> get doc => db.collection('config').doc('faultTargets');
  static Future<FaultTargets> load() async {
    try {
      final s = await doc.get();
      final m = s.data() ?? <String, dynamic>{};
      return FaultTargets(_int(m['assignMin']) > 0 ? _int(m['assignMin']) : 10, _int(m['arriveMin']) > 0 ? _int(m['arriveMin']) : 15);
    } catch (_) {
      return const FaultTargets(10, 15);
    }
  }
}

const Map<String, String> kPerfGroups = {'': 'Tümü', 'sargi': 'Sargı makineleri', 'uretim': 'Üretim makineleri', 'tesis': 'Tesis ekipmanları'};

bool perfGroupOk(String g, String group, bool tesis) {
  if (g.isEmpty) return true;
  if (g == 'tesis') return tesis || group == 'tesis';
  return !tesis && group != 'tesis' && mGroupOf(group).key == g;
}

class _Pct {
  int ok = 0, all = 0;
  double? get v => all == 0 ? null : ok * 100 / all;
}

class TechPerf {
  final String name;
  int count = 0, helper = 0, closed = 0;
  final _Pct arrive = _Pct(), firstFix = _Pct();
  int arriveSum = 0, arriveN = 0, repairSum = 0, repairN = 0, partSum = 0;
  TechPerf(this.name);
  double? get perf {
    final l = [arrive.v, firstFix.v].whereType<double>().toList();
    return l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
  }
}

class FaultPerf {
  final _Pct assign = _Pct(), arrive = _Pct(), firstFix = _Pct();
  int count = 0, open = 0, noStop = 0, downSec = 0, repairSum = 0, repairN = 0, arriveSum = 0, arriveN = 0, partSec = 0, researchSec = 0;
  double? avail;
  final Map<String, TechPerf> techs = {};
  final Map<String, List<MFault>> byMachine = {};

  double? get team {
    final l = [assign.v, arrive.v, firstFix.v].whereType<double>().toList();
    return l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
  }

  static int _overlap(DateTime? a, DateTime? b, DateTime from, DateTime to) {
    if (a == null) return 0;
    final s = a.isAfter(from) ? a : from;
    final e0 = b ?? DateTime.now();
    final e = e0.isBefore(to) ? e0 : to;
    final d = e.difference(s).inSeconds;
    return d > 0 ? d : 0;
  }

  static FaultPerf calc(List<MFault> all, int machineCount, DateTime from, DateTime to, FaultTargets t) {
    final p = FaultPerf();
    final end = to.isAfter(DateTime.now()) ? DateTime.now() : to;
    for (final f in all) {
      if (f.cancelled || f.status == 'yonay') continue;
      p.count++;
      if (f.open) p.open++;
      if (f.noStop) p.noStop++;
      p.byMachine.putIfAbsent(f.machineId, () => <MFault>[]).add(f);
      // zamanında atama
      if (f.assignedAt != null || f.startedAt != null) {
        p.assign.all++;
        if (f.waitSec <= t.assignMin * 60) p.assign.ok++;
      } else if (f.open && f.waitSec > t.assignMin * 60) {
        p.assign.all++; // hâlâ atanmamış ve hedef süre geçti
      }
      // zamanında varış
      if (f.assignedAt != null && f.startedAt != null) {
        p.arrive.all++;
        if (f.arriveSec <= t.arriveMin * 60) p.arrive.ok++;
        p.arriveSum += f.arriveSec;
        p.arriveN++;
      }
      // ilk seferde çözüm
      if (f.status == 'kapandi') {
        p.firstFix.all++;
        if (f.rejectCount == 0) p.firstFix.ok++;
        p.repairSum += f.netRepairSec;
        p.repairN++;
      }
      p.partSec += f.partNow;
      p.researchSec += f.researchNow;
      if (!f.noStop) p.downSec += _overlap(f.createdAt, f.approvedAt, from, end);
      // teknisyen
      if (f.assigneeName.isNotEmpty) {
        final k = f.assigneeName.trim().toLowerCase(); // aynı kişi eski kayıtlarda uid'siz olabilir
        final tp = p.techs.putIfAbsent(k, () => TechPerf(f.assigneeName));
        tp.count++;
        if (f.assignedAt != null && f.startedAt != null) {
          tp.arrive.all++;
          if (f.arriveSec <= t.arriveMin * 60) tp.arrive.ok++;
          tp.arriveSum += f.arriveSec;
          tp.arriveN++;
        }
        if (f.status == 'kapandi') {
          tp.closed++;
          tp.firstFix.all++;
          if (f.rejectCount == 0) tp.firstFix.ok++;
          tp.repairSum += f.netRepairSec;
          tp.repairN++;
        }
        tp.partSum += f.partNow;
      }
      if (f.assignee2Name.isNotEmpty) {
        final k = f.assignee2Name.trim().toLowerCase();
        p.techs.putIfAbsent(k, () => TechPerf(f.assignee2Name)).helper++;
      }
    }
    final span = end.difference(from).inSeconds;
    if (machineCount > 0 && span > 0) p.avail = math.max(0, 100 - p.downSec * 100 / (machineCount * span));
    return p;
  }
}

String pctText(double? v) => v == null ? '—' : '%${v.toStringAsFixed(0)}';
Color pctColor(double? v) => v == null ? kMuted : (v >= 90 ? const Color(0xFF2B8A3E) : (v >= 75 ? const Color(0xFFD9480F) : const Color(0xFFC92A2A)));

class FaultPerfPage extends StatefulWidget {
  final MGroup? group;
  const FaultPerfPage({super.key, this.group});
  @override
  State<FaultPerfPage> createState() => _FaultPerfPageState();
}

class _FaultPerfPageState extends State<FaultPerfPage> {
  int _days = 7; // 1 = bugün
  late String _g = widget.group?.key ?? '';
  FaultTargets _t = const FaultTargets(10, 15);
  List<MFault> _all = [];
  List<LineMachine> _machines = [];
  bool _loading = true;

  DateTime get _from => dayStart(DateTime.now()).subtract(Duration(days: _days - 1));
  DateTime get _to => dayStart(DateTime.now()).add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _t = await FaultTargets.load();
      final ms = await MachineOps.col.get();
      _machines = ms.docs.map((d) => LineMachine.fromDoc(d)).toList();
      rememberMachineGroups(_machines);
      final s = await MFaultOps.col.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_from)).where('createdAt', isLessThan: Timestamp.fromDate(_to)).get();
      _all = s.docs.map((d) => MFault.fromDoc(d)).toList();
    } catch (e) {
      toast('Yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editTargets() async {
    final a = TextEditingController(text: '${_t.assignMin}');
    final b = TextEditingController(text: '${_t.arriveMin}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hedef süreler'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bildirimden atamaya (dk)')),
          TextField(controller: b, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Atamadan arızaya varışa (dk)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FaultTargets.doc.set({'assignMin': int.tryParse(a.text.trim()) ?? 10, 'arriveMin': int.tryParse(b.text.trim()) ?? 15});
      await _load();
    } catch (e) {
      toast('Kaydedilemedi: $e');
    }
  }

  Widget _kpi(String label, String value, Color color, String sub) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE3E6EA))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          Text(sub, style: const TextStyle(color: kMuted, fontSize: 11), maxLines: 2),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final list = _all.where((f) => perfGroupOk(_g, f.group, f.tesis)).toList();
    final mCount = _machines.where((m) => perfGroupOk(_g, m.group, m.tesis)).length;
    final p = FaultPerf.calc(list, mCount, _from, _to, _t);
    final techs = p.techs.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    final machines = p.byMachine.values.toList()
      ..sort((a, b) => b.fold<int>(0, (s, f) => s + f.machineDownSec).compareTo(a.fold<int>(0, (s, f) => s + f.machineDownSec)));
    return Scaffold(
      appBar: AppBar(title: const Text('Arıza ekibi performansı'), actions: [
        if (currentUser?.isAdmin ?? false) IconButton(tooltip: 'Hedef süreler', icon: const Icon(Icons.tune), onPressed: _editTargets),
        IconButton(tooltip: "Arızaları Excel'e aktar", icon: const Icon(Icons.download), onPressed: () => exportFaultsExcel(list, 'Arıza ekibi performansı')),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 1, label: Text('Bugün')), ButtonSegment(value: 7, label: Text('7 gün')), ButtonSegment(value: 30, label: Text('30 gün'))],
            selected: {_days},
            onSelectionChanged: (v) {
              setState(() => _days = v.first);
              _load();
            },
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in kPerfGroups.entries) ChoiceChip(label: Text(e.value), selected: _g == e.key, onSelected: (_) => setState(() => _g = e.key)),
          ]),
          const SizedBox(height: 10),
          if (_loading) const LinearProgressIndicator(),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: [
              _kpi('Ekip performansı', pctText(p.team), pctColor(p.team), 'atama, varış ve ilk seferde çözüm ortalaması'),
              _kpi('Zamanında atama', pctText(p.assign.v), pctColor(p.assign.v), '${p.assign.ok}/${p.assign.all} · hedef ${_t.assignMin} dk'),
              _kpi('Zamanında varış', pctText(p.arrive.v), pctColor(p.arrive.v), '${p.arrive.ok}/${p.arrive.all} · hedef ${_t.arriveMin} dk'),
              _kpi('İlk seferde çözüm', pctText(p.firstFix.v), pctColor(p.firstFix.v), '${p.firstFix.ok}/${p.firstFix.all} kapanan arıza'),
              _kpi('Makine kullanılabilirlik', p.avail == null ? '—' : '%${p.avail!.toStringAsFixed(1)}', pctColor(p.avail), '$mCount makine · arıza duruşu ${fmtSec(p.downSec)}'),
              _kpi('Arıza sayısı', '${p.count}', kDark, '${p.open} açık · ${p.noStop} duruşsuz'),
              _kpi('Ort. varış', p.arriveN == 0 ? '—' : fmtSec(p.arriveSum ~/ p.arriveN), kDark, 'atamadan "Başladım"a'),
              _kpi('Ort. net onarım', p.repairN == 0 ? '—' : fmtSec(p.repairSum ~/ p.repairN), kDark, 'parça bekleme düşülmüş · parça ${fmtSec(p.partSec)}'),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Teknisyenler', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (techs.isEmpty) const Text('Bu aralıkta atanmış arıza yok.', style: TextStyle(color: kMuted)),
          for (final t in techs)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(
                        '${t.count} arıza · ${t.closed} kapandı${t.helper > 0 ? ' · ${t.helper} yardımcı' : ''}\n'
                        'Varış ${t.arriveN == 0 ? '—' : fmtSec(t.arriveSum ~/ t.arriveN)} (${pctText(t.arrive.v)} zamanında) · '
                        'net onarım ${t.repairN == 0 ? '—' : fmtSec(t.repairSum ~/ t.repairN)} · ilk seferde ${pctText(t.firstFix.v)}',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  ]),
                ),
                Text(pctText(t.perf), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: pctColor(t.perf))),
              ]),
            ),
          const SizedBox(height: 14),
          const Text('En çok duran makineler', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (machines.isEmpty) const Text('Arıza yok.', style: TextStyle(color: kMuted)),
          for (final l in machines.take(10))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Expanded(child: Text('${l.first.machineName}${l.first.line.isEmpty ? '' : ' · ${l.first.line}'}${l.first.tesis ? ' · tesis' : ''}')),
                Text('${l.length} arıza · ${fmtSec(l.fold<int>(0, (s, f) => s + f.machineDownSec))}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          const SizedBox(height: 12),
          const Text(
            'Zamanında atama: bildirimden teknisyen atamasına kadar hedef süre içinde kalanlar (hedefi geçmiş, hâlâ atanmamış arızalar da sayılır). '
            'Zamanında varış: atamadan "Başladım"a kadar hedef süre içinde kalanlar. İlk seferde çözüm: "Giderilmedi" denmeden kapanan arızalar. '
            'Kullanılabilirlik: seçilen sürede makinelerin arıza yüzünden durmadığı süre (duruşsuz arızalar düşülmez). Reddedilen arızalar sayılmaz.',
            style: TextStyle(color: kMuted, fontSize: 12),
          ),
        ]),
      ),
    );
  }
}
