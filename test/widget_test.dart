import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanflow/main.dart';

void main() {
  testWidgets('ScanFlow app shell renders', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ScanFlowApp()));
    await tester.pump();

    expect(find.text('ScanFlow'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
