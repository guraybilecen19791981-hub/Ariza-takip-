part of 'main.dart';

// ---------------------------------------------------------------------------
// Paketleme takip modülü (v3)
// ---------------------------------------------------------------------------

const Map<String, String> kStopReasons = {
  'mola': 'Mola',
  'urun_yok': 'Ürün yok',
  'koli_yok': 'Koli yok',
  'kalite': 'Kalite onayı bekleniyor',
  'ariza': 'Arıza',
  'diger': 'Diğer',
};

// Bu nedenlerde kalite, vardiya amiri ve admine bildirim gider
const Set<String> kAlertReasons = {'urun_yok', 'kalite'};

const Map<String, String> kWorkTypes = {
  'uretim': 'Üretim',
  'karekod': 'Karekod hazırlık',
  'onhazirlik': 'Ön hazırlık',
};

const Map<String, String> kPhotoStages = {
  'uretim': 'Üretim',
  'onhazirlik': 'Ön hazırlık',
  'karekod': 'Karekod hazırlık',
  'diger': 'Diğer',
};

const Map<String, String> kApproverRoles = {'kalite': 'Kalite', 'ihracat': 'İhracat'};

String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

int _toInt(dynamic v) => (v is num) ? v.toInt() : 0;

String? reasonKeyFromLabel(String? label) {
  if (label == null) return null;
  for (final e in kStopReasons.entries) {
    if (e.value == label) return e.key;
  }
  return null;
}

class PackOrder {
  final String id;
  final String orderNo;
  final String productCode;
  final String workType;
  final int perBox;
  final String ownerUid;
  final String ownerName;
  final String status; // calisiyor | durdu | beklemede | bitti
  final String? stopReason;
  final String stopNote;
  final DateTime? stopStartedAt;
  final String currentDay;
  final int workers;
  final int daily;
  final int totalBoxes;
  final int totalUnits;
  final int todayBoxes;
  final int todayUnits;
  final DateTime? todayStartAt;
  final DateTime? lastUpdateAt;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final String finishNote;
  final int dayCount;
  final int pendingApprovals;
  final Map<String, int> stopMin;

  PackOrder({
    required this.id,
    required this.orderNo,
    required this.productCode,
    required this.workType,
    required this.perBox,
    required this.ownerUid,
    required this.ownerName,
    required this.status,
    required this.stopReason,
    required this.stopNote,
    required this.stopStartedAt,
    required this.currentDay,
    required this.workers,
    required this.daily,
    required this.totalBoxes,
    required this.totalUnits,
    required this.todayBoxes,
    required this.todayUnits,
    required this.todayStartAt,
    required this.lastUpdateAt,
    required this.createdAt,
    required this.finishedAt,
    required this.finishNote,
    required this.dayCount,
    required this.pendingApprovals,
    required this.stopMin,
  });

  factory PackOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final sm = <String, int>{};
    final raw = m['stopMin'];
    if (raw is Map) {
      raw.forEach((k, v) => sm[k.toString()] = _toInt(v));
    }
    return PackOrder(
      id: d.id,
      orderNo: (m['orderNo'] ?? '').toString(),
      productCode: (m['productCode'] ?? '').toString(),
      workType: (m['workType'] ?? '').toString(),
      perBox: _toInt(m['perBox']),
      ownerUid: (m['ownerUid'] ?? '').toString(),
      ownerName: (m['ownerName'] ?? '').toString(),
      status: (m['status'] ?? 'calisiyor').toString(),
      stopReason: m['stopReason']?.toString(),
      stopNote: (m['stopNote'] ?? '').toString(),
      stopStartedAt: tsToDate(m['stopStartedAt']),
      currentDay: (m['currentDay'] ?? '').toString(),
      workers: _toInt(m['workers']),
      daily: _toInt(m['daily']),
      totalBoxes: _toInt(m['totalBoxes']),
      totalUnits: _toInt(m['totalUnits']),
      todayBoxes: _toInt(m['todayBoxes']),
      todayUnits: _toInt(m['todayUnits']),
      todayStartAt: tsToDate(m['todayStartAt']),
      lastUpdateAt: tsToDate(m['lastUpdateAt']),
      createdAt: tsToDate(m['createdAt']),
      finishedAt: tsToDate(m['finishedAt']),
      finishNote: (m['finishNote'] ?? '').toString(),
      dayCount: _toInt(m['dayCount']),
      pendingApprovals: _toInt(m['pendingApprovals']),
      stopMin: sm,
    );
  }

  bool get isFinished => status == 'bitti';
  bool get needsDayStart => !isFinished && (status == 'beklemede' || currentDay != dayKey(DateTime.now()));
  bool get isToday => !needsDayStart && !isFinished;
  String get workTypeLabel => kWorkTypes[workType] ?? '';

  int get remUnits => perBox > 0 ? totalUnits - totalBoxes * perBox : 0;
  int get todayRem => perBox > 0 ? todayUnits - todayBoxes * perBox : 0;
  String get qtyText => remUnits > 0 ? '$totalBoxes koli + $remUnits adet' : '$totalBoxes koli';
  String get todayText => todayRem > 0 ? '$todayBoxes koli + $todayRem adet' : '$todayBoxes koli';

  String get statusLabel {
    if (isFinished) return 'Bitti';
    if (needsDayStart) return status == 'beklemede' ? 'Gün bitti' : 'Bugün başlatılmadı';
    if (status == 'durdu') return 'Durdu: ${kStopReasons[stopReason] ?? 'Diğer'}';
    return 'Çalışıyor';
  }

  Color get statusBgColor {
    if (isFinished || needsDayStart) return const Color(0xFFE9ECEF);
    if (status == 'durdu') return const Color(0xFFFFE3D0);
    return const Color(0xFFD3F9D8);
  }

  Color get statusFgColor {
    if (isFinished || needsDayStart) return kMuted;
    if (status == 'durdu') return const Color(0xFF9A3412);
    return const Color(0xFF1B6B2B);
  }

  String get rateText {
    final start = todayStartAt;
    if (start == null || todayBoxes == 0 || !isToday) return '';
    final hours = DateTime.now().difference(start).inMinutes / 60.0;
    if (hours < 0.1) return '';
    return '${(todayBoxes / hours).toStringAsFixed(0)} koli/saat';
  }

  int get totalStopMin => stopMin.values.fold(0, (a, b) => a + b);
}

class PackEvent {
  final String id;
  final String type;
  final DateTime? t;
  final String by;
  final String text;
  final int qty;
  final int units;
  final String? reasonKey;
  final int? workers;
  final int? daily;
  final bool edited;

  PackEvent({
    required this.id,
    required this.type,
    required this.t,
    required this.by,
    required this.text,
    required this.qty,
    required this.units,
    required this.reasonKey,
    required this.workers,
    required this.daily,
    required this.edited,
  });

  factory PackEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    return PackEvent(
      id: d.id,
      type: (m['type'] ?? '').toString(),
      t: tsToDate(m['t']),
      by: (m['by'] ?? '').toString(),
      text: (m['text'] ?? '').toString(),
      qty: _toInt(m['qty']),
      units: _toInt(m['units']),
      reasonKey: m['reasonKey']?.toString() ?? reasonKeyFromLabel(m['reason']?.toString()),
      workers: m['workers'] is num ? (m['workers'] as num).toInt() : null,
      daily: m['daily'] is num ? (m['daily'] as num).toInt() : null,
      edited: m['editedBy'] != null,
    );
  }

  bool get isEntry => type == 'koli';

  String get displayText {
    if (isEntry) {
      final parts = <String>[];
      if (qty != 0) parts.add('+$qty koli');
      if (units != 0) parts.add('+$units adet');
      return parts.isEmpty ? '+0' : parts.join(' ');
    }
    return text;
  }
}

