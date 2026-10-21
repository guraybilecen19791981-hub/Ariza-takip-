part of 'main.dart';

// ---------------------------------------------------------------------------
// Paletleme modülü
// ---------------------------------------------------------------------------

double _toDouble(dynamic v) => (v is num) ? v.toDouble() : 0.0;
double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
String _trimNum(double v, int dec) {
  var t = v.toStringAsFixed(dec);
  if (t.contains('.')) t = t.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return t;
}
String fmtKg(double v) => _trimNum(v, 2);
String fmtKg3(double v) => _trimNum(v, 3);

class PLine {
  String productCode;
  int boxes;
  int perBox;
  String lot;
  String skt;
  double boxGross; // 1 koli brüt kg
  double boxNet; // 1 koli net kg
  PLine({required this.productCode, required this.boxes, required this.perBox, this.lot = '', this.skt = '', this.boxGross = 0, this.boxNet = 0});

  factory PLine.fromMap(dynamic m) {
    final x = (m is Map) ? m : <String, dynamic>{};
    return PLine(
      productCode: (x['productCode'] ?? '').toString(),
      boxes: _toInt(x['boxes']),
      perBox: _toInt(x['perBox']),
      lot: (x['lot'] ?? '').toString(),
      skt: (x['skt'] ?? '').toString(),
      boxGross: _toDouble(x['boxGross']),
      boxNet: _toDouble(x['boxNet']),
    );
  }

  Map<String, dynamic> toMap() =>
      {'productCode': productCode, 'boxes': boxes, 'perBox': perBox, 'lot': lot, 'skt': skt, 'boxGross': boxGross, 'boxNet': boxNet};
  int get units => boxes * perBox;
  double get gross => boxes * boxGross;
  double get net => boxes * boxNet;
  bool get hasKg => boxGross > 0 || boxNet > 0;
  PLine copy() => PLine(productCode: productCode, boxes: boxes, perBox: perBox, lot: lot, skt: skt, boxGross: boxGross, boxNet: boxNet);
}

List<PLine> _lines(dynamic v) => v is List ? v.map((e) => PLine.fromMap(e)).toList() : <PLine>[];

class PalletOrder {
  final String id;
  final String orderNo;
  final String customer;
  final String status; // acik | bitti
  final String createdBy;
  final String createdByUid;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final DateTime? shippedAt;
  final String finishNote;
  final List<PLine> lines;
  final int palletCount;
  final int totalBoxes;
  final int totalUnits;
  final double gross;
  final double net;
  final int photoCount;
  final int nextNo;
  final Map<String, int> packedByProduct;

  PalletOrder({
    required this.id,
    required this.orderNo,
    required this.customer,
    required this.status,
    required this.createdBy,
    required this.createdByUid,
    required this.createdAt,
    required this.finishedAt,
    required this.shippedAt,
    required this.finishNote,
    required this.lines,
    required this.palletCount,
    required this.totalBoxes,
    required this.totalUnits,
    required this.gross,
    required this.net,
    required this.photoCount,
    required this.nextNo,
    required this.packedByProduct,
  });

  factory PalletOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final pb = <String, int>{};
    final raw = m['packedByProduct'];
    if (raw is Map) raw.forEach((k, v) => pb[k.toString()] = _toInt(v));
    return PalletOrder(
      id: d.id,
      orderNo: (m['orderNo'] ?? '').toString(),
      customer: (m['customer'] ?? '').toString(),
      status: (m['status'] ?? 'acik').toString(),
      createdBy: (m['createdBy'] ?? '').toString(),
      createdByUid: (m['createdByUid'] ?? '').toString(),
      createdAt: tsToDate(m['createdAt']),
      finishedAt: tsToDate(m['finishedAt']),
      shippedAt: tsToDate(m['shippedAt']),
      finishNote: (m['finishNote'] ?? '').toString(),
      lines: _lines(m['lines']),
      palletCount: _toInt(m['palletCount']),
      totalBoxes: _toInt(m['totalBoxes']),
      totalUnits: _toInt(m['totalUnits']),
      gross: _toDouble(m['gross']),
      net: _toDouble(m['net']),
      photoCount: _toInt(m['photoCount']),
      nextNo: math.max(1, _toInt(m['nextNo'])),
      packedByProduct: pb,
    );
  }

  bool get isFinished => status == 'bitti';
  bool get isShipped => isFinished && shippedAt != null;
  bool get isReady => isFinished && shippedAt == null;
  String get stateLabel => !isFinished ? 'Açık' : (isShipped ? 'Sevk edildi' : 'Sevke hazır');
  int get orderedBoxes => lines.fold(0, (a, l) => a + l.boxes);
}

class Pallet {
  final String id;
  final int no;
  final String size;
  final double gross;
  final double net;
  final List<PLine> items;
  final String by;

  Pallet({required this.id, required this.no, required this.size, required this.gross, required this.net, required this.items, required this.by});

  factory Pallet.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    return Pallet(
      id: d.id,
      no: _toInt(m['no']),
      size: (m['size'] ?? '').toString(),
      gross: _toDouble(m['gross']),
      net: _toDouble(m['net']),
      items: _lines(m['items']),
      by: (m['by'] ?? '').toString(),
    );
  }

  int get boxes => items.fold(0, (a, l) => a + l.boxes);
  int get units => items.fold(0, (a, l) => a + l.units);
}

bool canEditPallet(PalletOrder o) {
  final me = currentUser;
  if (me == null) return false;
  return me.can('paletleme', 'gir');
}

