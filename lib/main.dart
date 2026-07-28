import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';
import 'repository.dart';

const forest = Color(0xFF214E34),
    leaf = Color(0xFF3C7A57),
    cream = Color(0xFFF7F3EA),
    ink = Color(0xFF24342A),
    gold = Color(0xFFC49A52),
    line = Color(0xFFE7E1D7),
    softGreen = Color(0xFFE7F0E8);
const supabaseUrl = 'https://qrsvrytndvcwcwvtdkxb.supabase.co';
const supabaseKey = 'sb_publishable_G56gHZOm2deflE2bY-aKTg_qwu2XMM4';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(const MyMemberApp());
}

String err(Object e) => e
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('PostgrestException(message: ', '')
    .split(', code:')
    .first;
String dt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String longDate(DateTime d) {
  const months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

void snack(BuildContext c, String s, {bool bad = false}) =>
    ScaffoldMessenger.of(c).showSnackBar(
      SnackBar(
        content: Text(s),
        backgroundColor: bad ? Colors.red.shade700 : forest,
      ),
    );

class MyMemberApp extends StatelessWidget {
  const MyMemberApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'MyMember',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: forest),
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        foregroundColor: ink,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: leaf, width: 1.4),
        ),
        floatingLabelStyle: const TextStyle(color: forest),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: line),
        ),
      ),
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(forest)),
      ),
    ),
    home: const AuthGate(),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AppRepository repo = AppRepository(Supabase.instance.client);
  @override
  void initState() {
    super.initState();
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) =>
      Supabase.instance.client.auth.currentSession == null
      ? LoginPage(repo: repo)
      : FutureBuilder(
          future: repo.ensureAdmin(),
          builder: (c, s) => s.connectionState != ConnectionState.done
              ? const Splash()
              : s.hasError
              ? AccessDenied(message: err(s.error!), repo: repo)
              : Home(repo: repo),
        );
}

class Splash extends StatelessWidget {
  const Splash({super.key});
  @override
  Widget build(BuildContext c) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_2, color: forest, size: 60),
          SizedBox(height: 16),
          CircularProgressIndicator(),
        ],
      ),
    ),
  );
}

class AccessDenied extends StatelessWidget {
  const AccessDenied({super.key, required this.message, required this.repo});
  final String message;
  final AppRepository repo;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, color: Colors.red, size: 58),
            const SizedBox(height: 12),
            const Text(
              'Akses ditolak',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: repo.signOut, child: const Text('Kembali')),
          ],
        ),
      ),
    ),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.repo});
  final AppRepository repo;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), pass = TextEditingController();
  bool busy = false, first = false, checked = false;
  @override
  void initState() {
    super.initState();
    widget.repo
        .hasAdmin()
        .then((v) {
          if (mounted)
            setState(() {
              first = !v;
              checked = true;
            });
        })
        .catchError((_) {
          if (mounted) setState(() => checked = true);
        });
  }

  Future<void> go() async {
    if (email.text.trim().isEmpty || pass.text.length < 8) {
      snack(context, 'Email valid dan password minimal 8 karakter', bad: true);
      return;
    }
    setState(() => busy = true);
    try {
      if (first) {
        await widget.repo.createFirstAdmin(email.text.trim(), pass.text);
      } else {
        await widget.repo.signIn(email.text.trim(), pass.text);
      }
    } catch (e) {
      if (mounted) snack(context, err(e), bad: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: forest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.groups_2,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'MyMember',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                  Text(
                    !checked
                        ? 'Memeriksa sistem…'
                        : first
                        ? 'Buat admin pertama'
                        : 'Masuk sebagai admin',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    obscureText: true,
                    onSubmitted: (_) => go(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy || !checked ? null : go,
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(first ? 'Buat admin' : 'Masuk'),
                      ),
                    ),
                  ),
                  if (first)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Hanya akun pertama yang otomatis menjadi admin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.repo});
  final AppRepository repo;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0, refresh = 0;
  void reload() => setState(() => refresh++);

  Future<void> scanMember() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (code == null || !mounted) return;
    try {
      final member = await widget.repo.memberByBarcode(code);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MemberDetail(repo: widget.repo, id: member.id),
        ),
      );
      reload();
    } catch (e) {
      if (mounted) snack(context, err(e), bad: true);
    }
  }

  @override
  Widget build(BuildContext c) {
    final pages = <Widget>[
      Dashboard(
        repo: widget.repo,
        key: ValueKey('d$refresh'),
        nav: (i) => setState(() => tab = i),
      ),
      MembersPage(repo: widget.repo, key: ValueKey('m$refresh')),
      EventsPage(repo: widget.repo, key: ValueKey('e$refresh')),
      SettingsPage(repo: widget.repo, key: ValueKey('s$refresh')),
    ];
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.groups_2, color: forest),
            SizedBox(width: 9),
            Text('MyMember', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(bottom: false, child: pages[tab]),
      bottomNavigationBar: MyMemberBottomNav(
        selectedIndex: tab,
        onSelected: (v) => setState(() => tab = v),
        onScan: scanMember,
      ),
    );
  }
}