class PackOps {
  static CollectionReference<Map<String, dynamic>> get col => db.collection('packOrders');
  static DocumentReference<Map<String, dynamic>> ref(String id) => col.doc(id);

  static Map<String, dynamic> _event(String type, String text, [Map<String, dynamic>? extra, DateTime? at]) {
    final now = at ?? DateTime.now();
    return {
      'type': type,
      'text': text,
      't': Timestamp.fromDate(now),
      't2': now.millisecondsSinceEpoch,
      'by': currentUser?.name ?? '',
      ...?extra,
    };
  }

  static Future<void> _addEvent(String id, Map<String, dynamic> e) => ref(id).collection('events').add(e);

  // Açık bir duruş varsa süresini kapatır
  static Map<String, dynamic> _closeStop(PackOrder o) {
    if (o.status != 'durdu' || o.stopStartedAt == null) return <String, dynamic>{};
    final mins = math.max(1, DateTime.now().difference(o.stopStartedAt!).inMinutes);
    return {
      'stopMin.${o.stopReason ?? 'diger'}': FieldValue.increment(mins),
      'stopReason': null,
      'stopNote': '',
      'stopStartedAt': null,
    };
  }

  static Future<String> create({
    required String orderNo,
    required String productCode,
    required String workType,
    required int perBox,
    required int workers,
    required int daily,
  }) async {
    final me = currentUser!;
    final now = DateTime.now();
    final doc = col.doc();
    await doc.set({
      'orderNo': orderNo,
      'productCode': productCode,
      'workType': workType,
      'perBox': perBox,
      'ownerUid': me.uid,
      'ownerName': me.name,
      'status': 'calisiyor',
      'stopReason': null,
      'stopNote': '',
      'stopStartedAt': null,
      'currentDay': dayKey(now),
      'workers': workers,
      'daily': daily,
      'totalBoxes': 0,
      'totalUnits': 0,
      'todayBoxes': 0,
      'todayUnits': 0,
      'todayStartAt': Timestamp.fromDate(now),
      'lastUpdateAt': Timestamp.fromDate(now),
      'createdAt': FieldValue.serverTimestamp(),
      'finishedAt': null,
      'finishNote': '',
      'dayCount': 1,
      'pendingApprovals': 0,
      'stopMin': <String, dynamic>{},
    });
    await _addEvent(doc.id, _event('basla', '${kWorkTypes[workType] ?? ''} başladı · $workers çalışan + $daily günlükçü', {
      'workers': workers,
      'daily': daily,
    }));
    return doc.id;
  }

  static Future<void> addEntry(PackOrder o, int boxes, int units) async {
    final now = DateTime.now();
    final data = <String, dynamic>{'lastUpdateAt': Timestamp.fromDate(now)};
    if (o.perBox > 0) {
      final add = boxes * o.perBox + units;
      final tu = o.totalUnits + add;
      final du = o.todayUnits + add;
      data['totalUnits'] = tu;
      data['totalBoxes'] = tu ~/ o.perBox;
      data['todayUnits'] = du;
      data['todayBoxes'] = du ~/ o.perBox;
    } else {
      data['totalBoxes'] = FieldValue.increment(boxes);
      data['todayBoxes'] = FieldValue.increment(boxes);
    }
    await ref(o.id).update(data);
    await _addEvent(o.id, _event('koli', '', {'qty': boxes, 'units': units}, now));
  }

  static Future<void> stop(PackOrder o, String reason, String note) async {
    final now = DateTime.now();
    await ref(o.id).update({
      'status': 'durdu',
      'stopReason': reason,
      'stopNote': note,
      'stopStartedAt': Timestamp.fromDate(now),
      'lastUpdateAt': Timestamp.fromDate(now),
    });
    final label = kStopReasons[reason] ?? reason;
    await _addEvent(o.id, _event('dur', 'Durduruldu: $label${note.isEmpty ? '' : ' ($note)'}', {'reason': label, 'reasonKey': reason}));
    if (kAlertReasons.contains(reason)) {
      await db.collection('packAlerts').add({
        'type': 'durus',
        'createdAt': FieldValue.serverTimestamp(),
        'orderId': o.id,
        'orderNo': o.orderNo,
        'productCode': o.productCode,
        'reason': reason,
        'reasonLabel': label,
        'note': note,
        'by': currentUser?.name ?? '',
      });
    }
  }

  static Future<void> resume(PackOrder o) async {
    final label = kStopReasons[o.stopReason] ?? 'Diğer';
    final mins = o.stopStartedAt == null ? 0 : math.max(1, DateTime.now().difference(o.stopStartedAt!).inMinutes);
    await ref(o.id).update({
      ..._closeStop(o),
      'status': 'calisiyor',
      'lastUpdateAt': Timestamp.now(),
    });
    await _addEvent(o.id, _event('devam', 'Devam edildi · $label duruşu ${fmtMin(mins)}', {'reason': label, 'reasonKey': o.stopReason, 'minutes': mins}));
  }

  static Future<void> changeWorkers(PackOrder o, int workers, int daily) async {
    await ref(o.id).update({'workers': workers, 'daily': daily, 'lastUpdateAt': Timestamp.now()});
    await _addEvent(o.id, _event('personel', 'Çalışan sayısı güncellendi: ${o.workers}+${o.daily} → $workers+$daily', {
      'workers': workers,
      'daily': daily,
    }));
  }

  static Future<void> endDay(PackOrder o) async {
    await ref(o.id).update({
      ..._closeStop(o),
      'status': 'beklemede',
      'lastUpdateAt': Timestamp.now(),
    });
    await _addEvent(o.id, _event('gun_bitti', 'Gün bitti · bugün ${o.todayText}'));
  }

  static Future<void> startDay(PackOrder o, int workers, int daily) async {
    final now = DateTime.now();
    await ref(o.id).update({
      ..._closeStop(o),
      'status': 'calisiyor',
      'currentDay': dayKey(now),
      'workers': workers,
      'daily': daily,
      'todayBoxes': 0,
      'todayUnits': 0,
      'todayStartAt': Timestamp.fromDate(now),
      'dayCount': FieldValue.increment(1),
      'lastUpdateAt': Timestamp.fromDate(now),
    });
    await _addEvent(o.id, _event('basla', 'Yeni gün başladı · $workers çalışan + $daily günlükçü', {'workers': workers, 'daily': daily}));
  }

  static Future<void> finish(PackOrder o, String note) async {
    final now = DateTime.now();
    await ref(o.id).update({
      ..._closeStop(o),
      'status': 'bitti',
      'finishedAt': Timestamp.fromDate(now),
      'finishNote': note,
      'lastUpdateAt': Timestamp.fromDate(now),
    });
    await _addEvent(o.id, _event('bitti', 'Sipariş bitti · ${o.qtyText}${note.isEmpty ? '' : ' · Not: $note'}'));
  }

