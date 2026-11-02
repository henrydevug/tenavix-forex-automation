/// Shared enums and value types for Tenavix domain.
library;

enum UserStatus { active, suspended, deleted }

enum AccountEnvironment { demo, live }

enum AccountStatus { active, disconnected, suspended }

enum LicenseStatus { active, expired, revoked, suspended }

enum SubscriptionStatus { active, cancelled, expired, pastDue }

enum PaymentStatus { succeeded, failed, pending, refunded }

enum AuditOutcome { success, failure }

extension UserStatusX on UserStatus {
  String get value => name;
  static UserStatus fromString(String v) =>
      UserStatus.values.firstWhere((e) => e.name == v, orElse: () => UserStatus.active);
}

extension AccountEnvironmentX on AccountEnvironment {
  String get value => name;
  static AccountEnvironment fromString(String v) =>
      AccountEnvironment.values.firstWhere((e) => e.name == v, orElse: () => AccountEnvironment.demo);
}

extension AccountStatusX on AccountStatus {
  String get value => name;
  static AccountStatus fromString(String v) =>
      AccountStatus.values.firstWhere((e) => e.name == v, orElse: () => AccountStatus.active);
}

extension LicenseStatusX on LicenseStatus {
  String get value => name;
  static LicenseStatus fromString(String v) =>
      LicenseStatus.values.firstWhere((e) => e.name == v, orElse: () => LicenseStatus.active);
}

extension SubscriptionStatusX on SubscriptionStatus {
  String get value {
    switch (this) {
      case SubscriptionStatus.pastDue:
        return 'past_due';
      default:
        return name;
    }
  }

  static SubscriptionStatus fromString(String v) {
    if (v == 'past_due') return SubscriptionStatus.pastDue;
    return SubscriptionStatus.values.firstWhere((e) => e.name == v, orElse: () => SubscriptionStatus.active);
  }
}

/// Standard API error codes used across endpoints.
class ErrorCodes {
  static const unauthorized = 'UNAUTHORIZED';
  static const forbidden = 'FORBIDDEN';
  static const notFound = 'NOT_FOUND';
  static const validation = 'VALIDATION_ERROR';
  static const conflict = 'CONFLICT';
  static const internal = 'INTERNAL_ERROR';
  static const rateLimited = 'RATE_LIMITED';
  static const licenseInvalid = 'LICENSE_INVALID';
  static const subscriptionInactive = 'SUBSCRIPTION_INACTIVE';
}

class AppException implements Exception {
  final String code;
  final String message;
  final int statusCode;
  final Map<String, dynamic>? details;

  const AppException({
    required this.code,
    required this.message,
    this.statusCode = 400,
    this.details,
  });

  @override
  String toString() => 'AppException($code): $message';
}