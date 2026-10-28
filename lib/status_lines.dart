part of 'main.dart';

// ---------- جمل حالة الاتصال تحت اسم الطرف الثاني ----------
// الجمل المخصصة تنعرض إذا الجنسين مختلفين. إذا نفس الجنس أو غير معروف، تنعرض جمل محايدة.
// لتعديل أي جملة: غيّر النص داخل علامات التنصيص فقط.

/// الصيغة العربية حسب العدد: دقيقة، دقيقتين، 3 دقايق، 11 دقيقة
String _countAr(int n, String one, String two, String few, String many) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n >= 3 && n <= 10) return '$n $few';
  return '$n $many';
}

/// قائمة الجمل المتاحة للحالة الحالية (إذا فيها أكثر من جملة تتبدل كل 4 ثواني)
List<String> statusLines({
  required bool online,
  required double? age,
  required String? readerGender,
  required String? partnerGender,
}) {
  final mixed = (readerGender == 'male' && partnerGender == 'female') ||
      (readerGender == 'female' && partnerGender == 'male');
  final reader = readerGender == 'male'; // القارئ ذكر؟

  // 1) متصل الآن
  if (online) {
    if (!mixed) return ['متصل الآن'];
    return [reader ? 'موجودة وياك' : 'موجود وياج'];
  }
  // 6) أخفى حالته
  if (age == null) {
    if (!mixed) return ['الحالة مخفية'];
    return [reader ? 'متثق بيك' : 'ميثق بيج'];
  }
  // 2) طلع قبل لحظات
  if (age < 90) {
    if (!mixed) return ['آخر ظهور قبل لحظات'];
    return [reader ? 'شوفها وين طمست' : 'شوفيه وين طمس'];
  }
  final mins = (age / 60).floor();
  final hours = (mins / 60).floor();
  final days = (hours / 24).floor();

  // 3) قبل X دقايق (الوقت + جملتك يتبدلون)
  if (mins < 60) {
    final time =
        'آخر ظهور قبل ${_countAr(mins, 'دقيقة', 'دقيقتين', 'دقايق', 'دقيقة')}';
    if (!mixed) return [time];
    return [time, reader ? 'يمكن علستك' : 'يمكن علسج'];
  }
  // 4) قبل X ساعات
  if (hours < 24) {
    final time =
        'آخر ظهور قبل ${_countAr(hours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}';
    if (!mixed) return [time];
    return [time, reader ? 'ناسيتك' : 'نساج'];
  }
  // 5) قبل X أيام
  final time = 'آخر ظهور قبل ${_countAr(days, 'يوم', 'يومين', 'أيام', 'يوم')}';
  if (!mixed) return [time];
  return [
    time,
    reader ? 'بعد حتى بليوتيوب ما تشوفها' : 'بعد حتى بليوتيوب ما تشوفينه',
  ];
}
