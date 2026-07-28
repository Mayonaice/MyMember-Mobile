import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

class AppRepository {
  AppRepository(this.db);
  final SupabaseClient db;

  Future<bool> hasAdmin() async => (await db.rpc('has_admin')) as bool;
  Future<void> signIn(String email, String password) async =>
      db.auth.signInWithPassword(email: email, password: password);
  Future<void> createFirstAdmin(String email, String password) async {
    if (await hasAdmin()) throw Exception('Admin pertama sudah dibuat');
    final res = await db.auth.signUp(email: email, password: password);
    if (res.user == null) throw Exception('Gagal membuat admin');
    if (res.session == null)
      throw Exception('Cek email untuk verifikasi, lalu login');
    await ensureAdmin();
  }

  Future<void> ensureAdmin() async {
    final ok = await db.rpc('is_admin') as bool;
    if (!ok) {
      await db.auth.signOut();
      throw Exception('Akun ini tidak punya akses admin');
    }
  }

  Future<void> signOut() => db.auth.signOut();

  Future<List<MemberType>> memberTypes({bool includeInactive = false}) async {
    var q = db.from('member_types').select();
    final rows = includeInactive
        ? await q.order('name')
        : await q.eq('is_active', true).order('name');
    return (rows as List).map((e) => MemberType.fromJson(e)).toList();
  }

  Future<void> saveMemberType({
    int? id,
    required String name,
    required String code,
    required bool active,
  }) async {
    final data = {'name': name.trim(), 'type_code': code, 'is_active': active};
    if (id == null) {
      await db.from('member_types').insert(data);
    } else {
      await db.from('member_types').update(data).eq('id', id);
    }
  }

  Future<List<CustomField>> customFields({bool includeInactive = false}) async {
    var q = db.from('member_field_definitions').select();
    final rows = includeInactive
        ? await q.order('sort_order')
        : await q.eq('is_active', true).order('sort_order');
    return (rows as List).map((e) => CustomField.fromJson(e)).toList();
  }

