import 'dart:io';

String? get bootstrapPassword => Platform.environment['BOOTSTRAP_PASSWORD'];
String get apiBaseUrl =>
    Platform.environment['API_BASE_URL'] ??
    (const String.fromEnvironment('API_BASE_URL').isNotEmpty
        ? const String.fromEnvironment('API_BASE_URL')
        : null) ??
    (Platform.isAndroid ? 'http://10.0.2.2:8787' : 'http://127.0.0.1:8787');
