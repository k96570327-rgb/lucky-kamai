import 'dart:math';
import 'package:flutter/material.dart';
import 'package:scratcher/scratcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const minWithdraw = 50.0, dailySpins = 3, dailyCards = 3, refBonus = 10.0;
const prizes = [0.10, 0.50, 0.20, 1.0, 0.05, 0.30, 2.0, 0.10];
const ink = Color(0xFF3A1030), rose = Color(0xFFC2386B), gold = Color(0xFFF5A524), teal = Color(0xFF0E7C7B), cream = Color(0xFFFFF4DC);

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Lucky Kamai',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: rose, scaffoldBackgroundColor: cream, useMaterial3: true),
        home: const Home(),
      );
}

class Store extends ChangeNotifier {
  late SharedPreferences p;
  double bal = 0;
  int spins = dailySpins, cards = dailyCards, refs = 0;
  String code = '', upi = '';
  bool usedRef = false;
  List<String> hist = [];

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    bal = p.getDouble('bal') ?? 0;
    refs = p.getInt('refs') ?? 0;
    usedRef = p.getBool('usedRef') ?? false;
    upi = p.getString('upi') ?? '';
    hist = p.getStringList('hist') ?? [];
    code = p.getString('code') ?? 'LUCKY${_rnd(5)}';
    if (p.getString('day') != today) {
      spins = dailySpins; cards = dailyCards;
      await p.setString('day', today);
    } else {
      spins = p.getInt('spins') ?? dailySpins;
      cards = p.getInt('cards') ?? dailyCards;
    }
    await _save();
  }

  String _rnd(int n) {
    const ch = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(n, (_) => ch[r.nextInt(ch.length)]).join();
  }

  Future<void> _save() async {
    await p.setDouble('bal', bal); await p.setInt('refs', refs);
    await p.setBool('usedRef', usedRef); await p.setString('upi', upi);
    await p.setStringList('hist', hist.take(50).toList());
    await p.setString('code', code);
    await p.setInt('spins', spins); await p.setInt('cards', cards);
    notifyListeners();
  }

  Future<void> add(double a, String why) async {
    bal = double.parse((bal + a).toStringAsFixed(2));
    hist.insert(0, '${a.toStringAsFixed(2)}|$why|${DateTime.now().toString().substring(0, 16)}');
    await _save();
  }

  Future<void> useSpin() async { spins--; await _save(); }
  Future<void> useCard() async { cards--; await _save(); }

  Future<String?> applyCode(String c) async {
    c = c.trim().toUpperCase();
    if (usedRef) return 'Aap pehle hi code laga chuke hain';
    if (!RegExp(r'^LUCKY[A-Z0-9]{5}$').hasMatch(c)) return 'Code galat hai';
    if (c == code) return 'Apna code khud nahi laga sakte';
    usedRef = true;
    await add(refBonus, 'Referral bonus ($c)');
    return null;
  }

  Future<String?> withdraw(String id) async {
    if (!RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(id.trim())) return 'UPI ID sahi daalo (naam@bank)';
    if (bal < minWithdraw) return 'Minimum ₹${minWithdraw.toInt()} chahiye';
    final amt = bal;
    upi = id.trim();
    await add(-amt, 'Withdraw → $upi (pending)');
    return null;
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
  int tab = 0;

  @override
  void initState() {
    super.initState();
    s.load().then((_) => setState(() => ready = true));
  }

  void toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return ListenableBuilder(
      listenable: s,
      builder: (_, __) => Scaffold(
        appBar: AppBar(
          backgroundColor: cream,
          title: const Text('Lucky Kamai', style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(99)),
              child: Text('₹${s.bal.toStringAsFixed(2)}', style: const TextStyle(color: cream, fontSize: 18, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: [SpinTab(s, toast), ScratchTab(s, toast), ReferTab(s, toast), WalletTab(s, toast)][tab],
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

class SpinTab extends StatefulWidget {
  final Store s; final void Function(String) toast;
  const SpinTab(this.s, this.toast, {super.key});
  @override
  State<SpinTab> createState() => _SpinTabState();
}

class _SpinTabState extends State<SpinTab> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  double rot = 0; Animation<double>? anim; bool busy = false;

  Future<void> spin() async {
    if (widget.s.spins < 1 || busy) return;
    setState(() => busy = true);
    await widget.s.useSpin();
    final i = Random.secure().nextInt(prizes.length);
    final center = i * pi / 4 + pi / 8;
    final cur = rot % (2 * pi);
    final target = rot + 2 * pi * 5 + ((2 * pi - center) - cur + 2 * pi) % (2 * pi);
    anim = Tween(begin: rot, end: target).animate(CurvedAnimation(parent: ctl, curve: Curves.easeOutCubic));
    ctl.reset();
    await ctl.forward();
    rot = target;
    await widget.s.add(prizes[i], 'Spin reward');
    widget.toast('Badhai! ₹${prizes[i]} mile');
    setState(() => busy = false);
  }

  @override
  void dispose() { ctl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('Aaj ke spin bache: ${widget.s.spins} / $dailySpins'),
        const SizedBox(height: 16),
        SizedBox(
          width: 300, height: 320,
          child: Stack(alignment: Alignment.topCenter, children: [
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: AnimatedBuilder(
                animation: ctl,
                builder: (_, __) => Transform.rotate(angle: anim?.value ?? rot, child: CustomPaint(size: const Size(290, 290), painter: WheelPainter())),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 56, color: ink),
          ]),
        ),
        FilledButton(onPressed: widget.s.spins > 0 && !busy ? spin : null, child: const Padding(padding: EdgeInsets.all(10), child: Text('Spin', style: TextStyle(fontSize: 20)))),
      ]);
}

class WheelPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size sz) {
    final r = sz.width / 2, o = Offset(r, r);
    const cols = [gold, rose, teal];
    for (var i = 0; i < 8; i++) {
      final a = -pi / 2 + i * pi / 4;
      c.drawArc(Rect.fromCircle(center: o, radius: r), a, pi / 4, true, Paint()..color = cols[i % 3]);
      final tp = TextPainter(text: TextSpan(text: '₹${prizes[i]}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), textDirection: TextDirection.ltr)..layout();
      final m = a + pi / 8;
      c.save();
      c.translate(o.dx + cos(m) * r * 0.68, o.dy + sin(m) * r * 0.68);
      c.rotate(m + pi / 2);
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
      c.restore();
    }
    c.drawCircle(o, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = ink);
    c.drawCircle(o, 18, Paint()..color = ink);
  }
  @override
  bool shouldRepaint(_) => false;
}

class ScratchTab extends StatefulWidget {
  final Store s; final void Function(String) toast;
  const ScratchTab(this.s, this.toast, {super.key});
  @override
  State<ScratchTab> createState() => _ScratchTabState();
}

class _ScratchTabState extends State<ScratchTab> {
  double? value; bool claimed = true; Key key = UniqueKey();

  Future<void> newCard() async {
    if (widget.s.cards < 1 || !claimed) return;
    await widget.s.useCard();
    setState(() { value = prizes[Random.secure().nextInt(prizes.length)]; claimed = false; key = UniqueKey(); });
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('Aaj ke card bache: ${widget.s.cards} / $dailyCards'),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 280, height: 150,
            child: value == null
                ? Container(color: Colors.black12, alignment: Alignment.center, child: const Text('Naya card lo'))
                : Scratcher(
                    key: key, brushSize: 34, threshold: 45, color: rose,
                    onThreshold: () async {
                      if (claimed) return;
                      claimed = true;
                      await widget.s.add(value!, 'Scratch card');
                      widget.toast('Badhai! ₹$value mile');
                      setState(() {});
                    },
                    child: Container(width: 280, height: 150, color: const Color(0xFFFFF3C9), alignment: Alignment.center,
                        child: Text('₹$value', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: ink))),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: widget.s.cards > 0 && claimed ? newCard : null, child: const Text('Naya card lo')),
      ]);
}

class ReferTab extends StatelessWidget {
  final Store s; final void Function(String) toast;
  ReferTab(this.s, this.toast, {super.key});
  final c = TextEditingController();
  @override
  Widget build(BuildContext context) => ListView(children: [
        const Text('Dost bulao, ₹10 kamao', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14), alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: gold, width: 2), borderRadius: BorderRadius.circular(14)),
          child: SelectableText(s.code, style: const TextStyle(fontSize: 30, letterSpacing: 3, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.share),
          label: const Text('Share karo'),
          onPressed: () => Share.share('Lucky Kamai pe spin aur scratch karke UPI mein paise kamao! Mera code ${s.code} use karo aur ₹10 bonus pao.\nApp link: https://YOUR-APP-LINK'),
        ),
        const SizedBox(height: 4),
        Text('Joined dost: ${s.refs}'),
        const Divider(height: 32),
        TextField(controller: c, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Dost ka code', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: s.usedRef ? null : () async { final e = await s.applyCode(c.text); toast(e ?? '₹10 bonus mil gaya'); },
          child: const Text('Code lagao'),
        ),
      ]);
}