class MyMemberBottomNav extends StatelessWidget {
  const MyMemberBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onScan,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: line)),
      boxShadow: [
        BoxShadow(
          color: Color(0x160F2F20),
          blurRadius: 24,
          offset: Offset(0, -6),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 78,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Beranda',
                  selected: selectedIndex == 0,
                  onTap: () => onSelected(0),
                ),
                _NavItem(
                  icon: Icons.people_outline_rounded,
                  activeIcon: Icons.people_rounded,
                  label: 'Member',
                  selected: selectedIndex == 1,
                  onTap: () => onSelected(1),
                ),
                const SizedBox(width: 78),
                _NavItem(
                  icon: Icons.calendar_month_outlined,
                  activeIcon: Icons.calendar_month_rounded,
                  label: 'Event',
                  selected: selectedIndex == 2,
                  onTap: () => onSelected(2),
                ),
                _NavItem(
                  icon: Icons.tune_outlined,
                  activeIcon: Icons.tune_rounded,
                  label: 'Lainnya',
                  selected: selectedIndex == 3,
                  onTap: () => onSelected(3),
                ),
              ],
            ),
            Positioned(
              top: -24,
              child: Semantics(
                button: true,
                label: 'Scan barcode member',
                child: InkWell(
                  onTap: onScan,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: forest,
                      shape: BoxShape.circle,
                      border: Border.all(color: cream, width: 5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x3D214E34),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 43,
              child: Text(
                'Scan',
                style: TextStyle(
                  color: forest,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon, activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkResponse(
      onTap: onTap,
      radius: 34,
      child: Padding(
        padding: const EdgeInsets.only(top: 11, bottom: 7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? activeIcon : icon,
              color: selected ? forest : Colors.black45,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? forest : Colors.black54,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.repo, required this.nav});
  final AppRepository repo;
  final ValueChanged<int> nav;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: Future.wait([repo.members(status: 'active'), repo.events()]),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return ErrorView(
          error: snapshot.error!,
          retry: () => (context as Element).markNeedsBuild(),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final members = snapshot.data![0] as List<Member>;
      final events = snapshot.data![1] as List<AppEvent>;
      final now = DateTime.now();
      final ongoing = events.where((e) => e.status == 'ongoing').toList();
      final upcoming =
          events
              .where((e) => e.status == 'ongoing' || e.start.isAfter(now))
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
      final focus = ongoing.firstOrNull ?? upcoming.firstOrNull;

      return RefreshIndicator(
        onRefresh: () async => (context as Element).markNeedsBuild(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          children: [
            Text(
              longDate(now),
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Ringkasan operasional',
              style: TextStyle(
                fontSize: 25,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 17),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  DashboardMetric(
                    value: '${members.length}',
                    label: 'Member aktif',
                  ),
                  const _MetricDivider(),
                  DashboardMetric(
                    value: '${ongoing.length}',
                    label: 'Event berjalan',
                  ),
                  const _MetricDivider(),
                  DashboardMetric(
                    value: focus == null ? '0' : '${focus.present}',
                    label: 'Hadir sekarang',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const SectionTitle(title: 'Fokus hari ini'),
            const SizedBox(height: 10),
            if (focus == null)
              const Empty(text: 'Belum ada event aktif atau mendatang')
            else
              _FocusEventCard(event: focus, onTap: () => nav(2)),
            const SizedBox(height: 22),
            SectionTitle(
              title: 'Agenda berikutnya',
              action: 'Lihat semua',
              onAction: () => nav(2),
            ),
            const SizedBox(height: 2),
            ...upcoming
                .where((e) => e.id != focus?.id)
                .take(2)
                .map((e) => _AgendaRow(event: e)),
          ],
        ),
      );
    },
  );
}

class DashboardMetric extends StatelessWidget {
  const DashboardMetric({super.key, required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: ink,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, fontSize: 11),
        ),
      ],
    ),
  );
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 38, color: line);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
    ],
  );
}

class _FocusEventCard extends StatelessWidget {
  const _FocusEventCard({required this.event, required this.onTap});
  final AppEvent event;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: forest,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _DashboardStatus(status: event.status),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white70,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                event.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${dt(event.start)}  ·  ${event.location ?? 'Lokasi belum diisi'}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: event.eligible == 0
                            ? 0
                            : event.present / event.eligible,
                        minHeight: 7,
                        backgroundColor: Colors.white24,
                        color: const Color(0xFFE2C687),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${event.present}/${event.eligible} hadir',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DashboardStatus extends StatelessWidget {
  const _DashboardStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white12,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.white24),
    ),
    child: Text(
      status == 'ongoing' ? 'SEDANG BERJALAN' : 'EVENT BERIKUTNYA',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: .7,
      ),
    ),
  );
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.event});
  final AppEvent event;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: softGreen,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            event.start.day.toString().padLeft(2, '0'),
            style: const TextStyle(
              color: forest,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                '${dt(event.start)} · ${event.location ?? '-'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
        StatusChip(event.status),
      ],
    ),
  );
}