  static Future<void> undoFinish(PackOrder o) async {
    await ref(o.id).update({'status': 'beklemede', 'finishedAt': null, 'lastUpdateAt': Timestamp.now()});
    await _addEvent(o.id, _event('geri_al', 'Bitiş geri alındı, sipariş yeniden açık'));
  }

  static Future<void> addNote(PackOrder o, String note) async {
    await ref(o.id).update({'lastUpdateAt': Timestamp.now()});
    await _addEvent(o.id, _event('not', 'Not: $note'));
  }

  static Future<void> editOrder(PackOrder o, String orderNo, String productCode, String workType, int perBox) async {
    final changes = <String>[];
    if (orderNo != o.orderNo) changes.add('Sipariş no ${o.orderNo} → $orderNo');
    if (productCode != o.productCode) changes.add('Ürün kodu ${o.productCode} → $productCode');
    if (workType != o.workType) changes.add('İş türü → ${kWorkTypes[workType] ?? workType}');
    if (perBox != o.perBox) changes.add('Koli içi adet ${o.perBox} → $perBox');
    if (changes.isEmpty) return;
    await ref(o.id).update({'orderNo': orderNo, 'productCode': productCode, 'workType': workType, 'perBox': perBox});
    await _addEvent(o.id, _event('duzenle', 'Düzenlendi: ${changes.join(', ')}'));
    if (perBox != o.perBox) await recompute(o.id);
  }

  // Siparişin başlangıç / bitiş saatini düzeltir (ilgili hareketlerin saatini değiştirir)
  static Future<void> setTimes(PackOrder o, DateTime? start, DateTime? finish) async {
    final evSnap = await ref(o.id).collection('events').orderBy('t2').get();
    final events = evSnap.docs.map((d) => PackEvent.fromDoc(d)).toList();
    final changes = <String>[];
    Map<String, dynamic> tdata(DateTime at) => {
          't': Timestamp.fromDate(at),
          't2': at.millisecondsSinceEpoch,
          'editedBy': currentUser?.name ?? '',
          'editedAt': Timestamp.now(),
        };
    if (start != null && (o.createdAt == null || start.difference(o.createdAt!).inMinutes.abs() >= 1)) {
      PackEvent? first;
      for (final e in events) {
        if (e.type == 'basla') {
          first = e;
          break;
        }
      }
      if (first != null) {
        await ref(o.id).collection('events').doc(first.id).update(tdata(start));
      } else {
        await ref(o.id).update({'createdAt': Timestamp.fromDate(start)});
      }
      changes.add('Başlangıç ${fmtFull(o.createdAt)} → ${fmtFull(start)}');
    }
    if (finish != null && o.isFinished && (o.finishedAt == null || finish.difference(o.finishedAt!).inMinutes.abs() >= 1)) {
      PackEvent? last;
      for (final e in events) {
        if (e.type == 'bitti') last = e;
      }
      if (last != null) {
        await ref(o.id).collection('events').doc(last.id).update(tdata(finish));
      } else {
        await ref(o.id).update({'finishedAt': Timestamp.fromDate(finish)});
      }
      changes.add('Bitiş ${fmtFull(o.finishedAt)} → ${fmtFull(finish)}');
    }
    if (changes.isEmpty) return;
    await _addEvent(o.id, _event('duzenle', 'Saat düzeltildi: ${changes.join(', ')}'));
    await recompute(o.id);
  }

  static Future<void> editEvent(PackOrder o, PackEvent e, DateTime at, int qty, int units) async {
    final data = <String, dynamic>{
      't': Timestamp.fromDate(at),
      't2': at.millisecondsSinceEpoch,
      'editedBy': currentUser?.name ?? '',
      'editedAt': Timestamp.now(),
    };
    if (e.isEntry) {
      data['qty'] = qty;
      data['units'] = units;
    }
    await ref(o.id).collection('events').doc(e.id).update(data);
    await recompute(o.id);
  }

  static Future<void> deleteEvent(PackOrder o, PackEvent e) async {
    await ref(o.id).collection('events').doc(e.id).delete();
    await _addEvent(o.id, _event('duzenle', 'Kayıt silindi: ${e.displayText} (${fmtFull(e.t)})'));
    await recompute(o.id);
  }

  static Future<void> deleteOrder(PackOrder o) async {
    for (final sub in ['events', 'photos']) {
      final s = await ref(o.id).collection(sub).get();
      for (final d in s.docs) {
        if (sub == 'photos') await deleteStoredPhoto(d.data()['path']);
        await d.reference.delete();
      }
    }
    await ref(o.id).delete();
  }

  // Tüm hareketlerden toplamları, duruş sürelerini ve saatleri yeniden hesaplar
  static Future<void> recompute(String id) async {
    final snap = await ref(id).get();
    final o = PackOrder.fromDoc(snap);
    final evSnap = await ref(id).collection('events').orderBy('t2').get();
    final events = evSnap.docs.map((d) => PackEvent.fromDoc(d)).toList();
    int total = 0;
    int today = 0;
    final stopMin = <String, int>{};
    DateTime? openAt;
    String openReason = 'diger';
    DateTime? firstAt;
    DateTime? lastStartToday;
    DateTime? lastFinish;
    for (final e in events) {
      final at = e.t;
      if (at == null) continue;
      if (e.type == 'basla') firstAt ??= at;
      if (e.type == 'basla' && dayKey(at) == o.currentDay) lastStartToday = at;
      if (e.type == 'bitti') lastFinish = at;
      if (e.isEntry) {
        final v = o.perBox > 0 ? e.qty * o.perBox + e.units : e.qty;
        total += v;
        if (dayKey(at) == o.currentDay) today += v;
      } else if (e.type == 'dur') {
        openAt = at;
        openReason = e.reasonKey ?? 'diger';
      } else if (openAt != null && (e.type == 'devam' || e.type == 'gun_bitti' || e.type == 'bitti' || e.type == 'basla')) {
        final mins = math.max(1, at.difference(openAt).inMinutes);
        stopMin[openReason] = (stopMin[openReason] ?? 0) + mins;
        openAt = null;
      }
    }
    final data = <String, dynamic>{'stopMin': stopMin, 'lastUpdateAt': Timestamp.now()};
    if (firstAt != null) data['createdAt'] = Timestamp.fromDate(firstAt);
    if (lastStartToday != null) data['todayStartAt'] = Timestamp.fromDate(lastStartToday);
    if (o.status == 'durdu' && openAt != null) data['stopStartedAt'] = Timestamp.fromDate(openAt);
    if (o.status == 'bitti' && lastFinish != null) data['finishedAt'] = Timestamp.fromDate(lastFinish);
    if (o.perBox > 0) {
      data['totalUnits'] = total;
      data['totalBoxes'] = total ~/ o.perBox;
      data['todayUnits'] = today;
      data['todayBoxes'] = today ~/ o.perBox;
    } else {
      data['totalUnits'] = 0;
      data['totalBoxes'] = total;
      data['todayUnits'] = 0;
      data['todayBoxes'] = today;
    }
    await ref(id).update(data);
  }

