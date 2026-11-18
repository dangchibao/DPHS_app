import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/sync/cloud_api.dart';

Uint8List compressAuditSource(Uint8List source) =>
    Uint8List.fromList(GZipEncoder().encode(source));

class AuditArchivesPage extends StatefulWidget {
  const AuditArchivesPage({
    super.key,
    required this.api,
    required this.storeId,
    this.canArchive = false,
  });
  final CloudApi api;
  final String storeId;
  final bool canArchive;
  @override
  State<AuditArchivesPage> createState() => _AuditArchivesPageState();
}

class _AuditArchivesPageState extends State<AuditArchivesPage> {
  List<Map<String, dynamic>> rows = [], devices = [];
  String? device, error;
  int direction = 1, retention = 90;
  bool busy = false, enabled = false, more = false, moreDevices = false;
  String cursor = '', deviceCursor = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool next = false, bool nextDevices = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final q = Uri(
        queryParameters: {
          'store': widget.storeId,
          if (next) 'cursor': cursor,
          if (nextDevices) 'device_cursor': deviceCursor,
        },
      ).query;
      final data = await widget.api.send('/audit/archives?$q');
      if (mounted) {
        setState(() {
          rows = (data['rows'] as List).cast<Map<String, dynamic>>();
          devices = (data['devices'] as List).cast<Map<String, dynamic>>();
          if (!devices.any((d) => d['id'] == device)) {
            device = devices.firstOrNull?['id'] as String?;
          }
          deviceCursor = data['device_cursor'] as String? ?? '';
          moreDevices = data['more_devices'] == true;
          cursor = data['cursor'] as String;
          more = data['has_more'] == true;
          enabled = data['enabled'] == true;
          retention = data['retention_days'] as int;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> process([Map<String, dynamic>? existing]) async {
    if (busy ||
        !widget.canArchive ||
        !enabled ||
        device == null && existing == null) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = existing?['id'] as String? ?? const Uuid().v7();
      final prepared = await widget.api.send(
        '/audit/archives',
        body: {
          'action': 'prepare',
          'id': id,
          'store_id': widget.storeId,
          'device_id': existing?['device_id'] ?? device,
          'direction': existing?['direction'] ?? direction,
        },
      );
      if (prepared['status'] == 'committed') return;
      if (prepared['status'] == 'cancelled') throw StateError('Lô đã hủy.');
      final manifest = Map<String, dynamic>.from(prepared['manifest'] as Map);
      if (manifest['status'] == 'prepared') {
        final bytes = base64Decode(prepared['source_base64'] as String);
        if (bytes.length > 192000 ||
            bytes.length != manifest['source_bytes'] ||
            sha256.convert(bytes).toString() != manifest['source_hash']) {
          throw StateError('Nguồn cloud sai checksum/kích thước.');
        }
        final compressed = await compute(compressAuditSource, bytes);
        await widget.api.archiveBytes(id, upload: compressed);
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lưu trữ log cũ đã xác minh'),
          content: Text(
            '${manifest['record_count']} log · cửa hàng ${widget.storeId}\nThiết bị ${manifest['device_id']} · từ ${manifest['first_index']} đến ${manifest['last_index']}\n\nFile gzip đã được cloud kiểm tra và đọc lại từ kho private. Hoàn tất sẽ giữ manifest/checkpoint và chuyển phần chi tiết cũ ra khỏi D1. Log gần đây và dữ liệu bán hàng vẫn được giữ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hoàn tất lưu trữ'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        final ack = await widget.api.send(
          '/audit/archives',
          body: {'action': 'commit', 'id': id, 'confirmed': true},
        );
        if (ack['id'] != id || ack['committed'] != true) {
          throw StateError('Cloud chưa xác nhận hoàn tất.');
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await refreshPreservingError();
      }
    }
  }

  Future<void> refreshPreservingError() async {
    final previous = error;
    await load();
    if (previous != null && mounted) setState(() => error = previous);
  }

  Future<void> download(Map<String, dynamic> row) async {
    if (busy) return;
    setState(() => busy = true);
    final token = widget.api.token;
    try {
      final data = await widget.api.archiveBytes(row['id'] as String);
      if (data.length != row['gzip_bytes'] ||
          sha256.convert(data).toString() != row['gzip_hash']) {
        throw StateError('File tải về sai checksum.');
      }
      if (!mounted || widget.api.token != token) return;
      await FilePicker.saveFile(
        fileName: 'audit-${row['id']}.json.gz',
        bytes: data,
        mimeType: 'application/gzip',
        dialogTitle: 'Lưu kho nhật ký',
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel(Map<String, dynamic> row) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hủy lô đang chờ'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Lý do bắt buộc'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hủy lô'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && reason.text.trim().isNotEmpty) {
      setState(() => busy = true);
      try {
        await widget.api.send(
          '/audit/archives',
          body: {
            'action': 'cancel',
            'id': row['id'],
            'reason': reason.text.trim(),
          },
        );
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      } finally {
        if (mounted) {
          setState(() => busy = false);
          await refreshPreservingError();
        }
      }
    }
    reason.dispose();
  }

  String status(Object? value) => switch (value) {
    'prepared' => 'Chờ file',
    'verified' => 'Đã xác minh file',
    'committed' => 'Đã lưu trữ',
    'cancelled' => 'Đã hủy',
    _ => value.toString(),
  };
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Text(
        'Kho nhật ký · ${widget.storeId} · Giữ gần đây $retention ngày theo thời điểm lên cloud.',
      ),
      const Text(
        'File private có checksum; không phải bản sao lưu toàn bộ dữ liệu. Dữ liệu trên thiết bị chưa đồng bộ không nằm trong kho này.',
      ),
      if (!enabled)
        const Text(
          'Chưa cấu hình kho R2 private. Không có log nào được tự giảm trong D1.',
        ),
      const SizedBox(height: 16),
      if (widget.canArchive)
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                key: ValueKey(devices.firstOrNull?['id']),
                initialValue: device,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Thiết bị có chain cần lưu trữ',
                ),
                items: [
                  for (final d in devices)
                    DropdownMenuItem(
                      value: d['id'] as String,
                      child: Text('${d['code']} · ${d['name']}'),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => device = v),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                initialValue: direction,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Log ứng dụng')),
                  DropdownMenuItem(value: -1, child: Text('Log API')),
                ],
                onChanged: busy ? null : (v) => setState(() => direction = v!),
              ),
            ),
            FilledButton(
              onPressed: !busy && enabled ? () => process() : null,
              child: const Text('Chuẩn bị lô log cũ'),
            ),
          ],
        ),
      if (moreDevices)
        TextButton(
          onPressed: busy ? null : () => load(nextDevices: true),
          child: const Text('Nhóm thiết bị tiếp'),
        ),
      TextButton(
        onPressed: busy ? null : () => load(),
        child: const Text('Tải lại'),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      for (final row in rows)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${status(row['status'])} · ${row['record_count']} log · ${row['device_id']}',
                ),
                Text(
                  '${row['first_index']} → ${row['last_index']} · ${row['created_at']}',
                ),
                SelectableText('SHA256 nguồn: ${row['source_hash']}'),
                Wrap(
                  spacing: 8,
                  children: [
                    if (['verified', 'committed'].contains(row['status']))
                      OutlinedButton(
                        onPressed: busy ? null : () => download(row),
                        child: const Text('Tải file gzip'),
                      ),
                    if (widget.canArchive &&
                        ['prepared', 'verified'].contains(row['status'])) ...[
                      FilledButton(
                        onPressed: busy ? null : () => process(row),
                        child: const Text('Tiếp tục / hoàn tất'),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => cancel(row),
                        child: const Text('Hủy lô'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      if (more)
        OutlinedButton(
          onPressed: busy ? null : () => load(next: true),
          child: const Text('Trang tiếp'),
        ),
    ],
  );
}
