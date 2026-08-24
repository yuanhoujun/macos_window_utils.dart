import 'package:flutter_test/flutter_test.dart';
import 'package:macos_window_utils/src/native_view_geometry.dart';

void main() {
  test('accepts finite native view geometry', () {
    expect(
      isValidNativeViewGeometry(
        x: -10,
        y: 20,
        width: 0,
        height: 30,
      ),
      isTrue,
    );
  });

  test('rejects non-finite coordinates and dimensions', () {
    expect(
      isValidNativeViewGeometry(
        x: double.nan,
        y: 0,
        width: 10,
        height: 10,
      ),
      isFalse,
    );
    expect(
      isValidNativeViewGeometry(
        x: 0,
        y: double.infinity,
        width: 10,
        height: 10,
      ),
      isFalse,
    );
    expect(
      isValidNativeViewGeometry(
        x: 0,
        y: 0,
        width: double.negativeInfinity,
        height: 10,
      ),
      isFalse,
    );
  });

  test('rejects negative dimensions', () {
    expect(
      isValidNativeViewGeometry(
        x: 0,
        y: 0,
        width: -1,
        height: 10,
      ),
      isFalse,
    );
    expect(
      isValidNativeViewGeometry(
        x: 0,
        y: 0,
        width: 10,
        height: -1,
      ),
      isFalse,
    );
  });
}
