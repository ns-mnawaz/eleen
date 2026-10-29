// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles
    with TableInfo<$ProfilesTable, ProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _allowanceMinutesMeta = const VerificationMeta(
    'allowanceMinutes',
  );
  @override
  late final GeneratedColumn<int> allowanceMinutes = GeneratedColumn<int>(
    'allowance_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isParentMeta = const VerificationMeta(
    'isParent',
  );
  @override
  late final GeneratedColumn<bool> isParent = GeneratedColumn<bool>(
    'is_parent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_parent" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    avatar,
    allowanceMinutes,
    isParent,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    } else if (isInserting) {
      context.missing(_avatarMeta);
    }
    if (data.containsKey('allowance_minutes')) {
      context.handle(
        _allowanceMinutesMeta,
        allowanceMinutes.isAcceptableOrUnknown(
          data['allowance_minutes']!,
          _allowanceMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_allowanceMinutesMeta);
    }
    if (data.containsKey('is_parent')) {
      context.handle(
        _isParentMeta,
        isParent.isAcceptableOrUnknown(data['is_parent']!, _isParentMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      )!,
      allowanceMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}allowance_minutes'],
      )!,
      isParent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_parent'],
      )!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class ProfileRow extends DataClass implements Insertable<ProfileRow> {
  final String id;
  final String name;
  final String avatar;

  /// The [AllowanceMinutes] allowance, serialized as its minutes int.
  /// Ignored for parent profiles (their sessions are never ticked).
  final int allowanceMinutes;

  /// Parent profiles need the parent PIN to select on the TV and never
  /// expire (v3).
  final bool isParent;
  const ProfileRow({
    required this.id,
    required this.name,
    required this.avatar,
    required this.allowanceMinutes,
    required this.isParent,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['avatar'] = Variable<String>(avatar);
    map['allowance_minutes'] = Variable<int>(allowanceMinutes);
    map['is_parent'] = Variable<bool>(isParent);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      name: Value(name),
      avatar: Value(avatar),
      allowanceMinutes: Value(allowanceMinutes),
      isParent: Value(isParent),
    );
  }

  factory ProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      avatar: serializer.fromJson<String>(json['avatar']),
      allowanceMinutes: serializer.fromJson<int>(json['allowanceMinutes']),
      isParent: serializer.fromJson<bool>(json['isParent']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'avatar': serializer.toJson<String>(avatar),
      'allowanceMinutes': serializer.toJson<int>(allowanceMinutes),
      'isParent': serializer.toJson<bool>(isParent),
    };
  }

  ProfileRow copyWith({
    String? id,
    String? name,
    String? avatar,
    int? allowanceMinutes,
    bool? isParent,
  }) => ProfileRow(
    id: id ?? this.id,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    allowanceMinutes: allowanceMinutes ?? this.allowanceMinutes,
    isParent: isParent ?? this.isParent,
  );
  ProfileRow copyWithCompanion(ProfilesCompanion data) {
    return ProfileRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      allowanceMinutes: data.allowanceMinutes.present
          ? data.allowanceMinutes.value
          : this.allowanceMinutes,
      isParent: data.isParent.present ? data.isParent.value : this.isParent,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('allowanceMinutes: $allowanceMinutes, ')
          ..write('isParent: $isParent')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, avatar, allowanceMinutes, isParent);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.avatar == this.avatar &&
          other.allowanceMinutes == this.allowanceMinutes &&
          other.isParent == this.isParent);
}