class PalletOps {
  static CollectionReference<Map<String, dynamic>> get col => db.collection('palletOrders');
  static DocumentReference<Map<String, dynamic>> ref(String id) => col.doc(id);

  static Future<String> create(String orderNo, String customer, List<PLine> lines) async {
    final me = currentUser!;
    final doc = col.doc();
    await doc.set({
      'orderNo': orderNo,
      'customer': customer,
      'status': 'acik',
      'createdBy': me.name,
      'createdByUid': me.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'finishedAt': null,
      'finishNote': '',
      'lines': lines.map((l) => l.toMap()).toList(),
      'palletCount': 0,
      'totalBoxes': 0,
      'totalUnits': 0,
      'gross': 0,
      'net': 0,
      'photoCount': 0,
      'nextNo': 1,
      'packedByProduct': <String, dynamic>{},
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> editOrder(PalletOrder o, String orderNo, String customer, List<PLine> lines) async {
    await ref(o.id).update({
      'orderNo': orderNo,
      'customer': customer,
      'lines': lines.map((l) => l.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> savePallet(PalletOrder o, Pallet? existing, int no, String size, List<PLine> items) async {
    double gross = items.fold(0.0, (a, l) => a + l.gross);
    double net = items.fold(0.0, (a, l) => a + l.net);
    if (existing != null && !items.any((l) => l.hasKg)) {
      gross = existing.gross; // eski kayıtlar: koli ağırlığı girilmemişse eski toplamı koru
      net = existing.net;
    }
    final data = {
      'no': no,
      'size': size,
      'gross': gross,
      'net': net,
      'items': items.map((l) => l.toMap()).toList(),
      'by': currentUser?.name ?? '',
      't2': DateTime.now().millisecondsSinceEpoch,
    };
    if (existing == null) {
      await ref(o.id).collection('pallets').add(data);
      if (no >= o.nextNo) await ref(o.id).update({'nextNo': no + 1});
    } else {
      await ref(o.id).collection('pallets').doc(existing.id).update(data);
    }
    await recompute(o.id);
  }

  static Future<void> deletePallet(PalletOrder o, Pallet p) async {
    await ref(o.id).collection('pallets').doc(p.id).delete();
    await recompute(o.id);
  }

  static Future<void> recompute(String id) async {
    final s = await ref(id).collection('pallets').get();
    final pallets = s.docs.map((d) => Pallet.fromDoc(d)).toList();
    int boxes = 0, units = 0;
    double gross = 0, net = 0;
    final byProduct = <String, int>{};
    for (final p in pallets) {
      boxes += p.boxes;
      units += p.units;
      gross += p.gross;
      net += p.net;
      for (final it in p.items) {
        byProduct[it.productCode] = (byProduct[it.productCode] ?? 0) + it.boxes;
      }
    }
    await ref(id).update({
      'palletCount': pallets.length,
      'totalBoxes': boxes,
      'totalUnits': units,
      'gross': gross,
      'net': net,
      'packedByProduct': byProduct,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> finish(PalletOrder o, String note) =>
      ref(o.id).update({'status': 'bitti', 'finishedAt': Timestamp.now(), 'finishNote': note, 'updatedAt': FieldValue.serverTimestamp()});

  static Future<void> undo(PalletOrder o) =>
      ref(o.id).update({'status': 'acik', 'finishedAt': null, 'shippedAt': null, 'updatedAt': FieldValue.serverTimestamp()});

  static Future<void> ship(PalletOrder o, DateTime? at) => ref(o.id).update({
        'shippedAt': at == null ? null : Timestamp.fromDate(at),
        'shippedBy': at == null ? '' : (currentUser?.name ?? ''),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> deleteOrder(PalletOrder o) async {
    for (final sub in ['pallets', 'photos']) {
      final s = await ref(o.id).collection(sub).get();
      for (final d in s.docs) {
        await d.reference.delete();
      }
    }
    await ref(o.id).delete();
  }

  static Future<void> addPhoto(PalletOrder o, Uint8List bytes) async {
    await ref(o.id).collection('photos').add({
      't': Timestamp.now(),
      't2': DateTime.now().millisecondsSinceEpoch,
      'by': currentUser?.name ?? '',
      'data': base64Encode(bytes),
    });
    await ref(o.id).update({'photoCount': FieldValue.increment(1)});
  }

  static Future<void> deletePhoto(PalletOrder o, String photoId) async {
    await ref(o.id).collection('photos').doc(photoId).delete();
    await ref(o.id).update({'photoCount': FieldValue.increment(-1)});
  }
}

Stream<List<PalletOrder>> palletStream() {
  return PalletOps.col
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map((d) => PalletOrder.fromDoc(d)).toList());
}

// ---------------------------------------------------------------------------
// Ana ekran
// ---------------------------------------------------------------------------

class PalletHome extends StatelessWidget {
  final AppUser me;
  final Widget? nav;
  const PalletHome({super.key, required this.me, this.nav});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bind · Paletleme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Text('${me.name} · ${me.roleLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
            ],
          ),
          actions: [
            IconButton(tooltip: "Sevke hazır + sevk edilenler Excel", icon: const Icon(Icons.download), onPressed: exportShipments),
            ...commonActions(me),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Açık'), Tab(text: 'Sevke hazır'), Tab(text: 'Sevk edildi')],
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFADB5BD),
            indicatorColor: kOrange,
          ),
        ),
        floatingActionButton: me.can('paletleme', 'gir')
            ? FloatingActionButton.extended(
                backgroundColor: kOrange,
                foregroundColor: Colors.white,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PalletOrderFormPage())),
                icon: const Icon(Icons.add),
                label: const Text('Yeni paletleme'),
              )
            : null,
        bottomNavigationBar: nav,
        body: const TabBarView(children: [
          PalletList(mode: 0),
          PalletList(mode: 1),
          PalletList(mode: 2),
        ]),
      ),
    );
  }
}

class PalletList extends StatefulWidget {
  final int mode; // 0 açık, 1 sevke hazır, 2 sevk edildi
  const PalletList({super.key, required this.mode});

  @override
  State<PalletList> createState() => _PalletListState();
}

class _PalletListState extends State<PalletList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PalletOrder>>(
      stream: palletStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final q = _q.trim().toLowerCase();
        final list = snap.data!.where((o) => widget.mode == 0 ? !o.isFinished : (widget.mode == 1 ? o.isReady : o.isShipped)).where((o) {
          if (q.isEmpty) return true;
          return '${o.orderNo} ${o.customer} ${o.lines.map((l) => l.productCode).join(' ')}'.toLowerCase().contains(q);
        }).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Sipariş no, müşteri, ürün kodu ara'),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(child: Text(const ['Açık paletleme yok.', 'Sevke hazır sipariş yok.', 'Sevk edilen sipariş yok.'][widget.mode], style: const TextStyle(color: kMuted))),
              ),
            for (final o in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE3E6EA))),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PalletDetailPage(orderId: o.id))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Sipariş ${o.orderNo}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            if (o.isReady)
                              const Text('SEVKE HAZIR', style: TextStyle(color: Color(0xFF1B6B2B), fontWeight: FontWeight.w700)),
                            if (o.isShipped)
                              Text('Sevk edildi: ${fmtDT(o.shippedAt)}', style: const TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.w600)),
                            Text(o.customer.isEmpty ? 'Müşteri girilmedi' : o.customer, style: const TextStyle(color: kMuted)),
                            Text('${o.lines.map((l) => l.productCode).join(', ')}', style: const TextStyle(color: kMuted, fontSize: 13)),
                            Text('${o.createdBy} · ${fmtDT(o.createdAt)}${o.isFinished ? ' · Bitiş ${fmtDT(o.finishedAt)}' : ''}',
                                style: const TextStyle(color: kMuted, fontSize: 13)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${o.palletCount}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                          const Text('palet', style: TextStyle(color: kMuted)),
                          Text('${o.totalBoxes}${o.orderedBoxes > 0 ? '/${o.orderedBoxes}' : ''} koli', style: const TextStyle(fontSize: 13)),
                          if (o.isFinished && canEditPallet(o))
                            IconButton(
                              tooltip: 'Siparişi sil',
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFC92A2A)),
                              onPressed: () => askDeletePallet(context, o),
                            ),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Yeni / düzenle (sipariş bilgileri)
