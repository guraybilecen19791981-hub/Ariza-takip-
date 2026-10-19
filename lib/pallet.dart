part of 'main.dart';

// ---------------------------------------------------------------------------
// Paletleme modülü
// ---------------------------------------------------------------------------

double _toDouble(dynamic v) => (v is num) ? v.toDouble() : 0.0;
double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
String fmtKg(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class PLine {
  String productCode;
  int boxes;
  int perBox;
  PLine({required this.productCode, required this.boxes, required this.perBox});

  factory PLine.fromMap(dynamic m) {
    final x = (m is Map) ? m : <String, dynamic>{};
    return PLine(productCode: (x['productCode'] ?? '').toString(), boxes: _toInt(x['boxes']), perBox: _toInt(x['perBox']));
  }

  Map<String, dynamic> toMap() => {'productCode': productCode, 'boxes': boxes, 'perBox': perBox};
  int get units => boxes * perBox;
  PLine copy() => PLine(productCode: productCode, boxes: boxes, perBox: perBox);
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

  static Future<void> savePallet(PalletOrder o, Pallet? existing, int no, String size, double gross, double net, List<PLine> items) async {
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
      ref(o.id).update({'status': 'acik', 'finishedAt': null, 'updatedAt': FieldValue.serverTimestamp()});

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
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bind · Paletleme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Text('${me.name} · ${me.roleLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
            ],
          ),
          actions: [...commonActions(me)],
          bottom: const TabBar(
            tabs: [Tab(text: 'Açık'), Tab(text: 'Bitenler')],
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
          PalletList(finished: false),
          PalletList(finished: true),
        ]),
      ),
    );
  }
}

class PalletList extends StatefulWidget {
  final bool finished;
  const PalletList({super.key, required this.finished});

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
        final list = snap.data!.where((o) => o.isFinished == widget.finished).where((o) {
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
                child: Center(child: Text(widget.finished ? 'Biten paletleme yok.' : 'Açık paletleme yok.', style: const TextStyle(color: kMuted))),
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
  _LineCtrls(PLine l)
      : code = TextEditingController(text: l.productCode),
        boxes = TextEditingController(text: l.boxes > 0 ? '${l.boxes}' : ''),
        perBox = TextEditingController(text: l.perBox > 0 ? '${l.perBox}' : '');
  PLine toLine() => PLine(productCode: code.text.trim(), boxes: int.tryParse(boxes.text.trim()) ?? 0, perBox: int.tryParse(perBox.text.trim()) ?? 0);
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
  late final TextEditingController _gross = TextEditingController(text: widget.existing == null ? '' : fmtKg(widget.existing!.gross));
  late final TextEditingController _net = TextEditingController(text: widget.existing == null ? '' : fmtKg(widget.existing!.net));
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
      await PalletOps.savePallet(widget.order, widget.existing, no, _size.text.trim(), parseNum(_gross.text) ?? 0, parseNum(_net.text) ?? 0, items);
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
    setState(() => _items.add(_LineCtrls(PLine(productCode: code, boxes: 0, perBox: perBox))));
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
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _gross, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Brüt kg'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _net, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Net kg'))),
          ]),
          const SizedBox(height: 16),
          const Text('Paletteki ürünler', style: TextStyle(fontWeight: FontWeight.w600)),
          if (codes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text('Siparişteki ürünler: ${codes.join(', ')}', style: const TextStyle(color: kMuted, fontSize: 13)),
            ),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(flex: 3, child: TextField(controller: _items[i].code, decoration: const InputDecoration(labelText: 'Ürün kodu', isDense: true))),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: TextField(controller: _items[i].boxes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Koli', isDense: true))),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: TextField(controller: _items[i].perBox, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Koli içi', isDense: true))),
                IconButton(
                  tooltip: 'Satırı sil',
                  icon: const Icon(Icons.close),
                  onPressed: _items.length > 1 ? () => setState(() => _items.removeAt(i)) : null,
                ),
              ]),
            ),
          OutlinedButton.icon(onPressed: _addItem, icon: const Icon(Icons.add_box), label: const Text('Yeni koli / ürün ekle')),
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
      appBar: AppBar(title: const Text('Paletleme detayı')),
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
                _Chip(o.isFinished ? 'Bitti' : 'Açık', o.isFinished ? const Color(0xFFE9ECEF) : const Color(0xFFD3F9D8),
                    o.isFinished ? kMuted : const Color(0xFF1B6B2B)),
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
                            Text('Brüt ${fmtKg(p.gross)} kg · Net ${fmtKg(p.net)} kg · ${p.boxes} koli', style: const TextStyle(color: kMuted, fontSize: 13)),
                            for (final it in p.items)
                              Text('• ${it.productCode}: ${it.boxes} koli${it.perBox > 0 ? ' × ${it.perBox} = ${it.units} adet' : ''}'),
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
      t('Palet no'), t('Palet ebatı (cm)'), t('Ürün kodu'), t('Koli'), t('Koli içi adet'), t('Toplam adet'), t('Brüt kg'), t('Net kg'),
    ]);
    int tb = 0, tu = 0;
    double tg = 0, tn = 0;
    for (final p in pallets) {
      for (var i = 0; i < p.items.length; i++) {
        final it = p.items[i];
        sh.appendRow(<xl.CellValue?>[
          n(p.no), t(i == 0 ? p.size : ''), t(it.productCode), n(it.boxes), n(it.perBox), n(it.units),
          i == 0 ? dbl(p.gross) : null, i == 0 ? dbl(p.net) : null,
        ]);
      }
      tb += p.boxes;
      tu += p.units;
      tg += p.gross;
      tn += p.net;
    }
    sh.appendRow(<xl.CellValue?>[]);
    sh.appendRow(<xl.CellValue?>[t('TOPLAM'), t('${pallets.length} palet'), null, n(tb), null, n(tu), dbl(tg), dbl(tn)]);

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