  // Görseller
  static Future<void> addPhoto(PackOrder o, Uint8List bytes, String stage, List<String> approvers, String note) async {
    final now = DateTime.now();
    final up = await uploadPhoto('packOrders/${o.id}', bytes);
    await ref(o.id).collection('photos').add({
      't': Timestamp.fromDate(now),
      't2': now.millisecondsSinceEpoch,
      'by': currentUser?.name ?? '',
      'byUid': currentUser?.uid ?? '',
      'stage': stage,
      'note': note,
      'url': up['url'],
      'path': up['path'],
      'approvers': approvers,
      'approvals': <String, dynamic>{},
      'status': approvers.isEmpty ? 'bilgi' : 'bekliyor',
    });
    if (approvers.isNotEmpty) {
      await ref(o.id).update({'pendingApprovals': FieldValue.increment(1), 'lastUpdateAt': Timestamp.now()});
      await db.collection('packAlerts').add({
        'type': 'onay',
        'targetRoles': approvers,
        'createdAt': FieldValue.serverTimestamp(),
        'orderId': o.id,
        'orderNo': o.orderNo,
        'productCode': o.productCode,
        'reasonLabel': 'Görsel onayı',
        'by': currentUser?.name ?? '',
      });
    }
    final who = approvers.map((r) => kApproverRoles[r] ?? r).join(', ');
    await _addEvent(o.id, _event('gorsel', 'Görsel eklendi (${kPhotoStages[stage] ?? stage})${who.isEmpty ? '' : ' · onay isteniyor: $who'}'));
  }

  static Future<void> decidePhoto(PackOrder o, PackPhoto p, String role, bool approve, String note) async {
    final approvals = Map<String, dynamic>.from(p.approvals);
    approvals[role] = {
      'status': approve ? 'onay' : 'red',
      'by': currentUser?.name ?? '',
      't': Timestamp.now(),
      'note': note,
    };
    String status = 'bekliyor';
    bool anyRed = false;
    bool allOk = true;
    for (final r in p.approvers) {
      final a = approvals[r];
      final st = (a is Map) ? (a['status'] ?? '').toString() : '';
      if (st == 'red') anyRed = true;
      if (st != 'onay') allOk = false;
    }
    if (anyRed) {
      status = 'reddedildi';
    } else if (allOk) {
      status = 'onaylandi';
    }
    await ref(o.id).collection('photos').doc(p.id).update({'approvals': approvals, 'status': status});
    if (p.status == 'bekliyor' && status != 'bekliyor') {
      await ref(o.id).update({'pendingApprovals': FieldValue.increment(-1), 'lastUpdateAt': Timestamp.now()});
    } else if (p.status != 'bekliyor' && status == 'bekliyor') {
      await ref(o.id).update({'pendingApprovals': FieldValue.increment(1), 'lastUpdateAt': Timestamp.now()});
    }
    await _addEvent(o.id, _event('onay',
        'Görsel ${approve ? 'onaylandı' : 'reddedildi'} (${kApproverRoles[role] ?? role} · ${currentUser?.name ?? ''})${note.isEmpty ? '' : ': $note'}'));
  }
}

class PackPhoto {
  final String id;
  final DateTime? t;
  final String by;
  final String stage;
  final String note;
  final String data;
  final String url;
  final List<String> approvers;
  final Map<String, dynamic> approvals;
  final String status;

  PackPhoto({
    required this.id,
    required this.t,
    required this.by,
    required this.stage,
    required this.note,
    required this.data,
    this.url = '',
    required this.approvers,
    required this.approvals,
    required this.status,
  });

  factory PackPhoto.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final ap = m['approvers'];
    final al = m['approvals'];
    return PackPhoto(
      id: d.id,
      t: tsToDate(m['t']),
      by: (m['by'] ?? '').toString(),
      stage: (m['stage'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      data: (m['data'] ?? '').toString(),
      url: (m['url'] ?? '').toString(),
      approvers: ap is List ? ap.map((e) => e.toString()).toList() : <String>[],
      approvals: al is Map ? Map<String, dynamic>.from(al) : <String, dynamic>{},
      status: (m['status'] ?? 'bilgi').toString(),
    );
  }

  String roleStatus(String role) {
    final a = approvals[role];
    if (a is Map) return (a['status'] ?? '').toString();
    return '';
  }

  String roleInfo(String role) {
    final a = approvals[role];
    if (a is! Map) return 'Bekliyor';
    final st = a['status'] == 'onay' ? 'Onaylandı' : 'Reddedildi';
    final note = (a['note'] ?? '').toString();
    return '$st · ${a['by'] ?? ''} · ${fmtDT(tsToDate(a['t']))}${note.isEmpty ? '' : ' · $note'}';
  }
}

Stream<List<PackOrder>> packStream() {
  return PackOps.col
      .orderBy('createdAt', descending: true)
      .limit(400)
      .snapshots()
      .map((s) => s.docs.map((d) => PackOrder.fromDoc(d)).toList());
}

bool canEditPack(PackOrder o) {
  final me = currentUser;
  if (me == null) return false;
  if (me.can('paketleme', 'yonet')) return true;
  return me.uid == o.ownerUid && me.can('paketleme', 'gir');
}

bool isApprover(AppUser me) => me.isAdmin || kApproverRoles.containsKey(me.role);

// ---------------------------------------------------------------------------
// Ana ekran (paketleme)
// ---------------------------------------------------------------------------

class PackHome extends StatelessWidget {
  final AppUser me;
  final Widget? nav;
  const PackHome({super.key, required this.me, this.nav});

  @override
  Widget build(BuildContext context) {
    final canEnter = me.can('paketleme', 'gir');
    final seeAll = me.can('paketleme', 'yonet') || !canEnter;
    final bool Function(PackOrder) scope = seeAll ? (o) => true : (o) => o.ownerUid == me.uid;
    final approver = isApprover(me);
    final tabs = <Tab>[
      Tab(text: seeAll ? 'Canlı' : 'Aktif'),
      if (approver) const Tab(text: 'Onay bekleyen'),
      const Tab(text: 'Bitenler'),
    ];
    final views = <Widget>[
      PackList(filter: (o) => scope(o) && !o.isFinished, empty: canEnter ? 'Aktif paketleme yok.\nSağ alttaki düğmeyle başlatın.' : 'Şu an aktif paketleme yok.'),
      if (approver) PackList(filter: (o) => o.pendingApprovals > 0, empty: 'Onay bekleyen görsel yok.'),
      PackList(filter: (o) => scope(o) && o.isFinished, empty: 'Biten sipariş bulunamadı.', searchable: true),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bind · Paketleme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Text('${me.name} · ${me.roleLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
            ],
          ),
          actions: [
            if (me.can('rapor', 'gor'))
              IconButton(tooltip: "Excel'e aktar", icon: const Icon(Icons.download), onPressed: exportPackExcel),
            ...commonActions(me),
          ],
          bottom: TabBar(
            tabs: tabs,
            isScrollable: tabs.length > 2,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFADB5BD),
            indicatorColor: kOrange,
          ),
        ),
        floatingActionButton: canEnter
            ? FloatingActionButton.extended(
                backgroundColor: kOrange,
                foregroundColor: Colors.white,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewPackPage())),
                icon: const Icon(Icons.add),
                label: const Text('Yeni Paketleme'),
              )
            : null,
        bottomNavigationBar: nav,
        body: TabBarView(children: views),
      ),
    );
  }
}

class PackList extends StatefulWidget {
  final bool Function(PackOrder) filter;
  final String empty;
  final bool searchable;
  const PackList({super.key, required this.filter, required this.empty, this.searchable = false});