class WalletTab extends StatelessWidget {
  final Store s; final void Function(String) toast;
  WalletTab(this.s, this.toast, {super.key}) { u.text = s.upi; }
  final u = TextEditingController();
  @override
  Widget build(BuildContext context) => ListView(children: [
        Text('UPI se nikalo (minimum ₹${minWithdraw.toInt()})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (s.bal / minWithdraw).clamp(0, 1), minHeight: 10, borderRadius: BorderRadius.circular(9)),
        const SizedBox(height: 12),
        TextField(controller: u, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'UPI ID (naam@bank)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(onPressed: () async { final e = await s.withdraw(u.text); toast(e ?? 'Request bhej di gayi'); }, child: const Text('Withdraw request bhejo')),
        const Divider(height: 32),
        const Text('History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (s.hist.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Abhi koi kamai nahi. Pehla spin kar lo.')),
        ...s.hist.map((h) {
          final p = h.split('|'); final a = double.parse(p[0]);
          return ListTile(
            dense: true, title: Text(p[1]), subtitle: Text(p[2]),
            trailing: Text('${a >= 0 ? '+' : '-'}₹${a.abs().toStringAsFixed(2)}', style: TextStyle(color: a >= 0 ? teal : rose, fontWeight: FontWeight.bold)),
          );
        }),
      ]);
}
