part of 'main.dart';

// ثوابت التصميم الموحدة: أحجام الخطوط والمسافات.
// نستخدمها بدل الأرقام المتفرقة حتى يبقى شكل الشاشات متناسق، وأي تعديل يصير بمكان واحد.

/// أحجام الخطوط
class _Fs {
  _Fs._();
  static const double caption = 11; // ملاحظات صغيرة جداً
  static const double small = 12; // وقت، حالة، شرح صغير
  static const double meta = 13; // نص ثانوي
  static const double body = 14; // نص عادي
  static const double bodyL = 15; // نص مقروء أكبر
  static const double title = 16; // عنوان فرعي
  static const double titleL = 17; // اسم، عنوان بطاقة
  static const double heading = 18; // عنوان قسم
  static const double display = 20; // عنوان شاشة
  static const double big = 24; // رقم أو إيموجي كبير
}

/// المسافات (من مضاعفات 4)
class _Sp {
  _Sp._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}