// ---------------------------------------------------------------------------

class _LineCtrls {
  final TextEditingController code;
  final TextEditingController boxes;
  final TextEditingController perBox;
  final TextEditingController lot;
  final TextEditingController skt;
  final TextEditingController boxGross;
  final TextEditingController boxNet;
  _LineCtrls(PLine l)
      : code = TextEditingController(text: l.productCode),
        boxes = TextEditingController(text: l.boxes > 0 ? '${l.boxes}' : ''),
        perBox = TextEditingController(text: l.perBox > 0 ? '${l.perBox}' : ''),
        lot = TextEditingController(text: l.lot),
        skt = TextEditingController(text: l.skt),
        boxGross = TextEditingController(text: l.boxGross > 0 ? fmtKg3(l.boxGross) : ''),
        boxNet = TextEditingController(text: l.boxNet > 0 ? fmtKg3(l.boxNet) : '');
  PLine toLine() => PLine(
        productCode: code.text.trim(),
        boxes: int.tryParse(boxes.text.trim()) ?? 0,
        perBox: int.tryParse(perBox.text.trim()) ?? 0,
        lot: lot.text.trim(),
        skt: skt.text.trim(),
        boxGross: parseNum(boxGross.text) ?? 0,
        boxNet: parseNum(boxNet.text) ?? 0,
      );
  void fillFrom(PLine p) {
    if (boxGross.text.trim().isEmpty && p.boxGross > 0) boxGross.text = fmtKg3(p.boxGross);
    if (boxNet.text.trim().isEmpty && p.boxNet > 0) boxNet.text = fmtKg3(p.boxNet);
    if (lot.text.trim().isEmpty) lot.text = p.lot;
    if (skt.text.trim().isEmpty) skt.text = p.skt;
  }
}

class PalletOrderFormPage extends StatefulWidget {
  final PalletOrder? existing;
  const PalletOrderFormPage({super.key, this.existing});

  @override
  State<PalletOrderFormPage> createState() => _PalletOrderFormPageState();
}

