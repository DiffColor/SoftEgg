import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_egg_packager/src/app/soft_egg_app.dart';

void main() {
  testWidgets('step 1 gateway 기본 렌더링', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const SoftEggApp());

    expect(find.text('SoftEgg'), findsOneWidget);
    expect(find.text('Partner Access Gateway'), findsOneWidget);
    expect(find.text('Authorize Access'), findsOneWidget);
  });
}
