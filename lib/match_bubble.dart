part of 'main.dart';

// ---------- البحث عن شريك: فقاعة زجاجية مرنة (ذكر مع أنثى فقط، والمطابقة بالسيرفر) ----------

class _MatchBubble extends StatefulWidget {
  const _MatchBubble({required this.onMatched});

  /// تنادى لما الطرفين يقبلون وتنشأ المحادثة
  final Future<void> Function() onMatched;

  @override
  State<_MatchBubble> createState() => _MatchBubbleState();
}

class _MatchBubbleState extends State<_MatchBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));
  Timer? _beat;
  bool _searching = false;
  bool _busy = false;
  bool _offerOpen = false;

  @override
  void dispose() {
    _beat?.cancel();
    _pulse.dispose();
    if (_searching) unawaited(_cancelQuietly());
    super.dispose();
  }

  Future<void> _cancelQuietly() async {
    try {
      await _db.rpc('match_cancel');
    } catch (_) {}
  }

  void _stopSearch() {
    _beat?.cancel();
    _beat = null;
    _pulse.stop();
    _pulse.reset();
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_searching) {
      _stopSearch();
      await _cancelQuietly();
      return;
    }
    setState(() => _busy = true);
    final ok = await _step();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    if (!_searching && !_offerOpen) {
      setState(() => _searching = true);
      unawaited(_pulse.repeat());
    }
    _beat ??= Timer.periodic(const Duration(seconds: 6), (_) {
      if (_searching && !_offerOpen) unawaited(_step());
    });
  }

  /// خطوة بحث وحدة. ترجع false إذا صار خطأ يوقف البحث.
  Future<bool> _step() async {
    try {
      final r = await _db.rpc('match_start');
      final res = Map<String, dynamic>.from(r as Map);
      if (res['status'] == 'offer') {
        await _showOffer((res['offer_id'] as num).toInt());
      }
      return true;
    } on PostgrestException catch (e) {
      final m = e.message;
      if (m.contains('already_paired')) {
        _stopSearch();
        await widget.onMatched();
        return false;
      }
      _stopSearch();
      if (!mounted) return false;
      if (m.contains('under_18')) {
        _toast(context, 'البحث عن شريك للي عمرهم 18 سنة وفوق. تقدر ترتبط برمز دعوة.');
      } else if (m.contains('profile_incomplete')) {
        _toast(context, 'كمّل ملفك (الاسم وتاريخ الميلاد) أولاً.');
      } else if (m.contains('daily_limit')) {
        _toast(context, 'وصلت حد البحث اليوم (10 مرات). جرّب باچر.');
      } else if (m.contains('function') || m.contains('match_start')) {
        _toast(context, 'البحث غير مفعّل بالسيرفر بعد.');
      } else {
        _toast(context, 'تعذر البحث، جرّب مرة ثانية.');
      }
      return false;
    } catch (_) {
      if (mounted && !_searching) _toast(context, 'تعذر الاتصال بالسيرفر.');
      return _searching;
    }
  }

  Future<void> _showOffer(int offerId) async {
    if (_offerOpen || !mounted) return;
    _offerOpen = true;
    _pulse.stop();
    final res = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OfferDialog(offerId: offerId),
    );
    _offerOpen = false;
    if (!mounted) return;
    if (res == 'accepted') {
      _stopSearch();
      await widget.onMatched();
      return;
    }
    if (res == 'declined' || res == 'expired') {
      _toast(
          context,
          res == 'declined'
              ? 'ما تمت المطابقة. نكمل البحث...'
              : 'انتهى الوقت. نكمل البحث...');
    }
    if (_searching) {
      unawaited(_pulse.repeat());
      unawaited(_step());
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: _searching ? 'إلغاء البحث' : 'ابحث لي عن شريك',
            child: _Press(
              onTap: _busy ? null : _toggle,
              dimWhenOff: false,
              scale: 0.86,
              child: SizedBox(
                width: 190,
                height: 190,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) {
                    final v = _pulse.value;
                    final breathe =
                        _searching ? 1 + 0.04 * math.sin(v * 2 * math.pi) : 1.0;
                    return Stack(alignment: Alignment.center, children: [
                      if (_searching) ...[
                        _ring(v),
                        _ring((v + 0.5) % 1),
                      ],
                      Transform.scale(scale: breathe, child: child),
                    ]);
                  },
                  child: _orb(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _searching
                  ? 'جاري البحث... اضغط للإلغاء'
                  : 'ابحث لي عن شريك',
              key: ValueKey<bool>(_searching),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );

  /// موجة تتمدد وتختفي حول الفقاعة وقت البحث
  Widget _ring(double v) => Opacity(
        opacity: (1 - v).clamp(0.0, 1.0) * 0.7,
        child: Container(
          width: 130 + 60 * v,
          height: 130 + 60 * v,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFF7EB6), width: 2),
          ),
        ),
      );

  /// الفقاعة نفسها: زجاج دائري بلمعة وتوهج
  Widget _orb() => Container(
        width: 136,
        height: 136,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.35, -0.45),
            radius: 0.95,
            colors: [Color(0x99FFFFFF), Color(0x40FF7EB6), Color(0x2E7A5CFF)],
            stops: [0, 0.45, 1],
          ),
          border: Border.all(color: const Color(0x99FFFFFF), width: 1.2),
          boxShadow: const [
            BoxShadow(color: Color(0x66FF5FA2), blurRadius: 36, spreadRadius: 2),
          ],
        ),
        child: Stack(alignment: Alignment.center, children: [
          // لمعة صغيرة فوق يسار
          Positioned(
            top: 18,
            left: 28,
            child: Container(
              width: 34,
              height: 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0x66FFFFFF),
              ),
            ),
          ),
          _busy
              ? const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: Colors.white))
              : Icon(
                  _searching ? Icons.close_rounded : Icons.favorite_rounded,
                  size: 54,
                  color: Colors.white,
                ),
        ]),
      );
}