class _PalletOrderFormPageState extends State<PalletOrderFormPage> {
  late final TextEditingController _order = TextEditingController(text: widget.existing?.orderNo ?? '');
  late final TextEditingController _customer = TextEditingController(text: widget.existing?.customer ?? '');
  late final List<_LineCtrls> _rows = (widget.existing?.lines ?? <PLine>[PLine(productCode: '', boxes: 0, perBox: 0)]).map((l) => _LineCtrls(l)).toList();
  Map<String, List<PLine>> _packIndex = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPackOrders();
  }

  Future<void> _loadPackOrders() async {
    try {
      final s = await PackOps.col.orderBy('createdAt', descending: true).limit(300).get();
      final idx = <String, List<PLine>>{};
      for (final d in s.docs) {
        final o = PackOrder.fromDoc(d);
        final list = idx.putIfAbsent(o.orderNo, () => <PLine>[]);
        if (!list.any((l) => l.productCode == o.productCode)) {
          list.add(PLine(productCode: o.productCode, boxes: o.totalBoxes, perBox: o.perBox));
        }
      }
      if (mounted) setState(() => _packIndex = idx);
    } catch (_) {}
  }

  void _fillFrom(String orderNo) {
    final lines = _packIndex[orderNo];
    if (lines == null || lines.isEmpty) return;
    setState(() {
      _rows
        ..clear()
        ..addAll(lines.map((l) => _LineCtrls(l)));
    });
    toast('Paketlemeden ${lines.length} ürün bilgisi geldi; koli adetlerini kontrol edin.');
  }

  Future<void> _save() async {
    final lines = _rows.map((r) => r.toLine()).where((l) => l.productCode.isNotEmpty).toList();
    if (_order.text.trim().isEmpty) {
      toast('Sipariş numarası gerekli.');
      return;
    }
    if (lines.isEmpty) {
      toast('En az bir ürün kodu girin.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.existing == null) {
        final id = await PalletOps.create(_order.text.trim(), _customer.text.trim(), lines);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PalletDetailPage(orderId: id)));
      } else {
        await PalletOps.editOrder(widget.existing!, _order.text.trim(), _customer.text.trim(), lines);
        if (!mounted) return;
        Navigator.of(context).pop();
        toast('Kaydedildi');
      }
    } catch (e) {
      toast('Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _packIndex.keys.toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Yeni paletleme' : 'Sipariş bilgilerini düzenle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _order.text),
            optionsBuilder: (v) {
              final q = v.text.trim().toLowerCase();
              if (q.isEmpty) return options.take(20);
              return options.where((o) => o.toLowerCase().contains(q)).take(20);
            },
            onSelected: (v) {
              _order.text = v;
              _fillFrom(v);
            },
            fieldViewBuilder: (context, ctrl, focus, onSubmit) {
              return TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: const InputDecoration(labelText: 'Sipariş numarası', helperText: 'Paketlemedeki bir sipariş seçilirse ürünler otomatik gelir'),
                onChanged: (v) => _order.text = v,
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _customer, decoration: const InputDecoration(labelText: 'Müşteri')),
          const SizedBox(height: 16),
          const Text('Ürünler (sipariş koli adedi ve koli içi adet)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(flex: 3, child: TextField(controller: _rows[i].code, decoration: const InputDecoration(labelText: 'Ürün kodu', isDense: true))),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: TextField(controller: _rows[i].boxes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sipariş koli', isDense: true))),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: TextField(controller: _rows[i].perBox, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Koli içi', isDense: true))),
                IconButton(
                  tooltip: 'Satırı sil',
                  icon: const Icon(Icons.close),
                  onPressed: _rows.length > 1 ? () => setState(() => _rows.removeAt(i)) : null,
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: () => setState(() => _rows.add(_LineCtrls(PLine(productCode: '', boxes: 0, perBox: 0)))),
            icon: const Icon(Icons.add),
            label: const Text('Ürün ekle'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Kaydediliyor…' : 'Kaydet')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Palet ekle / düzenle
// ---------------------------------------------------------------------------

class PalletFormPage extends StatefulWidget {
  final PalletOrder order;
  final Pallet? existing;
  const PalletFormPage({super.key, required this.order, this.existing});

  @override
  State<PalletFormPage> createState() => _PalletFormPageState();
}

class _PalletFormPageState extends State<PalletFormPage> {
  late final TextEditingController _no = TextEditingController(text: '${widget.existing?.no ?? widget.order.nextNo}');
  late final TextEditingController _size = TextEditingController(text: widget.existing?.size ?? '120x80x');
  late final List<_LineCtrls> _items = (widget.existing?.items ??
          <PLine>[
            if (widget.order.lines.isNotEmpty)
              PLine(productCode: widget.order.lines.first.productCode, boxes: 0, perBox: widget.order.lines.first.perBox)
            else
              PLine(productCode: '', boxes: 0, perBox: 0)
          ])
      .map((l) => _LineCtrls(l))
      .toList();
  bool _busy = false;
  final Map<String, PLine> _prev = {};

  @override
  void initState() {
    super.initState();
    _loadPrev();
  }

  // Önceki paletlerdeki aynı ürünün koli kg, lot ve SKT bilgisini öneri olarak getirir
  Future<void> _loadPrev() async {
    try {
      final s = await PalletOps.ref(widget.order.id).collection('pallets').orderBy('no').get();
      for (final p in s.docs.map((d) => Pallet.fromDoc(d))) {
        for (final it in p.items) {
          if (it.productCode.isNotEmpty) _prev[it.productCode] = it;
        }
      }
      if (!mounted || widget.existing != null) return;
      setState(() {
        for (final r in _items) {
          final p = _prev[r.code.text.trim()];
          if (p != null) r.fillFrom(p);
        }
      });
    } catch (_) {}
  }

  double get _sumGross => _items.fold(0.0, (a, r) => a + r.toLine().gross);
  double get _sumNet => _items.fold(0.0, (a, r) => a + r.toLine().net);

  Future<void> _save() async {
    final no = int.tryParse(_no.text.trim());
    final items = _items.map((r) => r.toLine()).where((l) => l.productCode.isNotEmpty && l.boxes > 0).toList();
    if (no == null) {
      toast('Palet numarasını rakamla girin.');
      return;
    }
    if (items.isEmpty) {
      toast('En az bir ürün ve koli adedi girin.');
      return;
    }
    setState(() => _busy = true);
    try {
      await PalletOps.savePallet(widget.order, widget.existing, no, _size.text.trim(), items);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast('Palet $no kaydedildi');
    } catch (e) {
      toast('Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addItem() {
    String code = '';
    int perBox = 0;
    final used = _items.map((r) => r.code.text.trim()).toSet();
    for (final l in widget.order.lines) {
      if (!used.contains(l.productCode)) {
        code = l.productCode;
        perBox = l.perBox;
        break;
      }
    }
    final c = _LineCtrls(PLine(productCode: code, boxes: 0, perBox: perBox));
    final p = _prev[code];
    if (p != null) c.fillFrom(p);
    setState(() => _items.add(c));
  }

  @override
  Widget build(BuildContext context) {
    final codes = widget.order.lines.map((l) => l.productCode).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Palet ekle' : 'Palet ${widget.existing!.no}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: TextField(controller: _no, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Palet no'))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: TextField(controller: _size, decoration: const InputDecoration(labelText: 'Palet ebatı (cm)', hintText: '120x80x150'))),
          ]),
          const SizedBox(height: 16),
          const Text('Paletteki ürünler', style: TextStyle(fontWeight: FontWeight.w600)),
          if (codes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text('Siparişteki ürünler: ${codes.join(', ')}', style: const TextStyle(color: kMuted, fontSize: 13)),
            ),
          for (var i = 0; i < _items.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(10, 10, 0, 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE3E6EA))),
              child: Column(children: [
                Row(children: [
                  Expanded(flex: 3, child: TextField(controller: _items[i].code, decoration: const InputDecoration(labelText: 'Ürün kodu', isDense: true))),
                  const SizedBox(width: 6),
                  Expanded(
                      flex: 2,
                      child: TextField(
                          controller: _items[i].boxes,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'Koli', isDense: true))),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: TextField(controller: _items[i].perBox, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Koli içi', isDense: true))),
                  IconButton(
                    tooltip: 'Satırı sil',
                    icon: const Icon(Icons.close),
                    onPressed: _items.length > 1 ? () => setState(() => _items.removeAt(i)) : null,
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: TextField(controller: _items[i].lot, decoration: const InputDecoration(labelText: 'Lot no', isDense: true))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _items[i].skt,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(labelText: 'SKT', hintText: 'GG.AA.YYYY', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 48),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _items[i].boxGross,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: '1 koli brüt kg', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _items[i].boxNet,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: '1 koli net kg', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 48),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 10),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Bu ürün: brüt ${fmtKg(_items[i].toLine().gross)} kg · net ${fmtKg(_items[i].toLine().net)} kg',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  ),
                ),
              ]),
            ),
          OutlinedButton.icon(onPressed: _addItem, icon: const Icon(Icons.add_box), label: const Text('Yeni koli / ürün ekle')),
          const SizedBox(height: 14),
          _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Palet toplamı: brüt ${fmtKg(_sumGross)} kg · net ${fmtKg(_sumNet)} kg', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            const Text('Not: Palet ağırlıkları dahil değildir.', style: TextStyle(color: Color(0xFF9A3412), fontSize: 13)),
          ])),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Kaydediliyor…' : 'Paleti kaydet')),
          if (widget.existing != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: const Color(0xFFC92A2A)),
              onPressed: () async {
                if (!await confirm(context, 'Palet silinsin mi?', 'Palet ${widget.existing!.no} ve içindeki bilgiler silinecek.', 'Sil')) return;
                try {
                  await PalletOps.deletePallet(widget.order, widget.existing!);
                  if (!mounted) return;
                  Navigator.of(this.context).pop();
                  toast('Palet silindi');
                } catch (e) {
                  toast('Silinemedi: $e');
                }
              },
              child: const Text('Paleti sil'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detay
// ---------------------------------------------------------------------------

class PalletDetailPage extends StatelessWidget {
  final String orderId;
  const PalletDetailPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paletleme detayı'), actions: [
        IconButton(
          tooltip: 'Siparişi sil',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final s = await PalletOps.ref(orderId).get();
            if (!s.exists || !context.mounted) return;
            final o = PalletOrder.fromDoc(s);
            if (!o.isFinished) {
              toast('Sadece bitmiş (sevke hazır / sevk edilmiş) siparişler silinebilir.');
              return;
            }
            if (await askDeletePallet(context, o) && context.mounted) Navigator.of(context).pop();
          },
        ),
      ]),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: PalletOps.ref(orderId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (!snap.data!.exists) return const Center(child: Text('Kayıt bulunamadı.'));
          final o = PalletOrder.fromDoc(snap.data!);
          final edit = canEditPallet(o);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Sipariş ${o.orderNo}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                  if (edit && !o.isFinished)
                    IconButton(
                      tooltip: 'Düzenle',
                      icon: const Icon(Icons.edit),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PalletOrderFormPage(existing: o))),
                    ),
                ]),
                _Chip(
                  o.stateLabel,
                  !o.isFinished ? const Color(0xFFFFE8CC) : (o.isShipped ? const Color(0xFFDBE8FF) : const Color(0xFFD3F9D8)),
                  !o.isFinished ? const Color(0xFF9A3412) : (o.isShipped ? const Color(0xFF1D4ED8) : const Color(0xFF1B6B2B)),
                ),
                if (o.isShipped)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Sevk tarihi: ${fmtFull(o.shippedAt)}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8))),
                  ),
                const SizedBox(height: 6),
                Text('Müşteri: ${o.customer.isEmpty ? '-' : o.customer}'),
                Text('${o.createdBy} · ${fmtDT(o.createdAt)}${o.isFinished ? ' · Bitiş ${fmtDT(o.finishedAt)}' : ''}', style: const TextStyle(color: kMuted)),
                if (o.finishNote.isNotEmpty) Text('Bitiş notu: ${o.finishNote}', style: const TextStyle(fontStyle: FontStyle.italic)),
              ])),
              const SizedBox(height: 10),
              _box(Wrap(spacing: 24, runSpacing: 8, children: [
                _kv('Palet', '${o.palletCount}'),
                _kv('Koli', '${o.totalBoxes}${o.orderedBoxes > 0 ? ' / ${o.orderedBoxes}' : ''}'),
                _kv('Adet', '${o.totalUnits}'),
                _kv('Brüt kg', fmtKg(o.gross)),
                _kv('Net kg', fmtKg(o.net)),
                const Text('Palet ağırlıkları dahil değildir.', style: TextStyle(color: Color(0xFF9A3412), fontSize: 12)),
              ])),
              const SizedBox(height: 10),
              _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Sipariş / paletlenen', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final l in o.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text('${l.productCode}${l.perBox > 0 ? ' (koli içi ${l.perBox})' : ''}')),
                      Text('${o.packedByProduct[l.productCode] ?? 0} / ${l.boxes} koli',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: (o.packedByProduct[l.productCode] ?? 0) >= l.boxes && l.boxes > 0 ? const Color(0xFF1B6B2B) : kDark,
                          )),
                    ]),
                  ),
              ])),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (edit && !o.isFinished)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kOrange, minimumSize: const Size(0, 48)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PalletFormPage(order: o))),
                    icon: const Icon(Icons.add),
                    label: const Text('Palet ekle'),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => exportPackingList(o),
                  icon: const Icon(Icons.download),
                  label: const Text('Çeki listesi (Excel)'),
                ),
                if (edit && !o.isFinished)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: const Color(0xFFC92A2A)),
                    onPressed: () async {
                      final note = await askText(context, 'Paletleme bitirilsin mi?', 'Bilgi notu (isteğe bağlı)', ok: 'Bitir');
                      if (note == null) return;
                      try {
                        await PalletOps.finish(o, note);
                      } catch (e) {
                        toast('Hata: $e');
                      }
                    },
                    child: const Text('Bitir'),
                  ),
                if (edit && o.isFinished)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: o.isShipped ? kDark : const Color(0xFF1B6B2B), minimumSize: const Size(0, 48)),
                    onPressed: () async {
                      final at = await pickDateTime(context, o.shippedAt ?? DateTime.now(), o.isShipped ? 'Sevk tarihini düzelt' : 'Sevk tarihi ve saati');
                      if (at == null) return;
                      try {
                        await PalletOps.ship(o, at);
                        toast('Sevk tarihi kaydedildi');
                      } catch (e) {
                        toast('Hata: $e');
                      }
                    },
                    icon: const Icon(Icons.local_shipping),
                    label: Text(o.isShipped ? 'Sevk tarihini düzelt' : 'Sevk edildi'),
                  ),
                if (edit && o.isShipped)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () async {
                      if (!await confirm(context, 'Sevk geri alınsın mı?', 'Sipariş tekrar "Sevke hazır" olur.', 'Geri al')) return;
                      try {
                        await PalletOps.ship(o, null);
                      } catch (e) {
                        toast('Hata: $e');
                      }
                    },
                    child: const Text('Sevki geri al'),
                  ),
                if (edit && o.isFinished)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kDark, minimumSize: const Size(0, 48)),
                    onPressed: () async {
                      if (!await confirm(context, 'Bitiş geri alınsın mı?', 'Paletleme yeniden açılır.', 'Geri al')) return;
                      try {
                        await PalletOps.undo(o);
                      } catch (e) {
                        toast('Hata: $e');
                      }
                    },
                    icon: const Icon(Icons.undo),
                    label: const Text('Bitişi geri al'),
                  ),
              ]),
              const SizedBox(height: 10),
              PalletPhotos(order: o, edit: edit),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: PalletOps.ref(o.id).collection('pallets').orderBy('no').snapshots(),
                builder: (context, ps) {
                  if (!ps.hasData) return const SizedBox.shrink();
                  final pallets = ps.data!.docs.map((d) => Pallet.fromDoc(d)).toList();
                  if (pallets.isEmpty) return _box(const Text('Henüz palet eklenmedi.', style: TextStyle(color: kMuted)));
                  return Column(children: [
                    for (final p in pallets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: edit && !o.isFinished
                              ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PalletFormPage(order: o, existing: p)))
                              : null,
                          child: _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('Palet ${p.no}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                              Text(p.size, style: const TextStyle(color: kMuted)),
                            ]),
                            Text('Brüt ${fmtKg(p.gross)} kg · Net ${fmtKg(p.net)} kg · ${p.boxes} koli (palet ağırlığı hariç)', style: const TextStyle(color: kMuted, fontSize: 13)),
                            for (final it in p.items)
                              Text('• ${it.productCode}: ${it.boxes} koli${it.perBox > 0 ? ' × ${it.perBox} = ${it.units} adet' : ''}'
                                  '${it.lot.isNotEmpty ? ' · Lot ${it.lot}' : ''}${it.skt.isNotEmpty ? ' · SKT ${it.skt}' : ''}'
                                  '${it.hasKg ? ' · ${fmtKg(it.gross)}/${fmtKg(it.net)} kg' : ''}'),
                          ])),
                        ),
                      ),
                  ]);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(color: kMuted, fontSize: 12)),
        Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ]);
}

