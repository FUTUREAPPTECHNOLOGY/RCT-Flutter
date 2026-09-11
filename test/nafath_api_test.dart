import 'package:flutter_test/flutter_test.dart';
import 'package:rct/view-model/services/nafath_api.dart';

void main() {
  group('NafathApi', () {
    test('can be instantiated and exposes a status check method', () {
      final api = NafathApi();
      expect(api, isA<NafathApi>());
      expect(api.checkStatus, isA<Function>());
    });
  });
}
