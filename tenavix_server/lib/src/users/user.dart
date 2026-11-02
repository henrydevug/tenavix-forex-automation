import 'package:equatable/equatable.dart';
import '../common/types.dart';

/// Platform user (distinct from MT5 trading accounts).
class User extends Equatable {
  final String id;
  final String email;
  final String passwordHash;
  final String? fullName;
  final UserStatus status;
  final DateTime? emailVerifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;
  final List<String> roles; // role names: ADMIN, TRADER

  const User({
    required this.id,
    required this.email,
    required this.passwordHash,
    this.fullName,
    required this.status,
    this.emailVerifiedAt,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
    this.roles = const [],
  });

  bool get isAdmin => roles.contains('ADMIN');
  bool get isTrader => roles.contains('TRADER');
  bool get isActive => status == UserStatus.active;

  User copyWith({
    String? fullName,
    UserStatus? status,
    DateTime? emailVerifiedAt,
    DateTime? lastLoginAt,
    List<String>? roles,
    DateTime? updatedAt,
  }) {
    return User(
      id: id,
      email: email,
      passwordHash: passwordHash,
      fullName: fullName ?? this.fullName,
      status: status ?? this.status,
      emailVerifiedAt: emailVerifiedAt ?? this.emailVerifiedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      roles: roles ?? this.roles,
    );
  }

  /// Never expose passwordHash in API responses.
  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'status': status.value,
        'roles': roles,
        'emailVerifiedAt': emailVerifiedAt?.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'lastLoginAt': lastLoginAt?.toUtc().toIso8601String(),
      };

  @override
  List<Object?> get props => [id, email, status, roles];
}

/// Role definition.
class Role extends Equatable {
  final String id;
  final String name;
  final String? description;

  const Role({required this.id, required this.name, this.description});

  @override
  List<Object?> get props => [id, name];
}

/// Permission code (e.g. users:manage, licenses:revoke).
class Permission extends Equatable {
  final String id;
  final String code;
  final String? description;

  const Permission({required this.id, required this.code, this.description});

  @override
  List<Object?> get props => [id, code];
}