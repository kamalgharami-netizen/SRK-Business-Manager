import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'features/auth/cloud_auth_gate.dart';
import 'features/dashboard/dashboard_page.dart';

class SrkBusinessManagerApp extends StatelessWidget {
  const SrkBusinessManagerApp({super.key, required this.config});
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SRK Business Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2457A7)),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      home: config.hasSupabaseConfig
          ? const CloudAuthGate()
          : const DashboardPage(cloudConfigured: false),
    );
  }
}
