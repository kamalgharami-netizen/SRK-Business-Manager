import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'business_workspace_page.dart';
import 'cloud_auth_page.dart';

class CloudAuthGate extends StatelessWidget {
  const CloudAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (client.auth.currentSession == null) {
          return const CloudAuthPage();
        }
        return const BusinessWorkspacePage();
      },
    );
  }
}
