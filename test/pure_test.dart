import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/pure.dart';

void main() {
  test('distKm: same point is zero, Baghdad-Basra is about 450 km', () {
    expect(distKm(33.3, 44.4, 33.3, 44.4), closeTo(0, 0.001));
    final d = distKm(33.3152, 44.3661, 30.5085, 47.7835);
    expect(d, inInclusiveRange(440, 480));
  });

  test('asciiDigits converts Arabic-Indic digits', () {
    expect(asciiDigits('١٢٣٤٥٦٧٨٩٠'), '1234567890');
    expect(asciiDigits('abc ٥'), 'abc 5');
  });

  test('parseOffset and offsetStr round trip', () {
    expect(parseOffset('+03:00'), const Duration(hours: 3));
    expect(parseOffset('-05:30'), const Duration(hours: -5, minutes: -30));
    expect(parseOffset('bad'), isNull);
    expect(offsetStr(const Duration(hours: 3)), '+03:00');
    expect(offsetStr(const Duration(hours: -5, minutes: -30)), '-05:30');
  });

  test('splitTags trims, dedupes and caps at five', () {
    expect(splitTags('سفر، أكل, سفر ,  عيد'), ['سفر', 'أكل', 'عيد']);
    expect(splitTags('a,b,c,d,e,f,g').length, 5);
    expect(splitTags('thisistoolongtagname,ok'), ['ok']);
  });

  test('owedToPayer follows the split mode', () {
    expect(owedToPayer(100, 'equal'), 50);
    expect(owedToPayer(100, 'payer'), 0);
    expect(owedToPayer(100, 'other'), 100);
  });
}