class PalletPhotos extends StatelessWidget {
  final PalletOrder order;
  final bool edit;
  const PalletPhotos({super.key, required this.order, required this.edit});

  Future<void> _add(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Fotoğraf çek'), onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galeriden seç'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 60);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 700000) {
        toast('Fotoğraf çok büyük, lütfen tekrar deneyin.');
        return;
      }
      await PalletOps.addPhoto(order, bytes);
      toast('Görsel eklendi');
    } catch (e) {
      toast('Görsel eklenemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PalletOps.ref(order.id).collection('photos').orderBy('t2').snapshots(),
      builder: (context, snap) {
        final docs = snap.hasData ? snap.data!.docs : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Görseller (${docs.length}/3)', style: const TextStyle(fontWeight: FontWeight.w600))),
            if (edit && docs.length < 3)
              TextButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add_a_photo), label: const Text('Ekle')),
          ]),
          if (docs.isEmpty) const Text('Görsel yok.', style: TextStyle(color: kMuted)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in docs)
              Builder(builder: (_) {
                Uint8List? bytes;
                try {
                  bytes = base64Decode((d.data()['data'] ?? '').toString());
                } catch (_) {}
                if (bytes == null) return const SizedBox.shrink();
                final img = bytes;
                return Stack(children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(backgroundColor: Colors.black),
                        body: Center(child: InteractiveViewer(child: Image.memory(img))),
                      ),
                    )),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(img, width: 96, height: 96, fit: BoxFit.cover)),
                  ),
                  if (edit)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Görseli sil',
                        onPressed: () async {
                          if (!await confirm(context, 'Görsel silinsin mi?', '', 'Sil')) return;
                          try {
                            await PalletOps.deletePhoto(order, d.id);
                          } catch (e) {
                            toast('Silinemedi: $e');
                          }
                        },
                      ),
                    ),
                ]);
              }),
          ]),
        ]));
      },
    );
  }
}

