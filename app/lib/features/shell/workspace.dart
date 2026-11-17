import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import '../employees/employees_page.dart';
import '../employees/personnel_service.dart';
import '../catalog/catalog_service.dart';
import '../catalog/product_editor.dart';
import '../pos/pos_page.dart';
import '../pos/invoices_page.dart';
import '../backup/backup_page.dart';
import '../audit/audit_page.dart';
import '../debt/debts_page.dart';
import '../catalog/barcode_labels.dart';
import '../schools/schools_page.dart';
import '../catalog/combo_pages.dart';
import '../pricing/commercial_page.dart';
import '../tailoring/tailoring_page.dart';
import '../returns/returns_page.dart';
import '../reservations/reservations_page.dart';
import '../devices/management_page.dart';
import '../sizes/sizes_page.dart';
import '../transfers/transfers_page.dart';
import '../employees/attendance_page.dart';
import '../employees/payroll_page.dart';

final vnd = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: '₫',
  decimalDigits: 0,
);

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.service,
    required this.onLogout,
    this.onReload,
  });
  final LocalService service;
  final VoidCallback onLogout;
  final VoidCallback? onReload;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  int page = 0;
  String search = '';
  String? error;
  String branchLabel = '';
  bool loading = false;
  List<Map<String, Object?>> products = [];
  final searchController = TextEditingController();
  @override
  void initState() {
    super.initState();
    if (permissionsByRole[widget.service.session!.role]!.contains(
      Permission.sell,
    )) {
      page = 2;
    }
    refresh();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final rows = await widget.service.catalog(search: search);
      final identity = await widget.service.db.rows(
        'SELECT s.code AS store_code,d.code AS device_code FROM stores s JOIN devices d ON d.store_id=s.id WHERE s.id=? AND d.id=?',
        [widget.service.storeId, widget.service.deviceId],
      );
      if (mounted) {
        setState(() {
          products = rows;
          branchLabel = identity.isEmpty
              ? ''
              : '${identity.single['store_code']} · Máy ${identity.single['device_code']}';
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void message(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> changePassword() async {
    final oldPassword = TextEditingController(),
        newPassword = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đổi mật khẩu'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPassword,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mật khẩu cũ'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu mới (ít nhất 10 ký tự)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đổi mật khẩu'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await widget.service.changePassword(oldPassword.text, newPassword.text);
        message('Đã đổi mật khẩu.');
      } catch (e) {
        message(e);
      }
    }
    oldPassword.dispose();
    newPassword.dispose();
  }

  Future<void> adjust(Map<String, Object?> product) async {
    final quantity = TextEditingController(), reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Điều chỉnh · ${product['name']} / ${product['size']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số lượng (+ nhập / − xuất)',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Lý do bắt buộc'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ghi nhận'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await widget.service.adjustStock(
          product['id'] as String,
          int.parse(quantity.text),
          reason.text,
        );
        await refresh();
      } catch (e) {
        message(e);
      }
    }
    quantity.dispose();
    reason.dispose();
  }

  Future<void> addProduct() => editVariant();
  Future<void> editVariant([
    Map<String, Object?>? product,
    bool asNewVariant = false,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => ProductEditor(
        service: widget.service,
        product: product,
        asNewVariant: asNewVariant,
      ),
    );
    if (saved == true) await refresh();
  }

  Future<void> archive(Map<String, Object?> product) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ngừng bán biến thể'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Lý do'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ngừng bán'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await widget.service.archiveVariant(
          product['id'] as String,
          reason.text,
        );
        await refresh();
      } catch (e) {
        message(e);
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.service.session!.role;
    final canCatalog = permissionsByRole[role]!.contains(Permission.catalog),
        canStock = permissionsByRole[role]!.contains(Permission.stock),
        canStaff = permissionsByRole[role]!.contains(Permission.staff),
        canSell = permissionsByRole[role]!.contains(Permission.sell);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 1000;
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'ĐỒNG PHỤC NGỌC THANH',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            actions: [
              if (wide) Center(child: Text(branchLabel)),
              const SizedBox(width: 16),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'payroll') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Lương nhân viên')),
                          body: PayrollPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'attendance') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Chấm công')),
                          body: AttendancePage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'transfers') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('Chuyển kho cửa hàng'),
                          ),
                          body: TransfersPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'sizes') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Bảng size')),
                          body: SizesPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'management') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('Quản trị hệ thống'),
                          ),
                          body: ManagementPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'reservations') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('Giữ hàng · đặt trước'),
                          ),
                          body: ReservationsPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'logout') widget.onLogout();
                  if (value == 'returns') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text(
                              'Đổi size · đổi trả · hủy hóa đơn',
                            ),
                          ),
                          body: ReturnsPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'tailoring') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Đơn may riêng')),
                          body: TailoringPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'password') changePassword();
                  if (value == 'combos') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Combo đồng phục')),
                          body: CombosPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'commercial') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('Bảng giá · khuyến mãi · đại lý'),
                          ),
                          body: CommercialPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'schools') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('Trường · lớp · học sinh'),
                          ),
                          body: SchoolsPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'labels') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Tem mã vạch')),
                          body: BarcodeLabelsPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'debt') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('Đặt cọc & công nợ'),
                          ),
                          body: DebtsPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                  if (value == 'backup') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Sao lưu dữ liệu')),
                          body: BackupPage(
                            service: widget.service,
                            onReload: () {
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                              (widget.onReload ?? widget.onLogout)();
                            },
                          ),
                        ),
                      ),
                    );
                  }
                  if (value == 'audit') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Nhật ký')),
                          body: AuditPage(service: widget.service),
                        ),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => [
                  if (widget.service.session!.can(Permission.payroll))
                    const PopupMenuItem(
                      value: 'payroll',
                      child: Text('Lương · phiếu lương'),
                    ),
                  if (widget.service.session!.can(Permission.attendance))
                    const PopupMenuItem(
                      value: 'attendance',
                      child: Text('Chấm công nhân viên'),
                    ),
                  if (canStock)
                    const PopupMenuItem(
                      value: 'transfers',
                      child: Text('Chuyển kho cửa hàng'),
                    ),
                  if (canCatalog || canSell || canStock)
                    const PopupMenuItem(
                      value: 'sizes',
                      child: Text('Bảng quy đổi · gợi ý size'),
                    ),
                  if (widget.service.session!.can(Permission.configure))
                    const PopupMenuItem(
                      value: 'management',
                      child: Text('Cửa hàng · thiết bị'),
                    ),
                  if (widget.service.session!.can(Permission.reserve))
                    const PopupMenuItem(
                      value: 'reservations',
                      child: Text('Giữ hàng · đặt trước'),
                    ),
                  if (widget.service.session!.can(Permission.returns))
                    const PopupMenuItem(
                      value: 'returns',
                      child: Text('Đổi size · đổi trả'),
                    ),
                  if (widget.service.session!.can(Permission.tailoring))
                    const PopupMenuItem(
                      value: 'tailoring',
                      child: Text('Đơn may riêng'),
                    ),
                  PopupMenuItem(
                    value: 'logout',
                    child: Text('Đăng xuất · ${widget.service.session!.name}'),
                  ),
                  const PopupMenuItem(
                    value: 'password',
                    child: Text('Đổi mật khẩu'),
                  ),
                  if (canSell ||
                      canCatalog ||
                      widget.service.session!.can(Permission.reports))
                    const PopupMenuItem(
                      value: 'schools',
                      child: Text('Trường · lớp · học sinh'),
                    ),
                  if (canCatalog || canStock || canSell)
                    const PopupMenuItem(
                      value: 'combos',
                      child: Text('Combo đồng phục'),
                    ),
                  if (canCatalog)
                    const PopupMenuItem(
                      value: 'commercial',
                      child: Text('Bảng giá · khuyến mãi · đại lý'),
                    ),
                  if (canCatalog || canStock || canSell)
                    const PopupMenuItem(
                      value: 'labels',
                      child: Text('Xuất tem mã vạch PDF'),
                    ),
                  if (permissionsByRole[role]!.contains(Permission.collect))
                    const PopupMenuItem(
                      value: 'debt',
                      child: Text('Đặt cọc & công nợ'),
                    ),
                  if (permissionsByRole[role]!.contains(Permission.backup))
                    const PopupMenuItem(
                      value: 'backup',
                      child: Text('Sao lưu & khôi phục'),
                    ),
                  if (permissionsByRole[role]!.contains(Permission.audit))
                    const PopupMenuItem(
                      value: 'audit',
                      child: Text('Nhật ký thao tác'),
                    ),
                ],
              ),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!wide)
                NavigationBar(
                  selectedIndex: page,
                  onDestinationSelected: (v) => setState(() => page = v),
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.grid_view),
                      label: 'Sản phẩm',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      label: 'Tồn kho',
                    ),
                    if (canSell)
                      const NavigationDestination(
                        icon: Icon(Icons.point_of_sale),
                        label: 'Bán hàng',
                      ),
                    if (canSell)
                      const NavigationDestination(
                        icon: Icon(Icons.receipt_long),
                        label: 'Hóa đơn',
                      ),
                    if (canStaff)
                      const NavigationDestination(
                        icon: Icon(Icons.people_outline),
                        label: 'Nhân viên',
                      ),
                  ],
                ),
            ],
          ),
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  extended: true,
                  selectedIndex: page,
                  onDestinationSelected: (v) => setState(() => page = v),
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.grid_view),
                      label: Text('Sản phẩm'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      label: Text('Tồn kho'),
                    ),
                    if (canSell)
                      const NavigationRailDestination(
                        icon: Icon(Icons.point_of_sale),
                        label: Text('Bán hàng'),
                      ),
                    if (canSell)
                      const NavigationRailDestination(
                        icon: Icon(Icons.receipt_long),
                        label: Text('Hóa đơn'),
                      ),
                    if (canStaff)
                      const NavigationRailDestination(
                        icon: Icon(Icons.people_outline),
                        label: Text('Nhân viên'),
                      ),
                  ],
                ),
              Expanded(
                child: page == 2 && canSell
                    ? PosPage(service: widget.service)
                    : page == 3 && canSell
                    ? InvoicesPage(service: widget.service)
                    : page == 4
                    ? EmployeesPage(service: widget.service)
                    : Padding(
                        padding: EdgeInsets.all(wide ? 28 : 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 20,
                              runSpacing: 16,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      page == 0
                                          ? 'Danh mục sản phẩm'
                                          : 'Kho hàng chi nhánh',
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      page == 0
                                          ? 'Đồng phục cho từng mùa, từng năm học'
                                          : 'Mọi thay đổi đều được ghi vào sổ cái kho',
                                      style: const TextStyle(
                                        color: Color(0xff64748b),
                                      ),
                                    ),
                                  ],
                                ),
                                if (canCatalog && page == 0)
                                  FilledButton.icon(
                                    onPressed: addProduct,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Thêm sản phẩm'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: searchController,
                              onChanged: (value) {
                                search = value;
                                refresh();
                              },
                              decoration: InputDecoration(
                                hintText:
                                    'Tìm tên, mã sản phẩm hoặc quét mã vạch…',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: IconButton(
                                  onPressed: refresh,
                                  icon: const Icon(Icons.refresh),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (loading) const LinearProgressIndicator(),
                            if (error != null)
                              Text(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            Expanded(
                              child: products.isEmpty && !loading
                                  ? const Center(
                                      child: Text('Chưa có sản phẩm phù hợp.'),
                                    )
                                  : page == 1
                                  ? SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SingleChildScrollView(
                                        child: DataTable(
                                          columns: [
                                            for (final title in [
                                              'Sản phẩm',
                                              'Size',
                                              'Màu',
                                              'Mã vạch',
                                              'Tồn thực',
                                              'Cảnh báo',
                                              'Thao tác',
                                            ])
                                              DataColumn(label: Text(title)),
                                          ],
                                          rows: [
                                            for (final product in products)
                                              DataRow(
                                                cells: [
                                                  DataCell(
                                                    Text(
                                                      product['name'] as String,
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      product['size'] as String,
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      product['color']
                                                          as String,
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      product['barcode']
                                                              as String? ??
                                                          '',
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Text('${product['stock']}'),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      (product['stock']
                                                                  as int) <=
                                                              (product['threshold']
                                                                  as int)
                                                          ? 'Sắp hết'
                                                          : 'Đủ hàng',
                                                    ),
                                                  ),
                                                  DataCell(
                                                    canStock
                                                        ? TextButton(
                                                            onPressed: () =>
                                                                adjust(product),
                                                            child: const Text(
                                                              'Nhập / điều chỉnh',
                                                            ),
                                                          )
                                                        : const Text('—'),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : GridView.builder(
                                      gridDelegate:
                                          SliverGridDelegateWithMaxCrossAxisExtent(
                                            maxCrossAxisExtent: 270,
                                            mainAxisExtent: 262,
                                            crossAxisSpacing: 16,
                                            mainAxisSpacing: 16,
                                          ),
                                      itemCount: products.length,
                                      itemBuilder: (context, index) {
                                        final product = products[index];
                                        return Card(
                                          elevation: 0,
                                          color: Colors.white,
                                          clipBehavior: Clip.antiAlias,
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (canCatalog)
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child:
                                                        PopupMenuButton<String>(
                                                          onSelected: (action) {
                                                            if (action ==
                                                                'edit') {
                                                              editVariant(
                                                                product,
                                                              );
                                                            }
                                                            if (action ==
                                                                'variant') {
                                                              editVariant(
                                                                product,
                                                                true,
                                                              );
                                                            }
                                                            if (action ==
                                                                'archive') {
                                                              archive(product);
                                                            }
                                                          },
                                                          itemBuilder: (_) =>
                                                              const [
                                                                PopupMenuItem(
                                                                  value: 'edit',
                                                                  child: Text(
                                                                    'Chỉnh sửa',
                                                                  ),
                                                                ),
                                                                PopupMenuItem(
                                                                  value:
                                                                      'variant',
                                                                  child: Text(
                                                                    'Thêm size / màu',
                                                                  ),
                                                                ),
                                                                PopupMenuItem(
                                                                  value:
                                                                      'archive',
                                                                  child: Text(
                                                                    'Ngừng bán',
                                                                  ),
                                                                ),
                                                              ],
                                                        ),
                                                  ),
                                                Expanded(
                                                  child: Container(
                                                    width: double.infinity,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xffedf4ff,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Icon(
                                                      product['category'] ==
                                                              'Mũ'
                                                          ? Icons
                                                                .sports_baseball
                                                          : product['category'] ==
                                                                'Giày'
                                                          ? Icons.sports_soccer
                                                          : Icons.checkroom,
                                                      size: 52,
                                                      color: const Color(
                                                        0xff6c95cb,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  product['name'] as String,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Size ${product['size']} · ${product['color']}',
                                                  style: const TextStyle(
                                                    color: Color(0xff64748b),
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      vnd.format(
                                                        product['sale_price'],
                                                      ),
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xff1763c0,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 17,
                                                      ),
                                                    ),
                                                    Text(
                                                      'Còn ${product['stock']}',
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
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
}
