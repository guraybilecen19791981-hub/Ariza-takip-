part of 'main.dart';

// ---------------------------------------------------------------------------
// Görsel onaylar paneli: paketleme, sargı ve üretim siparişlerinde onay bekleyen tüm görseller tek yerde.
// Yetki admin tarafından verilir (Kullanıcılar → "Görsel onaylar"): Görür = görür, Girer = kendi rolüne
// istenenleri onaylar, Yönetir = hepsini onaylar. Tek onay yeterli; makine / paketleme durumu değişmez.
// ---------------------------------------------------------------------------

class ApprovalsHome extends StatefulWidget {
  final AppUser me;
  final Widget? nav;
  const ApprovalsHome({super.key, required this.me, this.nav});

  @override
  State<ApprovalsHome> createState() => _ApprovalsHomeState();
}

class _ApprovalsHomeState extends State<ApprovalsHome> {
  late bool _mine = widget.me.can('onay', 'gir') && !widget.me.can('onay', 'yonet') && !widget.me.isAdmin;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _packs = db.collection('packOrders').where('pendingApprovals', isGreaterThan: 0).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _jobs = MachineOps.jobs.where('pendingApprovals', isGreaterThan: 0).snapshots();

  int _n(QuerySnapshot<Map<String, dynamic>>? s) => (s?.docs ?? const []).fold(0, (a, d) => a + _int(d.data()['pendingApprovals']));

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _packs,
      builder: (context, ps) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _jobs,
        builder: (context, js) {
          final packs = ps.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final jobs = js.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final total = _n(ps.data) + _n(js.data);
          final loading = !ps.hasData || !js.hasData;
          return Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Görsel onaylar${loading ? '' : ' ($total)'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                Text('${me.name} · ${me.roleLabel}', style: const TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
              ]),
              actions: [...commonActions(me)],
            ),
            bottomNavigationBar: widget.nav,
            body: ps.hasError || js.hasError
                ? Center(child: Text('Hata: ${ps.error ?? js.error}'))
                : loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
                        if (me.can('onay', 'gir') && !me.can('onay', 'yonet') && !me.isAdmin)
                          SegmentedButton<bool>(
                            segments: const [ButtonSegment(value: true, label: Text('Bana gelenler')), ButtonSegment(value: false, label: Text('Tümü'))],
                            selected: {_mine},
                            onSelectionChanged: (v) => setState(() => _mine = v.first),
                          ),
                        if (!me.can('onay', 'gir'))
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text('Görme yetkiniz var; onay vermek için admin "Görsel onaylar" yetkinizi Girer ya da Yönetir yapmalı.',
                                style: TextStyle(color: kMuted, fontSize: 12)),
                          ),
                        const SizedBox(height: 8),
                        if (total == 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: Center(child: Text('Onay bekleyen görsel yok.', style: TextStyle(color: kMuted, fontSize: 16))),
                          ),
                        for (final d in packs) _ApprovalGroup(key: ValueKey('p-${d.id}'), kind: 'pack', doc: d, mine: _mine),
                        for (final d in jobs) _ApprovalGroup(key: ValueKey('j-${d.id}'), kind: 'job', doc: d, mine: _mine),
                      ]),
          );
        },
      ),
    );
  }
}

class _ApprovalGroup extends StatelessWidget {
  final String kind; // pack | job
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool mine;
  const _ApprovalGroup({super.key, required this.kind, required this.doc, required this.mine});

  @override
  Widget build(BuildContext context) {
    final o = doc.data();
    final isPack = kind == 'pack';
    final src = isPack ? 'Paketleme' : mGroupOf((o['group'] ?? '').toString()).title;
    final title = 'Sipariş ${o['orderNo'] ?? ''} · ${o['productCode'] ?? ''}${isPack ? '' : ' · ${o['machineName'] ?? ''}'}';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: doc.reference.collection('photos').where('status', isEqualTo: 'bekliyor').snapshots(),
      builder: (context, snap) {
        final me = currentUser;
        var photos = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (mine) photos = photos.where((p) => canApprovePhoto(me, _approvers(p.data()))).toList();
        if (photos.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final p in photos) _ApprovalCard(src: src, title: title, isPack: isPack, order: doc, photo: p),
        ]);
      },
    );
  }
}

List<String> _approvers(Map<String, dynamic> m) => m['approvers'] is List ? (m['approvers'] as List).map((e) => e.toString()).toList() : <String>[];

class _ApprovalCard extends StatelessWidget {
  final String src;
  final String title;
  final bool isPack;
  final QueryDocumentSnapshot<Map<String, dynamic>> order;
  final QueryDocumentSnapshot<Map<String, dynamic>> photo;
  const _ApprovalCard({required this.src, required this.title, required this.isPack, required this.order, required this.photo});

  Future<void> _decide(BuildContext context, bool approve) async {
    final me = currentUser;
    if (me == null) return;
    final ap = _approvers(photo.data());
    final note = await askText(context, approve ? 'Görsel onaylansın mı?' : 'Görsel reddedilsin mi?', approve ? 'Açıklama (isteğe bağlı)' : 'Red nedeni',
        ok: approve ? 'Onayla' : 'Reddet', mustFill: !approve);
    if (note == null) return;
    final role = approveRoleFor(me, ap);
    try {
      if (isPack) {
        await PackOps.decidePhoto(PackOrder.fromDoc(order), PackPhoto.fromDoc(photo), role, approve, note.trim());
      } else {
        await JobPhotoOps.decide(order.id, photo, role, approve, note.trim());
      }
      toast(approve ? 'Onaylandı' : 'Reddedildi');
    } catch (e) {
      toast('Kaydedilemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = photo.data();
    final me = currentUser;
    final ap = _approvers(m);
    final can = canApprovePhoto(me, ap);
    final url = (m['url'] ?? '').toString(), data = (m['data'] ?? '').toString();
    final note = (m['note'] ?? '').toString();
    final stage = isPack ? (kPhotoStages[(m['stage'] ?? '').toString()] ?? '') : '';
    final forMe = me != null && ap.contains(me.role);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: forMe ? const Color(0xFFF59F00) : const Color(0xFFE3E6EA), width: forMe ? 2 : 1)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => openStoredImage(context, url, data),
            child: ClipRRect(borderRadius: BorderRadius.circular(8), child: storedImage(url, data, width: 104, height: 104)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, children: [
                _tag(src, isPack ? const Color(0xFF9A3412) : const Color(0xFF1D4ED8), isPack ? const Color(0xFFFFE8CC) : const Color(0xFFDBE8FF)),
                if (stage.isNotEmpty) _tag(stage, kMuted, const Color(0xFFF1F3F5)),
                if (forMe) _tag('Size', const Color(0xFF6B4F00), const Color(0xFFFFF3BF)),
              ]),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${m['by'] ?? ''} · ${fmtDT(tsToDate(m['t']))}', style: const TextStyle(color: kMuted, fontSize: 12)),
              if (note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 13)),
              Text('Onay istenen: ${ap.map(approverLabel).join(' / ')}', style: const TextStyle(color: Color(0xFF6B4F00), fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (can)
                Wrap(spacing: 6, children: [
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kGreen, visualDensity: VisualDensity.compact),
                    onPressed: () => _decide(context, true),
                    child: const Text('Onayla'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC92A2A), visualDensity: VisualDensity.compact),
                    onPressed: () => _decide(context, false),
                    child: const Text('Reddet'),
                  ),
                ])
              else
                const Text('Bu görseli onaylama yetkiniz yok.', style: TextStyle(color: kMuted, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tag(String t, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}
