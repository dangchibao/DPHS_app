import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/auth/login_page.dart';
import 'features/auth/session_boundary.dart';
import 'features/shell/sync_status_bar.dart';
import 'features/shell/workspace.dart';
import 'features/web/web_portal.dart';

void main() => runApp(const ProviderScope(child: NgocThanhApp()));

class NgocThanhApp extends StatelessWidget {
  const NgocThanhApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Đồng phục Ngọc Thanh',
    locale: const Locale('vi', 'VN'),
    supportedLocales: const [Locale('vi', 'VN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) {
      // printing còn dùng Flutter Material cũ; bridge theo hướng dẫn material_ui.
      // ignore: deprecated_member_use
      return MaterialUiCompatibilityBridge(
        child: AppSyncFrame(child: child ?? const SizedBox()),
      );
    },
    theme: ThemeData(
      fontFamily: 'NotoSans',
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1763c0)),
      scaffoldBackgroundColor: const Color(0xfff4f7fb),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: const AppRoot(),
  );
}

class AppSyncFrame extends ConsumerWidget {
  const AppSyncFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return child;
    }
    final service = ref.watch(localServiceProvider).asData?.value;
    return Overlay.wrap(
      child: Column(
        children: [
          Expanded(child: child),
          SyncStatusBar(engine: service?.syncEngine),
        ],
      ),
    );
  }
}

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});
  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  bool loggedIn = false;
  bool loggingOut = false;
  @override
  Widget build(BuildContext context) {
    if (loggingOut) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (kIsWeb) {
      return const WebPortal();
    }
    return ref
        .watch(localServiceProvider)
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText('Không mở được dữ liệu: $error'),
              ),
            ),
          ),
          data: (service) => SessionBoundary(
            service: service,
            active: loggedIn,
            builder: (context) =>
                loggedIn &&
                    service.session?.expiresAt.isAfter(service.clock()) == true
                ? Workspace(
                    service: service,
                    onReload: () {
                      setState(() => loggedIn = false);
                      ref.invalidate(localServiceProvider);
                    },
                    onLogout: () async {
                      service.session = null;
                      setState(() {
                        loggedIn = false;
                        loggingOut = true;
                      });
                      try {
                        await service.syncEngine?.pauseAndDrain();
                        await service.syncEngine?.api.logout();
                      } finally {
                        if (mounted) setState(() => loggingOut = false);
                      }
                    },
                  )
                : LoginPage(
                    service: service,
                    onReconfigure: () {
                      setState(() => loggedIn = false);
                      ref.invalidate(localServiceProvider);
                    },
                    onLogin: (_) => setState(() => loggedIn = true),
                  ),
          ),
        );
  }
}
