class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  final String supabaseUrl;
  final String supabasePublishableKey;

  bool get hasSupabaseConfig =>
      supabaseUrl.startsWith('https://') && supabasePublishableKey.isNotEmpty;

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey:
          String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
  }
}