  @override
  State<PackList> createState() => _PackListState();
}

class _PackListState extends State<PackList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PackOrder>>(
      stream: packStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final q = _q.trim().toLowerCase();
        final list = snap.data!.where(widget.filter).where((o) {
          if (q.isEmpty) return true;
          return '${o.orderNo} ${o.productCode} ${o.ownerName} ${o.finishNote}'.toLowerCase().contains(q);
        }).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Sipariş no, ürün kodu, kişi ara'),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(child: Text(widget.empty, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 15))),
              ),
            for (final o in list)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: PackCard(o: o)),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Chip(this.text, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class PackStatusChip extends StatelessWidget {
  final PackOrder o;
  const PackStatusChip({super.key, required this.o});

  @override
  Widget build(BuildContext context) => _Chip(o.statusLabel, o.statusBgColor, o.statusFgColor);
}

bool canDeletePack(PackOrder o) {
  final me = currentUser;
  return me != null && (me.isAdmin || me.can('paketleme', 'yonet') || (me.uid == o.ownerUid && me.can('paketleme', 'gir')));
}

Future<bool> askDeletePack(BuildContext context, PackOrder o) async {
  if (!canDeletePack(o)) {
    toast('Bu siparişi silme yetkiniz yok.');
    return false;
  }
  if (!await confirm(context, 'Sipariş tamamen silinsin mi?',
      'Sipariş ${o.orderNo}, tüm koli girişleri, duruşlar ve görseller kalıcı olarak silinecek. Bu işlem geri alınamaz.', 'Sil')) {
    return false;
  }
  try {
    await PackOps.deleteOrder(o);
    toast('Sipariş silindi');
    return true;
  } catch (e) {
    toast('Silinemedi: $e');
    return false;
  }
}

class PackCard extends StatelessWidget {
  final PackOrder o;
  const PackCard({super.key, required this.o});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE3E6EA))),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PackDetailPage(orderId: o.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      PackStatusChip(o: o),
                      if (o.workTypeLabel.isNotEmpty) _Chip(o.workTypeLabel, const Color(0xFFDBE8FF), const Color(0xFF1D4ED8)),
                      if (o.pendingApprovals > 0) _Chip('${o.pendingApprovals} görsel onay bekliyor', const Color(0xFFFFF3BF), const Color(0xFF6B4F00)),
                    ]),
                    const SizedBox(height: 6),
                    Text('Sipariş ${o.orderNo}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text('Ürün: ${o.productCode}${o.perBox > 0 ? ' · koli içi ${o.perBox}' : ''}', style: const TextStyle(color: kMuted)),
                    const SizedBox(height: 2),
                    Text(
                      o.isFinished ? '${o.ownerName} · Bitiş: ${fmtDT(o.finishedAt)}' : '${o.ownerName} · Son güncelleme: ${fmtDT(o.lastUpdateAt)}',
                      style: const TextStyle(color: kMuted, fontSize: 13),
                    ),
                    if (o.isToday)
                      Text(
                        'Bugün: ${o.todayText}${o.rateText.isEmpty ? '' : ' · ${o.rateText}'} · ${o.workers}+${o.daily} kişi',
                        style: const TextStyle(color: kMuted, fontSize: 13),
                      ),
                    if (o.status == 'durdu' && o.stopStartedAt != null && o.isToday)
                      Row(children: [
                        const Text('Duruş süresi: ', style: TextStyle(color: Color(0xFF9A3412), fontSize: 13)),
                        Elapsed(start: o.stopStartedAt!, style: const TextStyle(color: Color(0xFF9A3412), fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${o.totalBoxes}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  Text(o.remUnits > 0 ? 'koli + ${o.remUnits} ad.' : 'koli', style: const TextStyle(color: kMuted)),
                  if (o.isFinished && canDeletePack(o))
                    IconButton(
                      tooltip: 'Siparişi sil',
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFC92A2A)),
                      onPressed: () => askDeletePack(context, o),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Yeni paketleme
// ---------------------------------------------------------------------------

class NewPackPage extends StatefulWidget {
  const NewPackPage({super.key});

  @override
  State<NewPackPage> createState() => _NewPackPageState();
}

class _NewPackPageState extends State<NewPackPage> {
  final _order = TextEditingController();
  final _product = TextEditingController();
  final _perBox = TextEditingController();
  final _workers = TextEditingController();
  final _daily = TextEditingController(text: '0');
  String? _type;
  bool _busy = false;

  Future<void> _start() async {
    final workers = int.tryParse(_workers.text.trim());
    final daily = int.tryParse(_daily.text.trim().isEmpty ? '0' : _daily.text.trim());
    final perBox = int.tryParse(_perBox.text.trim().isEmpty ? '0' : _perBox.text.trim());
    if (_type == null) {
      toast('Lütfen iş türünü seçin: Üretim, Karekod hazırlık ya da Ön hazırlık.');
      return;
    }
    if (_order.text.trim().isEmpty || _product.text.trim().isEmpty) {
      toast('Sipariş numarası ve ürün kodu gerekli.');
      return;
    }
    if (workers == null || daily == null || perBox == null) {
      toast('Sayıları rakamla girin.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await PackOps.create(
        orderNo: _order.text.trim(),
        productCode: _product.text.trim(),
        workType: _type!,
        perBox: perBox,
        workers: workers,
        daily: daily,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PackDetailPage(orderId: id)));
    } catch (e) {
      toast('Başlatılamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni paketleme')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('İş türü', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kWorkTypes.entries)
                ChoiceChip(
                  label: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(e.value)),
                  selected: _type == e.key,
                  onSelected: (_) => setState(() => _type = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(controller: _order, decoration: const InputDecoration(labelText: 'Sipariş numarası')),
          const SizedBox(height: 12),
          TextField(controller: _product, decoration: const InputDecoration(labelText: 'Ürün kodu')),
          const SizedBox(height: 12),
          TextField(
            controller: _perBox,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Koli içi adet (isteğe bağlı)', helperText: 'Girilirse koli yerine adet de girebilirsiniz'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _workers, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Çalışan sayısı'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _daily, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Günlükçü sayısı'))),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kGreen),
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(_busy ? 'Başlatılıyor…' : 'Başlat'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diyaloglar
// ---------------------------------------------------------------------------

Future<List<int>?> askEntry(BuildContext context, PackOrder o) {
  final c = TextEditingController();
  bool units = false;
  return showDialog<List<int>>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text(units ? 'Kaç adet eklendi?' : 'Kaç koli eklendi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (o.perBox > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(value: false, label: Text('Koli')),
                    ButtonSegment<bool>(value: true, label: Text('Adet')),
                  ],
                  selected: <bool>{units},
                  onSelectionChanged: (s) => setS(() => units = s.first),
                ),
              ),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(hintText: '0'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in const [10, 20, 50, 100]) ActionChip(label: Text('+$n'), onPressed: () => c.text = '$n'),
              ],
            ),
            if (units && o.perBox > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Koli içi ${o.perBox} adet; toplam otomatik koliye çevrilir.', style: const TextStyle(color: kMuted, fontSize: 13)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(c.text.trim());
              if (n == null || n <= 0) return;
              Navigator.pop(d, units ? <int>[0, n] : <int>[n, 0]);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    ),
  );
}

Future<List<int>?> askWorkers(BuildContext context, PackOrder o, {String title = 'Bugün kaç kişi çalışıyor?', String ok = 'Başlat'}) {
  final w = TextEditingController(text: o.workers > 0 ? '${o.workers}' : '');
  final dl = TextEditingController(text: '${o.daily}');
  return showDialog<List<int>>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: w, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Çalışan sayısı')),
          const SizedBox(height: 12),
          TextField(controller: dl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Günlükçü sayısı')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final a = int.tryParse(w.text.trim());
            final b = int.tryParse(dl.text.trim().isEmpty ? '0' : dl.text.trim());
            if (a == null || b == null) return;
            Navigator.pop(d, <int>[a, b]);
          },
          child: Text(ok),
        ),
      ],
    ),
  );
}

