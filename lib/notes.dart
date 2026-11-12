part of 'main.dart';

// ---------------------------------------------------------------------------
// Notlar: Sargı / Üretim makineleri (sipariş ya da makine), Paketleme ve Paletleme siparişlerine
// istenildiği kadar not eklenir. Notlar raporlarda ve Excel'de görünür.
// ---------------------------------------------------------------------------

const Map<String, String> kNoteModules = {'sargi': 'Sargı makineleri', 'uretim': 'Üretim makineleri', 'paketleme': 'Paketleme', 'paletleme': 'Paletleme'};

class NoteRef {
  final String module; // sargi | uretim | paketleme | paletleme
  final String refType; // job | machine | pack | pallet
  final String refId;
  final String title;
  final String machineId;
  final String machineName;
  final String orderNo;
  final String productCode;
  final String line;
  const NoteRef({
    required this.module,
    required this.refType,
    required this.refId,
    required this.title,
    this.machineId = '',
    this.machineName = '',
    this.orderNo = '',
    this.productCode = '',
    this.line = '',
  });

  // Makinede aktif sipariş varsa siparişe, yoksa makineye not eklenir
  factory NoteRef.machine(LineMachine m) => m.hasJob
      ? NoteRef(
          module: m.grp.key,
          refType: 'job',
          refId: m.jobId,
          title: 'Sipariş ${m.orderNo} · ${m.name}',
          machineId: m.id,
          machineName: m.name,
          orderNo: m.orderNo,
          productCode: m.productCode,
          line: m.line)
      : NoteRef(module: m.grp.key, refType: 'machine', refId: m.id, title: m.name, machineId: m.id, machineName: m.name, line: m.line);

  factory NoteRef.job(MJob j) => NoteRef(
      module: mGroupOf(j.group).key,
      refType: 'job',
      refId: j.id,
      title: 'Sipariş ${j.orderNo} · ${j.machineName}',
      machineId: j.machineId,
      machineName: j.machineName,
      orderNo: j.orderNo,
      productCode: j.productCode,
      line: j.line);
}

class MNote {
  final String id;
  final String module;
  final String refType;
  final String refId;
  final String machineId;
  final String machineName;
  final String orderNo;
  final String productCode;
  final String line;
  final String text;
  final String by;
  final String byUid;
  final DateTime? t;
  const MNote(this.id, this.module, this.refType, this.refId, this.machineId, this.machineName, this.orderNo, this.productCode, this.line, this.text,
      this.by, this.byUid, this.t);

  factory MNote.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    String s(String k) => (m[k] ?? '').toString();
    return MNote(d.id, s('module'), s('refType'), s('refId'), s('machineId'), s('machineName'), s('orderNo'), s('productCode'), s('line'), s('text'),
        s('by'), s('byUid'), tsToDate(m['t']));
  }

  String get line1 => '${fmtFull(t)} · $by: $text';
}

class NotesOps {
  static CollectionReference<Map<String, dynamic>> get col => db.collection('notes');

  static List<MNote> _sorted(Iterable<MNote> l) => l.toList()..sort((a, b) => (a.t ?? DateTime(2000)).compareTo(b.t ?? DateTime(2000)));

  static Stream<List<MNote>> byRef(String refId) =>
      col.where('refId', isEqualTo: refId).snapshots().map((s) => _sorted(s.docs.map((d) => MNote.fromDoc(d))));

  static Future<void> add(NoteRef r, String text) => col.add({
        'module': r.module,
        'refType': r.refType,
        'refId': r.refId,
        'machineId': r.machineId,
        'machineName': r.machineName,
        'orderNo': r.orderNo,
        'productCode': r.productCode,
        'line': r.line,
        'text': text,
        'by': currentUser?.name ?? '',
        'byUid': currentUser?.uid ?? '',
        't': Timestamp.now(),
      });

  // Bir paneldeki tüm notlar (Excel için), kayıt kimliğine göre gruplu
  static Future<Map<String, List<MNote>>> byModule(String module) async {
    final s = await col.where('module', isEqualTo: module).get();
    final out = <String, List<MNote>>{};
    for (final n in _sorted(s.docs.map((d) => MNote.fromDoc(d)))) {
      out.putIfAbsent(n.refId, () => <MNote>[]).add(n);
    }
    return out;
  }

  // Tarih aralığındaki notlar (makine raporu için)
  static Future<List<MNote>> between(String module, DateTime from, DateTime to) async {
    final s = await col.where('t', isGreaterThanOrEqualTo: Timestamp.fromDate(from)).where('t', isLessThan: Timestamp.fromDate(to)).get();
    return _sorted(s.docs.map((d) => MNote.fromDoc(d)).where((n) => n.module == module));
  }

  static String joined(List<MNote>? l) => (l ?? const <MNote>[]).map((n) => n.line1).join(' | ');
}

Future<void> addNoteDialog(BuildContext context, NoteRef r) async {
  final t = await askText(context, 'Not ekle', r.title, ok: 'Ekle', mustFill: true);
  if (t == null || t.trim().isEmpty) return;
  try {
    await NotesOps.add(r, t.trim());
    toast('Not eklendi');
  } catch (e) {
    toast('Kaydedilemedi: $e');
  }
}

class NotesPage extends StatelessWidget {
  final NoteRef ref;
  const NotesPage({super.key, required this.ref});

  @override
  Widget build(BuildContext context) {
    final me = currentUser;
    return Scaffold(
      appBar: AppBar(title: Text('Notlar · ${ref.title}')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kOrange,
        foregroundColor: Colors.white,
        onPressed: () => addNoteDialog(context, ref),
        icon: const Icon(Icons.note_add),
        label: const Text('Not ekle'),
      ),
      body: StreamBuilder<List<MNote>>(
        stream: NotesOps.byRef(ref.refId),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!.reversed.toList();
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Henüz not yok. Olan her şeyi (ayar, sorun, bilgi) "Not ekle" ile yazın; raporlarda ve Excel\'de görünür.',
                    textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final n = list[i];
              final canDel = me != null && (me.isAdmin || me.uid == n.byUid);
              return GestureDetector(
                onLongPress: canDel
                    ? () async {
                        if (!await confirm(context, 'Not silinsin mi?', n.text, 'Sil')) return;
                        try {
                          await NotesOps.col.doc(n.id).delete();
                        } catch (e) {
                          toast('Silinemedi: $e');
                        }
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFFF9DB), borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${n.by} · ${fmtFull(n.t)}', style: const TextStyle(color: kMuted, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(n.text, style: const TextStyle(fontSize: 15)),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Not düğmesi: not sayısını gösterir, dokununca notlar sayfası açılır
class NotesButton extends StatelessWidget {
  final NoteRef noteRef;
  const NotesButton({super.key, required this.noteRef});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MNote>>(
      stream: NotesOps.byRef(noteRef.refId),
      builder: (context, snap) {
        final l = snap.data ?? const <MNote>[];
        return OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotesPage(ref: noteRef))),
          icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
          label: Text(l.isEmpty ? 'Notlar · not ekle' : 'Notlar (${l.length}) · son: ${l.last.text}', maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}
