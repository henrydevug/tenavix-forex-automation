import '../common/types.dart';
import '../users/user.dart';

/// Server-side authorization helpers.
/// Every protected endpoint must call one of these checks.
class Authorization {
  /// Require that the caller is authenticated and active.
  static void requireAuthenticated(User? user) {
    if (user == null || !user.isActive) {
      throw const AppException(
        code: ErrorCodes.unauthorized,
        message: 'Authentication required',
        statusCode: 401,
      );
    }
  }

  /// Require ADMIN role.
  static void requireAdmin(User user) {
    requireAuthenticated(user);
    if (!user.isAdmin) {
      throw const AppException(
        code: ErrorCodes.forbidden,
        message: 'Administrator privileges required',
        statusCode: 403,
      );
    }
  }

  /// Require that the resource belongs to the calling user (or caller is ADMIN).
  static void requireOwnershipOrAdmin({
    required User caller,
    required String resourceOwnerId,
  }) {
    requireAuthenticated(caller);
    if (caller.isAdmin) return;
    if (caller.id != resourceOwnerId) {
      throw const AppException(
        code: ErrorCodes.forbidden,
        message: 'Access denied to this resource',
        statusCode: 403,
      );
    }
  }

  /// Require at least one of the given roles.
  static void requireAnyRole(User user, List<String> roles) {
    requireAuthenticated(user);
    final has = roles.any((r) => user.roles.contains(r));
    if (!has) {
      throw const AppException(
        code: ErrorCodes.forbidden,
        message: 'Insufficient privileges',
        statusCode: 403,
      );
    }
  }
}