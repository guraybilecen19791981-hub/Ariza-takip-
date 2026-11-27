part of 'main.dart';

// ---------------------------------------------------------------------------
// Makine arıza takibi (Sargı ve Üretim makinelerinin içinde)
// Operatör bildirir → teknik hizmet müdürü atar → teknisyen başlar / bitirir
// → arızayı açan onaylar (makine çalışır) ya da "giderilmedi" der.
// ---------------------------------------------------------------------------

const Map<String, String> kMFaultStatus = {
  'yonay': 'Yönetici onayı bekliyor',
  'acik': 'Bildirildi, atama bekliyor',
  'atandi': 'Teknisyen atandı',
  'basladi': 'Müdahale ediliyor',
  'parca': 'Parça bekliyor',
  'arastir': 'Arıza araştırılıyor',
  'onay': 'Onay bekliyor',
  'kapandi': 'Kapandı',
  'iptal': 'Reddedildi (arıza değil)',
};
const List<String> kMFaultOpen = ['yonay', 'acik', 'atandi', 'basladi', 'parca', 'arastir', 'onay'];
const List<String> kMFaultWorking = ['basladi', 'parca', 'arastir'];

Color mFaultColor(String s) {
  switch (s) {
    case 'yonay':
      return const Color(0xFF862E9C);
    case 'parca':
      return const Color(0xFFE67700);
    case 'arastir':
      return const Color(0xFF0B7285);
    case 'iptal':
      return const Color(0xFF868E96);
    case 'acik':
      return const Color(0xFFC92A2A);
    case 'atandi':
      return const Color(0xFFD9480F);
    case 'basladi':
      return const Color(0xFF1D4ED8);
    case 'onay':
      return const Color(0xFF7048E8);
    case 'kapandi':
      return const Color(0xFF2B8A3E);
  }
  return kMuted;
}

bool canTechSee(AppUser? me) => me != null && (me.isAdmin || me.can('teknik', 'gor'));
bool canTechWork(AppUser? me) => me != null && (me.isAdmin || me.can('teknik', 'gir'));
bool canTechManage(AppUser? me) => me != null && (me.isAdmin || me.can('teknik', 'yonet'));
bool canApproveFault(AppUser? me, MGroup g, String reporterUid) => me != null && (me.uid == reporterUid || canMachineManage(me, g));

// Kullanıcı bu hattı / bölgeyi görüyor mu (Yönetir yetkisinde de atanan hatlar geçerli)
bool userSeesLine(AppUser? me, MGroup g, String line) {
  if (me == null) return false;
  final gl = gMachineById.values.where((m) => g.owns(m.group)).map((m) => m.line).toSet()..add(line);
  final vis = visibleLines(me, g, gl);
  return vis == null || vis.contains(line);
}

// Yönetici onayı kaldırıldı (v29): Girer / Düzenler yetkili arızayı doğrudan bildirir.
// Önceden "Yönetici onayı bekliyor" olarak açılmış kayıtlar yönetici ekranından onaylanabilir / reddedilebilir.
bool faultNeedsMgr(AppUser? me, MGroup g) => false;

// Panel yöneticisi (Yönetir / Onay) ya da admin: Girer yetkilinin açtığı arızayı / düzenlemeyi onaylar
bool canMgrApprove(AppUser? me, MFault f) => me != null && (me.isAdmin || (canMachineManage(me, f.grp) && userSeesLine(me, f.grp, f.line)));

class MFault {
  final String id;
  final String code;
  final String group;
  final String machineId;
  final String machineName;
  final String line;
  final String orderNo;
  final String productCode;
  final String desc;
  final String reasonKey;
  final String reasonLabel;
  final String status;
  final String reportedByUid;
  final String reportedBy;
  final DateTime? createdAt;
  final String assigneeUid;
  final String assigneeName;
  final String assignedBy;
  final DateTime? assignedAt;
  final DateTime? startedAt;
  final DateTime? doneAt;
  final String doneNote;
  final String doneBy;
  final DateTime? approvedAt;
  final String approvedBy;
  final int rejectCount;
  final int photoCount;
  final List<Map<String, dynamic>> log;
  final String assignee2Uid; // 2. teknisyen (yardımcı)
  final String assignee2Name;
  final DateTime? holdAt; // parça bekliyor / araştırılıyor başlangıcı
  final String holdNote;
  final int partSec; // biten parça bekleme süreleri toplamı
  final int researchSec; // biten araştırma süreleri toplamı
  final Map<String, dynamic>? pendingEdit; // yönetici onayı bekleyen düzenleme
  final String cancelNote;
  final bool noStop; // duruşsuz arıza: makine çalışmaya devam ediyor
  final bool tesis; // tesis ekipmanı arızası (üretim dışı)

  MFault({
    required this.id,
    required this.code,
    required this.group,
    required this.machineId,
    required this.machineName,
    required this.line,
    required this.orderNo,
    required this.productCode,
    required this.desc,
    required this.reasonKey,
    required this.reasonLabel,
    required this.status,
    required this.reportedByUid,
    required this.reportedBy,
    required this.createdAt,
    required this.assigneeUid,
    required this.assigneeName,
    required this.assignedBy,
    required this.assignedAt,
    required this.startedAt,
    required this.doneAt,
    required this.doneNote,
    required this.doneBy,
    required this.approvedAt,
    required this.approvedBy,
    required this.rejectCount,
    required this.photoCount,
    required this.log,
    this.assignee2Uid = '',
    this.assignee2Name = '',
    this.holdAt,
    this.holdNote = '',
    this.partSec = 0,
    this.researchSec = 0,
    this.pendingEdit,
    this.cancelNote = '',
    this.noStop = false,
    this.tesis = false,
  });

