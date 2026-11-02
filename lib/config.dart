/// Where the Cloudflare Worker lives. Pass it at build time:
///   flutter run --dart-define=API_URL=https://purpose-money-api.<you>.workers.dev
const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8787');
