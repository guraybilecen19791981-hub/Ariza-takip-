part of 'main.dart';

// ---------------------------------------------------------------------------
// Paketleme takip modülü
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

String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

class PackOrder {
  final String id;
  final String orderNo;
  final String productCode;
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
  final int todayBoxes;
  final DateTime? todayStartAt;
  final DateTime? lastUpdateAt;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final int dayCount;
  final Map<String, int> stopMin;

  PackOrder({
    required this.id,
    required this.orderNo,
    required this.productCode,
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
    required this.todayBoxes,
    required this.todayStartAt,
    required this.lastUpdateAt,
    required this.createdAt,
    required this.finishedAt,
    required this.dayCount,
    required this.stopMin,
  });

  static int _i(dynamic v) => (v is num) ? v.toInt() : 0;

  factory PackOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final sm = <String, int>{};
    final raw = m['stopMin'];
    if (raw is Map) {
      raw.forEach((k, v) => sm[k.toString()] = _i(v));
    }
    return PackOrder(
      id: d.id,
      orderNo: (m['orderNo'] ?? '').toString(),
      productCode: (m['productCode'] ?? '').toString(),
      ownerUid: (m['ownerUid'] ?? '').toString(),
      ownerName: (m['ownerName'] ?? '').toString(),
      status: (m['status'] ?? 'calisiyor').toString(),
      stopReason: m['stopReason']?.toString(),
      stopNote: (m['stopNote'] ?? '').toString(),
      stopStartedAt: tsToDate(m['stopStartedAt']),
      currentDay: (m['currentDay'] ?? '').toString(),
      workers: _i(m['workers']),
      daily: _i(m['daily']),
      totalBoxes: _i(m['totalBoxes']),
      todayBoxes: _i(m['todayBoxes']),
      todayStartAt: tsToDate(m['todayStartAt']),
      lastUpdateAt: tsToDate(m['lastUpdateAt']),
      createdAt: tsToDate(m['createdAt']),
      finishedAt: tsToDate(m['finishedAt']),
      dayCount: _i(m['dayCount']),
      stopMin: sm,
    );
  }

  bool get isFinished => status == 'bitti';
  bool get needsDayStart => !isFinished && (status == 'beklemede' || currentDay != dayKey(DateTime.now()));

  String get statusLabel {
    if (isFinished) return 'Bitti';
    if (needsDayStart) return status == 'beklemede' ? 'Gün bitti' : 'Bugün başlatılmadı';
    if (status == 'durdu') return 'Durdu: ${kStopReasons[stopReason] ?? 'Diğer'}';
    return 'Çalışıyor';
  }

  Color get statusBgColor {
    if (isFinished) return const Color(0xFFE9ECEF);
    if (needsDayStart) return const Color(0xFFE9ECEF);
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
    if (start == null || todayBoxes == 0 || currentDay != dayKey(DateTime.now())) return '';
    final hours = DateTime.now().difference(start).inMinutes / 60.0;
    if (hours < 0.1) return '';
    return '${(todayBoxes / hours).toStringAsFixed(0)} koli/saat';
  }

  int get totalStopMin => stopMin.values.fold(0, (a, b) => a + b);
}

class PackOps {
  static CollectionReference<Map<String, dynamic>> get col => db.collection('packOrders');
  static DocumentReference<Map<String, dynamic>> ref(String id) => col.doc(id);

