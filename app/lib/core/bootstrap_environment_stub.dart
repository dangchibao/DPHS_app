String? get bootstrapPassword => null;
String get apiBaseUrl => const String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8787',
);
