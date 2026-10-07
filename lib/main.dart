import 'dart:math';
import 'package:flutter/material.dart';
import 'package:scratcher/scratcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://cgjqjyypuwwjzvhsodlq.supabase.co';
const supabaseKey = 'sb_publishable_UBWjqI1A4cR2Lkv3S3N2aw_I6JO8ZxY'; // public key, safe in the app

const prizes = [10, 50, 20, 100, 5, 30, 200, 10]; // paise, same order as the server
const dailySpins = 3, dailyCards = 3, minWithdraw = 5000, refBonus = 500;
const ink = Color(0xFF0B0620), panel = Color(0xFF1B1038), rose = Color(0xFFD81B60), gold = Color(0xFFF5B301), teal = Color(0xFF2BD67B), cream = Color(0xFFFFE9A8), purple = Color(0xFF7B2CBF), blue = Color(0xFF3D35D1), green = Color(0xFF11A24C);

SupabaseClient get sb => Supabase.instance.client;
String rs(num paise) => '₹${(paise / 100).toStringAsFixed(2)}';
String errText(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  return 'Network problem. Dobara try karo';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Lucky Kamai',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: purple,
          scaffoldBackgroundColor: ink,
          useMaterial3: true,
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: ink, textStyle: const TextStyle(fontWeight: FontWeight.w800), shape: const StadiumBorder()),
          ),
          navigationBarTheme: NavigationBarThemeData(backgroundColor: panel, indicatorColor: gold.withAlpha(90)),
        ),
        home: const AuthGate(),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<AuthState>(
        stream: sb.auth.onAuthStateChange,
        builder: (_, __) {
          final s = sb.auth.currentSession;
          if (s == null) return const LoginPage();
          return Home(key: ValueKey(s.user.id));
        },
      );
}

// ---------- Login ----------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), pass = TextEditingController();
  bool busy = false;
  String err = '';

  Future<void> go(bool signup) async {
    final e = email.text.trim(), p = pass.text;
    if (!e.contains('@') || p.length < 6) {
      setState(() => err = 'Sahi email aur kam se kam 6 akshar ka password daalo');
      return;
    }
    setState(() { busy = true; err = ''; });
    try {
      if (signup) {
        final r = await sb.auth.signUp(email: e, password: p);
        if (r.session == null) err = 'Signup ho gaya. Ab Login dabao.';
      } else {
        await sb.auth.signInWithPassword(email: e, password: p);
      }
    } catch (x) {
      err = errText(x);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 40),
            const Text('Lucky Kamai', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: gold)),
            const Text('Spin. Scratch. Win.', style: TextStyle(color: cream, fontSize: 16)),
            const SizedBox(height: 32),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            FilledButton(onPressed: busy ? null : () => go(false), child: const Padding(padding: EdgeInsets.all(10), child: Text('Login'))),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : () => go(true), child: const Padding(padding: EdgeInsets.all(10), child: Text('Naya account banao'))),
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(err, style: const TextStyle(color: rose))),
          ]),
        ),
      );
}

// ---------- Store (all money logic lives on the server) ----------
class Store extends ChangeNotifier {
  int bal = 0, spins = dailySpins, cards = dailyCards, refs = 0;
  String code = '';
  bool pending = false, usedRef = false;
  List<Map<String, dynamic>> hist = [], wd = [];

  Future<void> load() async {
    final p = Map<String, dynamic>.from(await sb.rpc('ensure_profile') as Map);
    bal = p['balance'] as int;
    code = p['code'] as String;
    refs = p['ref_count'] as int;
    pending = p['pending_withdraw'] as bool;
    usedRef = p['ref_by'] != null;
    final today = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String().substring(0, 10);
    if (p['day'] == today) {
      spins = p['spins_left'] as int;
      cards = p['cards_left'] as int;
    } else {
      spins = dailySpins;
      cards = dailyCards;
    }
    final h = await sb.from('ledger').select().order('at', ascending: false).limit(50);
    hist = List<Map<String, dynamic>>.from(h);
    final w = await sb.from('withdrawals').select().order('created_at', ascending: false).limit(20);
    wd = List<Map<String, dynamic>>.from(w);
    notifyListeners();
  }

  Future<Map> playSpin() async {
    final r = await sb.rpc('spin') as Map;
    spins--;
    notifyListeners();
    return r;
  }

  Future<Map> playScratch() async {
    final r = await sb.rpc('scratch') as Map;
    cards--;
    notifyListeners();
    return r;
  }

  Future<String?> applyCode(String c) async {
    try {
      await sb.rpc('apply_referral', params: {'p_code': c});
      await load();
      return null;
    } catch (e) {
      return errText(e);
    }
  }

  Future<String?> withdraw(String upi) async {
    try {
      await sb.rpc('request_withdraw', params: {'p_upi': upi});
      await load();
      return null;
    } catch (e) {
      return errText(e);
    }
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final s = Store();
  bool ready = false;
  String? loadErr;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    try {
      await s.load();
      if (mounted) setState(() { ready = true; loadErr = null; });
    } catch (e) {
      if (mounted) setState(() => loadErr = errText(e));
    }
  }