  static Map<String, dynamic> _event(String type, String text, [Map<String, dynamic>? extra]) {
    final now = DateTime.now();
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

  static Future<String> create({required String orderNo, required String productCode, required int workers, required int daily}) async {
    final me = currentUser!;
    final now = DateTime.now();
    final doc = col.doc();
    await doc.set({
      'orderNo': orderNo,
      'productCode': productCode,
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
      'todayBoxes': 0,
      'todayStartAt': Timestamp.fromDate(now),
      'lastUpdateAt': Timestamp.fromDate(now),
      'createdAt': FieldValue.serverTimestamp(),
      'finishedAt': null,
      'dayCount': 1,
      'stopMin': <String, dynamic>{},
    });
    await _addEvent(doc.id, _event('basla', 'Paketleme başladı · $workers çalışan + $daily günlükçü', {
      'workers': workers,
      'daily': daily,
      'total': 0,
    }));
    return doc.id;
  }

  static Future<void> addBoxes(PackOrder o, int qty) async {
    final now = DateTime.now();
    await ref(o.id).update({
      'totalBoxes': FieldValue.increment(qty),
      'todayBoxes': FieldValue.increment(qty),
      'lastUpdateAt': Timestamp.fromDate(now),
    });
    await _addEvent(o.id, _event('koli', '+$qty koli · toplam ${o.totalBoxes + qty}', {'qty': qty, 'total': o.totalBoxes + qty}));
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
    await _addEvent(o.id, _event('dur', 'Durduruldu: $label${note.isEmpty ? '' : ' ($note)'}', {'reason': label, 'total': o.totalBoxes}));
    if (kAlertReasons.contains(reason)) {
      await db.collection('packAlerts').add({
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
    await _addEvent(o.id, _event('devam', 'Devam edildi · $label duruşu ${fmtMin(mins)}', {'reason': label, 'minutes': mins, 'total': o.totalBoxes}));
  }

  static Future<void> endDay(PackOrder o) async {
    await ref(o.id).update({
      ..._closeStop(o),
      'status': 'beklemede',
      'lastUpdateAt': Timestamp.now(),
    });
    await _addEvent(o.id, _event('gun_bitti', 'Gün bitti · bugün ${o.todayBoxes} koli', {'total': o.totalBoxes, 'qty': o.todayBoxes}));
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
      'todayStartAt': Timestamp.fromDate(now),
      'dayCount': FieldValue.increment(1),
      'lastUpdateAt': Timestamp.fromDate(now),
    });
    await _addEvent(o.id, _event('basla', 'Yeni gün başladı · $workers çalışan + $daily günlükçü', {
      'workers': workers,
      'daily': daily,
      'total': o.totalBoxes,
    }));
  }

  static Future<void> finish(PackOrder o) async {
    final now = DateTime.now();
    await ref(o.id).update({
      ..._closeStop(o),
      'status': 'bitti',
      'finishedAt': Timestamp.fromDate(now),
      'lastUpdateAt': Timestamp.fromDate(now),
    });
    await _addEvent(o.id, _event('bitti', 'Sipariş bitti · toplam ${o.totalBoxes} koli', {'total': o.totalBoxes}));
  }
}

Stream<List<PackOrder>> packStream() {
  return PackOps.col
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map((d) => PackOrder.fromDoc(d)).toList());
}

// ---------------------------------------------------------------------------
// Ana ekran (paketleme)
// ---------------------------------------------------------------------------

class PackHome extends StatelessWidget {
  final AppUser me;
  final bool monitor;
  final Widget? nav;
  const PackHome({super.key, required this.me, required this.monitor, this.nav});

  @override
  Widget build(BuildContext context) {
    final bool Function(PackOrder) mine = monitor ? (o) => true : (o) => o.ownerUid == me.uid;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paketleme Takip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Text('${me.name} · ${me.roleLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
            ],
          ),
          actions: [
            if (monitor)
              IconButton(
                tooltip: "Excel'e aktar",
                icon: const Icon(Icons.download),
                onPressed: exportPackExcel,
              ),
            ...commonActions(me),
          ],
          bottom: TabBar(
            tabs: [Tab(text: monitor ? 'Canlı' : 'Aktif'), const Tab(text: 'Bitenler')],
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFADB5BD),
            indicatorColor: kOrange,
          ),
        ),
        floatingActionButton: (me.role == 'paketci' || me.role == 'admin')
            ? FloatingActionButton.extended(
                backgroundColor: kOrange,
                foregroundColor: Colors.white,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewPackPage())),
                icon: const Icon(Icons.add),
                label: const Text('Yeni Paketleme'),
              )
            : null,
        bottomNavigationBar: nav,
        body: TabBarView(children: [
          PackList(filter: (o) => mine(o) && !o.isFinished, empty: monitor ? 'Şu an aktif paketleme yok.' : 'Aktif paketlemeniz yok.\nSağ alttaki düğmeyle başlatın.'),
          PackList(filter: (o) => mine(o) && o.isFinished, empty: 'Henüz biten sipariş yok.'),
        ]),
      ),
    );
  }
}

class PackList extends StatelessWidget {
  final bool Function(PackOrder) filter;
  final String empty;
  const PackList({super.key, required this.filter, required this.empty});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PackOrder>>(
      stream: packStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!.where(filter).toList();
        if (list.isEmpty) {
          return Center(child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 15)));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => PackCard(o: list[i]),
        );
      },
    );
  }
}