class LegacyDashboard extends StatelessWidget {
  const LegacyDashboard({super.key, required this.repo, required this.nav});
  final AppRepository repo;
  final ValueChanged<int> nav;
  @override
  Widget build(BuildContext c) => FutureBuilder<List<dynamic>>(
    future: Future.wait([repo.members(status: 'active'), repo.events()]),
    builder: (c, s) {
      if (s.hasError)
        return ErrorView(
          error: s.error!,
          retry: () => (c as Element).markNeedsBuild(),
        );
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final ms = s.data![0] as List<Member>, es = s.data![1] as List<AppEvent>;
      final today = DateTime.now();
      final up = es
          .where((e) => e.start.isAfter(today) || e.status == 'ongoing')
          .toList();
      return RefreshIndicator(
        onRefresh: () async => (c as Element).markNeedsBuild(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Operasional member dalam satu tempat.',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Member aktif',
                    value: '${ms.length}',
                    icon: Icons.people,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    label: 'Event',
                    value: '${es.length}',
                    icon: Icons.event_available,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(18),
                leading: const CircleAvatar(
                  backgroundColor: forest,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.qr_code_scanner),
                ),
                title: const Text(
                  'Absensi cepat',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Pilih event, lalu scan QR member.'),
                trailing: FilledButton(
                  onPressed: () => nav(2),
                  child: const Text('Buka'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Event terdekat',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (up.isEmpty)
              const Empty(text: 'Belum ada event aktif')
            else
              ...up
                  .take(3)
                  .map(
                    (e) => Card(
                      child: ListTile(
                        title: Text(e.name),
                        subtitle: Text('${dt(e.start)} • ${e.location ?? '-'}'),
                        trailing: Text(
                          '${e.present}/${e.eligible}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: leaf,
                          ),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      );
    },
  );
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext c) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: leaf),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          Text(label),
        ],
      ),
    ),
  );
}

