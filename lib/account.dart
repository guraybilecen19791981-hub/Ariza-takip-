part of 'main.dart';

// ---------------------------------------------------------------------------
// Şifre: kullanıcı kendi şifresini değiştirir; admin sıfırlar (bulut fonksiyonu)
// Şifreler kimseye görünmez; yalnız kimin, ne zaman, kim tarafından değiştirdiği kaydedilir.
// ---------------------------------------------------------------------------

const String kPwFnUrl = 'https://us-central1-ariza-takip-3bce3.cloudfunctions.net/adminSetPassword';

Future<void> changeOwnPasswordDialog(BuildContext context) async {
  final cur = TextEditingController();
  final n1 = TextEditingController();
  final n2 = TextEditingController();
  bool show = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: const Text('Şifremi değiştir'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cur, obscureText: !show, autofocus: true, decoration: const InputDecoration(labelText: 'Mevcut şifre')),
            const SizedBox(height: 8),
            TextField(controller: n1, obscureText: !show, decoration: const InputDecoration(labelText: 'Yeni şifre (en az 6 karakter)')),
            const SizedBox(height: 8),
            TextField(controller: n2, obscureText: !show, decoration: const InputDecoration(labelText: 'Yeni şifre (tekrar)')),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: show,
              title: const Text('Şifreleri göster'),
              onChanged: (v) => setS(() => show = v == true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Değiştir')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (n1.text.length < 6) {
    toast('Yeni şifre en az 6 karakter olmalı.');
    return;
  }
  if (n1.text != n2.text) {
    toast('Yeni şifreler aynı değil.');
    return;
  }
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email ?? '';
  if (user == null || email.isEmpty) {
    toast('Oturum bulunamadı, lütfen yeniden giriş yapın.');
    return;
  }
  try {
    await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: email, password: cur.text));
    await user.updatePassword(n1.text);
    try {
      await db.collection('passwordLogs').add({
        'uid': user.uid,
        'name': currentUser?.name ?? '',
        'email': email,
        'kind': 'kendi',
        'byUid': user.uid,
        'byName': currentUser?.name ?? '',
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    toast('Şifreniz değiştirildi.');
  } on FirebaseAuthException catch (e) {
    if (e.code == 'wrong-password' || e.code == 'invalid-credential' || e.code == 'invalid-login-credentials') {
      toast('Mevcut şifre yanlış.');
    } else if (e.code == 'weak-password') {
      toast('Yeni şifre çok zayıf.');
    } else if (e.code == 'too-many-requests') {
      toast('Çok fazla deneme. Biraz sonra tekrar deneyin.');
    } else {
      toast('Şifre değiştirilemedi: ${e.message ?? e.code}');
    }
  } catch (e) {
    toast('Şifre değiştirilemedi: $e');
  }
}

// Admin: bulut fonksiyonu ile kullanıcıya yeni şifre belirler. Hata yoksa null döner.
Future<String?> adminSetPassword(String uid, String password) async {
  if (kIsWeb) return 'Web sürümünde yapılamıyor; web panelinden ya da telefondan sıfırlayın.';
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null) return 'Oturum bulunamadı.';
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(kPwFnUrl)).timeout(const Duration(seconds: 20));
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({'uid': uid, 'password': password})));
    final res = await req.close().timeout(const Duration(seconds: 40));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 200) return null;
    if (res.statusCode == 404) return 'Şifre sıfırlama servisi henüz kurulmamış (kurulum adımı yapılmalı).';
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] != null) return m['error'].toString();
    } catch (_) {}
    return 'Hata ${res.statusCode}';
  } catch (e) {
    return 'Bağlantı hatası: $e';
  } finally {
    client.close();
  }
}

Future<void> adminResetPasswordDialog(BuildContext context, AppUser u) async {
  final p = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('${u.name} · şifre sıfırla'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: p, autofocus: true, decoration: const InputDecoration(labelText: 'Yeni şifre (en az 6 karakter)')),
        const SizedBox(height: 8),
        const Text('Yeni şifreyi kişiye siz iletin. Kişi girişten sonra "Şifremi değiştir" ile kendi şifresini belirleyebilir.',
            style: TextStyle(color: kMuted, fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Şifreyi değiştir')),
      ],
    ),
  );
  if (ok != true) return;
  if (p.text.trim().length < 6) {
    toast('Şifre en az 6 karakter olmalı.');
    return;
  }
  toast('Şifre değiştiriliyor…');
  final err = await adminSetPassword(u.uid, p.text.trim());
  toast(err == null ? '${u.name} için yeni şifre kaydedildi.' : err);
}

class PasswordLogsPage extends StatelessWidget {
  const PasswordLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Şifre değişiklik kayıtları')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('passwordLogs').orderBy('at', descending: true).limit(300).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Hata: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Henüz şifre değişikliği yok.', style: TextStyle(color: kMuted)));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = docs[i].data();
              final self = m['kind'] == 'kendi';
              return ListTile(
                leading: Icon(self ? Icons.person : Icons.admin_panel_settings, color: self ? kMuted : kOrange),
                title: Text((m['name'] ?? '').toString()),
                subtitle: Text('${fmtFull(tsToDate(m['at']))} · ${self ? 'kendisi değiştirdi' : 'admin sıfırladı (${m['byName'] ?? ''})'}'),
              );
            },
          );
        },
      ),
    );
  }
}