  factory MFault.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    String s(String k) => (m[k] ?? '').toString();
    final raw = m['log'];
    final log = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) log.add(Map<String, dynamic>.from(e));
      }
    }
    log.sort((a, b) => (tsToDate(a['t']) ?? DateTime(2000)).compareTo(tsToDate(b['t']) ?? DateTime(2000)));
    return MFault(
      id: d.id,
      code: s('code'),
      group: (m['tesis'] == true || (gMachineById[s('machineId')]?.tesis ?? false)) ? 'tesis' : s('group'),
      machineId: s('machineId'),
      machineName: s('machineName'),
      line: s('line'),
      orderNo: s('orderNo'),
      productCode: s('productCode'),
      desc: s('desc'),
      reasonKey: s('reasonKey'),
      reasonLabel: s('reasonLabel'),
      status: m['status'] == null ? 'acik' : s('status'),
      reportedByUid: s('reportedByUid'),
      reportedBy: s('reportedBy'),
      createdAt: tsToDate(m['createdAt']),
      assigneeUid: s('assigneeUid'),
      assigneeName: s('assigneeName'),
      assignedBy: s('assignedBy'),
      assignedAt: tsToDate(m['assignedAt']),
      startedAt: tsToDate(m['startedAt']),
      doneAt: tsToDate(m['doneAt']),
      doneNote: s('doneNote'),
      doneBy: s('doneBy'),
      approvedAt: tsToDate(m['approvedAt']),
      approvedBy: s('approvedBy'),
      rejectCount: _int(m['rejectCount']),
      photoCount: _int(m['photoCount']),
      log: log,
      assignee2Uid: s('assignee2Uid'),
      assignee2Name: s('assignee2Name'),
      holdAt: tsToDate(m['holdAt']),
      holdNote: s('holdNote'),
      partSec: _int(m['partSec']),
      researchSec: _int(m['researchSec']),
      pendingEdit: m['pendingEdit'] is Map ? Map<String, dynamic>.from(m['pendingEdit'] as Map) : null,
      cancelNote: s('cancelNote'),
      noStop: m['noStop'] == true,
      tesis: m['tesis'] == true || (gMachineById[s('machineId')]?.tesis ?? false),
    );
  }

  MGroup get grp => mGroupOf(group);
  bool get open => status != 'kapandi' && status != 'iptal';
  bool get cancelled => status == 'iptal';
  bool get working => kMFaultWorking.contains(status);
  bool get onHold => status == 'parca' || status == 'arastir';
  bool get hasPendingEdit => pendingEdit != null && (pendingEdit!['desc'] ?? '').toString().isNotEmpty;
  String get statusLabel => kMFaultStatus[status] ?? status;
  String get techText => [assigneeName, assignee2Name].where((x) => x.isNotEmpty).join(' + ');

  int _sec(DateTime? a, DateTime? b) {
    if (a == null) return 0;
    final e = b ?? DateTime.now();
    final s = e.difference(a).inSeconds;
    return s > 0 ? s : 0;
  }

  // Bildirimden atamaya (atama yoksa başlamaya) kadar geçen bekleme
  int get waitSec => _sec(createdAt, assignedAt ?? startedAt ?? (open ? null : approvedAt));
  // Varış: atamadan teknisyenin "Başladım" demesine kadar (kaç dakikada arızaya gitti)
  int get arriveSec => (assignedAt == null || startedAt == null) ? 0 : _sec(assignedAt, startedAt);
  // Onarım: "Başladım"dan "Bitti"ye (devam ediyorsa şu ana kadar); parça bekleme ve araştırma dahil
  int get repairSec => startedAt == null ? 0 : _sec(startedAt, doneAt ?? (working ? null : approvedAt));
  // Parça bekleme ve araştırma süreleri (sürüyorsa şu ana kadar)
  int get partNow => partSec + (status == 'parca' ? _sec(holdAt, null) : 0);
  int get researchNow => researchSec + (status == 'arastir' ? _sec(holdAt, null) : 0);
  int get holdRunning => onHold ? _sec(holdAt, null) : 0;
  // Onay bekleme: "Bitti"den onaya
  int get approvalSec => doneAt == null ? 0 : _sec(doneAt, approvedAt);
  // Toplam süre: bildirimden onaya
  int get totalSec => _sec(createdAt, approvedAt);
  // Makinenin bu arıza yüzünden durduğu süre (duruşsuz arızada 0)
  int get machineDownSec => noStop || cancelled ? 0 : totalSec;
  // Teknisyen net onarım: parça bekleme düşülür (parça gecikmesi teknisyenin elinde değil)
  int get netRepairSec => math.max(0, repairSec - partNow);

  String get comments =>
      log.where((e) => e['kind'] == 'yorum').map((e) => '${e['by'] ?? ''} (${fmtFull(tsToDate(e['t']))}): ${e['text'] ?? ''}').join(' | ');
}

class MFaultOps {
  static CollectionReference<Map<String, dynamic>> get col => db.collection('machineFaults');

  static Map<String, dynamic> _ev(String text, {String kind = 'olay'}) => {
        't': Timestamp.now(),
        'by': currentUser?.name ?? '',
        'byUid': currentUser?.uid ?? '',
        'text': text,
        'kind': kind,
      };

  static String _code(DateTime n) => 'A-${two(n.year % 100)}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}';

  static Future<MFault?> load(String id) async {
    if (id.isEmpty) return null;
    final d = await col.doc(id).get();
    return d.exists ? MFault.fromDoc(d) : null;
  }

  static Future<LineMachine?> _machine(String id) async {
    if (id.isEmpty) return null;
    final d = await MachineOps.col.doc(id).get();
    return d.exists ? LineMachine.fromDoc(d) : null;
  }

