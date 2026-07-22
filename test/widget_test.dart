// Smoke test de l'application Yélé.
//
// Vérifie simplement que l'app se construit et affiche l'écran de test complet.

import 'package:flutter_test/flutter_test.dart';

import 'package:yele/main.dart';

void main() {
  testWidgets('YeleApp se construit sans erreur', (WidgetTester tester) async {
    await tester.pumpWidget(const YeleApp());
    await tester.pump();

    // L'app démarre sur l'écran « Test complet ».
    expect(find.text('Test complet'), findsWidgets);
  });
}