/// نافذة العرض: اسم وصورة الطرف الثاني، مع قبول أو تخطي خلال دقيقتين
class _OfferDialog extends StatefulWidget {
  const _OfferDialog({required this.offerId});
  final int offerId;

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  Map<String, dynamic>? _card;
  Timer? _poll;
  Timer? _clock;
  int _left = 120;
  bool _busy = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _load());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left > 0) setState(() => _left--);
      if (_left == 0) _close('expired');
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _close(String result) {
    if (_closed || !mounted) return;
    _closed = true;
    _poll?.cancel();
    _clock?.cancel();
    Navigator.of(context).pop(result);
  }

  Future<void> _load() async {
    try {
      final r = await _db.rpc('match_card', params: {'p_offer': widget.offerId});
      if (!mounted || r == null) return;
      final c = Map<String, dynamic>.from(r as Map);
      final st = c['status'] as String?;
      if (st == 'accepted') return _close('accepted');
      if (st == 'declined') return _close('declined');
      if (st == 'expired') return _close('expired');
      setState(() {
        _card = c;
        _left = (c['seconds_left'] as num?)?.toInt() ?? _left;
      });
    } catch (_) {}
  }

  Future<void> _answer(bool ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await _db.rpc('match_respond',
          params: {'p_offer': widget.offerId, 'p_ok': ok});
      final st = (Map<String, dynamic>.from(r as Map))['status'] as String?;
      if (st == 'pending') {
        await _load();
      } else {
        _close(st ?? 'expired');
        return;
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال، جرّب مرة ثانية.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = _card;
    final name = (c?['name'] as String?) ?? '...';
    final mineOk = c?['my_ok'] == true;
    final theyOk = c?['their_ok'] == true;
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(28),
        child: Glass(
          radius: 32,
          blur: 30,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('لقينا لك شخص!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              Center(
                child: c == null
                    ? const SizedBox(
                        height: 96,
                        child: Center(child: CircularProgressIndicator()))
                    : _Avatar(
                        path: c['avatar'] as String?,
                        radius: 48,
                        gender: c['gender'] as String?),
              ),
              const SizedBox(height: 12),
              Text(name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                theyOk && !mineOk
                    ? 'وافق على المطابقة. باقي ${_left}ث'
                    : mineOk
                        ? 'بانتظار موافقته... ${_left}ث'
                        : 'عندك $_left ثانية تقرر',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xCCFFFFFF)),
              ),
              const SizedBox(height: 20),
              if (!mineOk)
                _Btn(label: 'قبول', onTap: () => _answer(true), busy: _busy),
              if (!mineOk) const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => _answer(false),
                child: Text(mineOk ? 'إلغاء' : 'تخطي',
                    style: const TextStyle(color: Color(0xCCFFFFFF))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