  // Operatör arıza bildirir: makine arızalı olur, kayıt açılır, alarm gider
  static Future<String> report(LineMachine m, MReason r, String desc, List<Uint8List> photos, {bool noStop = false}) async {
    if (m.hasFault) noStop = true; // makine zaten arızayla durduysa yeni arıza duruşsuz açılır (ilk arıza bağlantısı korunur)
    final now = DateTime.now();
    final ref = col.doc();
    final uid = currentUser?.uid ?? '';
    final name = currentUser?.name ?? '';
    final mgr = faultNeedsMgr(currentUser, m.grp);
    final st0 = mgr ? 'yonay' : 'acik';
    final machineFields = <String, dynamic>{'faultId': ref.id, 'faultStatus': st0, 'faultAssignee': '', 'faultByUid': uid};
    void writes(WriteBatch b) {
          b.set(ref, {
            'noStop': noStop,
            'tesis': m.tesis,
            'code': _code(now),
            'group': m.group,
            'machineId': m.id,
            'machineName': m.name,
            'line': m.line,
            'jobId': m.jobId,
            'orderNo': m.orderNo,
            'productCode': m.productCode,
            'desc': desc,
            'reasonKey': r.key,
            'reasonLabel': r.label,
            'status': st0,
            'mgrPending': mgr,
            'reportedByUid': uid,
            'reportedBy': name,
            'createdAt': Timestamp.fromDate(now),
            'assigneeUid': '',
            'assigneeName': '',
            'assignedBy': '',
            'assignedAt': null,
            'startedAt': null,
            'doneAt': null,
            'doneNote': '',
            'doneBy': '',
            'approvedAt': null,
            'approvedBy': '',
            'rejectCount': 0,
            'photoCount': photos.length,
            'assigneeOpen': '',
            'awaitApproval': '',
            'assignee2Uid': '',
            'assignee2Name': '',
            'assignee2Open': '',
            'partSec': 0,
            'researchSec': 0,
            'log': [_ev('Arıza bildirildi: $desc${noStop ? ' (duruşsuz: makine çalışmaya devam ediyor)' : ''}${mgr ? ' (yönetici onayı bekleniyor)' : ''}')],
          });
          b.set(MachineOps.entries.doc(), MachineOps._entryData(m, 'ariza', now, text: 'Arıza bildirildi${noStop ? ' (duruşsuz)' : ''}: $desc'));
    }

    if (noStop) {
      // Makinenin durumu değişmez; arıza kaydı açılır ve teknik hizmete alarm gider
      final b = db.batch();
      writes(b);
      // Makinede birden çok duruşsuz arıza açık olabilir: listeye eklenir, durdurma arızasının yeri (faultId) boş kalır
      b.update(MachineOps.col.doc(m.id), {'nsFaults': FieldValue.arrayUnion([ref.id])});
      b.set(db.collection('machineAlerts').doc(), {
        'group': m.group,
        'machineId': m.id,
        'machineName': m.name,
        'line': m.line,
        'label': 'Duruşsuz arıza',
        'note': desc,
        'orderNo': m.orderNo,
        'fault': true,
        'by': name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await b.commit();
    } else {
      await MachineOps.setState(m, r.key, r.label, true, desc,
          force: true, fault: !mgr, extraMachine: machineFields, extraWrites: writes);
    }
    await _savePhotos(ref.id, photos, 0);
    return ref.id;
  }

  static Future<void> _savePhotos(String id, List<Uint8List> photos, int start) async {
    for (var i = 0; i < photos.length; i++) {
      try {
        final fields = await photoFields('machineFaults/$id', photos[i]);
        await col.doc(id).collection('photos').add({
          'i': start + i,
          ...fields,
          'by': currentUser?.name ?? '',
          't': Timestamp.now(),
        });
      } catch (_) {}
    }
  }

  static Future<void> addPhotos(MFault f, List<Uint8List> photos) async {
    if (photos.isEmpty) return;
    await col.doc(f.id).update({
      'photoCount': FieldValue.increment(photos.length),
      'log': FieldValue.arrayUnion([_ev('${photos.length} fotoğraf eklendi')]),
    });
    await _savePhotos(f.id, photos, f.photoCount);
  }

  // Kapanan / iptal / silinen duruşsuz arıza makinedeki açık listesinden çıkar
  static void _dropNs(WriteBatch b, LineMachine? m, MFault f) {
    if (m != null && m.nsFaults.contains(f.id)) b.update(MachineOps.col.doc(m.id), {'nsFaults': FieldValue.arrayRemove([f.id])});
  }

  static Future<void> _machineFields(MFault f, Map<String, dynamic> data) async {
    final m = await _machine(f.machineId);
    if (m == null || m.faultId != f.id) return;
    await MachineOps.col.doc(m.id).update(data);
  }

  // Yönetici onayı: Girer yetkilinin açtığı arıza geçerli → teknik hizmete alarm gider
  static Future<void> mgrApprove(MFault f) async {
    final m = await _machine(f.machineId);
    final b = db.batch();
    b.update(col.doc(f.id), {
      'status': 'acik',
      'mgrPending': f.hasPendingEdit,
      'mgrApprovedBy': currentUser?.name ?? '',
      'mgrApprovedAt': Timestamp.now(),
      'log': FieldValue.arrayUnion([_ev('Yönetici onayladı, teknik hizmete gönderildi')]),
    });
    if (m != null && m.faultId == f.id) b.update(MachineOps.col.doc(m.id), {'faultStatus': 'acik'});
    b.set(db.collection('machineAlerts').doc(), {
      'group': f.group,
      'machineId': f.machineId,
      'machineName': f.machineName,
      'line': f.line,
      'label': f.reasonLabel.isEmpty ? 'Arızalı' : f.reasonLabel,
      'note': f.desc,
      'orderNo': f.orderNo,
      'fault': true,
      'by': f.reportedBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await b.commit();
  }

  // Yönetici reddeder: arıza değil, kayıt kapanır, makine çalışır
  static Future<void> mgrReject(MFault f, String note) async {
    final now = DateTime.now();
    final m = await _machine(f.machineId);
    void writes(WriteBatch b) {
      b.update(col.doc(f.id), {
        'status': 'iptal',
        'mgrPending': false,
        'pendingEdit': null,
        'cancelNote': note,
        'approvedAt': Timestamp.fromDate(now),
        'approvedBy': currentUser?.name ?? '',
        'approvedByUid': currentUser?.uid ?? '',
        'assigneeOpen': '',
        'assignee2Open': '',
        'awaitApproval': '',
        'log': FieldValue.arrayUnion([_ev('Yönetici reddetti (arıza değil): $note')]),
      });
    }

    const clear = {'faultId': '', 'faultStatus': '', 'faultAssignee': '', 'faultByUid': ''};
    if (m != null && m.faultId == f.id && !m.off && !f.noStop) {
      await MachineOps.setState(m, kRunKey, 'Çalışıyor', false, 'Arıza reddedildi: $note',
          extraMachine: Map<String, dynamic>.from(clear), extraWrites: writes, force: true);
      return;
    }
    final b = db.batch();
    writes(b);
    if (m != null && m.faultId == f.id) b.update(MachineOps.col.doc(m.id), Map<String, dynamic>.from(clear));
    _dropNs(b, m, f);
    await b.commit();
  }

  // Düzenleme: yönetici / admin doğrudan; Girer yetkili yöneticinin onayına gönderir
  static Future<bool> edit(MFault f, String desc, String doneNote) async {
    final me = currentUser;
    final direct = !faultNeedsMgr(me, f.grp);
    if (direct) {
      final ch = <String>[
        if (desc != f.desc) 'açıklama: "${f.desc}" → "$desc"',
        if (doneNote != f.doneNote) 'yapılan iş: "${f.doneNote}" → "$doneNote"',
      ];
      if (ch.isEmpty) return true;
      await col.doc(f.id).update({'desc': desc, 'doneNote': doneNote, 'log': FieldValue.arrayUnion([_ev('Düzenlendi: ${ch.join(', ')}')])});
      return true;
    }
    if (desc == f.desc) return true;
    await col.doc(f.id).update({
      'pendingEdit': {'desc': desc, 'by': me?.name ?? '', 'byUid': me?.uid ?? '', 't': Timestamp.now()},
      'mgrPending': true,
      'log': FieldValue.arrayUnion([_ev('Düzenleme yönetici onayına gönderildi: "$desc"')]),
    });
    return false;
  }

  static Future<void> mgrEditDecision(MFault f, bool ok) async {
    final pe = f.pendingEdit;
    if (pe == null) return;
    await col.doc(f.id).update({
      if (ok) 'desc': (pe['desc'] ?? f.desc).toString(),
      'pendingEdit': null,
      'mgrPending': f.status == 'yonay',
      'log': FieldValue.arrayUnion([_ev(ok ? 'Düzenleme onaylandı: "${f.desc}" → "${pe['desc']}"' : 'Düzenleme reddedildi: "${pe['desc']}"')]),
    });
  }

  // Admin: arızayı siler (30 gün Silinenler'de bekler); makinedeki arıza bağlantısı kalkar
  static Future<void> remove(MFault f) async {
    final m = await _machine(f.machineId);
    await TrashOps.move(col.doc(f.id), kind: 'machineFault', title: '${f.code} · ${f.machineName} · ${f.desc}', subs: const ['photos']);
    if (m != null && m.faultId == f.id) {
      await MachineOps.col.doc(m.id).update({'faultId': '', 'faultStatus': '', 'faultAssignee': '', 'faultByUid': ''});
    }
    if (m != null && m.nsFaults.contains(f.id)) await MachineOps.col.doc(m.id).update({'nsFaults': FieldValue.arrayRemove([f.id])});
  }

  // 2. teknisyen (yardımcı) ekler / kaldırır
  static Future<void> setHelper(MFault f, String uid, String name) async {
    await col.doc(f.id).update({
      'assignee2Uid': uid,
      'assignee2Name': name,
      'assignee2Open': uid,
      'log': FieldValue.arrayUnion([_ev(uid.isEmpty ? '2. teknisyen kaldırıldı (${f.assignee2Name})' : '2. teknisyen: $name')]),
    });
    await _machineFields(f, {'faultAssignee': [f.assigneeName, name].where((x) => x.isNotEmpty).join(' + ')});
  }

  // Teknisyen yapamadığı arızayı başka teknisyene devreder
  static Future<void> transfer(MFault f, String uid, String name, String note) async {
    final helper = f.assignee2Uid == uid;
    await col.doc(f.id).update({
      'assigneeUid': uid,
      'assigneeName': name,
      'assigneeOpen': uid,
      'assignedBy': currentUser?.name ?? '',
      if (helper) ...{'assignee2Uid': '', 'assignee2Name': '', 'assignee2Open': ''},
      'log': FieldValue.arrayUnion([_ev('Devredildi: ${f.assigneeName.isEmpty ? '-' : f.assigneeName} → $name${note.isEmpty ? '' : ' · $note'}')]),
    });
    await _machineFields(f, {'faultAssignee': [name, helper ? '' : f.assignee2Name].where((x) => x.isNotEmpty).join(' + ')});
  }

  // Bekleyen parça / araştırma süresini toplama ekler
  static Map<String, dynamic> _closeHold(MFault f, DateTime now) {
    if (!f.onHold || f.holdAt == null) return {};
    final sec = now.difference(f.holdAt!).inSeconds;
    if (sec <= 0) return {'holdAt': null};
    return {f.status == 'parca' ? 'partSec' : 'researchSec': FieldValue.increment(sec), 'holdAt': null};
  }

  // Parça bekliyor / Arıza araştırılıyor (arıza açık kalır, süre ayrı sayılır)
  static Future<void> hold(MFault f, String kind, String note) async {
    final now = DateTime.now();
    await col.doc(f.id).update({
      ..._closeHold(f, now),
      'status': kind,
      'holdAt': Timestamp.fromDate(now),
      'holdNote': note,
      'log': FieldValue.arrayUnion([_ev('${kMFaultStatus[kind]}${note.isEmpty ? '' : ': $note'}')]),
    });
    await _machineFields(f, {'faultStatus': kind});
  }

  static Future<void> resume(MFault f) async {
    final now = DateTime.now();
    final what = f.status == 'parca' ? 'Parça geldi, müdahaleye devam' : 'Araştırma bitti, müdahaleye devam';
    await col.doc(f.id).update({
      ..._closeHold(f, now),
      'status': 'basladi',
      'holdNote': '',
      'log': FieldValue.arrayUnion([_ev(what)]),
    });
    await _machineFields(f, {'faultStatus': 'basladi'});
  }

  // Müdür teknisyen atar (ya da kendisi üstlenir)
  static Future<void> assign(MFault f, String uid, String name) async {
    final now = Timestamp.now();
    final st = f.status == 'acik' ? 'atandi' : f.status;
    await col.doc(f.id).update({
      'assigneeUid': uid,
      'assigneeName': name,
      'assignedBy': currentUser?.name ?? '',
      if (f.assignedAt == null) 'assignedAt': now,
      'status': st,
      'assigneeOpen': uid,
      'log': FieldValue.arrayUnion([_ev('Atandı: $name')]),
    });
    await _machineFields(f, {'faultStatus': st, 'faultAssignee': name});
  }

  // Teknisyen müdahaleye başlar
  static Future<void> start(MFault f) async {
    final now = Timestamp.now();
    final me = currentUser;
    final takeOver = f.assigneeUid.isEmpty;
    final name = takeOver ? (me?.name ?? '') : f.assigneeName;
    await col.doc(f.id).update({
      'status': 'basladi',
      if (f.startedAt == null) 'startedAt': now,
      if (takeOver) ...{'assigneeUid': me?.uid ?? '', 'assigneeName': name, 'assigneeOpen': me?.uid ?? ''},
      if (f.assignedAt == null) 'assignedAt': now,
      'log': FieldValue.arrayUnion([_ev('Müdahaleye başlandı')]),
    });
    await _machineFields(f, {'faultStatus': 'basladi', 'faultAssignee': name});
  }

  // Teknisyen bitirir: arızayı açanın onayı beklenir
  static Future<void> finish(MFault f, String note) async {
    final now = DateTime.now();
    final m = await _machine(f.machineId);
    void writes(WriteBatch b) {
      b.update(col.doc(f.id), {
        ..._closeHold(f, now),
        'status': 'onay',
        'doneAt': Timestamp.fromDate(now),
        'doneNote': note,
        'doneBy': currentUser?.name ?? '',
        'awaitApproval': f.reportedByUid,
        'log': FieldValue.arrayUnion([_ev('Bitti, onay bekleniyor: $note')]),
      });
    }

    if (m != null && m.faultId == f.id && !m.off && !f.noStop) {
      await MachineOps.setState(m, kFaultWaitKey, kFaultWaitLabel, false, note, extraMachine: {'faultStatus': 'onay'}, extraWrites: writes, force: true);
      return;
    }
    final b = db.batch();
    writes(b);
    if (m != null && m.faultId == f.id) b.update(MachineOps.col.doc(m.id), {'faultStatus': 'onay'});
    await b.commit();
  }

  // Arızayı açan onaylar: kayıt kapanır, makine çalışır
  static Future<void> approve(MFault f) async {
    final now = DateTime.now();
    final m = await _machine(f.machineId);
    void writes(WriteBatch b) {
      b.update(col.doc(f.id), {
        'status': 'kapandi',
        'approvedAt': Timestamp.fromDate(now),
        'approvedBy': currentUser?.name ?? '',
        'approvedByUid': currentUser?.uid ?? '',
        'assigneeOpen': '',
        'assignee2Open': '',
        'awaitApproval': '',
        'log': FieldValue.arrayUnion([_ev('Onaylandı, arıza kapandı')]),
      });
    }

    const clear = {'faultId': '', 'faultStatus': '', 'faultAssignee': '', 'faultByUid': ''};
    if (m != null && m.faultId == f.id && !f.noStop) {
      await MachineOps.setState(m, kRunKey, 'Çalışıyor', false, '', extraMachine: Map<String, dynamic>.from(clear), extraWrites: writes, force: true);
      return;
    }
    final b = db.batch();
    writes(b);
    if (m != null && m.faultId == f.id) b.update(MachineOps.col.doc(m.id), Map<String, dynamic>.from(clear)); // duruşsuz: durum değişmez
    _dropNs(b, m, f);
    await b.commit();
  }

  // Arızayı açan "giderilmedi" der: teknisyene geri döner, makine arızalı kalır
  static Future<void> reject(MFault f, String note) async {
    final m = await _machine(f.machineId);
    void writes(WriteBatch b) {
      b.update(col.doc(f.id), {
        'status': 'basladi',
        'doneAt': null,
        'rejectCount': FieldValue.increment(1),
        'awaitApproval': '',
        'log': FieldValue.arrayUnion([_ev('Giderilmedi: $note')]),
      });
    }

    if (m != null && m.faultId == f.id && !m.off && !f.noStop) {
      await MachineOps.setState(m, f.reasonKey.isEmpty ? 'ariza' : f.reasonKey, f.reasonLabel.isEmpty ? 'Arızalı' : f.reasonLabel, false, 'Giderilmedi: $note',
          extraMachine: {'faultStatus': 'basladi'}, extraWrites: writes, force: true);
      return;
    }
    final b = db.batch();
    writes(b);
    if (m != null && m.faultId == f.id) b.update(MachineOps.col.doc(m.id), {'faultStatus': 'basladi'});
    await b.commit();
  }

  static Future<void> comment(MFault f, String text) =>
      col.doc(f.id).update({'log': FieldValue.arrayUnion([_ev(text, kind: 'yorum')])});

  static List<MFault> _conv(QuerySnapshot<Map<String, dynamic>> s) => s.docs.map((d) => MFault.fromDoc(d)).toList();

  // Açık arızalar canlı; kapananlar seçili geçmiş aralığından
  static Stream<List<MFault>> listStream(MGroup? g) {
    final open = col.where('status', whereIn: kMFaultOpen).snapshots().map(_conv);
    final done = col.where('approvedAt', isGreaterThanOrEqualTo: histFrom()).snapshots().map((s) => _conv(s).where((f) => !f.open).toList());
    return mergeLists<MFault>([open, done], (f) => f.id).map((l) {
      final out = l.where((f) => g == null || g.owns(f.group)).toList();
      out.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
      return out;
    });
  }

  static Future<List<MFault>> between(MGroup g, DateTime from, DateTime to) async {
    final s = await col.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from)).where('createdAt', isLessThan: Timestamp.fromDate(to)).get();
    return _conv(s).where((f) => g.owns(f.group)).toList();
  }
}

// ---------------------------------------------------------------------------
// Akışlar (diyaloglar)
// ---------------------------------------------------------------------------

Future<Uint8List?> pickPhotoBytes(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Fotoğraf çek'), onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galeriden seç'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );
  if (source == null) return null;
  try {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 60);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 2500000) {
      toast('Fotoğraf çok büyük, lütfen tekrar deneyin.');
      return null;
    }
    return bytes;
  } catch (e) {
    toast('Fotoğraf alınamadı: $e');
    return null;
  }
}