class MembersPage extends StatefulWidget {
  const MembersPage({super.key, required this.repo});
  final AppRepository repo;
  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  final search = TextEditingController();
  String? status = 'active';
  String? role;
  int? typeId;
  int tick = 0;
  Future<void> chooseFilters() async {
    final types = await widget.repo.memberTypes();
    if (!mounted) return;
    var nextStatus = status;
    var nextRole = role;
    var nextType = typeId;
    final apply = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Filter member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: nextStatus,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Semua')),
                  ...[
                    'active',
                    'pending',
                    'inactive',
                    'expired',
                    'deleted',
                  ].map((x) => DropdownMenuItem(value: x, child: Text(x))),
                ],
                onChanged: (v) => set(() => nextStatus = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: nextRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Semua')),
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => set(() => nextRole = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: nextType,
                decoration: const InputDecoration(labelText: 'Tipe'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Semua')),
                  ...types.map(
                    (x) => DropdownMenuItem(value: x.id, child: Text(x.name)),
                  ),
                ],
                onChanged: (v) => set(() => nextType = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    );
    if (apply == true)
      setState(() {
        status = nextStatus;
        role = nextRole;
        typeId = nextType;
        tick++;
      });
  }

  @override
  Widget build(BuildContext c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Nama, User ID, NIK, no. HP',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Filter status, role, dan tipe',
              onPressed: chooseFilters,
              icon: Badge(
                isLabelVisible:
                    role != null || typeId != null || status != 'active',
                child: const Icon(Icons.filter_alt_outlined),
              ),
            ),
            IconButton(
              onPressed: () => MemberForm.open(c, widget.repo).then((v) {
                if (v == true) setState(() => tick++);
              }),
              icon: const Icon(Icons.person_add_alt_1, color: forest),
            ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Member>>(
          future: widget.repo.members(
            search: search.text,
            status: status,
            role: role,
            typeId: typeId,
          ),
          key: ValueKey('$tick-${search.text}-$status-$role-$typeId'),
          builder: (c, s) {
            if (s.hasError)
              return ErrorView(
                error: s.error!,
                retry: () => setState(() => tick++),
              );
            if (!s.hasData)
              return const Center(child: CircularProgressIndicator());
            final data = s.data!;
            if (data.isEmpty)
              return const Empty(text: 'Member tidak ditemukan');
            return RefreshIndicator(
              onRefresh: () async => setState(() => tick++),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                itemCount: data.length,
                itemBuilder: (_, i) {
                  final m = data[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 9),
                    child: ListTile(
                      onTap: () => Navigator.push(
                        c,
                        MaterialPageRoute(
                          builder: (_) =>
                              MemberDetail(repo: widget.repo, id: m.id),
                        ),
                      ).then((_) => setState(() => tick++)),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFDDECDD),
                        child: Text(m.name[0].toUpperCase()),
                      ),
                      title: Text(
                        m.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${m.userId} • ${m.typeName}'),
                      trailing: StatusChip(m.status),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ],
  );
}

class MemberForm extends StatefulWidget {
  const MemberForm({super.key, required this.repo, this.member});
  final AppRepository repo;
  final Member? member;
  static Future<bool?> open(BuildContext c, AppRepository r, [Member? m]) =>
      Navigator.push<bool>(
        c,
        MaterialPageRoute(
          builder: (_) => MemberForm(repo: r, member: m),
        ),
      );
  @override
  State<MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends State<MemberForm> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.member?.name),
      nik = TextEditingController(text: widget.member?.nik),
      email = TextEditingController(text: widget.member?.email),
      phone = TextEditingController(text: widget.member?.phone);
  int? typeId;
  String role = 'member', status = 'active';
  Uint8List? photo;
  String ext = 'jpg';
  bool busy = false;
  Map<int, TextEditingController> customs = {};
  @override
  void initState() {
    super.initState();
    typeId = widget.member?.typeId;
    role = widget.member?.role ?? 'member';
    status = widget.member?.status ?? 'active';
  }

  Future<void> pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Ambil dari kamera'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final x = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (x != null) {
      photo = await x.readAsBytes();
      ext = x.name.split('.').last.toLowerCase();
      setState(() {});
    }
  }

  Future<void> save(List<CustomField> fields) async {
    if (!(form.currentState?.validate() ?? false) || typeId == null) return;
    setState(() => busy = true);
    try {
      String? path = widget.member?.photoPath;
      if (photo != null)
        path = await widget.repo.uploadPhoto(widget.member?.id, photo!, ext);
      final data = {
        'member_type_id': typeId,
        'name': name.text.trim(),
        'nik': nik.text.trim(),
        'email': email.text.trim(),
        'phone': phone.text.trim(),
        'role': role,
        'status': status,
        'photo_path': path,
      };
      final cv = {for (final f in fields) f.id: customs[f.id]!.text.trim()};
      if (widget.member == null)
        await widget.repo.createMember(data, cv);
      else
        await widget.repo.updateMember(widget.member!.id, data, cv);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) snack(context, err(e), bad: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.member == null ? 'Tambah member' : 'Edit member'),
    ),
    body: FutureBuilder<List<dynamic>>(
      future: Future.wait([
        widget.repo.memberTypes(),
        widget.repo.customFields(),
      ]),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final types = s.data![0] as List<MemberType>,
            fields = s.data![1] as List<CustomField>;
        if (typeId == null && types.isNotEmpty) typeId = types.first.id;
        for (final f in fields) {
          customs.putIfAbsent(
            f.id,
            () =>
                TextEditingController(text: widget.member?.customValues[f.id]),
          );
        }
        return Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Center(
                child: InkWell(
                  onTap: pick,
                  borderRadius: BorderRadius.circular(60),
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFFDDECDD),
                    backgroundImage: photo == null ? null : MemoryImage(photo!),
                    child: photo == null
                        ? const Icon(Icons.add_a_photo, size: 30, color: forest)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Field(
                controller: name,
                label: 'Nama *',
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final typeField = DropdownButtonFormField<int>(
                    initialValue: typeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipe member'),
                    items: types
                        .map(
                          (x) => DropdownMenuItem(
                            value: x.id,
                            child: Text(
                              x.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => typeId = v),
                  );
                  final roleField = DropdownButtonFormField<String>(
                    initialValue: role,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: ['member', 'admin']
                        .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                        .toList(),
                    onChanged: (v) => role = v!,
                  );
                  if (constraints.maxWidth < 390) {
                    return Column(
                      children: [
                        typeField,
                        const SizedBox(height: 12),
                        roleField,
                        const SizedBox(height: 10),
                      ],
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(child: typeField),
                        const SizedBox(width: 10),
                        Expanded(child: roleField),
                      ],
                    ),
                  );
                },
              ),
              Field(
                controller: nik,
                label: 'NIK',
                keyboard: TextInputType.number,
              ),
              Field(
                controller: email,
                label: 'Email',
                keyboard: TextInputType.emailAddress,
              ),
              Field(
                controller: phone,
                label: 'No. HP',
                keyboard: TextInputType.phone,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<String>(
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: ['active', 'pending', 'inactive', 'expired', 'deleted']
                      .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                      .toList(),
                  onChanged: (v) => status = v!,
                ),
              ),
              if (fields.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Field tambahan',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ...fields.map(
                (f) => Field(
                  controller: customs[f.id]!,
                  label: '${f.label}${f.required ? ' *' : ''}',
                  keyboard: f.type == 'number'
                      ? TextInputType.number
                      : f.type == 'date'
                      ? TextInputType.datetime
                      : null,
                  validator: f.required
                      ? (v) =>
                            v == null || v.trim().isEmpty ? 'Wajib diisi' : null
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: busy ? null : () => save(fields),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: busy
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Simpan'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class MemberDetail extends StatefulWidget {
  const MemberDetail({super.key, required this.repo, required this.id});
  final AppRepository repo;
  final int id;
  @override
  State<MemberDetail> createState() => _MemberDetailState();
}

class _MemberDetailState extends State<MemberDetail> {
  int tick = 0;
  Future<void> printCard(Member m) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (_) => pw.Center(
          child: pw.Container(
            width: 260,
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(border: pw.Border.all()),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  'MyMember',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: m.barcode,
                  width: 150,
                  height: 150,
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  m.name,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(m.userId),
                pw.Text(m.typeName),
              ],
            ),
          ),
        ),
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: 'MyMember-${m.userId}',
    );
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<List<dynamic>>(
    future: Future.wait([
      widget.repo.member(widget.id),
      widget.repo.customFields(),
    ]),
    key: ValueKey(tick),
    builder: (c, s) {
      if (s.hasError)
        return Scaffold(
          body: ErrorView(error: s.error!, retry: () => setState(() => tick++)),
        );
      if (!s.hasData)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final m = s.data![0] as Member, fields = s.data![1] as List<CustomField>;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Detail member'),
          actions: [
            IconButton(
              onPressed: () => MemberForm.open(c, widget.repo, m).then((v) {
                if (v == true) setState(() => tick++);
              }),
              icon: const Icon(Icons.edit),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    MemberPhoto(repo: widget.repo, member: m),
                    const SizedBox(height: 12),
                    QrImageView(data: m.barcode, size: 190),
                    Text(
                      m.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      m.userId,
                      style: const TextStyle(letterSpacing: 2, color: leaf),
                    ),
                    const SizedBox(height: 8),
                    StatusChip(m.status),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => printCard(m),
                      icon: const Icon(Icons.print),
                      label: const Text('Cetak QR card'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Info('Tipe', m.typeName),
                    Info('Role', m.role),
                    Info('NIK', m.nik ?? '-', masked: true),
                    Info('Email', m.email ?? '-'),
                    Info('No. HP', m.phone ?? '-'),
                    ...fields
                        .where((f) => m.customValues.containsKey(f.id))
                        .map((f) => Info(f.label, m.customValues[f.id]!)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class EventsPage extends StatefulWidget {
  const EventsPage({super.key, required this.repo});
  final AppRepository repo;
  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  int tick = 0;
  @override
  Widget build(BuildContext c) => FutureBuilder(
    future: widget.repo.events(),
    key: ValueKey(tick),
    builder: (c, s) {
      if (s.hasError)
        return ErrorView(error: s.error!, retry: () => setState(() => tick++));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: forest,
          foregroundColor: Colors.white,
          onPressed: () => EventForm.open(c, widget.repo).then((v) {
            if (v == true) setState(() => tick++);
          }),
          icon: const Icon(Icons.add),
          label: const Text('Event'),
        ),
        body: Column(
          children: [
            // EventsPage is hosted inside Home's Scaffold, so its FAB can be
            // covered by the parent bottom navigation. Keep the create action
            // visible at the top as well.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => EventForm.open(c, widget.repo).then((v) {
                    if (v == true) setState(() => tick++);
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah event'),
                ),
              ),
            ),
            Expanded(
              child: s.data!.isEmpty
                  ? const Empty(text: 'Belum ada event')
                  : RefreshIndicator(
                      onRefresh: () async => setState(() => tick++),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
                        itemCount: s.data!.length,
                        itemBuilder: (_, i) {
                          final e = s.data![i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => Navigator.push(
                                c,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EventDetail(repo: widget.repo, event: e),
                                ),
                              ).then((_) => setState(() => tick++)),
                              title: Text(
                                e.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${dt(e.start)}\n${e.location ?? '-'}',
                              ),
                              isThreeLine: true,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  StatusChip(e.status),
                                  Text('${e.present}/${e.eligible}'),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class EventForm extends StatefulWidget {
  const EventForm({super.key, required this.repo, this.event});
  final AppRepository repo;
  final AppEvent? event;
  static Future<bool?> open(BuildContext c, AppRepository r, [AppEvent? e]) =>
      Navigator.push<bool>(
        c,
        MaterialPageRoute(
          builder: (_) => EventForm(repo: r, event: e),
        ),
      );
  @override
  State<EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<EventForm> {
  late final name = TextEditingController(text: widget.event?.name),
      desc = TextEditingController(text: widget.event?.description),
      location = TextEditingController(text: widget.event?.location);
  late DateTime start =
      widget.event?.start ?? DateTime.now().add(const Duration(hours: 1));
  late DateTime end = widget.event?.end ?? start.add(const Duration(hours: 2));
  late String status = widget.event?.status ?? 'upcoming';
  late Set<int> selected = {...?widget.event?.typeIds};
  bool busy = false;
  Future<DateTime?> pickDt(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (d == null) return null;
    if (!mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    return DateTime(
      d.year,
      d.month,
      d.day,
      t?.hour ?? initial.hour,
      t?.minute ?? initial.minute,
    );
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || selected.isEmpty) {
      snack(
        context,
        'Nama dan minimal satu tipe member wajib dipilih',
        bad: true,
      );
      return;
    }
    if (end.isBefore(start)) {
      snack(context, 'Waktu selesai harus setelah mulai', bad: true);
      return;
    }
    setState(() => busy = true);
    try {
      await widget.repo.saveEvent(
        id: widget.event?.id,
        data: {
          'name': name.text.trim(),
          'description': desc.text.trim(),
          'location': location.text.trim(),
          'start_at': start.toUtc().toIso8601String(),
          'end_at': end.toUtc().toIso8601String(),
          'status': status,
        },
        typeIds: selected.toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) snack(context, err(e), bad: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.event == null ? 'Tambah event' : 'Edit event'),
    ),
    body: FutureBuilder<List<MemberType>>(
      future: widget.repo.memberTypes(),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Field(controller: name, label: 'Nama event *'),
            Field(controller: desc, label: 'Deskripsi', lines: 3),
            Field(controller: location, label: 'Lokasi'),
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Text('Mulai'),
              subtitle: Text(dt(start)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final v = await pickDt(start);
                if (v != null) setState(() => start = v);
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Text('Selesai'),
              subtitle: Text(dt(end)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final v = await pickDt(end);
                if (v != null) setState(() => end = v);
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                'draft',
                'upcoming',
                'ongoing',
                'completed',
                'cancelled',
              ].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
              onChanged: (v) => status = v!,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 18, bottom: 8),
              child: Text(
                'Tipe member yang boleh ikut *',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...s.data!.map(
              (t) => CheckboxListTile(
                value: selected.contains(t.id),
                title: Text(t.name),
                activeColor: forest,
                onChanged: (v) => setState(
                  () => v! ? selected.add(t.id) : selected.remove(t.id),
                ),
              ),
            ),
            FilledButton(
              onPressed: busy ? null : save,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: busy
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Simpan & buat snapshot peserta'),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class EventDetail extends StatefulWidget {
  const EventDetail({super.key, required this.repo, required this.event});
  final AppRepository repo;
  final AppEvent event;
  @override
  State<EventDetail> createState() => _EventDetailState();
}

class _EventDetailState extends State<EventDetail> {
  int tick = 0;
  String filter = 'all', search = '';
  late String eventStatus;

  @override
  void initState() {
    super.initState();
    eventStatus = widget.event.status;
  }

  Future<void> changeEventStatus(String next) async {
    try {
      await widget.repo.setEventStatus(widget.event.id, next);
      if (!mounted) return;
      setState(() {
        eventStatus = next;
        tick++;
      });
      snack(
        context,
        next == 'ongoing' ? 'Event mulai berjalan' : 'Event sudah selesai',
      );
    } catch (e) {
      if (mounted) snack(context, err(e), bad: true);
    }
  }

  Future<void> scan() async {
    if (eventStatus != 'ongoing') {
      snack(context, 'Mulai event dulu sebelum scan presensi', bad: true);
      return;
    }
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (code == null) return;
    try {
      final r = await widget.repo.checkIn(widget.event.id, code);
      if (mounted) {
        snack(context, '${r['name']} berhasil hadir');
        setState(() => tick++);
      }
    } catch (e) {
      if (mounted) snack(context, err(e), bad: true);
    }
  }

  Future<void> export(List<Participant> p) async {
    final b = StringBuffer('user_id,nama,tipe,status,waktu_checkin\r\n');
    for (final x in p) {
      String q(String v) => '"${v.replaceAll('"', '""')}"';
      b.writeln(
        '${x.userId},${q(x.name)},${q(x.typeName)},${x.present ? 'hadir' : 'belum'},${x.checkedInAt == null ? '' : dt(x.checkedInAt!)}',
      );
    }
    await FilePicker.saveFile(
      dialogTitle: 'Simpan presensi',
      fileName: 'presensi_${widget.event.id}.csv',
      bytes: Uint8List.fromList(utf8.encode(b.toString())),
    );
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<List<Participant>>(
    future: widget.repo.participants(widget.event.id),
    key: ValueKey(tick),
    builder: (c, s) {
      if (!s.hasData)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final all = s.data!;
      final data = all
          .where(
            (x) =>
                (filter == 'all' || (filter == 'present') == x.present) &&
                (search.isEmpty ||
                    x.name.toLowerCase().contains(search.toLowerCase()) ||
                    x.userId.contains(search)),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.event.name),
          actions: [
            IconButton(
              onPressed: () => export(all),
              icon: const Icon(Icons.download),
            ),
            IconButton(
              onPressed: () =>
                  EventForm.open(
                    c,
                    widget.repo,
                    widget.event.copyWith(status: eventStatus),
                  ).then((v) {
                    if (v == true && c.mounted) Navigator.pop(c);
                  }),
              icon: const Icon(Icons.edit),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: eventStatus == 'ongoing' ? forest : Colors.grey,
          foregroundColor: Colors.white,
          onPressed: eventStatus == 'ongoing' ? scan : null,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(
            eventStatus == 'ongoing' ? 'Scan hadir' : 'Event belum berjalan',
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          children: [
            EventLifecyclePanel(
              status: eventStatus,
              onStart: () => changeEventStatus('ongoing'),
              onFinish: () => changeEventStatus('completed'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Eligible',
                    value: '${all.length}',
                    icon: Icons.groups,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCard(
                    label: 'Hadir',
                    value: '${all.where((x) => x.present).length}',
                    icon: Icons.how_to_reg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => search = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari peserta',
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Semua')),
                ButtonSegment(value: 'present', label: Text('Hadir')),
                ButtonSegment(value: 'absent', label: Text('Belum')),
              ],
              selected: {filter},
              onSelectionChanged: (v) => setState(() => filter = v.first),
            ),
            const SizedBox(height: 10),
            if (data.isEmpty)
              const Empty(text: 'Tidak ada peserta')
            else
              ...data.map(
                (p) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.userId} • ${p.typeName}${p.checkedInAt == null ? '' : '\n${dt(p.checkedInAt!)}'}',
                    ),
                    isThreeLine: p.checkedInAt != null,
                    trailing: Tooltip(
                      message: p.present
                          ? 'Sudah hadir melalui scan'
                          : 'Belum hadir — wajib scan QR',
                      child: Icon(
                        p.present
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: p.present ? Colors.green : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class EventLifecyclePanel extends StatelessWidget {
  const EventLifecyclePanel({
    super.key,
    required this.status,
    required this.onStart,
    required this.onFinish,
  });
  final String status;
  final VoidCallback onStart, onFinish;

  @override
  Widget build(BuildContext context) {
    final ongoing = status == 'ongoing';
    final completed = status == 'completed';
    final cancelled = status == 'cancelled';
    final title = ongoing
        ? 'Event sedang berjalan'
        : completed
        ? 'Event sudah selesai'
        : cancelled
        ? 'Event dibatalkan'
        : 'Event belum dimulai';
    final description = ongoing
        ? 'Scanner presensi aktif. Semua kehadiran wajib melalui scan QR.'
        : completed
        ? 'Presensi ditutup. Data event tetap bisa diedit.'
        : cancelled
        ? 'Event ini tidak menerima presensi.'
        : 'Tekan Mulai event untuk membuka scanner presensi.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ongoing ? softGreen : Colors.white,
        border: Border.all(color: ongoing ? leaf : line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ongoing ? forest : cream,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              ongoing
                  ? Icons.play_arrow_rounded
                  : completed
                  ? Icons.done_all_rounded
                  : Icons.schedule_rounded,
              color: ongoing ? Colors.white : forest,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!completed && !cancelled)
            FilledButton.tonal(
              onPressed: ongoing ? onFinish : onStart,
              child: Text(ongoing ? 'Selesaikan' : 'Mulai'),
            ),
        ],
      ),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool done = false;
  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Scan QR member'),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null &&
                  v.startsWith('MYMEMBER:MEMBER:') &&
                  v.endsWith(':v1')) {
                done = true;
                Navigator.pop(c, v);
                return;
              }
            }
            snack(c, 'QR bukan milik MyMember', bad: true);
          },
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: gold, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        const Positioned(
          left: 20,
          right: 20,
          bottom: 40,
          child: Text(
            'Arahkan kamera ke QR card member',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    ),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.repo});
  final AppRepository repo;
  @override
  Widget build(BuildContext c) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Konfigurasi',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 10),
      SettingTile(
        icon: Icons.category_outlined,
        title: 'Tipe member',
        sub: 'Kode User ID dan status tipe',
        onTap: () => Navigator.push(
          c,
          MaterialPageRoute(builder: (_) => MemberTypesPage(repo: repo)),
        ),
      ),
      SettingTile(
        icon: Icons.view_list_outlined,
        title: 'Custom fields',
        sub: 'Tambah kolom member saat aplikasi berjalan',
        onTap: () => Navigator.push(
          c,
          MaterialPageRoute(builder: (_) => CustomFieldsPage(repo: repo)),
        ),
      ),
      SettingTile(
        icon: Icons.upload_file,
        title: 'Import member CSV',
        sub: 'Masukkan data member massal',
        onTap: () => importMembers(c, repo),
      ),
      SettingTile(
        icon: Icons.download,
        title: 'Export member CSV',
        sub: 'Backup daftar member',
        onTap: () => exportMembers(c, repo),
      ),
      SettingTile(
        icon: Icons.history,
        title: 'Audit log',
        sub: 'Riwayat perubahan data',
        onTap: () => Navigator.push(
          c,
          MaterialPageRoute(builder: (_) => AuditPage(repo: repo)),
        ),
      ),
      SettingTile(
        icon: Icons.logout,
        title: 'Keluar',
        sub: 'Akhiri sesi admin',
        onTap: repo.signOut,
      ),
    ],
  );
}

class MemberTypesPage extends StatefulWidget {
  const MemberTypesPage({super.key, required this.repo});
  final AppRepository repo;
  @override
  State<MemberTypesPage> createState() => _MemberTypesPageState();
}

class _MemberTypesPageState extends State<MemberTypesPage> {
  int tick = 0;
  Future<void> edit([MemberType? x]) async {
    final n = TextEditingController(text: x?.name),
        code = TextEditingController(text: x?.code ?? '1');
    bool active = x?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(x == null ? 'Tambah tipe' : 'Edit tipe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Field(controller: n, label: 'Nama'),
              Field(
                controller: code,
                label: 'Kode 1 digit',
                keyboard: TextInputType.number,
              ),
              SwitchListTile(
                value: active,
                onChanged: (v) => set(() => active = v),
                title: const Text('Aktif'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        if (code.text.length != 1 || !RegExp(r'^\d$').hasMatch(code.text))
          throw Exception('Kode wajib satu digit');
        await widget.repo.saveMemberType(
          id: x?.id,
          name: n.text,
          code: code.text,
          active: active,
        );
        setState(() => tick++);
      } catch (e) {
        if (mounted) snack(context, err(e), bad: true);
      }
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Tipe member')),
    floatingActionButton: FloatingActionButton(
      onPressed: edit,
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<List<MemberType>>(
      future: widget.repo.memberTypes(includeInactive: true),
      key: ValueKey(tick),
      builder: (c, s) => !s.hasData
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: s.data!
                  .map(
                    (x) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => edit(x),
                        title: Text(x.name),
                        subtitle: Text('Kode ${x.code}'),
                        trailing: StatusChip(x.active ? 'active' : 'inactive'),
                      ),
                    ),
                  )
                  .toList(),
            ),
    ),
  );
}

class CustomFieldsPage extends StatefulWidget {
  const CustomFieldsPage({super.key, required this.repo});
  final AppRepository repo;
  @override
  State<CustomFieldsPage> createState() => _CustomFieldsPageState();
}

class _CustomFieldsPageState extends State<CustomFieldsPage> {
  int tick = 0;
  Future<void> edit([CustomField? x]) async {
    final key = TextEditingController(text: x?.key),
        label = TextEditingController(text: x?.label);
    String type = x?.type ?? 'text';
    bool req = x?.required ?? false, active = x?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(x == null ? 'Tambah field' : 'Edit field'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Field(controller: label, label: 'Label'),
              Field(controller: key, label: 'Key unik'),
              DropdownButtonFormField(
                initialValue: type,
                items: ['text', 'number', 'date', 'boolean']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => set(() => type = v!),
              ),
              SwitchListTile(
                value: req,
                onChanged: (v) => set(() => req = v),
                title: const Text('Wajib'),
              ),
              SwitchListTile(
                value: active,
                onChanged: (v) => set(() => active = v),
                title: const Text('Aktif'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await widget.repo.saveCustomField(
          id: x?.id,
          key: key.text,
          label: label.text,
          type: type,
          required: req,
          active: active,
          order: x?.order ?? DateTime.now().millisecondsSinceEpoch % 100000,
        );
        setState(() => tick++);
      } catch (e) {
        if (mounted) snack(context, err(e), bad: true);
      }
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Custom fields')),
    floatingActionButton: FloatingActionButton(
      onPressed: edit,
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<List<CustomField>>(
      future: widget.repo.customFields(includeInactive: true),
      key: ValueKey(tick),
      builder: (c, s) => !s.hasData
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: s.data!
                  .map(
                    (x) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => edit(x),
                        title: Text(x.label),
                        subtitle: Text(
                          '${x.key} • ${x.type}${x.required ? ' • wajib' : ''}',
                        ),
                        trailing: StatusChip(x.active ? 'active' : 'inactive'),
                      ),
                    ),
                  )
                  .toList(),
            ),
    ),
  );
}

class AuditPage extends StatelessWidget {
  const AuditPage({super.key, required this.repo});
  final AppRepository repo;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Audit log')),
    body: FutureBuilder(
      future: repo.auditLogs(),
      builder: (c, s) => !s.hasData
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: s.data!.length,
              itemBuilder: (_, i) {
                final x = s.data![i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.history, color: leaf),
                    title: Text('${x['action']} • ${x['table_name']}'),
                    subtitle: Text(
                      'Record ${x['record_id']}\n${dt(DateTime.parse(x['changed_at']).toLocal())}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    ),
  );
}

Future<void> exportMembers(BuildContext c, AppRepository r) async {
  try {
    final list = await r.members();
    final b = StringBuffer('nama,nik,email,nohp,tipe,status,user_id\r\n');
    String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    for (final m in list) {
      b.writeln(
        '${q(m.name)},${q(m.nik)},${q(m.email)},${q(m.phone)},${q(m.typeName)},${m.status},${m.userId}',
      );
    }
    final bytes = Uint8List.fromList(utf8.encode(b.toString()));
    await FilePicker.saveFile(
      dialogTitle: 'Export member',
      fileName: 'mymember_members.csv',
      bytes: bytes,
    );
    if (c.mounted) snack(c, 'Export selesai');
  } catch (e) {
    if (c.mounted) snack(c, err(e), bad: true);
  }
}

List<List<String>> parseCsv(String input) {
  final rows = <List<String>>[], row = <String>[];
  var cell = StringBuffer(), quoted = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '"') {
      if (quoted && i + 1 < input.length && input[i + 1] == '"') {
        cell.write('"');
        i++;
      } else
        quoted = !quoted;
    } else if (ch == ',' && !quoted) {
      row.add(cell.toString());
      cell = StringBuffer();
    } else if ((ch == '\n' || ch == '\r') && !quoted) {
      if (ch == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell = StringBuffer();
      if (row.any((x) => x.isNotEmpty)) rows.add(List.of(row));
      row.clear();
    } else
      cell.write(ch);
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

Future<void> importMembers(BuildContext c, AppRepository r) async {
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (picked == null) return;
    final bytes =
        picked.files.single.bytes ??
        await File(picked.files.single.path!).readAsBytes();
    final rows = parseCsv(utf8.decode(bytes));
    if (rows.length < 2)
      throw Exception('CSV kosong. Header: nama,nik,email,nohp,tipe,status');
    final h = rows.first.map((x) => x.trim().toLowerCase()).toList(),
        types = await r.memberTypes();
    int done = 0;
    for (final row in rows.skip(1)) {
      String get(String k) {
        final i = h.indexOf(k);
        return i >= 0 && i < row.length ? row[i].trim() : '';
      }

      final type = types
          .where((x) => x.name.toLowerCase() == get('tipe').toLowerCase())
          .firstOrNull;
      if (type == null || get('nama').isEmpty) continue;
      await r.createMember({
        'member_type_id': type.id,
        'name': get('nama'),
        'nik': get('nik'),
        'email': get('email'),
        'phone': get('nohp'),
        'role': 'member',
        'status': get('status').isEmpty ? 'active' : get('status'),
        'photo_path': null,
      }, {});
      done++;
    }
    if (c.mounted) snack(c, '$done member berhasil diimport');
  } catch (e) {
    if (c.mounted) snack(c, err(e), bad: true);
  }
}

class MemberPhoto extends StatelessWidget {
  const MemberPhoto({super.key, required this.repo, required this.member});
  final AppRepository repo;
  final Member member;
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: repo.signedPhotoUrl(member.photoPath),
    builder: (context, snap) => CircleAvatar(
      radius: 46,
      backgroundColor: const Color(0xFFDDECDD),
      backgroundImage: snap.data == null ? null : NetworkImage(snap.data!),
      child: snap.data == null
          ? Text(
              member.name[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: forest,
              ),
            )
          : null,
    ),
  );
}

class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.keyboard,
    this.lines = 1,
  });
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboard;
  final int lines;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboard,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

class Info extends StatelessWidget {
  const Info(this.label, this.value, {this.masked = false, super.key});
  final String label, value;
  final bool masked;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            masked && value.length > 6
                ? '${value.substring(0, 4)}••••${value.substring(value.length - 2)}'
                : value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext c) {
    final good = ['active', 'ongoing', 'present', 'completed'].contains(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: good ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: good ? Colors.green.shade800 : Colors.orange.shade900,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class Empty extends StatelessWidget {
  const Empty({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 55, color: Colors.black38),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: Colors.red, size: 48),
          const SizedBox(height: 8),
          Text(err(error), textAlign: TextAlign.center),
          TextButton(onPressed: retry, child: const Text('Coba lagi')),
        ],
      ),
    ),
  );
}

class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFDDECDD),
        foregroundColor: forest,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(sub),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}
