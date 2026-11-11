import 'package:discipline_personal_habit_tracker/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app loads the habit tracker home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DisciplineApp());
    await tester.pumpAndSettle();

    expect(find.text('Discipline'), findsOneWidget);
    expect(find.text('Trang chủ'), findsOneWidget);
  });
}