// Operatör: arıza bildirimi (açıklama + isteğe bağlı fotoğraf)
Future<void> reportFaultFlow(BuildContext context, LineMachine m, MReason r, String note, {bool noStop0 = false}) async {
  final desc = TextEditingController(text: note);
  final photos = <Uint8List>[];
  final forced = m.hasFault; // makine zaten arızayla duruyor: yeni arıza duruşsuz açılır
  var noStop = noStop0 || forced;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('Arıza bildir · ${m.name}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: desc,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Arıza açıklaması (ne oldu?)'),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < photos.length; i++)
                Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photos[i], width: 72, height: 72, fit: BoxFit.cover)),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () => setS(() => photos.removeAt(i)),
                      child: Container(color: Colors.black54, child: const Icon(Icons.close, color: Colors.white, size: 18)),
                    ),
                  ),
                ]),
              if (photos.length < kMaxPhotos)
                OutlinedButton.icon(
                  onPressed: () async {
                    final b = await pickPhotoBytes(d);
                    if (b != null) setS(() => photos.add(b));
                  },
                  icon: const Icon(Icons.add_a_photo, size: 18),
                  label: const Text('Fotoğraf'),
                ),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: noStop,
              onChanged: forced ? null : (v) => setS(() => noStop = v == true),
              title: const Text('Makine çalışmaya devam ediyor (duruşsuz arıza)'),
              subtitle: Text(
                  forced
                      ? 'Makinede açık bir arıza zaten var; bu arıza ayrı bir duruşsuz kayıt olarak açılır.'
                      : 'Makinenin durumu değişmez; arıza teknik hizmete gider ve onların performansına sayılır. Bir makinede birden çok duruşsuz arıza açılabilir.',
                  style: const TextStyle(fontSize: 12)),
            ),
            Text(
                noStop
                    ? 'Kaydedince makine durumu değişmez; teknik hizmete alarm gider.'
                    : faultNeedsMgr(currentUser, m.grp)
                    ? 'Kaydedince makine arızalı olur; arıza önce panel yöneticisinin onayına gider, onaylanınca teknik hizmete alarm gider.'
                    : 'Kaydedince makine arızalı olur, teknik hizmete alarm gider.',
                style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC92A2A)),
            onPressed: () {
              if (desc.text.trim().isEmpty) {
                toast('Lütfen arızayı kısaca yazın.');
                return;
              }
              Navigator.pop(d, true);
            },
            child: const Text('Arıza bildir'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    toast('Arıza bildiriliyor…');
    await MFaultOps.report(m, r, desc.text.trim(), photos, noStop: noStop);
    toast(faultNeedsMgr(currentUser, m.grp) ? '${m.name}: arıza bildirildi, yönetici onayı bekleniyor' : '${m.name}: arıza bildirildi, teknik hizmete alarm gitti');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

// Bir makinenin açık arızaları (durduran + duruşsuzlar)
class MachineFaultsPage extends StatelessWidget {
  final LineMachine machine;
  const MachineFaultsPage({super.key, required this.machine});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${machine.name} · açık arızalar')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: MFaultOps.col.where('machineId', isEqualTo: machine.id).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!.docs.map((d) => MFault.fromDoc(d)).where((f) => f.open).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
          if (list.isEmpty) return const Center(child: Text('Açık arıza yok.', style: TextStyle(color: kMuted)));
          return ListView(padding: const EdgeInsets.all(12), children: [
            for (final f in list)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MFaultDetailPage(faultId: f.id))),
                  leading: Icon(Icons.build_circle, color: mFaultColor(f.status)),
                  title: Text(f.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${f.code} · ${f.noStop ? 'Duruşsuz' : 'Makineyi durdurdu'} · ${kMFaultStatus[f.status] ?? f.status}'
                      '${f.assigneeName.isEmpty ? '' : ' · ${f.assigneeName}'} · ${fmtDT(f.createdAt)}'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

Future<void> approveFaultFlow(BuildContext context, MFault f) async {
  if (!await confirm(context, 'Arıza giderildi mi?', '${f.machineName}: ${f.doneNote.isEmpty ? f.desc : f.doneNote}\n\nOnaylarsanız arıza kapanır ve makine "Çalışıyor" olur.', 'Onayla')) {
    return;
  }
  try {
    await MFaultOps.approve(f);
    toast('${f.machineName}: arıza kapandı, makine çalışıyor');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> rejectFaultFlow(BuildContext context, MFault f) async {
  final t = await askText(context, 'Arıza giderilmedi', 'Ne sorun devam ediyor?', ok: 'Teknisyene geri gönder', mustFill: true);
  if (t == null || t.isEmpty) return;
  try {
    await MFaultOps.reject(f, t);
    toast('Arıza teknisyene geri gönderildi');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> assignFaultFlow(BuildContext context, MFault f) async {
  final pick = await pickTechnician(context, 'Teknisyen seçin', allowSelf: true);
  if (pick == null) return;
  try {
    await MFaultOps.assign(f, pick.uid, pick.name);
    toast('Atandı: ${pick.name}');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> helperFaultFlow(BuildContext context, MFault f) async {
  final pick = await pickTechnician(context, '2. teknisyen (yardımcı) seçin', exclude: {f.assigneeUid});
  if (pick == null) return;
  try {
    await MFaultOps.setHelper(f, pick.uid, pick.name);
    toast('2. teknisyen: ${pick.name}');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> transferFaultFlow(BuildContext context, MFault f) async {
  final pick = await pickTechnician(context, 'Arızayı kime devrediyorsunuz?', exclude: {f.assigneeUid});
  if (pick == null || !context.mounted) return;
  final note = await askText(context, 'Devir nedeni', 'Neden devrediliyor? (isteğe bağlı)', ok: 'Devret');
  if (note == null) return;
  try {
    await MFaultOps.transfer(f, pick.uid, pick.name, note.trim());
    toast('Devredildi: ${pick.name}');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> holdFaultFlow(BuildContext context, MFault f, String kind) async {
  final t = await askText(context, kMFaultStatus[kind] ?? kind, kind == 'parca' ? 'Hangi parça bekleniyor?' : 'Ne araştırılıyor?', ok: 'Kaydet', mustFill: true);
  if (t == null || t.trim().isEmpty) return;
  try {
    await MFaultOps.hold(f, kind, t.trim());
    toast(kMFaultStatus[kind] ?? kind);
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> editFaultFlow(BuildContext context, MFault f) async {
  final d = TextEditingController(text: f.hasPendingEdit ? (f.pendingEdit!['desc'] ?? f.desc).toString() : f.desc);
  final n = TextEditingController(text: f.doneNote);
  final direct = !faultNeedsMgr(currentUser, f.grp);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Arızayı düzenle · ${f.machineName}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: d, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Arıza açıklaması')),
          if (direct && f.doneAt != null) TextField(controller: n, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Yapılan iş')),
          const SizedBox(height: 8),
          Text(direct ? 'Değişiklik hemen kaydedilir ve geçmişe yazılır.' : 'Değişiklik panel yöneticisinin onayına gider; onaylanınca geçerli olur.',
              style: const TextStyle(color: kMuted, fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(direct ? 'Kaydet' : 'Onaya gönder')),
      ],
    ),
  );
  if (ok != true || d.text.trim().isEmpty) return;
  try {
    final done = await MFaultOps.edit(f, d.text.trim(), direct ? n.text.trim() : f.doneNote);
    toast(done ? 'Kaydedildi' : 'Düzenleme yöneticinin onayına gönderildi');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> deleteFaultFlow(BuildContext context, MFault f) async {
  if (!await confirm(context, 'Arıza kaydı silinsin mi?', '${f.code} · ${f.machineName}\n${f.desc}\n\nKayıt 30 gün "Silinenler"de bekler, oradan geri getirilebilir.', 'Sil')) return;
  try {
    await MFaultOps.remove(f);
    toast('Arıza kaydı silindi');
    if (context.mounted) Navigator.of(context).maybePop();
  } catch (e) {
    toast('Silinemedi: $e');
  }
}

Future<AppUser?> pickTechnician(BuildContext context, String title, {bool allowSelf = false, Set<String> exclude = const {}}) async {
  List<AppUser> techs;
  try {
    final s = await db.collection('users').get();
    // Yalnız teknisyenler ve teknik hizmet ekibi (adminler listede çıkmaz; admin yine her şeyi görür ve atar)
    techs = s.docs.map((d) => AppUser.fromDoc(d)).where((u) => u.role != 'bekliyor' && !u.isAdmin && (u.role == 'teknisyen' || u.can('teknik', 'gir'))).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  } catch (e) {
    toast('Kullanıcılar okunamadı: $e');
    return null;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<AppUser>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (allowSelf && currentUser != null && !currentUser!.isAdmin)
            ListTile(
              leading: const Icon(Icons.person_pin),
              title: const Text('Kendim üstleniyorum'),
              onTap: () => Navigator.pop(c, currentUser),
            ),
          for (final u in techs.where((u) => u.uid != currentUser?.uid && !exclude.contains(u.uid)))
            ListTile(
              leading: Icon(Icons.circle, size: 12, color: u.isOnline ? const Color(0xFF2F9E44) : const Color(0xFFADB5BD)),
              title: Text(u.name),
              subtitle: Text(u.roleLabel),
              onTap: () => Navigator.pop(c, u),
            ),
          if (techs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Teknisyen yok. Kullanıcılar sayfasından teknisyen rolü ya da Teknik hizmet (Girer) yetkisi verin.', style: TextStyle(color: kMuted)),
            ),
        ]),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Arıza detayı
// ---------------------------------------------------------------------------

class MFaultDetailPage extends StatelessWidget {
  final String faultId;
  const MFaultDetailPage({super.key, required this.faultId});

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: kMuted))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arıza detayı')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: MFaultOps.col.doc(faultId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (!snap.data!.exists) return const Center(child: Text('Arıza kaydı bulunamadı.'));
          final f = MFault.fromDoc(snap.data!);
          final me = currentUser;
          final c = mFaultColor(f.status);
          final mine = me != null && f.assigneeUid == me.uid;
          final mine2 = me != null && f.assignee2Uid.isNotEmpty && f.assignee2Uid == me.uid;
          final work = canTechWork(me);
          final manage = canTechManage(me);
          final pendingMgr = f.status == 'yonay';
          final mgr = canMgrApprove(me, f);
          final canStart = !pendingMgr && work && (f.status == 'acik' || f.status == 'atandi') && (f.assigneeUid.isEmpty || mine || mine2 || manage);
          final canFinish = f.working && (mine || mine2 || manage);
          final canApprove = f.status == 'onay' && canApproveFault(me, f.grp, f.reportedByUid);
          final canComment = work || (me != null && (me.uid == f.reportedByUid || canMachineEnter(me, f.grp)));
          final canEdit = canFixRecords(me); // arıza kaydını düzeltme yalnız admin
          final canHelp = f.open && !pendingMgr && f.assigneeUid.isNotEmpty && (manage || mine);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text('${f.machineName}${f.line.isEmpty ? '' : ' · ${f.line}'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(999)),
                child: Text(f.statusLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
            Text('${f.code} · ${f.grp.title}${f.tesis ? ' · Tesis ekipmanı' : ''}${f.noStop ? ' · DURUŞSUZ (makine çalışıyor)' : ''}',
                style: TextStyle(color: f.noStop ? const Color(0xFF1D4ED8) : kMuted, fontWeight: f.noStop ? FontWeight.w700 : FontWeight.w400)),
            const SizedBox(height: 10),
            _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.desc, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _row('Bildiren', '${f.reportedBy} · ${fmtFull(f.createdAt)}'),
              if (f.orderNo.isNotEmpty) _row('Sipariş', '${f.orderNo} · ${f.productCode}'),
              _row('Teknisyen', f.assigneeName.isEmpty ? 'Atanmadı' : '${f.assigneeName}${f.assignedBy.isEmpty ? '' : ' (atayan: ${f.assignedBy})'}'),
              if (f.assignee2Name.isNotEmpty) _row('2. teknisyen', f.assignee2Name),
              if (f.assignedAt != null) _row('Atama', fmtFull(f.assignedAt)),
              if (f.startedAt != null) _row('Başlama', fmtFull(f.startedAt)),
              if (f.onHold) _row(f.status == 'parca' ? 'Parça bekleniyor' : 'Araştırılıyor', '${f.holdNote} · ${fmtSec(f.holdRunning)}'),
              if (f.cancelled) _row('Reddedildi', '${f.approvedBy} · ${f.cancelNote}'),
              if (f.doneAt != null) _row('Bitti', '${fmtFull(f.doneAt)}${f.doneNote.isEmpty ? '' : ' · ${f.doneNote}'}'),
              if (f.approvedAt != null) _row('Onay', '${fmtFull(f.approvedAt)} · ${f.approvedBy}'),
              if (f.rejectCount > 0) _row('Giderilmedi', '${f.rejectCount} kez geri gönderildi'),
              const Divider(height: 16),
              _row('Atama bekleme', fmtSec(f.waitSec)),
              if (f.startedAt != null) _row('Varış süresi', '${fmtSec(f.arriveSec)} (atamadan arızaya gidişe)'),
              _row('Onarım', fmtSec(f.repairSec)),
              if (f.partNow > 0) _row('Parça bekleme', fmtSec(f.partNow)),
              if (f.researchNow > 0) _row('Araştırma', fmtSec(f.researchNow)),
              if (f.doneAt != null || f.approvedAt != null) _row('Onay bekleme', fmtSec(f.approvalSec)),
              _row(f.noStop ? 'Toplam süre' : 'Toplam duruş', '${fmtSec(f.totalSec)}${f.open ? ' (devam ediyor)' : ''}${f.noStop ? ' · makine durmadı' : ''}'),
            ])),
            const SizedBox(height: 10),
            if (pendingMgr)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: const Color(0xFFF8F0FC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5DBFF))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Bu arıza panel yöneticisinin onayını bekliyor. Onaylanınca teknik hizmete alarm gider.',
                      style: TextStyle(color: Color(0xFF862E9C), fontWeight: FontWeight.w600)),
                  if (mgr) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: kGreen, minimumSize: const Size.fromHeight(46)),
                          onPressed: () async {
                            try {
                              await MFaultOps.mgrApprove(f);
                              toast('Onaylandı, teknik hizmete gönderildi');
                            } catch (e) {
                              toast('Kaydedilemedi: $e');
                            }
                          },
                          icon: const Icon(Icons.verified),
                          label: const Text('Arızayı onayla'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC92A2A), minimumSize: const Size.fromHeight(46)),
                          onPressed: () async {
                            final t = await askText(context, 'Arıza reddedilsin mi?', 'Neden? (makine "Çalışıyor" olur)', ok: 'Reddet', mustFill: true);
                            if (t == null || t.trim().isEmpty) return;
                            try {
                              await MFaultOps.mgrReject(f, t.trim());
                              toast('Reddedildi');
                            } catch (e) {
                              toast('Kaydedilemedi: $e');
                            }
                          },
                          icon: const Icon(Icons.block),
                          label: const Text('Reddet'),
                        ),
                      ),
                    ]),
                  ],
                ]),
              ),
            if (f.hasPendingEdit)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: const Color(0xFFFFF9DB), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFE066))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Düzenleme onay bekliyor (${f.pendingEdit!['by'] ?? ''}): "${f.pendingEdit!['desc'] ?? ''}"', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (mgr) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: kGreen),
                          onPressed: () => MFaultOps.mgrEditDecision(f, true).then((_) => toast('Düzenleme onaylandı')).catchError((e) => toast('Kaydedilemedi: $e')),
                          child: const Text('Düzenlemeyi onayla'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => MFaultOps.mgrEditDecision(f, false).then((_) => toast('Düzenleme reddedildi')).catchError((e) => toast('Kaydedilemedi: $e')),
                          child: const Text('Reddet'),
                        ),
                      ),
                    ]),
                  ],
                ]),
              ),
            if (f.open) ...[
              if (manage && !pendingMgr)
                OutlinedButton.icon(
                  onPressed: () => assignFaultFlow(context, f),
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(f.assigneeUid.isEmpty ? 'Teknisyen ata' : 'Teknisyeni değiştir'),
                ),
              if (canHelp)
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => f.assignee2Uid.isEmpty
                          ? helperFaultFlow(context, f)
                          : MFaultOps.setHelper(f, '', '').then((_) => toast('2. teknisyen kaldırıldı')).catchError((e) => toast('Kaydedilemedi: $e')),
                      icon: Icon(f.assignee2Uid.isEmpty ? Icons.group_add_outlined : Icons.person_remove_outlined),
                      label: Text(f.assignee2Uid.isEmpty ? '2. teknisyen ekle' : '2. teknisyeni kaldır'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => transferFaultFlow(context, f),
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Başkasına devret'),
                    ),
                  ),
                ]),
              if (canStart)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1D4ED8), minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    try {
                      await MFaultOps.start(f);
                      toast('Müdahaleye başlandı');
                    } catch (e) {
                      toast('Kaydedilemedi: $e');
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Başladım'),
                ),
              if (canFinish && f.onHold)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1D4ED8), minimumSize: const Size.fromHeight(48)),
                  onPressed: () => MFaultOps.resume(f).then((_) => toast('Müdahaleye devam')).catchError((e) => toast('Kaydedilemedi: $e')),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(f.status == 'parca' ? 'Parça geldi, devam et' : 'Araştırma bitti, devam et'),
                ),
              if (canFinish)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    if (f.status != 'parca')
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE67700)),
                          onPressed: () => holdFaultFlow(context, f, 'parca'),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Parça bekliyor'),
                        ),
                      ),
                    if (f.status != 'parca' && f.status != 'arastir') const SizedBox(width: 8),
                    if (f.status != 'arastir')
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0B7285)),
                          onPressed: () => holdFaultFlow(context, f, 'arastir'),
                          icon: const Icon(Icons.manage_search),
                          label: const Text('Arıza araştırılıyor'),
                        ),
                      ),
                  ]),
                ),
              if (canFinish)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kGreen, minimumSize: const Size.fromHeight(48)),
                  onPressed: () async {
                    final t = await askText(context, 'Arıza giderildi', 'Yapılan iş (ne yapıldı, hangi parça değişti?)', ok: 'Bitti, onaya gönder', mustFill: true);
                    if (t == null || t.isEmpty) return;
                    try {
                      await MFaultOps.finish(f, t);
                      toast('Bitti; arızayı açanın onayı bekleniyor');
                    } catch (e) {
                      toast('Kaydedilemedi: $e');
                    }
                  },
                  icon: const Icon(Icons.flag),
                  label: const Text('Bitti, onaya gönder'),
                ),
              if (canApprove)
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: kGreen, minimumSize: const Size.fromHeight(48)),
                      onPressed: () => approveFaultFlow(context, f),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Onayla'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC92A2A), minimumSize: const Size.fromHeight(48)),
                      onPressed: () => rejectFaultFlow(context, f),
                      icon: const Icon(Icons.cancel),
                      label: const Text('Giderilmedi'),
                    ),
                  ),
                ]),
              if (f.status == 'onay' && !canApprove)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Arızayı açan kişinin onayı bekleniyor.', style: TextStyle(color: Color(0xFF7048E8), fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 8),
            ],
            Row(children: [
              if (canComment)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await askText(context, 'Yorum / bilgi', 'Yorumunuz', ok: 'Ekle', mustFill: true);
                      if (t == null || t.isEmpty) return;
                      try {
                        await MFaultOps.comment(f, t);
                      } catch (e) {
                        toast('Kaydedilemedi: $e');
                      }
                    },
                    icon: const Icon(Icons.comment_outlined),
                    label: const Text('Yorum yaz'),
                  ),
                ),
              if (canComment) const SizedBox(width: 8),
              if (canComment)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final b = await pickPhotoBytes(context);
                      if (b == null) return;
                      try {
                        toast('Fotoğraf yükleniyor…');
                        await MFaultOps.addPhotos(f, [b]);
                        toast('Fotoğraf eklendi');
                      } catch (e) {
                        toast('Kaydedilemedi: $e');
                      }
                    },
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Fotoğraf ekle'),
                  ),
                ),
            ]),
            if (canEdit || (me?.isAdmin ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  if (canEdit)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => editFaultFlow(context, f),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Düzenle'),
                      ),
                    ),
                  if (canEdit && (me?.isAdmin ?? false)) const SizedBox(width: 8),
                  if (me?.isAdmin ?? false)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC92A2A)),
                        onPressed: () => deleteFaultFlow(context, f),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Sil (admin)'),
                      ),
                    ),
                ]),
              ),
            if (f.photoCount > 0) ...[
              const SizedBox(height: 12),
              MFaultPhotos(key: ValueKey('ph-${f.id}-${f.photoCount}'), faultId: f.id),
            ],
            const SizedBox(height: 16),
            const Text('Geçmiş ve yorumlar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final e in f.log.reversed)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: e['kind'] == 'yorum' ? const Color(0xFFFFF9DB) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE9ECEF)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e['by'] ?? ''} · ${fmtFull(tsToDate(e['t']))}${e['kind'] == 'yorum' ? ' · yorum' : ''}', style: const TextStyle(color: kMuted, fontSize: 12)),
                  Text((e['text'] ?? '').toString()),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class MFaultPhotos extends StatelessWidget {
  final String faultId;
  const MFaultPhotos({super.key, required this.faultId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: MFaultOps.col.doc(faultId).collection('photos').orderBy('i').get(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
        final images = snap.data!.docs.map((d) => [(d.data()['url'] ?? '').toString(), (d.data()['data'] ?? '').toString()]).toList();
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final img in images)
            GestureDetector(
              onTap: () => openStoredImage(context, img[0], img[1]),
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: storedImage(img[0], img[1], width: 96, height: 96)),
            ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Arıza listesi (makine panelinden ya da Teknik hizmet sekmesinden)
// ---------------------------------------------------------------------------

class MFaultList extends StatefulWidget {
  final MGroup? group; // null = iki panel birlikte
  const MFaultList({super.key, this.group});

  @override
  State<MFaultList> createState() => _MFaultListState();
}

class _MFaultListState extends State<MFaultList> {
  int _tab = 0; // 0 açık, 1 kapanan, 2 tümü
  String _q = '';
  String _grp = ''; // '', sargi, uretim (yalnız group == null iken)
  Stream<List<MFault>>? _s;
  int _sd = -1;
  List<MFault> _last = const [];

  Stream<List<MFault>> get _stream {
    if (_s == null || _sd != gHistDays.value) {
      _sd = gHistDays.value;
      _s = MFaultOps.listStream(widget.group);
    }
    return _s!;
  }

  List<MFault> _apply(List<MFault> all) {
    final q = _q.trim().toLowerCase();
    final me = currentUser;
    // Hat / bölge kısıtı makine panelindeki gibi (teknik hizmet yetkisi olanlar hepsini görür)
    final g = widget.group;
    final base = (g != null && !canTechSee(me)) ? filterVisible<MFault>(me, g, all, (f) => f.line) : all;
    return base.where((f) {
      if (_tab == 0 && !f.open) return false;
      if (_tab == 1 && f.open) return false;
      if (g == null && _grp.isNotEmpty && !mGroupOf(_grp).owns(f.group)) return false;
      if (q.isEmpty) return true;
      return '${f.code} ${f.machineName} ${f.line} ${f.desc} ${f.assigneeName} ${f.reportedBy} ${f.orderNo}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: gHistDays,
      builder: (context, _, __) => StreamBuilder<List<MFault>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = _apply(snap.data!);
          _last = list;
          final openN = snap.data!.where((f) => f.open).length;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
            HistBar(onFind: null),
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Makine, arıza, teknisyen ara', isDense: true),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: "Excel'e aktar",
                onPressed: () => exportFaultsExcel(_last, widget.group?.title ?? 'Makine arızaları'),
                icon: const Icon(Icons.download),
              ),
              IconButton.filledTonal(
                tooltip: 'Arıza ekibi performansı',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FaultPerfPage(group: widget.group))),
                icon: const Icon(Icons.speed),
              ),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                ButtonSegment<int>(value: 0, label: Text('Açık ($openN)')),
                const ButtonSegment<int>(value: 1, label: Text('Kapanan')),
                const ButtonSegment<int>(value: 2, label: Text('Tümü')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
            if (widget.group == null) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final e in {'': 'İki panel', 'sargi': 'Sargı', 'uretim': 'Üretim'}.entries)
                  ChoiceChip(label: Text(e.value), selected: _grp == e.key, onSelected: (_) => setState(() => _grp = e.key)),
              ]),
            ],
            const SizedBox(height: 10),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Center(child: Text(_tab == 0 ? 'Açık arıza yok.' : 'Kayıt yok.', style: const TextStyle(color: kMuted))),
              ),
            for (final f in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MFaultDetailPage(faultId: f.id))),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: mFaultColor(f.status), width: 5)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text('${f.machineName}${f.line.isEmpty ? '' : ' · ${f.line}'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        Text(f.statusLabel, style: TextStyle(color: mFaultColor(f.status), fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                      Text(f.desc, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        '${f.code}${widget.group == null ? ' · ${f.grp.title}' : ''} · ${f.reportedBy} · ${fmtDT(f.createdAt)}'
                        '${f.techText.isEmpty ? '' : ' · Teknisyen: ${f.techText}'}${f.startedAt != null && f.assignedAt != null ? ' · varış ${fmtSec(f.arriveSec)}' : ''}',
                        style: const TextStyle(color: kMuted, fontSize: 12),
                      ),
                      Text(
                          '${f.noStop ? 'Duruşsuz · ' : ''}${f.open ? '${f.noStop ? 'Süre' : 'Duruş'}: ${fmtSec(f.totalSec)} (devam ediyor)' : '${f.noStop ? 'Toplam süre' : 'Toplam duruş'}: ${fmtSec(f.totalSec)} · onarım ${fmtSec(f.repairSec)}'}',
                          style: TextStyle(color: f.open ? const Color(0xFFC92A2A) : kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class MFaultsPage extends StatelessWidget {
  final MGroup group;
  const MFaultsPage({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text('${group.title} · arızalar')), body: MFaultList(group: group));
  }
}

// Teknik hizmet sekmesi (teknisyen ve teknik hizmet müdürü için)
class TechHome extends StatelessWidget {
  final AppUser me;
  final Widget? nav;
  const TechHome({super.key, required this.me, this.nav});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Bind · Teknik hizmet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          Text('${me.name} · ${me.roleLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
        ]),
        actions: [...commonActions(me)],
      ),
      bottomNavigationBar: nav,
      body: const MFaultList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Excel
