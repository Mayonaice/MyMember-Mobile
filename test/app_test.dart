import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymember/main.dart';
import 'package:mymember/models.dart';
import 'package:mymember/repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FormTestRepository extends AppRepository {
  _FormTestRepository()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  Future<List<MemberType>> memberTypes({bool includeInactive = false}) async =>
      const [MemberType(id: 1, name: 'Regular', code: '1', active: true)];

  @override
  Future<List<CustomField>> customFields({
    bool includeInactive = false,
  }) async => const [];
}

void main() {
  test('CSV parser supports quoted comma and escaped quote', () {
    final rows = parseCsv('nama,tipe\r\n"Doe, John","VIP ""Gold"""\r\n');
    expect(rows, [
      ['nama', 'tipe'],
      ['Doe, John', 'VIP "Gold"'],
    ]);
  });

  test('CSV parser supports multiline values', () {
    final rows = parseCsv('nama,catatan\nBudi,"baris 1\nbaris 2"');
    expect(rows[1][1], 'baris 1\nbaris 2');
  });

  test('date formatter uses Indonesian operational format', () {
    expect(dt(DateTime(2026, 2, 17, 9, 5)), '17/02/2026 09:05');
  });

  test('long date uses Indonesian month name', () {
    expect(longDate(DateTime(2026, 7, 16)), '16 Juli 2026');
  });

  testWidgets('bottom navigation exposes elevated scan as fifth action', (
    tester,
  ) async {
    var scanned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MyMemberBottomNav(
            selectedIndex: 0,
            onSelected: (_) {},
            onScan: () => scanned = true,
          ),
        ),
      ),
    );

    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Event'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    expect(scanned, isTrue);
  });

  testWidgets('event lifecycle exposes start and finish actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventLifecyclePanel(
            status: 'ongoing',
            onStart: () {},
            onFinish: () {},
          ),
        ),
      ),
    );
    expect(find.text('Event sedang berjalan'), findsOneWidget);
    expect(find.text('Selesaikan'), findsOneWidget);
  });

  testWidgets('member form does not overflow on a narrow Android screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: MemberForm(repo: _FormTestRepository())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tipe member'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
