import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dashboard/dashboard_page.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/business_sync_service.dart';
import 'company_setup_page.dart';

class BusinessWorkspacePage extends StatefulWidget {
  const BusinessWorkspacePage({super.key});

  @override
  State<BusinessWorkspacePage> createState() => _BusinessWorkspacePageState();
}

class _BusinessWorkspacePageState extends State<BusinessWorkspacePage> {
  late Future<List<Map<String, dynamic>>> _businesses;

  @override
  void initState() {
    super.initState();
    _businesses = _loadBusinesses();
  }

  Future<List<Map<String, dynamic>>> _loadBusinesses() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return [];
    final memberships = await client
        .from('business_members')
        .select('business_id, role')
        .eq('user_id', user.id);
    final ids = memberships
        .map((row) => row['business_id'] as String)
        .toList();
    if (ids.isEmpty) return [];
    return client
        .from('businesses')
        .select('id, name, legal_name, gstin, currency_code')
        .inFilter('id', ids)
        .order('name');
  }

  Future<void> _createBusiness() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CompanySetupPage(),
    );
    if (created == true && mounted) {
      setState(() => _businesses = _loadBusinesses());
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _openBusiness(Map<String, dynamic> business) async {
    final businessId = business['id'] as String?;
    if (businessId == null || businessId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business identifier is missing.')),
      );
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(business['name'] as String? ?? 'Business'),
        content: const Text(
          'This business will use its own offline database on this device. '
          'Your existing device-local data will remain separate. Supported '
          'cloud records are synchronised when a connection is available. '
          'Apply the required Supabase migrations in order before using cloud '
          'sync across devices. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    try {
      await AppDatabase.instance.openBusinessDatabase(businessId);
      try {
        final result = await BusinessSyncService(
          businessId: businessId,
        ).syncNow();
        if (mounted &&
            (result.uploaded > 0 ||
                result.downloaded > 0 ||
                result.uploadFailures > 0 ||
                result.downloadFailures > 0)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sync: ${result.uploaded} uploaded, '
                '${result.downloaded} downloaded, '
                '${result.uploadFailures + result.downloadFailures} failed.',
              ),
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cloud sync unavailable. Your local data is preserved. $error',
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const DashboardPage(cloudConfigured: true),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open this business database: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Choose a business'),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _businesses,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load your businesses.'),
                      const SizedBox(height: 8),
                      Text(snapshot.error.toString(), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => setState(() => _businesses = _loadBusinesses()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final businesses = snapshot.data ?? [];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  shrinkWrap: true,
                  children: [
                    Text(
                      'Your businesses',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    if (businesses.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No business is linked to this account yet. Create your first business to continue.',
                          ),
                        ),
                      ),
                    for (final business in businesses)
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.store)),
                          title: Text(business['name'] as String? ?? 'Business'),
                          subtitle: Text([
                            if ((business['legal_name'] as String? ?? '').isNotEmpty)
                              business['legal_name'] as String,
                            if ((business['gstin'] as String? ?? '').isNotEmpty)
                              'GSTIN: ${business['gstin']}',
                          ].join(' • ')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openBusiness(business),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _createBusiness,
                      icon: const Icon(Icons.add_business),
                      label: const Text('Create a business'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}