// ---------------------------------------------------------------------------

List<String> kFaultExcelHead(String lineLabel) => [
      'Kod', 'Panel', 'Makine', lineLabel, 'Sipariş no', 'Ürün kodu', 'Arıza açıklaması', 'Bildiren', 'Bildirim', 'Durum', 'Teknisyen', 'Atayan',
      'Atama', 'Başlama', 'Bitiş', 'Onay', 'Onaylayan', 'Atama bekleme (dk)', 'Onarım (dk)', 'Onay bekleme (dk)', 'Toplam duruş (dk)',
      'Giderilmedi (kez)', 'Yapılan iş', 'Yorumlar', '2. teknisyen', 'Varış süresi (dk)', 'Parça bekleme (dk)', 'Araştırma (dk)', 'Red nedeni',
      'Duruşsuz', 'Makine duruşu (dk)', 'Tesis ekipmanı',
    ];

List<xl.CellValue?> faultExcelRow(MFault f) {
  xl.CellValue t(String v) => xl.TextCellValue(v);
  xl.CellValue n(int v) => xl.IntCellValue(v);
  int mins(int s) => (s / 60).round();
  String dt(DateTime? d) => d == null ? '' : fmtFull(d);
  return [
    t(f.code), t(f.grp.title), t(f.machineName), t(f.line), t(f.orderNo), t(f.productCode), t(f.desc), t(f.reportedBy), t(dt(f.createdAt)),
    t(f.statusLabel), t(f.assigneeName), t(f.assignedBy), t(dt(f.assignedAt)), t(dt(f.startedAt)), t(dt(f.doneAt)), t(dt(f.approvedAt)),
    t(f.approvedBy), n(mins(f.waitSec)), n(mins(f.repairSec)), n(mins(f.approvalSec)), n(mins(f.totalSec)), n(f.rejectCount), t(f.doneNote), t(f.comments),
    t(f.assignee2Name), n(mins(f.arriveSec)), n(mins(f.partNow)), n(mins(f.researchNow)), t(f.cancelNote),
    t(f.noStop ? 'Evet' : ''), n(mins(f.machineDownSec)), t(f.tesis ? 'Evet' : ''),
  ];
}