class PackStatusChip extends StatelessWidget {
  final PackOrder o;
  const PackStatusChip({super.key, required this.o});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: o.statusBgColor, borderRadius: BorderRadius.circular(999)),
      child: Text(o.statusLabel, style: TextStyle(color: o.statusFgColor, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class PackCard extends StatelessWidget {
  final PackOrder o;
  const PackCard({super.key, required this.o});

  @override
  Widget build(BuildContext context) {
    final today = o.currentDay == dayKey(DateTime.now());
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
                    PackStatusChip(o: o),
                    const SizedBox(height: 6),
                    Text('Sipariş ${o.orderNo}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text('Ürün: ${o.productCode}', style: const TextStyle(color: kMuted)),
                    const SizedBox(height: 2),
                    Text(
                      o.isFinished
                          ? '${o.ownerName} · Bitiş: ${fmtDT(o.finishedAt)}'
                          : '${o.ownerName} · Son güncelleme: ${fmtDT(o.lastUpdateAt)}',
                      style: const TextStyle(color: kMuted, fontSize: 13),
                    ),
                    if (!o.isFinished && today)
                      Text(
                        'Bugün: ${o.todayBoxes} koli${o.rateText.isEmpty ? '' : ' · ${o.rateText}'} · ${o.workers}+${o.daily} kişi',
                        style: const TextStyle(color: kMuted, fontSize: 13),
                      ),
                    if (o.status == 'durdu' && o.stopStartedAt != null && !o.needsDayStart)
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
                  const Text('koli', style: TextStyle(color: kMuted)),
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
  final _workers = TextEditingController();
  final _daily = TextEditingController(text: '0');
  bool _busy = false;

  Future<void> _start() async {
    final workers = int.tryParse(_workers.text.trim());
    final daily = int.tryParse(_daily.text.trim().isEmpty ? '0' : _daily.text.trim());
    if (_order.text.trim().isEmpty || _product.text.trim().isEmpty) {
      toast('Sipariş numarası ve ürün kodu gerekli.');
      return;
    }
    if (workers == null || daily == null) {
      toast('Çalışan sayılarını rakamla girin.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await PackOps.create(
        orderNo: _order.text.trim(),
        productCode: _product.text.trim(),
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
          TextField(controller: _order, decoration: const InputDecoration(labelText: 'Sipariş numarası')),
          const SizedBox(height: 12),
          TextField(controller: _product, decoration: const InputDecoration(labelText: 'Ürün kodu')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _workers,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Çalışan sayısı'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _daily,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Günlükçü sayısı'),
              ),
            ),
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
// Paketleme detayı
// ---------------------------------------------------------------------------

Future<int?> askBoxes(BuildContext context) {
  final c = TextEditingController();
  return showDialog<int>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Kaç koli eklendi?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
              for (final n in const [10, 20, 50, 100])
                ActionChip(label: Text('+$n'), onPressed: () => c.text = '$n'),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(c.text.trim());
            if (n == null || n <= 0) return;
            Navigator.pop(d, n);
          },
          child: const Text('Ekle'),
        ),
      ],
    ),
  );
}

Future<List<int>?> askWorkers(BuildContext context, PackOrder o) {
  final w = TextEditingController(text: o.workers > 0 ? '${o.workers}' : '');
  final dl = TextEditingController(text: '${o.daily}');
  return showDialog<List<int>>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Bugün kaç kişi çalışıyor?'),
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
          child: const Text('Başlat'),
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
                  leading: Icon(reason == e.key ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: reason == e.key ? kDark : kMuted),
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
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Paketleme detayı')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: PackOps.ref(orderId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (!snap.data!.exists) return const Center(child: Text('Kayıt bulunamadı.'));
          final o = PackOrder.fromDoc(snap.data!);
          final canEdit = me != null && (me.uid == o.ownerUid || me.role == 'admin') && !o.isFinished;
          final today = o.currentDay == dayKey(DateTime.now());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _box(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text('Sipariş ${o.orderNo}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                    PackStatusChip(o: o),
                  ]),
                  const SizedBox(height: 4),
                  Text('Ürün kodu: ${o.productCode}', style: const TextStyle(fontSize: 15)),
                  Text('Sorumlu: ${o.ownerName} · Başlangıç: ${fmtDT(o.createdAt)}', style: const TextStyle(color: kMuted)),
                  if (!o.isFinished && today)
                    Text('Bugün: ${o.workers} çalışan + ${o.daily} günlükçü', style: const TextStyle(color: kMuted)),
                  if (o.isFinished) Text('Bitiş: ${fmtDT(o.finishedAt)} · ${o.dayCount} gün', style: const TextStyle(color: kMuted)),
                ],
              )),
              const SizedBox(height: 10),
              Row(children: [
                _stat('Toplam koli', '${o.totalBoxes}'),
                const SizedBox(width: 10),
                _stat('Bugün', today ? '${o.todayBoxes}' : '-'),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _stat('Hız', o.rateText.isEmpty ? '-' : o.rateText.replaceAll(' koli/saat', '/sa')),
                const SizedBox(width: 10),
                _stat('Son güncelleme', fmtDT(o.lastUpdateAt)),
              ]),
              const SizedBox(height: 10),
              if (o.status == 'durdu' && o.stopStartedAt != null && !o.needsDayStart)
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
              if (o.stopMin.isNotEmpty) ...[
                const SizedBox(height: 4),
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
              ],
              const SizedBox(height: 10),
              PackEvents(orderId: o.id),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _actions(BuildContext context, PackOrder o) {
    const gap = SizedBox(height: 10);
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
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () async {
            if (await confirm(context, 'Sipariş bitirilsin mi?', 'Toplam ${o.totalBoxes} koli ile sipariş kapanacak.', 'Bitir')) {
              await _run(() => PackOps.finish(o));
            }
          },
          child: const Text('Siparişi bitir'),
        ),
        gap,
      ];
    }
    final running = o.status == 'calisiyor';
    return [
      if (running) ...[
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kGreen),
          onPressed: () async {
            final n = await askBoxes(context);
            if (n == null) return;
            await _run(() => PackOps.addBoxes(o, n));
          },
          icon: const Icon(Icons.add_box),
          label: const Text('Koli gir'),
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
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: const Color(0xFFC92A2A)),
            onPressed: () async {
              if (await confirm(context, 'Sipariş bitirilsin mi?', 'Toplam ${o.totalBoxes} koli ile sipariş kapanacak.', 'Bitir')) {
                await _run(() => PackOps.finish(o));
              }
            },
            child: const Text('Siparişi bitir'),
          ),
        ),
      ]),
      gap,
    ];
  }
}

