import 'package:flutter_test/flutter_test.dart';
import 'package:seven/main.dart';

void main() {
  test('HexaApp instantiation test', () {
    const app = HexaApp();
    expect(app, isA<HexaApp>());
  });
}
