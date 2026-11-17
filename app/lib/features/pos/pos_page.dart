import 'dart:convert';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import 'sales_service.dart';
import '../schools/school_service.dart';
import '../catalog/combo_pages.dart';
import 'pricing.dart';
import 'document_pdf.dart';
import '../pricing/commercial_rule.dart';
import '../pricing/commercial_service.dart';
import '../reservations/reservation_service.dart';

final _vnd = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: '₫',
  decimalDigits: 0,
);

class PosPage extends StatefulWidget {
  const PosPage({super.key, required this.service, this.initialReservationId});
  final LocalService service;
  final String? initialReservationId;
  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  VoidCallback? rebuildSheet;
  void update(VoidCallback action) {
    if (!mounted) return;
    setState(action);
    rebuildSheet?.call();
  }

  Future<void> openCart() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          rebuildSheet = () => setSheet(() {});
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * .88,
            child: cartPanel(),
          );
        },
      ),
    );
    rebuildSheet = null;
  }

  final search = TextEditingController(),
      discount = TextEditingController(text: '0');
  final scanFocus = FocusNode();
  final cart = <String, int>{};
  final comboGroups = <ComboSelection>[];
  List<Map<String, Object?>> products = [];
  String filter = '', category = 'Tất cả';
  String? error, heldId;
  bool busy = false;
  String? reservationId;
  Map<String, Object?>? reservationBuyer;
  Timer? refreshTimer;
  @override
  void initState() {
    super.initState();
    initialize();
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    search.dispose();
    discount.dispose();
    scanFocus.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final rows = await widget.service.catalog();
      if (mounted) {
        update(() {
          products = rows;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) update(() => error = e.toString());
    }
  }

  Future<void> initialize() async {
    await load();
    if (mounted && widget.initialReservationId != null) await loadReservation();
  }

  Future<void> loadReservation() async {
    try {
      final d = await widget.service.activeReservation(
        widget.initialReservationId!,
      );
      final lines = await widget.service.db.rows(
        'SELECT variant_id,quantity FROM reservation_lines WHERE store_id=? AND document_id=?',
        [widget.service.storeId, d['id']],
      );
      final meta = jsonDecode(d['metadata_json'] as String) as Map;
      if (!mounted) return;
      update(() {
        reservationId = d['id'] as String;
        reservationBuyer = {
          'customer_id': d['customer_id'],
          'name': meta['customer_name'],
          'phone': meta['phone'],
          'label': 'Giao ${d['code']} · ${meta['customer_name']}',
        };
        cart.addAll({
          for (final line in lines)
            line['variant_id'] as String: line['quantity'] as int,
        });
      });
    } catch (e) {
      if (mounted) message(e);
    }
  }

  List<CartItem> get items => [
    for (final e in cart.entries)
      CartItem(
        e.key,
        e.value,
        expectedPrice:
            products.firstWhere((p) => p['id'] == e.key)['sale_price'] as int,
      ),
  ];
  CartPrice quote(Map<String, int> quantities, List<ComboSelection> groups) =>
      priceCart(
        quantities.entries.map((e) {
          final p = products.firstWhere((p) => p['id'] == e.key);
          return PricedItem(
            id: e.key,
            productId: p['product_id'] as String,
            price: p['sale_price'] as int,
            quantity: e.value,
          );
        }).toList(),
        groups,
      );
  CartPrice get pricing => quote(cart, comboGroups);
  int get subtotal => pricing.amount;
  int get reduction => int.tryParse(discount.text) ?? 0;
  void message(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  void add(Map<String, Object?> product) {
    final id = product['id'] as String;
    changeQuantity(id, 1);
    scanFocus.requestFocus();
  }

  int comboQuantity(String id) {
    var count = 0;
    for (final g in comboGroups) {
      for (var i = 0; i < g.picks.length; i++) {
        if (g.picks[i] == id) {
          count += g.rule.parts[i].quantity * g.quantity;
        }
      }
    }
    return count;
  }

  void changeQuantity(String id, int difference) {
    final next = (cart[id] ?? 0) + difference;
    if (next < comboQuantity(id)) {
      message('Bỏ combo trước khi giảm món thành phần.');
      return;
    }
    if (next > 100000) {
      message('Tách thành đơn nhỏ hơn: tối đa 100.000 món mỗi biến thể.');
      return;
    }
    final quantities = Map<String, int>.of(cart);
    if (next <= 0) {
      quantities.remove(id);
    } else {
      quantities[id] = next;
    }
    try {
      quote(quantities, comboGroups);
    } catch (e) {
      message(e);
      return;
    }
    update(() {
      cart.clear();
      cart.addAll(quantities);
    });
  }

  Future<void> addCombo() async {
    if (busy) {
      return;
    }
    if (comboGroups.length >= 20) {
      message('Một giỏ có tối đa 20 nhóm combo.');
      return;
    }
    try {
      final group = await pickCombo(context, widget.service, products);
      if (group == null || !mounted) {
        return;
      }
      final quantities = Map<String, int>.of(cart);
      for (var i = 0; i < group.picks.length; i++) {
        final id = group.picks[i];
        quantities[id] =
            (quantities[id] ?? 0) +
            group.rule.parts[i].quantity * group.quantity;
      }
      if (quantities.values.any((n) => n > 100000)) {
        throw StateError(
          'Tách thành đơn nhỏ hơn: tối đa 100.000 món mỗi biến thể.',
        );
      }
      quote(quantities, [...comboGroups, group]);
      update(() {
        cart.clear();
        cart.addAll(quantities);
        comboGroups.add(group);
      });
      scanFocus.requestFocus();
    } catch (e) {
      message(e);
    }
  }

  void removeCombo(ComboSelection group) {
    update(() {
      comboGroups.remove(group);
      for (var i = 0; i < group.picks.length; i++) {
        final id = group.picks[i],
            remaining =
                (cart[id] ?? 0) - group.rule.parts[i].quantity * group.quantity;
        if (remaining <= 0) {
          cart.remove(id);
        } else {
          cart[id] = remaining;
        }
      }
    });
  }

  void scan(String code) {
    final matches = products
        .where((p) => p['barcode'] == code.trim() || p['sku'] == code.trim())
        .toList();
    if (matches.length == 1) {
      add(matches.single);
      search.clear();
      update(() => filter = '');
    } else {
      message('Không tìm thấy mã vạch $code.');
    }
    scanFocus.requestFocus();
  }

  Future<void> hold() async {
    if (reservationId != null) {
      message('Đang giao phiếu giữ hàng; quay lại danh sách để tiếp tục sau.');
      return;
    }
    if (cart.isEmpty) return;
    try {
      await widget.service.holdCart(
        items,
        'Đơn tạm ${DateFormat('HH:mm').format(DateTime.now())}',
        combos: comboGroups,
        existingId: heldId,
      );
      update(() {
        cart.clear();
        comboGroups.clear();
        heldId = null;
      });
      message('Đã giữ đơn tạm.');
    } catch (e) {
      message(e);
    }
  }

  Future<void> resume() async {
    if (reservationId != null) {
      message('Đang giao phiếu giữ hàng.');
      return;
    }
    final rows = await widget.service.db.rows(
      'SELECT * FROM held_carts WHERE store_id=? ORDER BY created_at DESC',
      [widget.service.storeId],
    );
    if (!mounted) return;
    final picked = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Đơn đang giữ tạm'),
        children: rows.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Chưa có đơn tạm.'),
                ),
              ]
            : [
                for (final row in rows)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, row),
                    child: Text('${row['name']} · ${row['created_at']}'),
                  ),
              ],
      ),
    );
    if (picked == null) return;
    if (cart.isNotEmpty) {
      message('Vui lòng giữ hoặc hoàn tất giỏ hiện tại trước.');
      return;
    }
    final payload = jsonDecode(picked['payload'] as String);
    final lines = payload is List ? payload : (payload as Map)['items'] as List;
    final groups = payload is Map
        ? (payload['combos'] as List? ?? [])
              .map(
                (v) => ComboSelection.fromJson(
                  Map<String, Object?>.from(v as Map),
                ),
              )
              .toList()
        : <ComboSelection>[];
    if (lines.any(
      (line) => !products.any((p) => p['id'] == line['variant_id']),
    )) {
      message('Đơn tạm có sản phẩm đã ngừng bán.');
      return;
    }
    update(() {
      for (final line in lines) {
        cart[line['variant_id'] as String] = line['quantity'] as int;
      }
      heldId = picked['id'] as String;
      comboGroups.addAll(groups);
    });
  }

  Future<void> checkout() async {
    if (cart.isEmpty || busy) return;
    busy = true;
    Map<String, List<Map<String, Object?>>> directory;
    List<CommercialRule> offers;
    List<Map<String, Object?>> dealers;
    try {
      directory = await widget.service.schoolDirectory();
      offers = (await widget.service.commercialRules(activeOnly: true))
          .map(CommercialRule.fromRow)
          .toList();
      dealers = await widget.service.db.rows(
        "SELECT id,name,phone FROM customers WHERE store_id=? AND kind='dealer' ORDER BY name",
        [widget.service.storeId],
      );
    } catch (e) {
      busy = false;
      message(e);
      return;
    }
    if (!mounted) {
      busy = false;
      return;
    }
    final activeSchools = directory['schools']!
        .where((r) => r['active'] == 1)
        .map((r) => r['id'])
        .toSet();
    final activeClasses = directory['classes']!
        .where(
          (r) => r['active'] == 1 && activeSchools.contains(r['school_id']),
        )
        .map((r) => r['id'])
        .toSet();
    final buyers = <Map<String, Object?>>[
      for (final dealer in dealers)
        {
          'label': 'Đại lý · ${dealer['name']}',
          'customer_id': dealer['id'],
          'name': dealer['name'],
          'phone': dealer['phone'],
        },
      for (final school in directory['schools']!.where((r) => r['active'] == 1))
        {
          'label': 'Đơn tập thể · ${school['name']}',
          'school_id': school['id'],
          'name': school['name'],
          'phone': school['phone'],
        },
      for (final student in directory['students']!.where(
        (r) => r['active'] == 1 && activeClasses.contains(r['class_id']),
      ))
        {
          'label':
              '${student['name']} · ${student['student_code']} · ${student['class_name']} · ${student['school_name']}',
          'student_id': student['id'],
          'school_id': student['school_id'],
          'name': student['parent_name'],
          'phone': student['phone'],
        },
    ];
    if (reservationBuyer != null) buyers.insert(0, reservationBuyer!);
    Map<String, Object?>? selectedBuyer = reservationBuyer;
    final buyerSearch = TextEditingController(), buyerFocus = FocusNode();
    final received = TextEditingController(text: '${subtotal - reduction}'),
        name = TextEditingController(
          text: reservationBuyer?['name'] as String? ?? '',
        ),
        phone = TextEditingController(
          text: reservationBuyer?['phone'] as String? ?? '',
        );
    var method = 'cash';
    String? failure;
    var saving = false;
    var pricingBusy = false, dialogOpen = true, quoteTicket = 0;
    var pricingInvalid = false;
    String? priceListId, promotionId;
    final voucher = TextEditingController();
    CommercialQuote? commercial;
    int payable() =>
        (commercial?.price.amount ?? subtotal) -
        reduction -
        (commercial?.promotionDiscount ?? 0);
    Future<void> reprice(StateSetter setDialog) async {
      final ticket = ++quoteTicket, previous = payable();
      setDialog(() {
        pricingBusy = true;
        failure = null;
      });
      try {
        final context = await widget.service.schoolSaleContext(
          schoolId: selectedBuyer?['school_id'] as String?,
          studentId: selectedBuyer?['student_id'] as String?,
          customerId: selectedBuyer?['customer_id'] as String?,
        );
        final result = await widget.service.commercialQuote(
          items: [
            for (final e in cart.entries)
              PricedItem(
                id: e.key,
                productId:
                    products.firstWhere((p) => p['id'] == e.key)['product_id']
                        as String,
                price:
                    products.firstWhere((p) => p['id'] == e.key)['sale_price']
                        as int,
                quantity: e.value,
              ),
          ],
          combos: comboGroups,
          context: context,
          priceListId: priceListId,
          promotionId: promotionId,
          voucher: voucher.text,
          manual: reduction,
        );
        if (!dialogOpen || !mounted || ticket != quoteTicket) return;
        setDialog(() {
          commercial = result;
          pricingBusy = false;
          pricingInvalid = false;
          if (int.tryParse(received.text) == previous) {
            received.text = '${payable()}';
          }
        });
      } catch (e) {
        if (dialogOpen && mounted && ticket == quoteTicket) {
          setDialog(() {
            pricingBusy = false;
            pricingInvalid = true;
            failure = e.toString().replaceFirst('Bad state: ', '');
          });
        }
      }
    }

    final commandId = widget.service.uuid.v7();
    SaleResult? sale;
    final checkoutRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Thanh toán'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _vnd.format(payable()),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff1763c0),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'cash',
                        label: Text('Tiền mặt'),
                        icon: Icon(Icons.payments_outlined),
                      ),
                      ButtonSegment(
                        value: 'bank',
                        label: Text('Chuyển khoản'),
                        icon: Icon(Icons.qr_code),
                      ),
                    ],
                    selected: {method},
                    onSelectionChanged: saving || pricingBusy
                        ? null
                        : (selection) =>
                              setDialog(() => method = selection.single),
                  ),
                  if (method == 'bank')
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: ListTile(
                        leading: Icon(Icons.qr_code_2, size: 42),
                        title: Text('QR chuyển khoản'),
                        subtitle: Text(
                          'Chưa cấu hình mã QR của cửa hàng. Chỉ ghi nhận tiền thực tế đã nhận.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: received,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Tiền đã nhận / đặt cọc (VND)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (buyers.isNotEmpty) ...[
                    Autocomplete<Map<String, Object?>>(
                      textEditingController: buyerSearch,
                      focusNode: buyerFocus,
                      displayStringForOption: (row) => row['label'] as String,
                      optionsBuilder: (value) {
                        final q = value.text.trim().toLowerCase();
                        return buyers
                            .where(
                              (r) =>
                                  q.isEmpty ||
                                  (r['label'] as String).toLowerCase().contains(
                                    q,
                                  ),
                            )
                            .take(30);
                      },
                      fieldViewBuilder: (context, controller, focus, submit) =>
                          TextField(
                            controller: controller,
                            focusNode: focus,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'Tìm học sinh / đơn tập thể',
                              helperText: 'Chọn kết quả để gắn hóa đơn.',
                            ),
                          ),
                      onSelected: (row) {
                        if (!saving) {
                          setDialog(() {
                            selectedBuyer = row;
                            name.text = row['name'] as String;
                            phone.text = row['phone'] as String;
                          });
                          reprice(setDialog);
                        }
                      },
                    ),
                    if (selectedBuyer != null)
                      InputChip(
                        label: Text(
                          'Đã chọn: ${selectedBuyer!['label']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: saving
                            ? null
                            : () => setDialog(() {
                                selectedBuyer = null;
                                buyerSearch.clear();
                                name.clear();
                                phone.clear();
                                reprice(setDialog);
                              }),
                      ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: name,
                    enabled: !saving && selectedBuyer == null,
                    decoration: const InputDecoration(
                      labelText: 'Tên khách (bắt buộc nếu còn nợ)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: phone,
                    enabled: !saving && selectedBuyer == null,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Điện thoại'),
                  ),
                  if (offers.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Bảng giá riêng',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Giá chung'),
                        ),
                        for (final rule in offers.where(
                          (r) => r.kind == 'price_list',
                        ))
                          DropdownMenuItem(
                            value: rule.id,
                            child: Text(
                              rule.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) {
                              priceListId = v!.isEmpty ? null : v;
                              reprice(setDialog);
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Khuyến mãi / voucher',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Không áp dụng'),
                        ),
                        for (final rule in offers.where(
                          (r) => r.kind == 'promotion',
                        ))
                          DropdownMenuItem(
                            value: rule.id,
                            child: Text(
                              rule.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) {
                              promotionId = v!.isEmpty ? null : v;
                              reprice(setDialog);
                            },
                    ),
                    TextField(
                      controller: voucher,
                      enabled: !saving,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Mã voucher',
                        helperText: 'Nhập đúng mã của chương trình đã chọn.',
                      ),
                      onChanged: (_) => reprice(setDialog),
                    ),
                    if (pricingBusy) const LinearProgressIndicator(),
                    if (commercial?.promotion != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Giảm khuyến mãi: ${_vnd.format(commercial!.promotionDiscount)}',
                        ),
                      ),
                  ],
                  if (failure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        failure!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: saving || pricingBusy || pricingInvalid
                  ? null
                  : () async {
                      setDialog(() {
                        saving = true;
                        failure = null;
                      });
                      try {
                        sale = await widget.service.sell(
                          items: items,
                          discount: reduction,
                          received: int.parse(received.text),
                          method: method,
                          customerName: name.text,
                          phone: phone.text,
                          commandId: commandId,
                          heldCartId: heldId,
                          studentId: selectedBuyer?['student_id'] as String?,
                          schoolId: selectedBuyer?['school_id'] as String?,
                          combos: comboGroups,
                          customerId: selectedBuyer?['customer_id'] as String?,
                          priceListId: priceListId,
                          promotionId: promotionId,
                          voucher: voucher.text,
                          expectedTotal: payable(),
                          reservationId: reservationId,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        setDialog(() {
                          failure = e.toString().replaceFirst(
                            'Bad state: ',
                            '',
                          );
                          saving = false;
                        });
                      }
                    },
              child: Text(saving ? 'Đang ghi nhận…' : 'Hoàn tất thanh toán'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(checkoutRoute);
    dialogOpen = false;
    quoteTicket++;
    await checkoutRoute.completed;
    voucher.dispose();
    received.dispose();
    name.dispose();
    phone.dispose();
    buyerSearch.dispose();
    buyerFocus.dispose();
    if (sale != null && mounted) {
      reservationId = null;
      reservationBuyer = null;
      final done = sale!;
      update(() {
        cart.clear();
        comboGroups.clear();
        heldId = null;
        discount.text = '0';
      });
      await load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 48,
          ),
          title: Text('Đã tạo ${done.code}'),
          content: Text(
            'Tổng tiền: ${_vnd.format(done.total)}\nĐã thu: ${_vnd.format(done.paid)}\nTiền thừa: ${_vnd.format(done.change)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đơn mới'),
            ),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await showInvoicePdf(context, widget.service, done.id);
                } catch (e) {
                  message(e);
                }
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Xem / lưu PDF'),
            ),
          ],
        ),
      );
    }
    scanFocus.requestFocus();
    busy = false;
  }

  Widget cartPanel() => Container(
    color: Colors.white,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Giỏ hàng',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(onPressed: resume, child: const Text('Đơn tạm')),
            IconButton(
              onPressed: busy ? null : addCombo,
              tooltip: 'Chọn combo',
              icon: const Icon(Icons.layers_outlined),
            ),
          ],
        ),
        const Divider(),
        if (reservationBuyer != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              reservationBuyer!['label'] as String,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xff1763c0),
              ),
            ),
          ),
        Expanded(
          child: cart.isEmpty
              ? const Center(
                  child: Text(
                    'Quét mã hoặc chọn sản phẩm\nđể bắt đầu bán hàng',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xff64748b)),
                  ),
                )
              : ListView(
                  children: [
                    for (final group in comboGroups)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InputChip(
                          label: Text(
                            '${group.rule.name} ×${group.quantity} · ${_vnd.format(group.rule.price * group.quantity)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () => removeCombo(group),
                          deleteIcon: const Icon(Icons.close),
                          deleteButtonTooltipMessage: 'Bỏ combo',
                        ),
                      ),
                    for (final e in cart.entries)
                      Builder(
                        builder: (context) {
                          final p = products.firstWhere(
                            (p) => p['id'] == e.key,
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['name'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${p['size']} · ${p['color']}',
                                  style: const TextStyle(
                                    color: Color(0xff64748b),
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () =>
                                          changeQuantity(e.key, -1),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                    Text('${e.value}'),
                                    IconButton(
                                      onPressed: () => changeQuantity(e.key, 1),
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _vnd.format(pricing.lines[e.key]!.amount),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
        const Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [const Text('Tiền hàng'), Text(_vnd.format(subtotal))],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: discount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => update(() {}),
          decoration: const InputDecoration(
            labelText: 'Giảm giá (VND)',
            prefixIcon: Icon(Icons.discount_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Tổng cộng',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  _vnd.format(subtotal - reduction),
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: Color(0xff1763c0),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: cart.isEmpty ? null : checkout,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Thanh toán · F9'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: cart.isEmpty ? null : hold,
            child: const Text('Giữ đơn tạm · F4'),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.f2): () =>
          scanFocus.requestFocus(),
      const SingleActivator(LogicalKeyboardKey.f4): hold,
      const SingleActivator(LogicalKeyboardKey.f9): checkout,
    },
    child: Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final visible = products
              .where(
                (p) =>
                    (category == 'Tất cả' || p['category'] == category) &&
                    ('${p['name']} ${p['sku']} ${p['barcode']} ${p['size']}'
                        .toLowerCase()
                        .contains(filter.toLowerCase())),
              )
              .toList();
          final shelf = Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bán hàng',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: search,
                  focusNode: scanFocus,
                  onChanged: (v) => update(() => filter = v),
                  onSubmitted: scan,
                  decoration: InputDecoration(
                    hintText: 'Quét mã vạch hoặc tìm sản phẩm · F2',
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    suffixIcon: IconButton(
                      onPressed: load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final name in [
                        'Tất cả',
                        ...products.map((p) => p['category'] as String).toSet(),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(name),
                            selected: category == name,
                            onSelected: (_) => update(() => category = name),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 225,
                          mainAxisExtent: 200,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final p = visible[index];
                      return Card(
                        color: Colors.white,
                        elevation: 0,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => add(p),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Expanded(
                                  child: Center(
                                    child: Icon(
                                      Icons.checkroom,
                                      size: 44,
                                      color: Color(0xff6c95cb),
                                    ),
                                  ),
                                ),
                                Text(
                                  p['name'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${p['size']} · ${p['color']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xff64748b),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _vnd.format(p['sale_price']),
                                  style: const TextStyle(
                                    color: Color(0xff1763c0),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Tồn: ${p['stock']} · Khả dụng máy: ${p['device_available']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
          if (c.maxWidth < 750) {
            return Column(
              children: [
                Expanded(child: shelf),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: openCart,
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: Text(
                        'Giỏ hàng (${cart.length}) · ${_vnd.format(subtotal - reduction)}',
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: shelf),
              SizedBox(width: 360, child: cartPanel()),
            ],
          );
        },
      ),
    ),
  );
}
