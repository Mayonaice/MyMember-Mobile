class MemberType {
  const MemberType({
    required this.id,
    required this.name,
    required this.code,
    required this.active,
  });
  final int id;
  final String name;
  final String code;
  final bool active;
  factory MemberType.fromJson(Map<String, dynamic> j) => MemberType(
    id: j['id'] as int,
    name: j['name'] as String,
    code: j['type_code'] as String,
    active: j['is_active'] as bool,
  );
}

class CustomField {
  const CustomField({
    required this.id,
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    required this.active,
    required this.order,
  });
  final int id;
  final String key, label, type;
  final bool required, active;
  final int order;
  factory CustomField.fromJson(Map<String, dynamic> j) => CustomField(
    id: j['id'] as int,
    key: j['field_key'] as String,
    label: j['label'] as String,
    type: j['data_type'] as String,
    required: j['is_required'] as bool,
    active: j['is_active'] as bool,
    order: j['sort_order'] as int,
  );
}

class Member {
  const Member({
    required this.id,
    required this.role,
    required this.typeId,
    required this.typeName,
    required this.userId,
    required this.barcode,
    required this.name,
    required this.status,
    this.nik,
    this.email,
    this.phone,
    this.photoPath,
    this.createdAt,
    this.customValues = const {},
  });
  final int id, typeId;
  final String role, typeName, userId, barcode, name, status;
  final String? nik, email, phone, photoPath;
  final DateTime? createdAt;
  final Map<int, String> customValues;
  factory Member.fromJson(Map<String, dynamic> j) {
    final mt = j['member_types'] as Map<String, dynamic>?;
    return Member(
      id: j['id'] as int,
      role: j['role'] as String,
      typeId: j['member_type_id'] as int,
      typeName: mt?['name'] as String? ?? '-',
      userId: j['user_id'] as String,
      barcode: j['barcode_value'] as String,
      name: j['name'] as String,
      nik: j['nik'] as String?,
      email: j['email'] as String?,
      phone: j['phone'] as String?,
      photoPath: j['photo_path'] as String?,
      status: j['status'] as String,
      createdAt: DateTime.tryParse(j['time_input']?.toString() ?? ''),
    );
  }
}

class AppEvent {
  const AppEvent({
    required this.id,
    required this.name,
    required this.start,
    required this.status,
    this.description,
    this.location,
    this.end,
    this.typeIds = const [],
    this.eligible = 0,
    this.present = 0,
  });
  final int id;
  final String name, status;
  final String? description, location;
  final DateTime start;
  final DateTime? end;
  final List<int> typeIds;
  final int eligible, present;
  AppEvent copyWith({String? status}) => AppEvent(
    id: id,
    name: name,
    description: description,
    location: location,
    start: start,
    end: end,
    status: status ?? this.status,
    typeIds: typeIds,
    eligible: eligible,
    present: present,
  );
  factory AppEvent.fromJson(Map<String, dynamic> j) => AppEvent(
    id: j['id'] as int,
    name: j['name'] as String,
    description: j['description'] as String?,
    location: j['location'] as String?,
    start: DateTime.parse(j['start_at'] as String),
    end: j['end_at'] == null ? null : DateTime.parse(j['end_at'] as String),
    status: j['status'] as String,
  );
}

class Participant {
  const Participant({
    required this.memberId,
    required this.name,
    required this.userId,
    required this.typeName,
    required this.present,
    this.checkedInAt,
  });
  final int memberId;
  final String name, userId, typeName;
  final bool present;
  final DateTime? checkedInAt;
}
