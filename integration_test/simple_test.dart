import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:expolog/main.dart';
import 'package:expolog/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('App startet und zeigt Entsperr-Screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExpoLogApp());
    await tester.pumpAndSettle();
    expect(find.byType(ExpoLogApp), findsOneWidget);
  });
}