Future<bool> askDeletePallet(BuildContext context, PalletOrder o) async {
  if (!canEditPallet(o)) {
    toast('Silme yetkiniz yok.');
    return false;
  }
  if (!await confirm(context, 'Paletleme silinsin mi?',
      'Sipariş ${o.orderNo}, tüm paletleri ve görselleri kalıcı olarak silinecek. Bu işlem geri alınamaz.', 'Sil')) {
    return false;
  }
  try {
    await PalletOps.deleteOrder(o);
    toast('Silindi');
    return true;
  } catch (e) {
    toast('Silinemedi: $e');
    return false;
  }
}

Future<DateTime?> pickDateTime(BuildContext context, DateTime initial, String title) async {
  final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2024), lastDate: DateTime(2100), helpText: title);
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute), helpText: title);
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

// Sevke hazır + sevk edilen tüm siparişler tek Excel'de
Future<void> exportShipments() async {
  try {
    toast('Sevkiyat listesi hazırlanıyor…');
    final s = await PalletOps.col.where('status', isEqualTo: 'bitti').get();
    final orders = s.docs.map((d) => PalletOrder.fromDoc(d)).toList()
      ..sort((a, b) {
        if (a.isReady != b.isReady) return a.isReady ? -1 : 1;
        final x = a.shippedAt ?? a.finishedAt ?? DateTime(2000);
        final y = b.shippedAt ?? b.finishedAt ?? DateTime(2000);
        return y.compareTo(x);
      });
    if (orders.isEmpty) {
      toast('Sevke hazır ya da sevk edilmiş sipariş yok.');
      return;
    }
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Sevkiyat');
    final xl.Sheet sh = excel['Sevkiyat'];
    final xl.Sheet det = excel['Palet detay'];
    xl.CellValue t(String v) => xl.TextCellValue(v);
    xl.CellValue n(int v) => xl.IntCellValue(v);
    xl.CellValue dbl(double v) => xl.DoubleCellValue(v);
    sh.appendRow(<xl.CellValue?>[
      t('Durum'), t('Sipariş no'), t('Müşteri'), t('Ürünler'), t('Palet'), t('Koli'), t('Adet'), t('Brüt kg'), t('Net kg'),
      t('Bitiş (sevke hazır)'), t('Sevk tarihi'), t('Not'),
    ]);
    det.appendRow(<xl.CellValue?>[
      t('Durum'), t('Sipariş no'), t('Müşteri'), t('Sevk tarihi'), t('Palet no'), t('Palet ebatı'), t('Ürün kodu'), t('Lot no'), t('SKT'),
      t('Koli'), t('Koli içi adet'), t('Toplam adet'), t('1 koli brüt kg'), t('1 koli net kg'), t('Brüt kg'), t('Net kg'),
    ]);
    for (final o in orders) {
      sh.appendRow(<xl.CellValue?>[
        t(o.stateLabel), t(o.orderNo), t(o.customer), t(o.lines.map((l) => l.productCode).join(', ')), n(o.palletCount), n(o.totalBoxes),
        n(o.totalUnits), dbl(o.gross), dbl(o.net), t(fmtFull(o.finishedAt)), t(o.isShipped ? fmtFull(o.shippedAt) : ''), t(o.finishNote),
      ]);
      final ps = await PalletOps.ref(o.id).collection('pallets').orderBy('no').get();
      for (final p in ps.docs.map((d) => Pallet.fromDoc(d))) {
        for (var i = 0; i < p.items.length; i++) {
          final it = p.items[i];
          det.appendRow(<xl.CellValue?>[
            t(o.stateLabel), t(o.orderNo), t(o.customer), t(o.isShipped ? fmtFull(o.shippedAt) : ''), n(p.no), t(i == 0 ? p.size : ''),
            t(it.productCode), t(it.lot), t(it.skt), n(it.boxes), n(it.perBox), n(it.units),
            it.hasKg ? dbl(it.boxGross) : null, it.hasKg ? dbl(it.boxNet) : null,
            p.items.any((x) => x.hasKg) ? dbl(it.gross) : (i == 0 ? dbl(p.gross) : null),
            p.items.any((x) => x.hasKg) ? dbl(it.net) : (i == 0 ? dbl(p.net) : null),
          ]);
        }
      }
    }
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[t('Not: Brüt ve net ağırlıklara palet ağırlıkları dahil değildir.')]);
    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final file = File('${dir.path}/sevkiyat_${now.year}${two(now.month)}${two(now.day)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Sevkiyat listesi');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}

