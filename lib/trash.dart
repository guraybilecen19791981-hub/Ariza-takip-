part of 'main.dart';

// ---------------------------------------------------------------------------
// Çöp kutusu (Silinenler): silinen kayıtlar 30 gün burada bekler, admin "Geri getir"
// ile eski yerine döndürür. Görsel dosyaları 30 gün dolana kadar silinmez.
// Yapı: trash/{id} (ana kayıt) + trash/{id}/items/{n} (siparişin hareketleri, paletleri, görselleri)
// ---------------------------------------------------------------------------

const int kTrashDays = 30;

const Map<String, String> kTrashKinds = {
  'packOrder': 'Paketleme siparişi',
  'packEvent': 'Paketleme kaydı',
  'palletOrder': 'Paletleme siparişi',
  'pallet': 'Palet',
  'machineJob': 'Makine siparişi (arşiv)',
  'machine': 'Makine',
  'note': 'Not',
  'machineFault': 'Makine arızası',
};

class TrashItem {
  final String id;
  final String kind;
  final String title;
  final String path;
  final Map<String, dynamic> data;
  final List<String> subs;
  final int itemCount;
  final String deletedBy;
  final DateTime? deletedAt;
  final DateTime? expireAt;
  const TrashItem(this.id, this.kind, this.title, this.path, this.data, this.subs, this.itemCount, this.deletedBy, this.deletedAt, this.expireAt);

  factory TrashItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final data = m['data'];
    return TrashItem(
      d.id,
      (m['kind'] ?? '').toString(),
      (m['title'] ?? '').toString(),
      (m['path'] ?? '').toString(),
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
      ((m['subs'] as List?) ?? const []).map((e) => e.toString()).toList(),
      (m['itemCount'] as num?)?.toInt() ?? 0,
      (m['deletedBy'] ?? '').toString(),
      tsToDate(m['deletedAt']),
      tsToDate(m['expireAt']),
    );
  }

  String get kindLabel => kTrashKinds[kind] ?? kind;
  int get daysLeft {
    final e = expireAt;
    if (e == null) return 0;
    final h = e.difference(DateTime.now()).inHours;
    return h <= 0 ? 0 : (h / 24).ceil();
  }
}

class TrashOps {
  static CollectionReference<Map<String, dynamic>> get col => db.collection('trash');

  static Future<void> _inBatches(List<void Function(WriteBatch b)> ops) async {
    for (int i = 0; i < ops.length; i += 400) {
      final b = db.batch();
      for (final op in ops.skip(i).take(400)) {
        op(b);
      }
      await b.commit();
    }
  }

  // Kaydı (ve alt koleksiyonlarını) çöp kutusuna taşır, sonra asıl yerden siler.
  // Önce kopyalanır, sonra silinir: yarıda kesilirse veri kaybolmaz.
  static Future<void> move(DocumentReference<Map<String, dynamic>> ref, {required String kind, required String title, List<String> subs = const []}) async {
    final snap = await ref.get();
    if (!snap.exists) return;
    final children = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final childSub = <String>[];
    for (final s in subs) {
      final q = await ref.collection(s).get();
      for (final d in q.docs) {
        children.add(d);
        childSub.add(s);
      }
    }
    final now = DateTime.now();
    final t = col.doc();
    await t.set({
      'kind': kind,
      'title': title,
      'path': ref.path,
      'data': snap.data(),
      'subs': subs,
      'itemCount': children.length,
      'deletedBy': currentUser?.name ?? '',
      'deletedByUid': currentUser?.uid ?? '',
      'deletedAt': Timestamp.fromDate(now),
      'expireAt': Timestamp.fromDate(now.add(const Duration(days: kTrashDays))),
    });
    await _inBatches([
      for (int i = 0; i < children.length; i++)
        (b) => b.set(t.collection('items').doc('$i'), {'sub': childSub[i], 'id': children[i].id, 'data': children[i].data()}),
    ]);
    await _inBatches([
      for (final c in children) (b) => b.delete(c.reference),
      (b) => b.delete(ref),
    ]);
  }

  static Stream<List<TrashItem>> stream() => col.orderBy('deletedAt', descending: true).limit(500).snapshots().map((s) => s.docs.map((d) => TrashItem.fromDoc(d)).toList());