Future<List<String>?> askStop(BuildContext context) {
  String? reason;
  final note = TextEditingController();
  return showDialog<List<String>>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: const Text('Duruş nedeni'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in kStopReasons.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(reason == e.key ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: reason == e.key ? kDark : kMuted),
                  title: Text(e.value),
                  subtitle: kAlertReasons.contains(e.key) ? const Text('Kalite ve vardiya amirine bildirim gider') : null,
                  onTap: () => setS(() => reason = e.key),
                ),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: reason == null ? null : () => Navigator.pop(d, <String>[reason!, note.text.trim()]),
            child: const Text('Durdur'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> askText(BuildContext context, String title, String label, {String initial = '', String ok = 'Kaydet', bool mustFill = false}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            if (mustFill && c.text.trim().isEmpty) return;
            Navigator.pop(d, c.text.trim());
          },
          child: Text(ok),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String text, String ok) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

Future<void> editOrderDialog(BuildContext context, PackOrder o) async {
  final order = TextEditingController(text: o.orderNo);
  final product = TextEditingController(text: o.productCode);
  final perBox = TextEditingController(text: o.perBox > 0 ? '${o.perBox}' : '');
  String type = kWorkTypes.containsKey(o.workType) ? o.workType : 'uretim';
  DateTime start = o.createdAt ?? DateTime.now();
  DateTime finish = o.finishedAt ?? DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: const Text('Siparişi düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'İş türü'),
                items: kWorkTypes.entries.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setS(() => type = v ?? type),
              ),
              const SizedBox(height: 10),
              TextField(controller: order, decoration: const InputDecoration(labelText: 'Sipariş numarası')),
              const SizedBox(height: 10),
              TextField(controller: product, decoration: const InputDecoration(labelText: 'Ürün kodu')),
              const SizedBox(height: 10),
              TextField(controller: perBox, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Koli içi adet')),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text('Başlangıç: ${fmtFull(start)}'),
                  onPressed: () async {
                    final v = await pickDateTime(d, start, 'Başlangıç tarihi ve saati');
                    if (v != null) setS(() => start = v);
                  },
                ),
              ),
              if (o.isFinished) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.flag, size: 18),
                    label: Text('Bitiş: ${fmtFull(finish)}'),
                    onPressed: () async {
                      final v = await pickDateTime(d, finish, 'Bitiş tarihi ve saati');
                      if (v != null) setS(() => finish = v);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final pb = int.tryParse(perBox.text.trim().isEmpty ? '0' : perBox.text.trim());
  if (order.text.trim().isEmpty || product.text.trim().isEmpty || pb == null) {
    toast('Sipariş no, ürün kodu ve sayı alanlarını kontrol edin.');
    return;
  }
  try {
    await PackOps.editOrder(o, order.text.trim(), product.text.trim(), type, pb);
    await PackOps.setTimes(o, start, o.isFinished ? finish : null);
    toast('Kaydedildi');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

Future<void> editEventDialog(BuildContext context, PackOrder o, PackEvent e) async {
  DateTime at = e.t ?? DateTime.now();
  final qty = TextEditingController(text: '${e.qty}');
  final units = TextEditingController(text: '${e.units}');
  final action = await showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: const Text('Kaydı düzenle / sil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.displayText, style: const TextStyle(color: kMuted)),
              const SizedBox(height: 4),
              const Text('Saati değiştirince başlangıç, duruş ve bitiş saatleri ile toplamlar yeniden hesaplanır.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('${two(at.day)}.${two(at.month)}.${at.year}'),
                    onPressed: () async {
                      final dt = await showDatePicker(context: d, initialDate: at, firstDate: DateTime(2024), lastDate: DateTime(2100));
                      if (dt != null) setS(() => at = DateTime(dt.year, dt.month, dt.day, at.hour, at.minute));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('${two(at.hour)}:${two(at.minute)}'),
                    onPressed: () async {
                      final tm = await showTimePicker(context: d, initialTime: TimeOfDay(hour: at.hour, minute: at.minute));
                      if (tm != null) setS(() => at = DateTime(at.year, at.month, at.day, tm.hour, tm.minute));
                    },
                  ),
                ),
              ]),
              if (e.isEntry) ...[
                const SizedBox(height: 12),
                TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Koli')),
                if (o.perBox > 0) ...[
                  const SizedBox(height: 10),
                  TextField(controller: units, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Adet')),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, 'sil'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC92A2A)),
              child: const Text('Sil'),
            ),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, 'kaydet'), child: const Text('Kaydet')),
        ],
      ),
    ),
  );
  try {
    if (action == 'sil') {
      if (!context.mounted) return;
      if (await confirm(context, 'Kayıt silinsin mi?', e.displayText, 'Sil')) {
        await PackOps.deleteEvent(o, e);
        toast('Silindi, toplamlar yeniden hesaplandı.');
      }
    } else if (action == 'kaydet') {
      final q = int.tryParse(qty.text.trim()) ?? e.qty;
      final u = int.tryParse(units.text.trim().isEmpty ? '0' : units.text.trim()) ?? e.units;
      await PackOps.editEvent(o, e, at, q, u);
      toast('Kaydedildi, toplamlar yeniden hesaplandı.');
    }
  } catch (err) {
    toast('İşlem yapılamadı: $err');
  }
}

Future<void> addPhotoDialog(BuildContext context, PackOrder o) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Fotoğraf çek'), onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galeriden seç'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ],
      ),
    ),
  );
  if (source == null) return;
  Uint8List bytes;
  try {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 60);
    if (picked == null) return;
    bytes = await picked.readAsBytes();
  } catch (e) {
    toast('Fotoğraf alınamadı: $e');
    return;
  }
  if (bytes.length > 700000) {
    toast('Fotoğraf çok büyük, lütfen tekrar deneyin.');
    return;
  }
  if (!context.mounted) return;
  String stage = o.workType.isNotEmpty && kPhotoStages.containsKey(o.workType) ? o.workType : 'uretim';
  final approvers = <String>{};
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: const Text('Görsel ekle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(bytes, height: 160, fit: BoxFit.cover)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: stage,
                decoration: const InputDecoration(labelText: 'Aşama'),
                items: kPhotoStages.entries.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setS(() => stage = v ?? stage),
              ),
              const SizedBox(height: 12),
              const Text('Onay iste', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final r in kApproverRoles.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: approvers.contains(r.key),
                  title: Text(r.value),
                  onChanged: (v) => setS(() => v == true ? approvers.add(r.key) : approvers.remove(r.key)),
                ),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Gönder')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await PackOps.addPhoto(o, bytes, stage, approvers.toList(), note.text.trim());
    toast(approvers.isEmpty ? 'Görsel eklendi.' : 'Görsel gönderildi, onay istendi.');
  } catch (e) {
    toast('Gönderilemedi: $e');
  }
}

