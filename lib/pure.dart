// دوال نقية (بدون واجهة ولا شبكة) تنختبر بـ flutter test
import 'dart:math' as math;

/// المسافة بالكيلومتر بين نقطتين (haversine)
double distKm(double la1, double ln1, double la2, double ln2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLa = rad(la2 - la1);
  final dLn = rad(ln2 - ln1);
  final a = math.pow(math.sin(dLa / 2), 2) +
      math.cos(rad(la1)) * math.cos(rad(la2)) * math.pow(math.sin(dLn / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}

/// يحوّل الأرقام العربية (٠-٩) لأرقام لاتينية
String asciiDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final c in s.split('')) {
    final i = ar.indexOf(c);
    b.write(i >= 0 ? '$i' : c);
  }
  return b.toString();
}

/// فرق التوقيت بصيغة +03:00 / -05:30
Duration? parseOffset(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final mins = int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
  return Duration(minutes: m.group(1) == '-' ? -mins : mins);
}

String offsetStr(Duration d) {
  final m = d.inMinutes.abs();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.isNegative ? '-' : '+'}${two(m ~/ 60)}:${two(m % 60)}';
}

/// وسوم مفصولة بفاصلة (عربية أو لاتينية) أو سطر جديد: بدون تكرار وبحد أقصى
List<String> splitTags(String s, {int max = 5, int maxLen = 14}) {
  final out = <String>[];
  for (final p in s.split(RegExp(r'[,،\n]'))) {
    final t = p.trim();
    if (t.isNotEmpty && t.length <= maxLen && !out.contains(t)) out.add(t);
    if (out.length >= max) break;
  }
  return out;
}

/// كم يرجّع الطرف الثاني للدافع حسب نمط التقسيم: equal نص نص، payer لي بس، other كله عليه
double owedToPayer(double amount, String mode) {
  switch (mode) {
    case 'other':
      return amount;
    case 'payer':
      return 0;
    default:
      return amount / 2;
  }
}