  void toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    if (loadErr != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(loadErr!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: init, child: const Text('Dobara try karo')),
              TextButton(onPressed: () => sb.auth.signOut(), child: const Text('Logout')),
            ]),
          ),
        ),
      );
    }
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return ListenableBuilder(
      listenable: s,
      builder: (_, __) => Scaffold(
        appBar: AppBar(
          backgroundColor: ink,
          title: const Text('Lucky Kamai', style: TextStyle(fontWeight: FontWeight.w800, color: gold)),
          actions: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFE08A), gold]), borderRadius: BorderRadius.circular(99)),
              child: Text(rs(s.bal), style: const TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: () => sb.auth.signOut()),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: gold, width: 2),
              boxShadow: [BoxShadow(color: purple.withAlpha(140), blurRadius: 24)],
            ),
            child: [SpinTab(s, toast), ScratchTab(s, toast), ReferTab(s, toast), WalletTab(s, toast)][tab],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.casino), label: 'Spin'),
            NavigationDestination(icon: Icon(Icons.style), label: 'Scratch'),
            NavigationDestination(icon: Icon(Icons.group_add), label: 'Refer'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
          ],
        ),
      ),
    );
  }
}

// ---------- Spin ----------
class SpinTab extends StatefulWidget {
  final Store s;
  final void Function(String) toast;
  const SpinTab(this.s, this.toast, {super.key});
  @override
  State<SpinTab> createState() => _SpinTabState();
}

class _SpinTabState extends State<SpinTab> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  double rot = 0;
  Animation<double>? anim;
  bool busy = false;

  Future<void> spin() async {
    if (widget.s.spins < 1 || busy) return;
    setState(() => busy = true);
    try {
      final r = await widget.s.playSpin();
      final i = r['index'] as int;
      final center = i * pi / 4 + pi / 8;
      final cur = rot % (2 * pi);
      final target = rot + 2 * pi * 5 + ((2 * pi - center) - cur + 2 * pi) % (2 * pi);
      anim = Tween<double>(begin: rot, end: target).animate(CurvedAnimation(parent: ctl, curve: Curves.easeOutCubic));
      ctl.reset();
      await ctl.forward();
      rot = target;
      await widget.s.load();
      widget.toast('Badhai! ${rs(r['amount'] as num)} mile');
    } catch (e) {
      widget.toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('Aaj ke spin bache: ${widget.s.spins} / $dailySpins'),
        const SizedBox(height: 16),
        SizedBox(
          width: 300,
          height: 320,
          child: Stack(alignment: Alignment.topCenter, children: [
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: AnimatedBuilder(
                animation: ctl,
                builder: (_, __) => Transform.rotate(angle: anim?.value ?? rot, child: CustomPaint(size: const Size(290, 290), painter: WheelPainter())),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 56, color: gold),
          ]),
        ),
        FilledButton(
          onPressed: widget.s.spins > 0 && !busy ? spin : null,
          child: const Padding(padding: EdgeInsets.all(10), child: Text('Spin', style: TextStyle(fontSize: 20))),
        ),
      ]);
}

class WheelPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size sz) {
    final r = sz.width / 2, o = Offset(r, r);
    const cols = [blue, purple, rose, green];
    for (var i = 0; i < 8; i++) {
      final a = -pi / 2 + i * pi / 4;
      c.drawArc(Rect.fromCircle(center: o, radius: r), a, pi / 4, true, Paint()..color = cols[i % 4]);
      final tp = TextPainter(
        text: TextSpan(text: '₹${prizes[i] / 100}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        textDirection: TextDirection.ltr,
      )..layout();
      final m = a + pi / 8;
      c.save();
      c.translate(o.dx + cos(m) * r * 0.68, o.dy + sin(m) * r * 0.68);
      c.rotate(m + pi / 2);
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
      c.restore();
    }
    for (var i = 0; i < 8; i++) {
      final a = -pi / 2 + i * pi / 4;
      final p = Offset(o.dx + cos(a) * r, o.dy + sin(a) * r);
      c.drawLine(o, p, Paint()..color = gold..strokeWidth = 3);
      c.drawCircle(p, 6, Paint()..color = gold);
    }
    c.drawCircle(o, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = gold);
    c.drawCircle(o, 22, Paint()..color = gold);
    c.drawCircle(o, 10, Paint()..color = purple);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ---------- Scratch ----------
class ScratchTab extends StatefulWidget {
  final Store s;
  final void Function(String) toast;
  const ScratchTab(this.s, this.toast, {super.key});
  @override
  State<ScratchTab> createState() => _ScratchTabState();
}

class _ScratchTabState extends State<ScratchTab> {
  int? value;
  bool claimed = true, loading = false;
  Key key = UniqueKey();

  Future<void> newCard() async {
    if (widget.s.cards < 1 || !claimed || loading) return;
    setState(() => loading = true);
    try {
      final r = await widget.s.playScratch();
      setState(() {
        value = r['amount'] as int;
        claimed = false;
        key = UniqueKey();
      });
    } catch (e) {
      widget.toast(errText(e));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('Aaj ke card bache: ${widget.s.cards} / $dailyCards'),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 280,
            height: 150,
            child: value == null
                ? Container(color: Colors.black12, alignment: Alignment.center, child: const Text('Naya card lo'))
                : Scratcher(
                    key: key,
                    brushSize: 34,
                    threshold: 45,
                    color: const Color(0xFFD4A017),
                    onThreshold: () async {
                      if (claimed) return;
                      claimed = true;
                      try {
                        await widget.s.load();
                      } catch (_) {}
                      widget.toast('Badhai! ${rs(value!)} mile');
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      width: 280,
                      height: 150,
                      color: const Color(0xFFFFF3C9),
                      alignment: Alignment.center,
                      child: Text(rs(value!), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: ink)),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: widget.s.cards > 0 && claimed && !loading ? newCard : null, child: const Text('Naya card lo')),
      ]);
}

// ---------- Refer ----------
class ReferTab extends StatefulWidget {
  final Store s;
  final void Function(String) toast;
  const ReferTab(this.s, this.toast, {super.key});
  @override
  State<ReferTab> createState() => _ReferTabState();
}

class _ReferTabState extends State<ReferTab> {
  final c = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ListView(children: [
      Text('Dost bulao, ${rs(refBonus)} kamao', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: gold, width: 2), borderRadius: BorderRadius.circular(14)),
        child: SelectableText(s.code, style: const TextStyle(fontSize: 30, letterSpacing: 3, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: const Icon(Icons.share),
        label: const Text('Share karo'),
        onPressed: () => Share.share('Lucky Kamai pe spin aur scratch karke UPI mein paise kamao! App mein signup karke mera code ${s.code} daalo aur ${rs(refBonus)} bonus pao.'),
      ),
      const SizedBox(height: 4),
      Text('Joined dost: ${s.refs}'),
      const Divider(height: 32),
      TextField(
        controller: c,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Dost ka code', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      FilledButton.tonal(
        onPressed: s.usedRef || busy
            ? null
            : () async {
                setState(() => busy = true);
                final e = await s.applyCode(c.text);
                widget.toast(e ?? '${rs(refBonus)} bonus mil gaya');
                if (mounted) setState(() => busy = false);
              },
        child: Text(s.usedRef ? 'Code pehle hi laga chuka hai' : 'Code lagao'),
      ),
    ]);
  }
}

// ---------- Wallet ----------
class WalletTab extends StatefulWidget {
  final Store s;
  final void Function(String) toast;
  const WalletTab(this.s, this.toast, {super.key});
  @override
  State<WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<WalletTab> {
  final u = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return RefreshIndicator(onRefresh: s.load, child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
      Text('UPI se nikalo (minimum ${rs(minWithdraw)})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: (s.bal / minWithdraw).clamp(0, 1).toDouble(), color: gold, minHeight: 10, borderRadius: BorderRadius.circular(9)),
      const SizedBox(height: 12),
      if (s.pending) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Aapki withdraw request pending hai. Paisa jaldi bheja jayega.', style: TextStyle(color: teal))),
      TextField(controller: u, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'UPI ID (naam@bank)', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                final e = await s.withdraw(u.text);
                widget.toast(e ?? 'Request bhej di gayi');
                if (mounted) setState(() => busy = false);
              },
        child: const Text('Withdraw request bhejo'),
      ),
      if (s.wd.isNotEmpty) ...[
        const Divider(height: 32),
        const Text('Withdraw history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ...s.wd.map((w) {
          final st = w['status'] as String;
          final label = st == 'paid' ? 'Paid ✓' : st == 'rejected' ? 'Rejected (paisa wapas)' : 'Pending';
          final colr = st == 'paid' ? teal : st == 'rejected' ? rose : gold;
          final when = DateTime.parse(w['created_at'] as String).toLocal().toString().substring(0, 16);
          return ListTile(
            dense: true,
            title: Text('${rs(w['amount'] as int)} → ${w['upi']}'),
            subtitle: Text(when),
            trailing: Text(label, style: TextStyle(color: colr, fontWeight: FontWeight.bold)),
          );
        }),
      ],
      const Divider(height: 32),
      const Text('History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      if (s.hist.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Abhi koi kamai nahi. Pehla spin kar lo.')),
      ...s.hist.map((h) {
        final a = h['amt'] as int;
        final when = DateTime.parse(h['at'] as String).toLocal().toString().substring(0, 16);
        return ListTile(
          dense: true,
          title: Text(h['why'] as String),
          subtitle: Text(when),
          trailing: Text('${a >= 0 ? '+' : '-'}${rs(a.abs())}', style: TextStyle(color: a >= 0 ? teal : rose, fontWeight: FontWeight.bold)),
        );
      }),
    ]));
  }
}
