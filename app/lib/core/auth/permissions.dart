enum Role { owner, manager, cashier, warehouse, accountant }

enum Permission {
  attendance,
  reserve,
  returns,
  voidInvoice,
  tailoring,
  collect,
  sell,
  catalog,
  stock,
  staff,
  payroll,
  audit,
  backup,
  reports,
  configure,
}

const permissionsByRole = <Role, Set<Permission>>{
  Role.owner: {...Permission.values},
  Role.manager: {
    Permission.attendance,
    Permission.reserve,
    Permission.returns,
    Permission.voidInvoice,
    Permission.tailoring,
    Permission.collect,
    Permission.sell,
    Permission.catalog,
    Permission.stock,
    Permission.staff,
    Permission.audit,
    Permission.backup,
    Permission.reports,
  },
  Role.cashier: {
    Permission.reserve,
    Permission.sell,
    Permission.collect,
    Permission.tailoring,
    Permission.returns,
  },
  Role.warehouse: {Permission.stock, Permission.tailoring, Permission.reserve},
  Role.accountant: {
    Permission.payroll,
    Permission.reports,
    Permission.collect,
    Permission.attendance,
  },
};

class LocalSession {
  const LocalSession({
    required this.userId,
    required this.name,
    required this.role,
    required this.storeId,
    required this.deviceId,
    required this.expiresAt,
    this.mustChangePassword = false,
  });
  final String userId, name, storeId, deviceId;
  final Role role;
  final DateTime expiresAt;
  final bool mustChangePassword;
  bool can(Permission permission) =>
      permissionsByRole[role]?.contains(permission) ?? false;
  void require(Permission permission, String targetStore, DateTime now) {
    if (!expiresAt.isAfter(now)) {
      throw StateError('Phiên offline đã hết hạn. Cần đăng nhập online lại.');
    }
    if (targetStore != storeId) {
      throw StateError('Không có quyền thao tác cửa hàng này.');
    }
    if (!(permissionsByRole[role]?.contains(permission) ?? false)) {
      throw StateError('Bạn không có quyền thực hiện thao tác này.');
    }
  }
}
