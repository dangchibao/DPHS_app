import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../core/local_service.dart';
import '../../core/auth/permissions.dart';
import 'school_service.dart';

class SchoolsPage extends StatefulWidget {
  const SchoolsPage({super.key, required this.service});
  final LocalService service;
  @override
  State<SchoolsPage> createState() => _SchoolsPageState();
}

class _SchoolsPageState extends State<SchoolsPage> {
  late Future<Map<String, List<Map<String, Object?>>>> data;
  int tab = 0;
  String search = '';
  static const keys = ['schools', 'classes', 'students'],
      labels = ['Trường', 'Lớp', 'Học sinh'];
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    data = widget.service.schoolDirectory();
  }

  Future<void> edit(
    Map<String, List<Map<String, Object?>>> directory, [
    Map<String, Object?>? row,
  ]) async {
    final editingTab = tab;
    final name = TextEditingController(text: row?['name'] as String? ?? ''),
        code = TextEditingController(
          text: row?['student_code'] as String? ?? '',
        ),
        parent = TextEditingController(
          text: row?['parent_name'] as String? ?? '',
        ),
        phone = TextEditingController(text: row?['phone'] as String? ?? ''),
        year = TextEditingController(
          text: row?['academic_year'] as String? ?? '2026–2027',
        );
    var level = row?['level'] as String? ?? 'Tiểu học',
        active = row?['active'] != 0,
        saving = false;
    String? school = row?['school_id'] as String?,
        schoolClass = row?['class_id'] as String?,
        error;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Text(
              '${row == null ? 'Thêm' : 'Cập nhật'} ${labels[editingTab].toLowerCase()}',
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      enabled: !saving,
                      decoration: InputDecoration(
                        labelText: editingTab == 2
                            ? 'Họ tên học sinh'
                            : 'Tên ${labels[editingTab].toLowerCase()}',
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (editingTab == 0)
                      DropdownButtonFormField<String>(
                        initialValue: level,
                        decoration: const InputDecoration(labelText: 'Cấp học'),
                        items: [
                          for (final value in [
                            'Mầm non',
                            'Tiểu học',
                            'THCS',
                            'THPT',
                          ])
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: saving ? null : (v) => level = v!,
                      ),
                    if (editingTab == 1) ...[
                      DropdownButtonFormField<String>(
                        initialValue: school,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Trường'),
                        items: [
                          for (final s in directory['schools']!)
                            DropdownMenuItem(
                              value: s['id'] as String,
                              child: Text(
                                '${s['name']}${s['active'] == 0 ? ' (ngừng theo dõi)' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: saving ? null : (v) => school = v,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: year,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Niên khóa',
                        ),
                      ),
                    ],
                    if (editingTab == 2) ...[
                      TextField(
                        controller: code,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Mã học sinh (không trùng)',
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: schoolClass,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Lớp / niên khóa',
                        ),
                        items: [
                          for (final cl in directory['classes']!)
                            DropdownMenuItem(
                              value: cl['id'] as String,
                              child: Text(
                                '${cl['name']} · ${cl['academic_year']} · ${cl['school_name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: saving ? null : (v) => schoolClass = v,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: parent,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Tên phụ huynh',
                        ),
                      ),
                    ],
                    if (editingTab != 1) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: phone,
                        enabled: !saving,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: editingTab == 0
                              ? 'Điện thoại liên hệ trường'
                              : 'Điện thoại phụ huynh',
                        ),
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Đang theo dõi'),
                      value: active,
                      onChanged: saving
                          ? null
                          : (v) => setDialog(() => active = v),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog),
                child: const Text('Đóng'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialog(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final id = row?['id'] as String?;
                          if (editingTab == 0) {
                            await widget.service.saveSchool(
                              id: id,
                              name: name.text,
                              level: level,
                              phone: phone.text,
                              active: active,
                            );
                          }
                          if (editingTab == 1) {
                            if (school == null) {
                              throw ArgumentError('Chọn trường trước.');
                            }
                            await widget.service.saveClass(
                              id: id,
                              schoolId: school!,
                              name: name.text,
                              year: year.text,
                              active: active,
                            );
                          }
                          if (editingTab == 2) {
                            if (schoolClass == null) {
                              throw ArgumentError('Chọn lớp trước.');
                            }
                            await widget.service.saveStudent(
                              id: id,
                              classId: schoolClass!,
                              code: code.text,
                              name: name.text,
                              parentName: parent.text,
                              phone: phone.text,
                              active: active,
                            );
                          }
                          if (dialog.mounted) {
                            Navigator.pop(dialog);
                          }
                          if (mounted) {
                            setState(refresh);
                          }
                        } catch (e) {
                          if (dialog.mounted) {
                            setDialog(() {
                              error = e.toString().contains('UNIQUE constraint')
                                  ? 'Mã học sinh đã được sử dụng.'
                                  : e.toString().replaceFirst(
                                      'Bad state: ',
                                      '',
                                    );
                              saving = false;
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Đang lưu…' : 'Lưu'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      code.dispose();
      parent.dispose();
      phone.dispose();
      year.dispose();
    }
  }

  Future<void> history(Map<String, Object?> student) async {
    try {
      final rows = await widget.service.studentHistory(student['id'] as String);
      if (!mounted) {
        return;
      }
      final money = NumberFormat.currency(
        locale: 'vi_VN',
        symbol: '₫',
        decimalDigits: 0,
      );
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Lịch sử mua · ${student['name']}'),
          content: SizedBox(
            width: 560,
            height: 380,
            child: rows.isEmpty
                ? const Center(child: Text('Chưa có hóa đơn gắn với học sinh.'))
                : ListView(
                    children: [
                      for (final d in rows)
                        ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text(
                            '${d['code']} · ${money.format(d['total'])}',
                          ),
                          subtitle: Text(
                            '${d['issued_at']} · ${d['school_year']}',
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: FutureBuilder(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final directory = snapshot.data!,
            rows = directory[keys[tab]]!
                .where(
                  (r) => r.values
                      .join(' ')
                      .toLowerCase()
                      .contains(search.toLowerCase()),
                )
                .toList();
        final canEdit =
            widget.service.session?.can(Permission.catalog) ?? false;
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: [
                      for (var i = 0; i < labels.length; i++)
                        ButtonSegment(value: i, label: Text(labels[i])),
                    ],
                    selected: {tab},
                    onSelectionChanged: (v) => setState(() => tab = v.single),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(refresh),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Tìm tên / lớp / trường / điện thoại',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => edit(directory),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('Chưa có dữ liệu phù hợp.'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final r = rows[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              tab == 0
                                  ? Icons.school
                                  : tab == 1
                                  ? Icons.meeting_room
                                  : Icons.person_outline,
                            ),
                            title: Text(
                              '${r['name']}${r['active'] == 0 ? ' · Ngừng theo dõi' : ''}',
                            ),
                            subtitle: Text(
                              tab == 0
                                  ? '${r['level']} · ${r['phone']}'
                                  : tab == 1
                                  ? '${r['school_name']} · ${r['academic_year']}'
                                  : '${r['student_code']} · ${r['class_name']} · ${r['school_name']}\nPhụ huynh: ${r['parent_name']} · ${r['phone']}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (tab == 2)
                                  IconButton(
                                    onPressed: () => history(r),
                                    tooltip: 'Lịch sử mua',
                                    icon: const Icon(Icons.history),
                                  ),
                                if (canEdit)
                                  IconButton(
                                    onPressed: () => edit(directory, r),
                                    tooltip: 'Chỉnh sửa',
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