class PackEvents extends StatelessWidget {
  final String orderId;
  const PackEvents({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PackOps.ref(orderId).collection('events').orderBy('t2', descending: true).limit(200).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        return _box(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hareketler', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final d in docs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: Text(fmtDT(tsToDate(d.data()['t'])), style: const TextStyle(color: kMuted, fontSize: 13))),
                    Expanded(child: Text((d.data()['text'] ?? '').toString(), style: const TextStyle(fontSize: 13))),
                  ],
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

    final reasonKeys = kStopReasons.keys.toList();
    s1.appendRow(<xl.CellValue?>[
      xl.TextCellValue('Sipariş no'),
      xl.TextCellValue('Ürün kodu'),
      xl.TextCellValue('Sorumlu'),
      xl.TextCellValue('Başlangıç'),
      xl.TextCellValue('Bitiş'),
      xl.TextCellValue('Durum'),
      xl.TextCellValue('Toplam koli'),
      xl.TextCellValue('Gün sayısı'),
      xl.TextCellValue('Son güncelleme'),
      for (final k in reasonKeys) xl.TextCellValue('${kStopReasons[k]} (dk)'),
    ]);
    s2.appendRow(<xl.CellValue?>[
      xl.TextCellValue('Sipariş no'),
      xl.TextCellValue('Ürün kodu'),
      xl.TextCellValue('Tarih saat'),
      xl.TextCellValue('İşlem'),
      xl.TextCellValue('Eklenen koli'),
      xl.TextCellValue('Toplam koli'),
      xl.TextCellValue('Çalışan'),
      xl.TextCellValue('Günlükçü'),
      xl.TextCellValue('Duruş nedeni'),
      xl.TextCellValue('Duruş (dk)'),
      xl.TextCellValue('Giren'),
    ]);

    for (final d in orders.docs) {
      final o = PackOrder.fromDoc(d);
      s1.appendRow(<xl.CellValue?>[
        xl.TextCellValue(o.orderNo),
        xl.TextCellValue(o.productCode),
        xl.TextCellValue(o.ownerName),
        xl.TextCellValue(fmtFull(o.createdAt)),
        xl.TextCellValue(fmtFull(o.finishedAt)),
        xl.TextCellValue(o.statusLabel),
        xl.IntCellValue(o.totalBoxes),
        xl.IntCellValue(o.dayCount),
        xl.TextCellValue(fmtFull(o.lastUpdateAt)),
        for (final k in reasonKeys) xl.IntCellValue(o.stopMin[k] ?? 0),
      ]);
      final ev = await PackOps.ref(o.id).collection('events').orderBy('t2').get();
      for (final e in ev.docs) {
        final m = e.data();
        int? n(String k) => (m[k] is num) ? (m[k] as num).toInt() : null;
        final qty = n('qty');
        final total = n('total');
        final workers = n('workers');
        final daily = n('daily');
        final minutes = n('minutes');
        s2.appendRow(<xl.CellValue?>[
          xl.TextCellValue(o.orderNo),
          xl.TextCellValue(o.productCode),
          xl.TextCellValue(fmtFull(tsToDate(m['t']))),
          xl.TextCellValue((m['text'] ?? '').toString()),
          qty == null ? null : xl.IntCellValue(qty),
          total == null ? null : xl.IntCellValue(total),
          workers == null ? null : xl.IntCellValue(workers),
          daily == null ? null : xl.IntCellValue(daily),
          xl.TextCellValue((m['reason'] ?? '').toString()),
          minutes == null ? null : xl.IntCellValue(minutes),
          xl.TextCellValue((m['by'] ?? '').toString()),
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
    final file = File('${dir.path}/paketleme_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Paketleme kayıtları');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}