// ---------------------------------------------------------------------------
// Paketleme detayı
// ---------------------------------------------------------------------------

class PackDetailPage extends StatelessWidget {
  final String orderId;
  const PackDetailPage({super.key, required this.orderId});

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      toast('İşlem yapılamadı: $e');
    }
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: _box(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: kMuted, fontSize: 13)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paketleme detayı'), actions: [
        IconButton(
          tooltip: 'Siparişi sil',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final s = await PackOps.ref(orderId).get();
            if (!s.exists) return;
            final o = PackOrder.fromDoc(s);
            if (!context.mounted) return;
            if (await askDeletePack(context, o) && context.mounted) Navigator.of(context).pop();
          },
        ),
      ]),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: PackOps.ref(orderId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (!snap.data!.exists) return const Center(child: Text('Kayıt bulunamadı.'));
          final o = PackOrder.fromDoc(snap.data!);
          final canEdit = canEditPack(o);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _box(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text('Sipariş ${o.orderNo}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                    if (canEdit)
                      IconButton(tooltip: 'Siparişi düzenle', icon: const Icon(Icons.edit), onPressed: () => editOrderDialog(context, o)),
                  ]),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    PackStatusChip(o: o),
                    if (o.workTypeLabel.isNotEmpty) _Chip(o.workTypeLabel, const Color(0xFFDBE8FF), const Color(0xFF1D4ED8)),
                  ]),
                  const SizedBox(height: 6),
                  Text('Ürün kodu: ${o.productCode}${o.perBox > 0 ? ' · koli içi ${o.perBox} adet' : ''}', style: const TextStyle(fontSize: 15)),
                  Text('Sorumlu: ${o.ownerName} · Başlangıç: ${fmtDT(o.createdAt)}', style: const TextStyle(color: kMuted)),
                  if (o.isToday) Text('Bugün: ${o.workers} çalışan + ${o.daily} günlükçü', style: const TextStyle(color: kMuted)),
                  if (o.isFinished) Text('Bitiş: ${fmtDT(o.finishedAt)} · ${o.dayCount} gün', style: const TextStyle(color: kMuted)),
                  if (o.finishNote.isNotEmpty) Text('Bitiş notu: ${o.finishNote}', style: const TextStyle(fontStyle: FontStyle.italic)),
                ],
              )),
              const SizedBox(height: 10),
              Row(children: [
                _stat('Toplam', o.qtyText),
                const SizedBox(width: 10),
                _stat('Bugün', o.isToday ? o.todayText : '-'),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _stat('Hız', o.rateText.isEmpty ? '-' : o.rateText.replaceAll(' koli/saat', '/sa')),
                const SizedBox(width: 10),
                _stat('Son güncelleme', fmtDT(o.lastUpdateAt)),
              ]),
              const SizedBox(height: 10),
              if (o.status == 'durdu' && o.stopStartedAt != null && o.isToday)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFFE3D0), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Duruşta: ${kStopReasons[o.stopReason] ?? 'Diğer'}${o.stopNote.isEmpty ? '' : ' · ${o.stopNote}'}',
                          style: const TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w600, fontSize: 16)),
                      Elapsed(start: o.stopStartedAt!, style: const TextStyle(color: Color(0xFF9A3412), fontSize: 32, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              if (canEdit) ..._actions(context, o),
              if (o.stopMin.values.any((v) => v > 0)) ...[
                _box(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Toplam duruş: ${fmtMin(o.totalStopMin)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    for (final e in o.stopMin.entries)
                      if (e.value > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Expanded(child: Text(kStopReasons[e.key] ?? e.key)),
                            Text(fmtMin(e.value), style: const TextStyle(color: kMuted)),
                          ]),
                        ),
                  ],
                )),
                const SizedBox(height: 10),
              ],
              PackPhotos(order: o),
              const SizedBox(height: 10),
              PackEvents(order: o, canEdit: canEdit),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _actions(BuildContext context, PackOrder o) {
    const gap = SizedBox(height: 10);
    final finishBtn = OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: const Color(0xFFC92A2A)),
      onPressed: () async {
        final note = await askText(context, 'Sipariş bitirilsin mi?', 'Bilgi notu (isteğe bağlı)', ok: 'Bitir');
        if (note == null) return;
        await _run(() => PackOps.finish(o, note));
      },
      child: const Text('Siparişi bitir'),
    );
    final noteBtn = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: () async {
        final note = await askText(context, 'Not ekle', 'Bilgi notu', mustFill: true);
        if (note == null || note.isEmpty) return;
        await _run(() => PackOps.addNote(o, note));
      },
      icon: const Icon(Icons.sticky_note_2_outlined),
      label: const Text('Not ekle'),
    );
    if (o.isFinished) {
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kDark),
          onPressed: () async {
            if (await confirm(context, 'Bitiş geri alınsın mı?', 'Sipariş yeniden açılır, "Bugün başlat" ile devam edebilirsiniz.', 'Geri al')) {
              await _run(() => PackOps.undoFinish(o));
            }
          },
          icon: const Icon(Icons.undo),
          label: const Text('Bitişi geri al'),
        ),
        gap,
        noteBtn,
        gap,
      ];
    }
    if (o.needsDayStart) {
      return [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kGreen),
          onPressed: () async {
            final r = await askWorkers(context, o);
            if (r == null) return;
            await _run(() => PackOps.startDay(o, r[0], r[1]));
          },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Bugün başlat'),
        ),
        gap,
        Row(children: [Expanded(child: noteBtn), const SizedBox(width: 10), Expanded(child: finishBtn)]),
        gap,
      ];
    }
    final running = o.status == 'calisiyor';
    return [
      if (running) ...[
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kGreen),
          onPressed: () async {
            final r = await askEntry(context, o);
            if (r == null) return;
            await _run(() => PackOps.addEntry(o, r[0], r[1]));
          },
          icon: const Icon(Icons.add_box),
          label: Text(o.perBox > 0 ? 'Koli / adet gir' : 'Koli gir'),
        ),
        gap,
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kOrange),
          onPressed: () async {
            final r = await askStop(context);
            if (r == null) return;
            await _run(() => PackOps.stop(o, r[0], r[1]));
          },
          icon: const Icon(Icons.pause),
          label: const Text('Durdur'),
        ),
      ] else ...[
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kGreen),
          onPressed: () => _run(() => PackOps.resume(o)),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Devam et'),
        ),
      ],
      gap,
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              final r = await askWorkers(context, o, title: 'Çalışan sayısını güncelle', ok: 'Güncelle');
              if (r == null) return;
              await _run(() => PackOps.changeWorkers(o, r[0], r[1]));
            },
            icon: const Icon(Icons.groups),
            label: const Text('Kişi sayısı'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: noteBtn),
      ]),
      gap,
      Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              if (await confirm(context, 'Gün bitirilsin mi?', 'Sipariş açık kalır, yarın "Bugün başlat" ile devam edersiniz.', 'Günü bitir')) {
                await _run(() => PackOps.endDay(o));
              }
            },
            child: const Text('Günü bitir'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: finishBtn),
      ]),
      gap,
    ];
  }
}