Future<void> exportFaultsExcel(List<MFault> list, String title) async {
  try {
    if (list.isEmpty) {
      toast('Aktarılacak arıza yok.');
      return;
    }
    toast('Arıza listesi hazırlanıyor…');
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Arızalar');
    final xl.Sheet sh = excel['Arızalar'];
    sh.appendRow(<xl.CellValue?>[for (final h in kFaultExcelHead('Hat / bölge')) xl.TextCellValue(h)]);
    for (final f in list) {
      sh.appendRow(faultExcelRow(f));
    }
    // Makine bazında özet
    final xl.Sheet sum = excel['Makine bazında'];
    sum.appendRow(<xl.CellValue?>[
      for (final h in ['Panel', 'Makine', 'Hat / bölge', 'Arıza sayısı', 'Toplam duruş (dk)', 'Toplam onarım (dk)', 'Ort. duruş (dk)', 'Ort. varış (dk)', 'Parça bekleme (dk)', 'Araştırma (dk)'])
        xl.TextCellValue(h)
    ]);
    final by = <String, List<MFault>>{};
    for (final f in list) {
      by.putIfAbsent('${f.group}|${f.machineId}', () => <MFault>[]).add(f);
    }
    for (final l0 in by.values) {
      final l = l0.where((f) => !f.cancelled).toList();
      if (l.isEmpty) continue;
      final tot = l.fold<int>(0, (a, f) => a + f.machineDownSec);
      final rep = l.fold<int>(0, (a, f) => a + f.repairSec);
      final arr = l.where((f) => f.startedAt != null && f.assignedAt != null).toList();
      sum.appendRow(<xl.CellValue?>[
        xl.TextCellValue(l.first.grp.title), xl.TextCellValue(l.first.machineName), xl.TextCellValue(l.first.line), xl.IntCellValue(l.length),
        xl.IntCellValue((tot / 60).round()), xl.IntCellValue((rep / 60).round()), xl.IntCellValue((tot / 60 / l.length).round()),
        xl.IntCellValue(arr.isEmpty ? 0 : (arr.fold<int>(0, (a, f) => a + f.arriveSec) / 60 / arr.length).round()),
        xl.IntCellValue((l.fold<int>(0, (a, f) => a + f.partNow) / 60).round()),
        xl.IntCellValue((l.fold<int>(0, (a, f) => a + f.researchNow) / 60).round()),
      ]);
    }
    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final now = DateTime.now();
    await shareBytes(bytes, 'arizalar_${now.year}${two(now.month)}${two(now.day)}.xlsx', '$title · arızalar');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}