class ProfilesCompanion extends UpdateCompanion<ProfileRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> avatar;
  final Value<int> allowanceMinutes;
  final Value<bool> isParent;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.avatar = const Value.absent(),
    this.allowanceMinutes = const Value.absent(),
    this.isParent = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String id,
    required String name,
    required String avatar,
    required int allowanceMinutes,
    this.isParent = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       avatar = Value(avatar),
       allowanceMinutes = Value(allowanceMinutes);
  static Insertable<ProfileRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? avatar,
    Expression<int>? allowanceMinutes,
    Expression<bool>? isParent,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (avatar != null) 'avatar': avatar,
      if (allowanceMinutes != null) 'allowance_minutes': allowanceMinutes,
      if (isParent != null) 'is_parent': isParent,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? avatar,
    Value<int>? allowanceMinutes,
    Value<bool>? isParent,
    Value<int>? rowid,
  }) {
    return ProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      allowanceMinutes: allowanceMinutes ?? this.allowanceMinutes,
      isParent: isParent ?? this.isParent,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (allowanceMinutes.present) {
      map['allowance_minutes'] = Variable<int>(allowanceMinutes.value);
    }
    if (isParent.present) {
      map['is_parent'] = Variable<bool>(isParent.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('allowanceMinutes: $allowanceMinutes, ')
          ..write('isParent: $isParent, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateKeyMeta = const VerificationMeta(
    'dateKey',
  );
  @override
  late final GeneratedColumn<int> dateKey = GeneratedColumn<int>(
    'date_key',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remainingSecondsMeta = const VerificationMeta(
    'remainingSeconds',
  );
  @override
  late final GeneratedColumn<int> remainingSeconds = GeneratedColumn<int>(
    'remaining_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    profileId,
    dateKey,
    remainingSeconds,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('date_key')) {
      context.handle(
        _dateKeyMeta,
        dateKey.isAcceptableOrUnknown(data['date_key']!, _dateKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dateKeyMeta);
    }
    if (data.containsKey('remaining_seconds')) {
      context.handle(
        _remainingSecondsMeta,
        remainingSeconds.isAcceptableOrUnknown(
          data['remaining_seconds']!,
          _remainingSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remainingSecondsMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    } else if (isInserting) {
      context.missing(_activeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, dateKey};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      dateKey: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_key'],
      )!,
      remainingSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remaining_seconds'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final String profileId;

  /// Date-only key `yyyymmdd`, derived from the engine's normalized dates.
  final int dateKey;
  final int remainingSeconds;
  final bool active;
  const Session({
    required this.profileId,
    required this.dateKey,
    required this.remainingSeconds,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['date_key'] = Variable<int>(dateKey);
    map['remaining_seconds'] = Variable<int>(remainingSeconds);
    map['active'] = Variable<bool>(active);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      profileId: Value(profileId),
      dateKey: Value(dateKey),
      remainingSeconds: Value(remainingSeconds),
      active: Value(active),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      profileId: serializer.fromJson<String>(json['profileId']),
      dateKey: serializer.fromJson<int>(json['dateKey']),
      remainingSeconds: serializer.fromJson<int>(json['remainingSeconds']),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'dateKey': serializer.toJson<int>(dateKey),
      'remainingSeconds': serializer.toJson<int>(remainingSeconds),
      'active': serializer.toJson<bool>(active),
    };
  }

  Session copyWith({
    String? profileId,
    int? dateKey,
    int? remainingSeconds,
    bool? active,
  }) => Session(
    profileId: profileId ?? this.profileId,
    dateKey: dateKey ?? this.dateKey,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    active: active ?? this.active,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      dateKey: data.dateKey.present ? data.dateKey.value : this.dateKey,
      remainingSeconds: data.remainingSeconds.present
          ? data.remainingSeconds.value
          : this.remainingSeconds,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('profileId: $profileId, ')
          ..write('dateKey: $dateKey, ')
          ..write('remainingSeconds: $remainingSeconds, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(profileId, dateKey, remainingSeconds, active);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.profileId == this.profileId &&
          other.dateKey == this.dateKey &&
          other.remainingSeconds == this.remainingSeconds &&
          other.active == this.active);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> profileId;
  final Value<int> dateKey;
  final Value<int> remainingSeconds;
  final Value<bool> active;
  final Value<int> rowid;
  const SessionsCompanion({
    this.profileId = const Value.absent(),
    this.dateKey = const Value.absent(),
    this.remainingSeconds = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String profileId,
    required int dateKey,
    required int remainingSeconds,
    required bool active,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       dateKey = Value(dateKey),
       remainingSeconds = Value(remainingSeconds),
       active = Value(active);
  static Insertable<Session> custom({
    Expression<String>? profileId,
    Expression<int>? dateKey,
    Expression<int>? remainingSeconds,
    Expression<bool>? active,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (dateKey != null) 'date_key': dateKey,
      if (remainingSeconds != null) 'remaining_seconds': remainingSeconds,
      if (active != null) 'active': active,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? profileId,
    Value<int>? dateKey,
    Value<int>? remainingSeconds,
    Value<bool>? active,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      profileId: profileId ?? this.profileId,
      dateKey: dateKey ?? this.dateKey,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      active: active ?? this.active,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (dateKey.present) {
      map['date_key'] = Variable<int>(dateKey.value);
    }
    if (remainingSeconds.present) {
      map['remaining_seconds'] = Variable<int>(remainingSeconds.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('profileId: $profileId, ')
          ..write('dateKey: $dateKey, ')
          ..write('remainingSeconds: $remainingSeconds, ')
          ..write('active: $active, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentPinMeta = const VerificationMeta(
    'parentPin',
  );
  @override
  late final GeneratedColumn<String> parentPin = GeneratedColumn<String>(
    'parent_pin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _tokenMeta = const VerificationMeta('token');
  @override
  late final GeneratedColumn<String> token = GeneratedColumn<String>(
    'token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _masterLockEnabledMeta = const VerificationMeta(
    'masterLockEnabled',
  );
  @override
  late final GeneratedColumn<bool> masterLockEnabled = GeneratedColumn<bool>(
    'master_lock_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("master_lock_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lockedActiveProfileIdMeta =
      const VerificationMeta('lockedActiveProfileId');
  @override
  late final GeneratedColumn<String> lockedActiveProfileId =
      GeneratedColumn<String>(
        'locked_active_profile_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    parentPin,
    token,
    masterLockEnabled,
    lockedActiveProfileId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('parent_pin')) {
      context.handle(
        _parentPinMeta,
        parentPin.isAcceptableOrUnknown(data['parent_pin']!, _parentPinMeta),
      );
    }
    if (data.containsKey('token')) {
      context.handle(
        _tokenMeta,
        token.isAcceptableOrUnknown(data['token']!, _tokenMeta),
      );
    }
    if (data.containsKey('master_lock_enabled')) {
      context.handle(
        _masterLockEnabledMeta,
        masterLockEnabled.isAcceptableOrUnknown(
          data['master_lock_enabled']!,
          _masterLockEnabledMeta,
        ),
      );
    }
    if (data.containsKey('locked_active_profile_id')) {
      context.handle(
        _lockedActiveProfileIdMeta,
        lockedActiveProfileId.isAcceptableOrUnknown(
          data['locked_active_profile_id']!,
          _lockedActiveProfileIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      parentPin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_pin'],
      )!,
      token: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token'],
      ),
      masterLockEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}master_lock_enabled'],
      )!,
      lockedActiveProfileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locked_active_profile_id'],
      ),
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  /// Always 1; the table intentionally holds at most one row.
  final int id;
  final String parentPin;
  final String? token;
  final bool masterLockEnabled;

  /// The profile whose active session was locked away by the last master
  /// lock (v2). Null when none was active at lock time.
  final String? lockedActiveProfileId;
  const AppSetting({
    required this.id,
    required this.parentPin,
    this.token,
    required this.masterLockEnabled,
    this.lockedActiveProfileId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['parent_pin'] = Variable<String>(parentPin);
    if (!nullToAbsent || token != null) {
      map['token'] = Variable<String>(token);
    }
    map['master_lock_enabled'] = Variable<bool>(masterLockEnabled);
    if (!nullToAbsent || lockedActiveProfileId != null) {
      map['locked_active_profile_id'] = Variable<String>(lockedActiveProfileId);
    }
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      id: Value(id),
      parentPin: Value(parentPin),
      token: token == null && nullToAbsent
          ? const Value.absent()
          : Value(token),
      masterLockEnabled: Value(masterLockEnabled),
      lockedActiveProfileId: lockedActiveProfileId == null && nullToAbsent
          ? const Value.absent()
          : Value(lockedActiveProfileId),
    );
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      id: serializer.fromJson<int>(json['id']),
      parentPin: serializer.fromJson<String>(json['parentPin']),
      token: serializer.fromJson<String?>(json['token']),
      masterLockEnabled: serializer.fromJson<bool>(json['masterLockEnabled']),
      lockedActiveProfileId: serializer.fromJson<String?>(
        json['lockedActiveProfileId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'parentPin': serializer.toJson<String>(parentPin),
      'token': serializer.toJson<String?>(token),
      'masterLockEnabled': serializer.toJson<bool>(masterLockEnabled),
      'lockedActiveProfileId': serializer.toJson<String?>(
        lockedActiveProfileId,
      ),
    };
  }

  AppSetting copyWith({
    int? id,
    String? parentPin,
    Value<String?> token = const Value.absent(),
    bool? masterLockEnabled,
    Value<String?> lockedActiveProfileId = const Value.absent(),
  }) => AppSetting(
    id: id ?? this.id,
    parentPin: parentPin ?? this.parentPin,
    token: token.present ? token.value : this.token,
    masterLockEnabled: masterLockEnabled ?? this.masterLockEnabled,
    lockedActiveProfileId: lockedActiveProfileId.present
        ? lockedActiveProfileId.value
        : this.lockedActiveProfileId,
  );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      id: data.id.present ? data.id.value : this.id,
      parentPin: data.parentPin.present ? data.parentPin.value : this.parentPin,
      token: data.token.present ? data.token.value : this.token,
      masterLockEnabled: data.masterLockEnabled.present
          ? data.masterLockEnabled.value
          : this.masterLockEnabled,
      lockedActiveProfileId: data.lockedActiveProfileId.present
          ? data.lockedActiveProfileId.value
          : this.lockedActiveProfileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('id: $id, ')
          ..write('parentPin: $parentPin, ')
          ..write('token: $token, ')
          ..write('masterLockEnabled: $masterLockEnabled, ')
          ..write('lockedActiveProfileId: $lockedActiveProfileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    parentPin,
    token,
    masterLockEnabled,
    lockedActiveProfileId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.id == this.id &&
          other.parentPin == this.parentPin &&
          other.token == this.token &&
          other.masterLockEnabled == this.masterLockEnabled &&
          other.lockedActiveProfileId == this.lockedActiveProfileId);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<int> id;
  final Value<String> parentPin;
  final Value<String?> token;
  final Value<bool> masterLockEnabled;
  final Value<String?> lockedActiveProfileId;
  const AppSettingsCompanion({
    this.id = const Value.absent(),
    this.parentPin = const Value.absent(),
    this.token = const Value.absent(),
    this.masterLockEnabled = const Value.absent(),
    this.lockedActiveProfileId = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.parentPin = const Value.absent(),
    this.token = const Value.absent(),
    this.masterLockEnabled = const Value.absent(),
    this.lockedActiveProfileId = const Value.absent(),
  });
  static Insertable<AppSetting> custom({
    Expression<int>? id,
    Expression<String>? parentPin,
    Expression<String>? token,
    Expression<bool>? masterLockEnabled,
    Expression<String>? lockedActiveProfileId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentPin != null) 'parent_pin': parentPin,
      if (token != null) 'token': token,
      if (masterLockEnabled != null) 'master_lock_enabled': masterLockEnabled,
      if (lockedActiveProfileId != null)
        'locked_active_profile_id': lockedActiveProfileId,
    });
  }

  AppSettingsCompanion copyWith({
    Value<int>? id,
    Value<String>? parentPin,
    Value<String?>? token,
    Value<bool>? masterLockEnabled,
    Value<String?>? lockedActiveProfileId,
  }) {
    return AppSettingsCompanion(
      id: id ?? this.id,
      parentPin: parentPin ?? this.parentPin,
      token: token ?? this.token,
      masterLockEnabled: masterLockEnabled ?? this.masterLockEnabled,
      lockedActiveProfileId:
          lockedActiveProfileId ?? this.lockedActiveProfileId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (parentPin.present) {
      map['parent_pin'] = Variable<String>(parentPin.value);
    }
    if (token.present) {
      map['token'] = Variable<String>(token.value);
    }
    if (masterLockEnabled.present) {
      map['master_lock_enabled'] = Variable<bool>(masterLockEnabled.value);
    }
    if (lockedActiveProfileId.present) {
      map['locked_active_profile_id'] = Variable<String>(
        lockedActiveProfileId.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('id: $id, ')
          ..write('parentPin: $parentPin, ')
          ..write('token: $token, ')
          ..write('masterLockEnabled: $masterLockEnabled, ')
          ..write('lockedActiveProfileId: $lockedActiveProfileId')
          ..write(')'))
        .toString();
  }
}

class $UsageRecordsTable extends UsageRecords
    with TableInfo<$UsageRecordsTable, UsageRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsageRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateKeyMeta = const VerificationMeta(
    'dateKey',
  );
  @override
  late final GeneratedColumn<int> dateKey = GeneratedColumn<int>(
    'date_key',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usedSecondsMeta = const VerificationMeta(
    'usedSeconds',
  );
  @override
  late final GeneratedColumn<int> usedSeconds = GeneratedColumn<int>(
    'used_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [profileId, dateKey, usedSeconds];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'usage_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<UsageRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('date_key')) {
      context.handle(
        _dateKeyMeta,
        dateKey.isAcceptableOrUnknown(data['date_key']!, _dateKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dateKeyMeta);
    }
    if (data.containsKey('used_seconds')) {
      context.handle(
        _usedSecondsMeta,
        usedSeconds.isAcceptableOrUnknown(
          data['used_seconds']!,
          _usedSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, dateKey};
  @override
  UsageRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UsageRecord(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      dateKey: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_key'],
      )!,
      usedSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}used_seconds'],
      )!,
    );
  }

  @override
  $UsageRecordsTable createAlias(String alias) {
    return $UsageRecordsTable(attachedDatabase, alias);
  }
}

class UsageRecord extends DataClass implements Insertable<UsageRecord> {
  final String profileId;

  /// Date-only key `yyyymmdd`, matching [Sessions.dateKey].
  final int dateKey;
  final int usedSeconds;
  const UsageRecord({
    required this.profileId,
    required this.dateKey,
    required this.usedSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['date_key'] = Variable<int>(dateKey);
    map['used_seconds'] = Variable<int>(usedSeconds);
    return map;
  }

  UsageRecordsCompanion toCompanion(bool nullToAbsent) {
    return UsageRecordsCompanion(
      profileId: Value(profileId),
      dateKey: Value(dateKey),
      usedSeconds: Value(usedSeconds),
    );
  }

  factory UsageRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UsageRecord(
      profileId: serializer.fromJson<String>(json['profileId']),
      dateKey: serializer.fromJson<int>(json['dateKey']),
      usedSeconds: serializer.fromJson<int>(json['usedSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'dateKey': serializer.toJson<int>(dateKey),
      'usedSeconds': serializer.toJson<int>(usedSeconds),
    };
  }

  UsageRecord copyWith({String? profileId, int? dateKey, int? usedSeconds}) =>
      UsageRecord(
        profileId: profileId ?? this.profileId,
        dateKey: dateKey ?? this.dateKey,
        usedSeconds: usedSeconds ?? this.usedSeconds,
      );
  UsageRecord copyWithCompanion(UsageRecordsCompanion data) {
    return UsageRecord(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      dateKey: data.dateKey.present ? data.dateKey.value : this.dateKey,
      usedSeconds: data.usedSeconds.present
          ? data.usedSeconds.value
          : this.usedSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UsageRecord(')
          ..write('profileId: $profileId, ')
          ..write('dateKey: $dateKey, ')
          ..write('usedSeconds: $usedSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(profileId, dateKey, usedSeconds);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UsageRecord &&
          other.profileId == this.profileId &&
          other.dateKey == this.dateKey &&
          other.usedSeconds == this.usedSeconds);
}

class UsageRecordsCompanion extends UpdateCompanion<UsageRecord> {
  final Value<String> profileId;
  final Value<int> dateKey;
  final Value<int> usedSeconds;
  final Value<int> rowid;
  const UsageRecordsCompanion({
    this.profileId = const Value.absent(),
    this.dateKey = const Value.absent(),
    this.usedSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsageRecordsCompanion.insert({
    required String profileId,
    required int dateKey,
    this.usedSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       dateKey = Value(dateKey);
  static Insertable<UsageRecord> custom({
    Expression<String>? profileId,
    Expression<int>? dateKey,
    Expression<int>? usedSeconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (dateKey != null) 'date_key': dateKey,
      if (usedSeconds != null) 'used_seconds': usedSeconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsageRecordsCompanion copyWith({
    Value<String>? profileId,
    Value<int>? dateKey,
    Value<int>? usedSeconds,
    Value<int>? rowid,
  }) {
    return UsageRecordsCompanion(
      profileId: profileId ?? this.profileId,
      dateKey: dateKey ?? this.dateKey,
      usedSeconds: usedSeconds ?? this.usedSeconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (dateKey.present) {
      map['date_key'] = Variable<int>(dateKey.value);
    }
    if (usedSeconds.present) {
      map['used_seconds'] = Variable<int>(usedSeconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsageRecordsCompanion(')
          ..write('profileId: $profileId, ')
          ..write('dateKey: $dateKey, ')
          ..write('usedSeconds: $usedSeconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsageEventsTable extends UsageEvents
    with TableInfo<$UsageEventsTable, UsageEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsageEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateKeyMeta = const VerificationMeta(
    'dateKey',
  );
  @override
  late final GeneratedColumn<int> dateKey = GeneratedColumn<int>(
    'date_key',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    dateKey,
    type,
    detail,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'usage_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<UsageEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('date_key')) {
      context.handle(
        _dateKeyMeta,
        dateKey.isAcceptableOrUnknown(data['date_key']!, _dateKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dateKeyMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UsageEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UsageEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      dateKey: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_key'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $UsageEventsTable createAlias(String alias) {
    return $UsageEventsTable(attachedDatabase, alias);
  }
}

class UsageEventRow extends DataClass implements Insertable<UsageEventRow> {
  /// Auto-incrementing log sequence (insert order).
  final int id;

  /// [EleenDatabase.appGlobalProfileId] for app-global events (the
  /// shutdown/powerOn pair, which belong to no single profile).
  final String profileId;

  /// Date-only key `yyyymmdd` of the day the event belongs to.
  final int dateKey;
  final String type;

  /// Free-form detail, e.g. the added seconds of an addTime event.
  final String? detail;

  /// Wall-clock epoch milliseconds when the event was recorded.
  final int createdAtMs;
  const UsageEventRow({
    required this.id,
    required this.profileId,
    required this.dateKey,
    required this.type,
    this.detail,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['date_key'] = Variable<int>(dateKey);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  UsageEventsCompanion toCompanion(bool nullToAbsent) {
    return UsageEventsCompanion(
      id: Value(id),
      profileId: Value(profileId),
      dateKey: Value(dateKey),
      type: Value(type),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory UsageEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UsageEventRow(
      id: serializer.fromJson<int>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      dateKey: serializer.fromJson<int>(json['dateKey']),
      type: serializer.fromJson<String>(json['type']),
      detail: serializer.fromJson<String?>(json['detail']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'profileId': serializer.toJson<String>(profileId),
      'dateKey': serializer.toJson<int>(dateKey),
      'type': serializer.toJson<String>(type),
      'detail': serializer.toJson<String?>(detail),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  UsageEventRow copyWith({
    int? id,
    String? profileId,
    int? dateKey,
    String? type,
    Value<String?> detail = const Value.absent(),
    int? createdAtMs,
  }) => UsageEventRow(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    dateKey: dateKey ?? this.dateKey,
    type: type ?? this.type,
    detail: detail.present ? detail.value : this.detail,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  UsageEventRow copyWithCompanion(UsageEventsCompanion data) {
    return UsageEventRow(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      dateKey: data.dateKey.present ? data.dateKey.value : this.dateKey,
      type: data.type.present ? data.type.value : this.type,
      detail: data.detail.present ? data.detail.value : this.detail,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UsageEventRow(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('dateKey: $dateKey, ')
          ..write('type: $type, ')
          ..write('detail: $detail, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, profileId, dateKey, type, detail, createdAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UsageEventRow &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.dateKey == this.dateKey &&
          other.type == this.type &&
          other.detail == this.detail &&
          other.createdAtMs == this.createdAtMs);
}

class UsageEventsCompanion extends UpdateCompanion<UsageEventRow> {
  final Value<int> id;
  final Value<String> profileId;
  final Value<int> dateKey;
  final Value<String> type;
  final Value<String?> detail;
  final Value<int> createdAtMs;
  const UsageEventsCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.dateKey = const Value.absent(),
    this.type = const Value.absent(),
    this.detail = const Value.absent(),
    this.createdAtMs = const Value.absent(),
  });
  UsageEventsCompanion.insert({
    this.id = const Value.absent(),
    required String profileId,
    required int dateKey,
    required String type,
    this.detail = const Value.absent(),
    required int createdAtMs,
  }) : profileId = Value(profileId),
       dateKey = Value(dateKey),
       type = Value(type),
       createdAtMs = Value(createdAtMs);
  static Insertable<UsageEventRow> custom({
    Expression<int>? id,
    Expression<String>? profileId,
    Expression<int>? dateKey,
    Expression<String>? type,
    Expression<String>? detail,
    Expression<int>? createdAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (dateKey != null) 'date_key': dateKey,
      if (type != null) 'type': type,
      if (detail != null) 'detail': detail,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
    });
  }

  UsageEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? profileId,
    Value<int>? dateKey,
    Value<String>? type,
    Value<String?>? detail,
    Value<int>? createdAtMs,
  }) {
    return UsageEventsCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      dateKey: dateKey ?? this.dateKey,
      type: type ?? this.type,
      detail: detail ?? this.detail,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (dateKey.present) {
      map['date_key'] = Variable<int>(dateKey.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsageEventsCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('dateKey: $dateKey, ')
          ..write('type: $type, ')
          ..write('detail: $detail, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }
}

class $MetaTable extends Meta with TableInfo<$MetaTable, MetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intValueMeta = const VerificationMeta(
    'intValue',
  );
  @override
  late final GeneratedColumn<int> intValue = GeneratedColumn<int>(
    'int_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, intValue];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('int_value')) {
      context.handle(
        _intValueMeta,
        intValue.isAcceptableOrUnknown(data['int_value']!, _intValueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  MetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      intValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}int_value'],
      ),
    );
  }

  @override
  $MetaTable createAlias(String alias) {
    return $MetaTable(attachedDatabase, alias);
  }
}

class MetaRow extends DataClass implements Insertable<MetaRow> {
  final String key;
  final int? intValue;
  const MetaRow({required this.key, this.intValue});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || intValue != null) {
      map['int_value'] = Variable<int>(intValue);
    }
    return map;
  }

  MetaCompanion toCompanion(bool nullToAbsent) {
    return MetaCompanion(
      key: Value(key),
      intValue: intValue == null && nullToAbsent
          ? const Value.absent()
          : Value(intValue),
    );
  }

  factory MetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaRow(
      key: serializer.fromJson<String>(json['key']),
      intValue: serializer.fromJson<int?>(json['intValue']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'intValue': serializer.toJson<int?>(intValue),
    };
  }

  MetaRow copyWith({
    String? key,
    Value<int?> intValue = const Value.absent(),
  }) => MetaRow(
    key: key ?? this.key,
    intValue: intValue.present ? intValue.value : this.intValue,
  );
  MetaRow copyWithCompanion(MetaCompanion data) {
    return MetaRow(
      key: data.key.present ? data.key.value : this.key,
      intValue: data.intValue.present ? data.intValue.value : this.intValue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaRow(')
          ..write('key: $key, ')
          ..write('intValue: $intValue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, intValue);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaRow &&
          other.key == this.key &&
          other.intValue == this.intValue);
}

class MetaCompanion extends UpdateCompanion<MetaRow> {
  final Value<String> key;
  final Value<int?> intValue;
  final Value<int> rowid;
  const MetaCompanion({
    this.key = const Value.absent(),
    this.intValue = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaCompanion.insert({
    required String key,
    this.intValue = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<MetaRow> custom({
    Expression<String>? key,
    Expression<int>? intValue,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (intValue != null) 'int_value': intValue,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaCompanion copyWith({
    Value<String>? key,
    Value<int?>? intValue,
    Value<int>? rowid,
  }) {
    return MetaCompanion(
      key: key ?? this.key,
      intValue: intValue ?? this.intValue,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (intValue.present) {
      map['int_value'] = Variable<int>(intValue.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaCompanion(')
          ..write('key: $key, ')
          ..write('intValue: $intValue, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$EleenDatabase extends GeneratedDatabase {
  _$EleenDatabase(QueryExecutor e) : super(e);
  $EleenDatabaseManager get managers => $EleenDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $UsageRecordsTable usageRecords = $UsageRecordsTable(this);
  late final $UsageEventsTable usageEvents = $UsageEventsTable(this);
  late final $MetaTable meta = $MetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    profiles,
    sessions,
    appSettings,
    usageRecords,
    usageEvents,
    meta,
  ];
}

typedef $$ProfilesTableCreateCompanionBuilder =
    ProfilesCompanion Function({
      required String id,
      required String name,
      required String avatar,
      required int allowanceMinutes,
      Value<bool> isParent,
      Value<int> rowid,
    });
typedef $$ProfilesTableUpdateCompanionBuilder =
    ProfilesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> avatar,
      Value<int> allowanceMinutes,
      Value<bool> isParent,
      Value<int> rowid,
    });

class $$ProfilesTableFilterComposer
    extends Composer<_$EleenDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get allowanceMinutes => $composableBuilder(
    column: $table.allowanceMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isParent => $composableBuilder(
    column: $table.isParent,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$EleenDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get allowanceMinutes => $composableBuilder(
    column: $table.allowanceMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isParent => $composableBuilder(
    column: $table.isParent,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$EleenDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<int> get allowanceMinutes => $composableBuilder(
    column: $table.allowanceMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isParent =>
      $composableBuilder(column: $table.isParent, builder: (column) => column);
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$EleenDatabase,
          $ProfilesTable,
          ProfileRow,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (
            ProfileRow,
            BaseReferences<_$EleenDatabase, $ProfilesTable, ProfileRow>,
          ),
          ProfileRow,
          PrefetchHooks Function()
        > {
  $$ProfilesTableTableManager(_$EleenDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> avatar = const Value.absent(),
                Value<int> allowanceMinutes = const Value.absent(),
                Value<bool> isParent = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion(
                id: id,
                name: name,
                avatar: avatar,
                allowanceMinutes: allowanceMinutes,
                isParent: isParent,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String avatar,
                required int allowanceMinutes,
                Value<bool> isParent = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion.insert(
                id: id,
                name: name,
                avatar: avatar,
                allowanceMinutes: allowanceMinutes,
                isParent: isParent,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfilesTable, ProfileRow>(table),
                  BaseReferences<_$EleenDatabase, $ProfilesTable, ProfileRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$EleenDatabase,
      $ProfilesTable,
      ProfileRow,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (ProfileRow, BaseReferences<_$EleenDatabase, $ProfilesTable, ProfileRow>),
      ProfileRow,
      PrefetchHooks Function()
    >;
typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String profileId,
      required int dateKey,
      required int remainingSeconds,
      required bool active,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> profileId,
      Value<int> dateKey,
      Value<int> remainingSeconds,
      Value<bool> active,
      Value<int> rowid,
    });

class $$SessionsTableFilterComposer
    extends Composer<_$EleenDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remainingSeconds => $composableBuilder(
    column: $table.remainingSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionsTableOrderingComposer
    extends Composer<_$EleenDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remainingSeconds => $composableBuilder(
    column: $table.remainingSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$EleenDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<int> get dateKey =>
      $composableBuilder(column: $table.dateKey, builder: (column) => column);

  GeneratedColumn<int> get remainingSeconds => $composableBuilder(
    column: $table.remainingSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$EleenDatabase,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, BaseReferences<_$EleenDatabase, $SessionsTable, Session>),
          Session,
          PrefetchHooks Function()
        > {
  $$SessionsTableTableManager(_$EleenDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<int> dateKey = const Value.absent(),
                Value<int> remainingSeconds = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                profileId: profileId,
                dateKey: dateKey,
                remainingSeconds: remainingSeconds,
                active: active,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required int dateKey,
                required int remainingSeconds,
                required bool active,
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                profileId: profileId,
                dateKey: dateKey,
                remainingSeconds: remainingSeconds,
                active: active,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionsTable, Session>(table),
                  BaseReferences<_$EleenDatabase, $SessionsTable, Session>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$EleenDatabase,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, BaseReferences<_$EleenDatabase, $SessionsTable, Session>),
      Session,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> id,
      Value<String> parentPin,
      Value<String?> token,
      Value<bool> masterLockEnabled,
      Value<String?> lockedActiveProfileId,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> id,
      Value<String> parentPin,
      Value<String?> token,
      Value<bool> masterLockEnabled,
      Value<String?> lockedActiveProfileId,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$EleenDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentPin => $composableBuilder(
    column: $table.parentPin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get masterLockEnabled => $composableBuilder(
    column: $table.masterLockEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lockedActiveProfileId => $composableBuilder(
    column: $table.lockedActiveProfileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$EleenDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentPin => $composableBuilder(
    column: $table.parentPin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get masterLockEnabled => $composableBuilder(
    column: $table.masterLockEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lockedActiveProfileId => $composableBuilder(
    column: $table.lockedActiveProfileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$EleenDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get parentPin =>
      $composableBuilder(column: $table.parentPin, builder: (column) => column);

  GeneratedColumn<String> get token =>
      $composableBuilder(column: $table.token, builder: (column) => column);

  GeneratedColumn<bool> get masterLockEnabled => $composableBuilder(
    column: $table.masterLockEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lockedActiveProfileId => $composableBuilder(
    column: $table.lockedActiveProfileId,
    builder: (column) => column,
  );
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$EleenDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$EleenDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$EleenDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> parentPin = const Value.absent(),
                Value<String?> token = const Value.absent(),
                Value<bool> masterLockEnabled = const Value.absent(),
                Value<String?> lockedActiveProfileId = const Value.absent(),
              }) => AppSettingsCompanion(
                id: id,
                parentPin: parentPin,
                token: token,
                masterLockEnabled: masterLockEnabled,
                lockedActiveProfileId: lockedActiveProfileId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> parentPin = const Value.absent(),
                Value<String?> token = const Value.absent(),
                Value<bool> masterLockEnabled = const Value.absent(),
                Value<String?> lockedActiveProfileId = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                id: id,
                parentPin: parentPin,
                token: token,
                masterLockEnabled: masterLockEnabled,
                lockedActiveProfileId: lockedActiveProfileId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<
                    _$EleenDatabase,
                    $AppSettingsTable,
                    AppSetting
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$EleenDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$EleenDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$UsageRecordsTableCreateCompanionBuilder =
    UsageRecordsCompanion Function({
      required String profileId,
      required int dateKey,
      Value<int> usedSeconds,
      Value<int> rowid,
    });
typedef $$UsageRecordsTableUpdateCompanionBuilder =
    UsageRecordsCompanion Function({
      Value<String> profileId,
      Value<int> dateKey,
      Value<int> usedSeconds,
      Value<int> rowid,
    });

class $$UsageRecordsTableFilterComposer
    extends Composer<_$EleenDatabase, $UsageRecordsTable> {
  $$UsageRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usedSeconds => $composableBuilder(
    column: $table.usedSeconds,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsageRecordsTableOrderingComposer
    extends Composer<_$EleenDatabase, $UsageRecordsTable> {
  $$UsageRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usedSeconds => $composableBuilder(
    column: $table.usedSeconds,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsageRecordsTableAnnotationComposer
    extends Composer<_$EleenDatabase, $UsageRecordsTable> {
  $$UsageRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<int> get dateKey =>
      $composableBuilder(column: $table.dateKey, builder: (column) => column);

  GeneratedColumn<int> get usedSeconds => $composableBuilder(
    column: $table.usedSeconds,
    builder: (column) => column,
  );
}

class $$UsageRecordsTableTableManager
    extends
        RootTableManager<
          _$EleenDatabase,
          $UsageRecordsTable,
          UsageRecord,
          $$UsageRecordsTableFilterComposer,
          $$UsageRecordsTableOrderingComposer,
          $$UsageRecordsTableAnnotationComposer,
          $$UsageRecordsTableCreateCompanionBuilder,
          $$UsageRecordsTableUpdateCompanionBuilder,
          (
            UsageRecord,
            BaseReferences<_$EleenDatabase, $UsageRecordsTable, UsageRecord>,
          ),
          UsageRecord,
          PrefetchHooks Function()
        > {
  $$UsageRecordsTableTableManager(_$EleenDatabase db, $UsageRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsageRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsageRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsageRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<int> dateKey = const Value.absent(),
                Value<int> usedSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsageRecordsCompanion(
                profileId: profileId,
                dateKey: dateKey,
                usedSeconds: usedSeconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required int dateKey,
                Value<int> usedSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsageRecordsCompanion.insert(
                profileId: profileId,
                dateKey: dateKey,
                usedSeconds: usedSeconds,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UsageRecordsTable, UsageRecord>(table),
                  BaseReferences<
                    _$EleenDatabase,
                    $UsageRecordsTable,
                    UsageRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsageRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$EleenDatabase,
      $UsageRecordsTable,
      UsageRecord,
      $$UsageRecordsTableFilterComposer,
      $$UsageRecordsTableOrderingComposer,
      $$UsageRecordsTableAnnotationComposer,
      $$UsageRecordsTableCreateCompanionBuilder,
      $$UsageRecordsTableUpdateCompanionBuilder,
      (
        UsageRecord,
        BaseReferences<_$EleenDatabase, $UsageRecordsTable, UsageRecord>,
      ),
      UsageRecord,
      PrefetchHooks Function()
    >;
typedef $$UsageEventsTableCreateCompanionBuilder =
    UsageEventsCompanion Function({
      Value<int> id,
      required String profileId,
      required int dateKey,
      required String type,
      Value<String?> detail,
      required int createdAtMs,
    });
typedef $$UsageEventsTableUpdateCompanionBuilder =
    UsageEventsCompanion Function({
      Value<int> id,
      Value<String> profileId,
      Value<int> dateKey,
      Value<String> type,
      Value<String?> detail,
      Value<int> createdAtMs,
    });

class $$UsageEventsTableFilterComposer
    extends Composer<_$EleenDatabase, $UsageEventsTable> {
  $$UsageEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsageEventsTableOrderingComposer
    extends Composer<_$EleenDatabase, $UsageEventsTable> {
  $$UsageEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsageEventsTableAnnotationComposer
    extends Composer<_$EleenDatabase, $UsageEventsTable> {
  $$UsageEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<int> get dateKey =>
      $composableBuilder(column: $table.dateKey, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$UsageEventsTableTableManager
    extends
        RootTableManager<
          _$EleenDatabase,
          $UsageEventsTable,
          UsageEventRow,
          $$UsageEventsTableFilterComposer,
          $$UsageEventsTableOrderingComposer,
          $$UsageEventsTableAnnotationComposer,
          $$UsageEventsTableCreateCompanionBuilder,
          $$UsageEventsTableUpdateCompanionBuilder,
          (
            UsageEventRow,
            BaseReferences<_$EleenDatabase, $UsageEventsTable, UsageEventRow>,
          ),
          UsageEventRow,
          PrefetchHooks Function()
        > {
  $$UsageEventsTableTableManager(_$EleenDatabase db, $UsageEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsageEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsageEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsageEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<int> dateKey = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> detail = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
              }) => UsageEventsCompanion(
                id: id,
                profileId: profileId,
                dateKey: dateKey,
                type: type,
                detail: detail,
                createdAtMs: createdAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String profileId,
                required int dateKey,
                required String type,
                Value<String?> detail = const Value.absent(),
                required int createdAtMs,
              }) => UsageEventsCompanion.insert(
                id: id,
                profileId: profileId,
                dateKey: dateKey,
                type: type,
                detail: detail,
                createdAtMs: createdAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UsageEventsTable, UsageEventRow>(table),
                  BaseReferences<
                    _$EleenDatabase,
                    $UsageEventsTable,
                    UsageEventRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsageEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$EleenDatabase,
      $UsageEventsTable,
      UsageEventRow,
      $$UsageEventsTableFilterComposer,
      $$UsageEventsTableOrderingComposer,
      $$UsageEventsTableAnnotationComposer,
      $$UsageEventsTableCreateCompanionBuilder,
      $$UsageEventsTableUpdateCompanionBuilder,
      (
        UsageEventRow,
        BaseReferences<_$EleenDatabase, $UsageEventsTable, UsageEventRow>,
      ),
      UsageEventRow,
      PrefetchHooks Function()
    >;
typedef $$MetaTableCreateCompanionBuilder =
    MetaCompanion Function({
      required String key,
      Value<int?> intValue,
      Value<int> rowid,
    });
typedef $$MetaTableUpdateCompanionBuilder =
    MetaCompanion Function({
      Value<String> key,
      Value<int?> intValue,
      Value<int> rowid,
    });

class $$MetaTableFilterComposer extends Composer<_$EleenDatabase, $MetaTable> {
  $$MetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intValue => $composableBuilder(
    column: $table.intValue,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MetaTableOrderingComposer
    extends Composer<_$EleenDatabase, $MetaTable> {
  $$MetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intValue => $composableBuilder(
    column: $table.intValue,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MetaTableAnnotationComposer
    extends Composer<_$EleenDatabase, $MetaTable> {
  $$MetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<int> get intValue =>
      $composableBuilder(column: $table.intValue, builder: (column) => column);
}

class $$MetaTableTableManager
    extends
        RootTableManager<
          _$EleenDatabase,
          $MetaTable,
          MetaRow,
          $$MetaTableFilterComposer,
          $$MetaTableOrderingComposer,
          $$MetaTableAnnotationComposer,
          $$MetaTableCreateCompanionBuilder,
          $$MetaTableUpdateCompanionBuilder,
          (MetaRow, BaseReferences<_$EleenDatabase, $MetaTable, MetaRow>),
          MetaRow,
          PrefetchHooks Function()
        > {
  $$MetaTableTableManager(_$EleenDatabase db, $MetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<int?> intValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion(key: key, intValue: intValue, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                Value<int?> intValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion.insert(
                key: key,
                intValue: intValue,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MetaTable, MetaRow>(table),
                  BaseReferences<_$EleenDatabase, $MetaTable, MetaRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MetaTableProcessedTableManager =
    ProcessedTableManager<
      _$EleenDatabase,
      $MetaTable,
      MetaRow,
      $$MetaTableFilterComposer,
      $$MetaTableOrderingComposer,
      $$MetaTableAnnotationComposer,
      $$MetaTableCreateCompanionBuilder,
      $$MetaTableUpdateCompanionBuilder,
      (MetaRow, BaseReferences<_$EleenDatabase, $MetaTable, MetaRow>),
      MetaRow,
      PrefetchHooks Function()
    >;

class $EleenDatabaseManager {
  final _$EleenDatabase _db;
  $EleenDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$UsageRecordsTableTableManager get usageRecords =>
      $$UsageRecordsTableTableManager(_db, _db.usageRecords);
  $$UsageEventsTableTableManager get usageEvents =>
      $$UsageEventsTableTableManager(_db, _db.usageEvents);
  $$MetaTableTableManager get meta => $$MetaTableTableManager(_db, _db.meta);
}