class PackPhotos extends StatelessWidget {
  final PackOrder order;
  const PackPhotos({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final me = currentUser;
    final canAdd = canEditPack(order);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PackOps.ref(order.id).collection('photos').orderBy('t2', descending: true).snapshots(),
      builder: (context, snap) {
        final photos = snap.hasData ? snap.data!.docs.map((d) => PackPhoto.fromDoc(d)).toList() : <PackPhoto>[];
        if (photos.isEmpty && !canAdd) return const SizedBox.shrink();
        return _box(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('Görseller ve onaylar', style: TextStyle(fontWeight: FontWeight.w600))),
              if (canAdd)
                TextButton.icon(onPressed: () => addPhotoDialog(context, order), icon: const Icon(Icons.add_a_photo), label: const Text('Görsel ekle')),
            ]),
            if (photos.isEmpty) const Text('Henüz görsel yok.', style: TextStyle(color: kMuted)),
            for (final p in photos) ...[
              const Divider(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => openStoredImage(context, p.url, p.data),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: storedImage(p.url, p.data, width: 96, height: 96),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${kPhotoStages[p.stage] ?? p.stage} · ${p.by}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(fmtDT(p.t), style: const TextStyle(color: kMuted, fontSize: 12)),
                        if (p.note.isNotEmpty) Text(p.note, style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        if (p.approvers.isEmpty) const Text('Bilgi amaçlı', style: TextStyle(color: kMuted, fontSize: 12)),
                        for (final r in p.approvers)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${kApproverRoles[r] ?? r}: ${p.roleInfo(r)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.roleStatus(r) == 'onay'
                                          ? const Color(0xFF1B6B2B)
                                          : (p.roleStatus(r) == 'red' ? const Color(0xFFC92A2A) : const Color(0xFF6B4F00)),
                                      fontWeight: FontWeight.w600,
                                    )),
                                if (me != null && (me.role == r || me.isAdmin))
                                  Wrap(spacing: 6, children: [
                                    OutlinedButton(
                                      onPressed: () async {
                                        final note = await askText(context, 'Onayla', 'Açıklama (isteğe bağlı)', ok: 'Onayla');
                                        if (note == null) return;
                                        try {
                                          await PackOps.decidePhoto(order, p, r, true, note);
                                        } catch (e) {
                                          toast('Hata: $e');
                                        }
                                      },
                                      child: const Text('Onayla'),
                                    ),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC92A2A)),
                                      onPressed: () async {
                                        final note = await askText(context, 'Reddet', 'Red nedeni', ok: 'Reddet', mustFill: true);
                                        if (note == null || note.isEmpty) return;
                                        try {
                                          await PackOps.decidePhoto(order, p, r, false, note);
                                        } catch (e) {
                                          toast('Hata: $e');
                                        }
                                      },
                                      child: const Text('Reddet'),
                                    ),
                                  ]),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ));
      },
    );
  }
}

class PackEvents extends StatelessWidget {
  final PackOrder order;
  final bool canEdit;
  const PackEvents({super.key, required this.order, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PackOps.ref(order.id).collection('events').orderBy('t2', descending: true).limit(300).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final events = snap.data!.docs.map((d) => PackEvent.fromDoc(d)).toList();
        return _box(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(canEdit ? 'Hareketler (düzenlemek için dokunun)' : 'Hareketler', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final e in events)
              InkWell(
                onTap: canEdit && e.type != 'duzenle' ? () => editEventDialog(context, order, e) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 120, child: Text(fmtFull(e.t), style: const TextStyle(color: kMuted, fontSize: 13))),
                      Expanded(
                        child: Text(
                          '${e.displayText} · ${e.by}${e.edited ? ' (düzenlendi)' : ''}',
                          style: TextStyle(fontSize: 13, fontWeight: e.isEntry ? FontWeight.w600 : FontWeight.normal),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ));
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Excel
// ---------------------------------------------------------------------------

Future<void> exportPackExcel() async {
  try {
    toast('Excel dosyası hazırlanıyor…');
    final orders = await PackOps.col.orderBy('createdAt').get();
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Siparişler');
    final xl.Sheet s1 = excel['Siparişler'];
    final xl.Sheet s2 = excel['Hareketler'];
    xl.CellValue t(String v) => xl.TextCellValue(v);
    xl.CellValue n(int v) => xl.IntCellValue(v);

    final reasonKeys = kStopReasons.keys.toList();
    s1.appendRow(<xl.CellValue?>[
      t('Sipariş no'), t('Ürün kodu'), t('İş türü'), t('Sorumlu'), t('Başlangıç'), t('Bitiş'), t('Durum'),
      t('Toplam koli'), t('Artan adet'), t('Koli içi adet'), t('Gün sayısı'), t('Son güncelleme'), t('Bitiş notu'),
      for (final k in reasonKeys) t('${kStopReasons[k]} (dk)'),
    ]);
    s2.appendRow(<xl.CellValue?>[
      t('Sipariş no'), t('Ürün kodu'), t('İş türü'), t('Tarih saat'), t('İşlem'), t('Eklenen koli'), t('Eklenen adet'),
      t('Toplam koli'), t('Çalışan'), t('Günlükçü'), t('Duruş nedeni'), t('Duruş (dk)'), t('Giren'), t('Düzenlendi'),
    ]);

    for (final d in orders.docs) {
      final o = PackOrder.fromDoc(d);
      s1.appendRow(<xl.CellValue?>[
        t(o.orderNo), t(o.productCode), t(o.workTypeLabel), t(o.ownerName), t(fmtFull(o.createdAt)), t(fmtFull(o.finishedAt)), t(o.statusLabel),
        n(o.totalBoxes), n(o.remUnits), n(o.perBox), n(o.dayCount), t(fmtFull(o.lastUpdateAt)), t(o.finishNote),
        for (final k in reasonKeys) n(o.stopMin[k] ?? 0),
      ]);
      final ev = await PackOps.ref(o.id).collection('events').orderBy('t2').get();
      int running = 0;
      for (final e in ev.docs) {
        final m = e.data();
        final pe = PackEvent.fromDoc(e);
        if (pe.isEntry) running += o.perBox > 0 ? pe.qty * o.perBox + pe.units : pe.qty;
        final runningBoxes = o.perBox > 0 ? running ~/ o.perBox : running;
        int? opt(String k) => (m[k] is num) ? (m[k] as num).toInt() : null;
        final minutes = opt('minutes');
        s2.appendRow(<xl.CellValue?>[
          t(o.orderNo), t(o.productCode), t(o.workTypeLabel), t(fmtFull(pe.t)), t(pe.displayText),
          pe.isEntry ? n(pe.qty) : null,
          pe.isEntry && pe.units != 0 ? n(pe.units) : null,
          pe.isEntry ? n(runningBoxes) : null,
          pe.workers == null ? null : n(pe.workers!),
          pe.daily == null ? null : n(pe.daily!),
          t(kStopReasons[pe.reasonKey] ?? ''),
          minutes == null ? null : n(minutes),
          t(pe.by),
          t(pe.edited ? 'Evet' : ''),
        ]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final file = File('${dir.path}/bind_paketleme_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Bind paketleme kayıtları');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}