  Future<void> saveCustomField({
    int? id,
    required String key,
    required String label,
    required String type,
    required bool required,
    required bool active,
    required int order,
  }) async {
    final data = {
      'field_key': key.trim().toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9_]+'),
        '_',
      ),
      'label': label.trim(),
      'data_type': type,
      'is_required': required,
      'is_active': active,
      'sort_order': order,
    };
    if (id == null) {
      await db.from('member_field_definitions').insert(data);
    } else {
      await db.from('member_field_definitions').update(data).eq('id', id);
    }
  }

  Future<List<Member>> members({
    String search = '',
    String? status,
    int? typeId,
    String? role,
  }) async {
    var q = db.from('members').select('*,member_types(name)');
    if (status != null) q = q.eq('status', status);
    if (typeId != null) q = q.eq('member_type_id', typeId);
    if (role != null) q = q.eq('role', role);
    if (search.trim().isNotEmpty) {
      final s = search.trim().replaceAll(',', '');
      q = q.or(
        'name.ilike.%$s%,user_id.ilike.%$s%,nik.ilike.%$s%,phone.ilike.%$s%',
      );
    }
    final rows = await q.order('name');
    return (rows as List).map((e) => Member.fromJson(e)).toList();
  }

  Future<Member> member(int id) async {
    final row = await db
        .from('members')
        .select('*,member_types(name)')
        .eq('id', id)
        .single();
    final values = await db
        .from('member_field_values')
        .select()
        .eq('member_id', id);
    final base = Member.fromJson(row);
    return Member(
      id: base.id,
      role: base.role,
      typeId: base.typeId,
      typeName: base.typeName,
      userId: base.userId,
      barcode: base.barcode,
      name: base.name,
      nik: base.nik,
      email: base.email,
      phone: base.phone,
      photoPath: base.photoPath,
      status: base.status,
      createdAt: base.createdAt,
      customValues: {
        for (final v in values)
          v['field_definition_id'] as int: v['value']?.toString() ?? '',
      },
    );
  }

  Future<Member> memberByBarcode(String barcode) async {
    final row = await db
        .from('members')
        .select('id')
        .eq('barcode_value', barcode)
        .maybeSingle();
    if (row == null) throw Exception('Barcode/member tidak ditemukan');
    return member(row['id'] as int);
  }

  Future<Member> createMember(
    Map<String, dynamic> data,
    Map<int, String> custom,
  ) async {
    final row = await db.rpc(
      'create_member',
      params: {
        'p_member_type_id': data['member_type_id'],
        'p_name': data['name'],
        'p_nik': data['nik'],
        'p_email': data['email'],
        'p_phone': data['phone'],
        'p_status': data['status'],
        'p_role': data['role'],
        'p_photo_path': data['photo_path'],
        'p_custom_values': {
          for (final e in custom.entries) '${e.key}': e.value,
        },
      },
    );
    return member((row as Map<String, dynamic>)['id'] as int);
  }

  Future<void> updateMember(
    int id,
    Map<String, dynamic> data,
    Map<int, String> custom,
  ) async {
    await db.rpc(
      'update_member',
      params: {
        'p_id': id,
        'p_data': data,
        'p_custom_values': {
          for (final e in custom.entries) '${e.key}': e.value,
        },
      },
    );
  }

  Future<String> uploadPhoto(
    int? memberId,
    Uint8List bytes,
    String extension,
  ) async {
    final path =
        '${db.auth.currentUser!.id}/${memberId ?? 'new'}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    await db.storage
        .from('member-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  Future<String?> signedPhotoUrl(String? path) async => path == null
      ? null
      : db.storage.from('member-photos').createSignedUrl(path, 3600);

  Future<List<AppEvent>> events() async {
    final rows = await db
        .from('events')
        .select()
        .order('start_at', ascending: false);
    final result = <AppEvent>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final types = await db
          .from('event_member_types')
          .select('member_type_id')
          .eq('event_id', id);
      final participants = await db
          .from('event_participants')
          .select('member_id')
          .eq('event_id', id);
      final attendance = await db
          .from('attendance')
          .select('id')
          .eq('event_id', id)
          .eq('status', 'present');
      final b = AppEvent.fromJson(row);
      result.add(
        AppEvent(
          id: b.id,
          name: b.name,
          description: b.description,
          location: b.location,
          start: b.start,
          end: b.end,
          status: b.status,
          typeIds: [for (final t in types) t['member_type_id'] as int],
          eligible: participants.length,
          present: attendance.length,
        ),
      );
    }
    return result;
  }

  Future<int> saveEvent({
    int? id,
    required Map<String, dynamic> data,
    required List<int> typeIds,
  }) async {
    return await db.rpc(
          'save_event',
          params: {'p_id': id, 'p_data': data, 'p_type_ids': typeIds},
        )
        as int;
  }

  Future<void> softDeleteEvent(int id) =>
      db.from('events').update({'status': 'cancelled'}).eq('id', id);

  Future<void> setEventStatus(int id, String status) =>
      db.from('events').update({'status': status}).eq('id', id);
  Future<List<Participant>> participants(int eventId) async {
    final p = await db
        .from('event_participants')
        .select('member_id,snapshot_name,snapshot_user_id,member_types(name)')
        .eq('event_id', eventId);
    final a = await db
        .from('attendance')
        .select()
        .eq('event_id', eventId)
        .eq('status', 'present');
    final byMember = {for (final x in a) x['member_id'] as int: x};
    return [
      for (final x in p)
        Participant(
          memberId: x['member_id'],
          name: x['snapshot_name'],
          userId: x['snapshot_user_id'],
          typeName: (x['member_types'] as Map?)?['name']?.toString() ?? '-',
          present: byMember.containsKey(x['member_id']),
          checkedInAt: DateTime.tryParse(
            byMember[x['member_id']]?['checked_in_at']?.toString() ?? '',
          ),
        ),
    ];
  }

  Future<Map<String, dynamic>> checkIn(int eventId, String barcode) async =>
      Map<String, dynamic>.from(
        await db.rpc(
          'check_in_member',
          params: {'p_event_id': eventId, 'p_barcode': barcode},
        ),
      );
  Future<List<Map<String, dynamic>>> auditLogs() async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('audit_logs')
            .select()
            .order('changed_at', ascending: false)
            .limit(200),
      );
}
