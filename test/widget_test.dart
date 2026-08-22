import 'package:flutter_test/flutter_test.dart';

import 'package:doc_manager/main.dart';

void main() {
  testWidgets('Home screen shows app title and new-folder action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DocManagerApp());
    await tester.pump();

    expect(find.text('Doc Manager'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
  });
}
