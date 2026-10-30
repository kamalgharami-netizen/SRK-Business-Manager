import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/app.dart';
import 'package:srk_business_manager/src/config/app_config.dart';

void main() {
  testWidgets('SRK Business Manager starts and shows dashboard', (tester) async {
    const config = AppConfig(
      supabaseUrl: '',
      supabasePublishableKey: '',
    );

    await tester.pumpWidget(const SrkBusinessManagerApp(config: config));

    expect(find.text('SRK Business Manager'), findsOneWidget);
    expect(find.text('Business overview'), findsOneWidget);
    expect(find.text('Sales & Invoices'), findsOneWidget);
  });
}
