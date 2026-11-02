import 'package:equatable/equatable.dart';
import '../common/types.dart';

/// Platform license bound to a single TradingAccount.
/// One active license per connected account (ADR-003).
class BotLicense extends Equatable {
  final String id;
  final String tradingAccountId;
  final String licenseKey;
  final LicenseStatus status;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final DateTime? lastValidatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BotLicense({
    required this.id,
    required this.tradingAccountId,
    required this.licenseKey,
    required this.status,
    required this.issuedAt,
    this.expiresAt,
    this.lastValidatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isUsable =>
      status == LicenseStatus.active &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now().toUtc()));

  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'tradingAccountId': tradingAccountId,
        'licenseKey': licenseKey,
        'status': status.value,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'lastValidatedAt': lastValidatedAt?.toUtc().toIso8601String(),
        'isUsable': isUsable,
      };

  /// Minimal payload returned to EA on validation (no internal IDs leakage beyond necessity).
  Map<String, dynamic> toValidationJson({required bool subscriptionActive}) => {
        'valid': isUsable && subscriptionActive,
        'licenseStatus': status.value,
        'subscriptionActive': subscriptionActive,
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'environmentAllowed': true, // refined later by config
      };

  @override
  List<Object?> get props => [id, tradingAccountId, licenseKey, status];
}