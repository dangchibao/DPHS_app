import 'package:material_ui/material_ui.dart';

import '../../core/sync/sync_engine.dart';

class SyncStatusBar extends StatelessWidget {
  const SyncStatusBar({super.key, this.engine});
  final SyncEngine? engine;
  @override
  Widget build(BuildContext context) {
    final sync = engine;
    Widget content() => ColoredBox(
      color: const Color(0xffeaf1fb),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            children: [
              Icon(
                sync?.status == SyncStatus.synced
                    ? Icons.cloud_done_outlined
                    : sync?.status == SyncStatus.syncing
                    ? Icons.sync
                    : Icons.cloud_off_outlined,
                size: 18,
                color: const Color(0xff536b8b),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Tooltip(
                  message: sync?.detail ?? 'Dữ liệu được lưu trên thiết bị',
                  child: Text(
                    '${sync?.label ?? 'Chưa kết nối cloud'}${sync == null ? '' : ' · ${sync.pending} thay đổi chờ gửi'}',
                    style: const TextStyle(color: Color(0xff536b8b)),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Đồng bộ ngay',
                onPressed: sync?.sync,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
    return sync == null
        ? content()
        : AnimatedBuilder(animation: sync, builder: (_, _) => content());
  }
}