// ---------------------------------------------------------------------------
// Çeki listesi (Excel)
// ---------------------------------------------------------------------------

Future<void> exportPackingList(PalletOrder o) async {
  try {
    toast('Çeki listesi hazırlanıyor…');
    final s = await PalletOps.ref(o.id).collection('pallets').orderBy('no').get();
    final pallets = s.docs.map((d) => Pallet.fromDoc(d)).toList();
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Çeki Listesi');
    final xl.Sheet sh = excel['Çeki Listesi'];
    final xl.Sheet sum = excel['Özet'];
    xl.CellValue t(String v) => xl.TextCellValue(v);
    xl.CellValue n(int v) => xl.IntCellValue(v);
    xl.CellValue dbl(double v) => xl.DoubleCellValue(v);

    sh.appendRow(<xl.CellValue?>[t('ÇEKİ LİSTESİ / PACKING LIST')]);
    sh.appendRow(<xl.CellValue?>[t('Sipariş no'), t(o.orderNo)]);
    sh.appendRow(<xl.CellValue?>[t('Müşteri'), t(o.customer)]);
    sh.appendRow(<xl.CellValue?>[t('Tarih'), t(fmtFull(DateTime.now()))]);
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[
      t('Palet no'), t('Palet ebatı (cm)'), t('Ürün kodu'), t('Lot no'), t('SKT'), t('Koli'), t('Koli içi adet'), t('Toplam adet'),
      t('1 koli brüt kg'), t('1 koli net kg'), t('Brüt kg'), t('Net kg'),
    ]);
    int tb = 0, tu = 0;
    double tg = 0, tn = 0;
    for (final p in pallets) {
      for (var i = 0; i < p.items.length; i++) {
        final it = p.items[i];
        final legacy = !p.items.any((x) => x.hasKg);
        sh.appendRow(<xl.CellValue?>[
          n(p.no), t(i == 0 ? p.size : ''), t(it.productCode), t(it.lot), t(it.skt), n(it.boxes), n(it.perBox), n(it.units),
          it.hasKg ? dbl(it.boxGross) : null, it.hasKg ? dbl(it.boxNet) : null,
          legacy ? (i == 0 ? dbl(p.gross) : null) : dbl(it.gross), legacy ? (i == 0 ? dbl(p.net) : null) : dbl(it.net),
        ]);
      }
      tb += p.boxes;
      tu += p.units;
      tg += p.gross;
      tn += p.net;
    }
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[t('TOPLAM'), t('${pallets.length} palet'), null, null, null, n(tb), null, n(tu), null, null, dbl(tg), dbl(tn)]);
    sh.appendRow(<xl.CellValue?>[t('Not: Brüt ve net ağırlıklara palet ağırlıkları dahil değildir.')]);

    sum.appendRow(<xl.CellValue?>[t('Ürün kodu'), t('Sipariş koli'), t('Paletlenen koli'), t('Fark'), t('Koli içi adet'), t('Paletlenen adet')]);
    final byProduct = <String, int>{};
    final unitsBy = <String, int>{};
    for (final p in pallets) {
      for (final it in p.items) {
        byProduct[it.productCode] = (byProduct[it.productCode] ?? 0) + it.boxes;
        unitsBy[it.productCode] = (unitsBy[it.productCode] ?? 0) + it.units;
      }
    }
    final codes = <String>{...o.lines.map((l) => l.productCode), ...byProduct.keys};
    for (final c in codes) {
      PLine? line;
      for (final l in o.lines) {
        if (l.productCode == c) line = l;
      }
      final ordered = line?.boxes ?? 0;
      final packed = byProduct[c] ?? 0;
      sum.appendRow(<xl.CellValue?>[t(c), n(ordered), n(packed), n(packed - ordered), n(line?.perBox ?? 0), n(unitsBy[c] ?? 0)]);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      toast('Excel oluşturulamadı.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final safe = o.orderNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/ceki_listesi_$safe.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Çeki listesi · Sipariş ${o.orderNo}');
  } catch (e) {
    toast('Excel hatası: $e');
  }
}
