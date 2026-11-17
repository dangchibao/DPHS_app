import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/local_service.dart';

/// Khi phiên/quyền đổi, đóng các route cũ để không giữ màn dữ liệu nhạy cảm.
class SessionBoundary extends StatefulWidget {
  const SessionBoundary({
    super.key,
    required this.service,
    required this.active,
    required this.builder,
  });
  final LocalService service;
  final bool active;
  final WidgetBuilder builder;
  @override
  State<SessionBoundary> createState() => _SessionBoundaryState();
}

class _SessionBoundaryState extends State<SessionBoundary> {
  String scope = '';
  Timer? timer;
  String readScope() {
    final session = widget.service.session;
    if (session == null || !session.expiresAt.isAfter(widget.service.clock())) {
      return '';
    }
    return '${session.userId}|${session.storeId}|${session.deviceId}|${session.role.name}';
  }

  @override
  void initState() {
    super.initState();
    scope = readScope();
    widget.service.syncEngine?.addListener(check);
    timer = Timer.periodic(const Duration(seconds: 30), (_) => check());
  }

  @override
  void didUpdateWidget(covariant SessionBoundary old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      old.service.syncEngine?.removeListener(check);
      widget.service.syncEngine?.addListener(check);
      scope = readScope();
    }
    if (!old.active && widget.active) {
      scope = readScope();
    }
  }

  void check() {
    if (!mounted || !widget.active) {
      return;
    }
    final current = readScope();
    if (current == scope) {
      return;
    }
    setState(() => scope = current);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.service.syncEngine?.removeListener(check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