  // Geri getir. Hata yoksa null döner.
  static Future<String?> restore(TrashItem it) async {
    if (it.path.isEmpty) return 'Kaydın yeri bilinmiyor.';
    final ref = db.doc(it.path);
    if ((await ref.get()).exists) return 'Bu kayıt zaten yerinde duruyor.';
    final seg = it.path.split('/');
    if (seg.length > 2) {
      final parent = db.doc(seg.sublist(0, seg.length - 2).join('/'));
      if (!(await parent.get()).exists) return 'Bağlı olduğu sipariş de silinmiş. Önce siparişi geri getirin.';
    }
    final items = await col.doc(it.id).collection('items').get();
    await ref.set(it.data);
    await _inBatches([
      for (final d in items.docs)
        (b) {
          final m = d.data();
          final data = m['data'];
          b.set(ref.collection((m['sub'] ?? '').toString()).doc((m['id'] ?? d.id).toString()), data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
        },
    ]);
    await _inBatches([
      for (final d in items.docs) (b) => b.delete(d.reference),
      (b) => b.delete(col.doc(it.id)),
    ]);
    // Toplamları yeniden hesapla
    try {
      if (it.kind == 'packEvent' && seg.length == 4) await PackOps.recompute(seg[1]);
      if (it.kind == 'pallet' && seg.length == 4) await PalletOps.recompute(seg[1]);
    } catch (_) {}
    return null;
  }

  // Kalıcı sil (görsel dosyaları dahil)
  static Future<void> purge(TrashItem it) async {
    final items = await col.doc(it.id).collection('items').get();
    for (final d in items.docs) {
      final data = d.data()['data'];
      if (d.data()['sub'] == 'photos' && data is Map) await deleteStoredPhoto(data['path']);
    }
    await _inBatches([
      for (final d in items.docs) (b) => b.delete(d.reference),
      (b) => b.delete(col.doc(it.id)),
    ]);
  }

  // Süresi (30 gün) dolanları temizler; admin Silinenler sayfasını açınca çalışır
  static Future<int> purgeExpired() async {
    final s = await col.where('expireAt', isLessThan: Timestamp.now()).limit(100).get();
    int n = 0;
    for (final d in s.docs) {
      try {
        await purge(TrashItem.fromDoc(d));
        n++;
      } catch (_) {}
    }
    return n;
  }
}

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});
  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  String _kind = '';
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    TrashOps.purgeExpired().then((n) {
      if (n > 0) toast('$n eski kayıt (30 günü dolan) kalıcı silindi');
    }).catchError((_) {});
  }

  Future<void> _restore(TrashItem it) async {
    if (!await confirm(context, 'Geri getirilsin mi?', '${it.kindLabel}: ${it.title}\nKayıt eski yerine döner.', 'Geri getir')) return;
    setState(() => _busy.add(it.id));
    try {
      final err = await TrashOps.restore(it);
      toast(err ?? 'Geri getirildi');
    } catch (e) {
      toast('Geri getirilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(it.id));
    }
  }

  Future<void> _purge(TrashItem it) async {
    if (!await confirm(context, 'Kalıcı silinsin mi?', '${it.kindLabel}: ${it.title}\nBu işlem geri alınamaz.', 'Kalıcı sil')) return;
    setState(() => _busy.add(it.id));
    try {
      await TrashOps.purge(it);
      toast('Kalıcı silindi');
    } catch (e) {
      toast('Silinemedi: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(it.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Silinenler')),
      body: StreamBuilder<List<TrashItem>>(
        stream: TrashOps.stream(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          final list = _kind.isEmpty ? all : all.where((x) => x.kind == _kind).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Silinen kayıtlar 30 gün burada bekler. "Geri getir" ile eski yerine döner; süre dolunca kalıcı silinir.',
                style: TextStyle(color: kMuted)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(label: Text('Tümü (${all.length})'), selected: _kind.isEmpty, onSelected: (_) => setState(() => _kind = '')),
              for (final e in kTrashKinds.entries)
                if (all.any((x) => x.kind == e.key))
                  ChoiceChip(
                      label: Text('${e.value} (${all.where((x) => x.kind == e.key).length})'),
                      selected: _kind == e.key,
                      onSelected: (_) => setState(() => _kind = e.key)),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Silinen kayıt yok.', style: TextStyle(color: kMuted)))),
            for (final it in list)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.kindLabel, style: const TextStyle(color: kOrange, fontSize: 12, fontWeight: FontWeight.w600)),
                    Text(it.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${it.deletedBy} sildi · ${fmtFull(it.deletedAt)} · ${it.daysLeft} gün kaldı${it.itemCount > 0 ? ' · ${it.itemCount} alt kayıt' : ''}',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2B8A3E)),
                        onPressed: _busy.contains(it.id) ? null : () => _restore(it),
                        icon: const Icon(Icons.restore),
                        label: const Text('Geri getir'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFC92A2A)),
                        onPressed: _busy.contains(it.id) ? null : () => _purge(it),
                        child: const Text('Kalıcı sil'),
                      ),
                      if (_busy.contains(it.id)) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                    ]),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
