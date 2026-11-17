part of 'main.dart';

// ---------- الجولة الثانية: إحصائيات أعمق ----------
// ساعات النشاط (371)، من يبدأ ومتوسط الرد (372)، سحابة الكلمات محلياً (373)،
// خريطة النشاط وأطول سلسلة (374)، مقارنة الشهر (375)، شارات (376)، لوحة شرف الألعاب (380)

class _Insight {
  final hours = List<int>.filled(24, 0);
  final days = <String, int>{};
  int starts = 0, startsOther = 0;
  Duration replyMine = Duration.zero, replyOther = Duration.zero;
  int replyMineN = 0, replyOtherN = 0;
  final words = <String, int>{};
  int monthMsgs = 0, prevMonthMsgs = 0, monthImgs = 0, prevMonthImgs = 0, monthCalls = 0, prevMonthCalls = 0;
  int audio = 0, images = 0, total = 0, callMs = 0, maxCallMs = 0;
  int longestStreak = 0, curStreak = 0;
  final wins = <String, int>{}; // اللاعب -> فوز
  int gamesPlayed = 0;
}

const _stop = {
  'في', 'من', 'على', 'انت', 'أنت', 'انا', 'أنا', 'هو', 'هي', 'شنو', 'ليش', 'هذا', 'هذي', 'هاي', 'مو',
  'لا', 'ما', 'كل', 'بس', 'الي', 'اللي', 'عن', 'الى', 'إلى', 'مع', 'يا', 'اي', 'إي', 'شي', 'شيء', 'لو',
  'اذا', 'إذا', 'بعد', 'قبل', 'هم', 'احنا', 'نحن', 'كان', 'كانت', 'يكون', 'وين', 'متى', 'شلون', 'كلش',
};

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<InsightsScreen> createState() => _InsightsState();
}

class _InsightsState extends State<InsightsScreen> {
  _Insight? _i;
  String? _err;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rows = <Map<String, dynamic>>[];
      for (var p = 0; p < 6; p++) {
        final part = await _net(
            _db
                .from('messages')
                .select('sender_id,kind,created_at,body,duration_ms')
                .eq('chat_id', widget.chatId)
                .order('id', ascending: false)
                .range(p * 1000, p * 1000 + 999),
            t: const Duration(seconds: 30));
        rows.addAll([for (final e in part) Map<String, dynamic>.from(e)]);
        if (part.length < 1000) break;
      }
      List<Map<String, dynamic>> games = const [];
      try {
        final g = await _db.from('chat_games').select('winner').eq('chat_id', widget.chatId).limit(1000);
        games = [for (final e in g) Map<String, dynamic>.from(e)];
      } catch (_) {}
      final i = await compute2(rows.reversed.toList(), games);
      if (mounted) setState(() => _i = i);
    } catch (e) {
      if (mounted) setState(() => _err = _friendlyError(e));
    }
  }

  Future<_Insight> compute2(List<Map<String, dynamic>> rows, List<Map<String, dynamic>> games) async {
    final me = _db.auth.currentUser?.id;
    final r = _Insight();
    final now = DateTime.now();
    final thisM = DateTime(now.year, now.month);
    final prevM = DateTime(now.year, now.month - 1);
    DateTime? prevAt;
    String? prevBy;
    for (final m in rows) {
      final at = DateTime.tryParse('${m['created_at']}')?.toLocal();
      if (at == null) continue;
      final kind = '${m['kind']}';
      final mine = m['sender_id'] == me;
      r.total++;
      r.hours[at.hour]++;
      final dk = _dayStr(at);
      r.days[dk] = (r.days[dk] ?? 0) + 1;
      if (kind == 'audio') r.audio++;
      if (kind == 'image') r.images++;
      if (kind == 'call') {
        final ms = (m['duration_ms'] as num?)?.toInt() ?? 0;
        r.callMs += ms;
        if (ms > r.maxCallMs) r.maxCallMs = ms;
      }
      final inThis = !at.isBefore(thisM);
      final inPrev = !inThis && !at.isBefore(prevM);
      if (inThis) {
        r.monthMsgs++;
        if (kind == 'image') r.monthImgs++;
        if (kind == 'call') r.monthCalls++;
      } else if (inPrev) {
        r.prevMonthMsgs++;
        if (kind == 'image') r.prevMonthImgs++;
        if (kind == 'call') r.prevMonthCalls++;
      }
      if (prevAt != null) {
        final gap = at.difference(prevAt);
        if (gap > const Duration(hours: 3)) {
          mine ? r.starts++ : r.startsOther++;
        } else if (prevBy != m['sender_id'] && gap < const Duration(hours: 3)) {
          if (mine) {
            r.replyMine += gap;
            r.replyMineN++;
          } else {
            r.replyOther += gap;
            r.replyOtherN++;
          }
        }
      } else {
        mine ? r.starts++ : r.startsOther++;
      }
      prevAt = at;
      prevBy = m['sender_id'] as String?;
      if (kind == 'text') {
        final b = '${m['body'] ?? ''}';
        if (!b.startsWith('http')) {
          for (final w in b.split(RegExp(r'[\s،,.!؟?:;()"«»\-_/\\]+'))) {
            final n = _wNorm(w.trim());
            if (n.length >= 3 && n.length <= 14 && !_stop.contains(n) && !RegExp(r'^[0-9٠-٩]+$').hasMatch(n) && !n.startsWith('http')) {
              r.words[n] = (r.words[n] ?? 0) + 1;
            }
          }
        }
      }
    }
    // أطول سلسلة أيام متتالية، والسلسلة الحالية
    final keys = r.days.keys.toList()..sort();
    var run = 0;
    DateTime? last;
    for (final k in keys) {
      final d = DateTime.parse(k);
      run = (last != null && d.difference(last).inDays == 1) ? run + 1 : 1;
      if (run > r.longestStreak) r.longestStreak = run;
      last = d;
    }
    var cur = 0;
    var d = DateTime(now.year, now.month, now.day);
    if (!r.days.containsKey(_dayStr(d))) d = d.subtract(const Duration(days: 1));
    while (r.days.containsKey(_dayStr(d))) {
      cur++;
      d = d.subtract(const Duration(days: 1));
    }
    r.curStreak = cur;
    for (final g in games) {
      final w = g['winner'] as String?;
      r.gamesPlayed++;
      if (w != null) r.wins[w] = (r.wins[w] ?? 0) + 1;
    }
    return r;
  }

  Widget _section(String t, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: _Sp.lg),
        child: Glass(
          radius: 24,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontSize: _Fs.title, fontWeight: FontWeight.w700)),
            const SizedBox(height: _Sp.md),
            child,
          ]),
        ),
      );

  String _avg(Duration d, int n) {
    if (n == 0) return '—';
    final m = d.inSeconds / n / 60;
    return m < 1 ? 'أقل من دقيقة' : (m < 60 ? '${_Fmt.digits(m.round().toString())} دقيقة' : '${_Fmt.digits((m / 60).toStringAsFixed(1))} ساعة');
  }

  String _delta(int a, int b) {
    if (b == 0) return a == 0 ? '—' : 'جديد';
    final p = ((a - b) * 100 / b).round();
    return p >= 0 ? '+${_Fmt.digits('$p')}%' : '${_Fmt.digits('$p')}%';
  }

  @override
  Widget build(BuildContext context) {
    final i = _i;
    if (_err != null) return _R2Page(title: 'إحصائيات أعمق', child: Center(child: Text(_err!)));
    if (i == null) return const _R2Page(title: 'إحصائيات أعمق', child: Center(child: CircularProgressIndicator()));
    final me = _db.auth.currentUser?.id ?? '';
    final maxH = i.hours.reduce(math.max).clamp(1, 1 << 30);
    final bestH = i.hours.indexOf(i.hours.reduce(math.max));
    final top = (i.words.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(28).toList();
    final topN = top.isEmpty ? 1 : top.first.value;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // خريطة آخر 12 أسبوع (عمود لكل أسبوع)
    final start = today.subtract(Duration(days: 7 * 11 + (today.weekday % 7)));
    final badges = <(String, String, bool)>[
      ('🔥', 'سلسلة 30 يوم', i.longestStreak >= 30),
      ('🎙️', '1000 رسالة صوتية', i.audio >= 1000),
      ('📞', 'مكالمة ساعة', i.maxCallMs >= 3600000),
      ('📸', '500 صورة', i.images >= 500),
      ('💬', '10 آلاف رسالة', i.total >= 10000),
      ('🌙', 'سهّيرة (نشاط بعد منتصف الليل)', i.hours.sublist(0, 5).fold<int>(0, (a, b) => a + b) >= 200),
    ];
    return _R2Page(
      title: 'إحصائيات أعمق',
      child: ListView(padding: const EdgeInsets.all(_Sp.lg), children: [
        _section(
            '⏰ أكثر وقت نتكلم فيه',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('الساعة ${_Fmt.digits('$bestH')}:00 هي الذروة', style: const TextStyle(color: Color(0xCCFFFFFF))),
              const SizedBox(height: _Sp.sm),
              SizedBox(
                height: 90,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var h = 0; h < 24; h++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        height: 4 + 82 * i.hours[h] / maxH,
                        decoration: BoxDecoration(
                            color: h == bestH ? const Color(0xFFFF5FA2) : const Color(0x88FFFFFF),
                            borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                ]),
              ),
              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('0', style: TextStyle(fontSize: 10)),
                Text('6', style: TextStyle(fontSize: 10)),
                Text('12', style: TextStyle(fontSize: 10)),
                Text('18', style: TextStyle(fontSize: 10)),
                Text('23', style: TextStyle(fontSize: 10)),
              ]),
            ])),
        _section(
            '🗣️ من يبدأ المحادثة',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('أنا بدأت ${_Fmt.digits('${i.starts}')} مرة، وهو ${_Fmt.digits('${i.startsOther}')} مرة'),
              const SizedBox(height: 4),
              Text('متوسط ردّي: ${_avg(i.replyMine, i.replyMineN)}'),
              Text('متوسط ردّه: ${_avg(i.replyOther, i.replyOtherN)}'),
            ])),
        _section(
            '📅 خريطة النشاط',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('الحالية: ${_Fmt.digits('${i.curStreak}')} يوم · الأطول: ${_Fmt.digits('${i.longestStreak}')} يوم'),
              const SizedBox(height: _Sp.sm),
              SizedBox(
                height: 7 * 17.0,
                child: Row(children: [
                  for (var w = 0; w < 12; w++)
                    Expanded(
                      child: Column(children: [
                        for (var d = 0; d < 7; d++)
                          Builder(builder: (_) {
                            final day = start.add(Duration(days: w * 7 + d));
                            final n = day.isAfter(today) ? -1 : (i.days[_dayStr(day)] ?? 0);
                            return Container(
                              height: 14,
                              margin: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                  color: n < 0
                                      ? Colors.transparent
                                      : n == 0
                                          ? const Color(0x1AFFFFFF)
                                          : Color.lerp(const Color(0x6634C759), const Color(0xFF34C759), (n / 40).clamp(0, 1).toDouble()),
                                  borderRadius: BorderRadius.circular(3)),
                            );
                          }),
                      ]),
                    ),
                ]),
              ),
            ])),
        _section(
            '📈 هالشهر مقابل الماضي',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('الرسائل: ${_Fmt.digits('${i.monthMsgs}')} (${_delta(i.monthMsgs, i.prevMonthMsgs)})'),
              Text('الصور: ${_Fmt.digits('${i.monthImgs}')} (${_delta(i.monthImgs, i.prevMonthImgs)})'),
              Text('المكالمات: ${_Fmt.digits('${i.monthCalls}')} (${_delta(i.monthCalls, i.prevMonthCalls)})'),
            ])),
        _section(
            '☁️ كلماتنا',
            top.isEmpty
                ? const Text('ما في كلمات كافية بعد.')
                : Wrap(spacing: 10, runSpacing: 4, children: [
                    for (final e in top)
                      Text(e.key,
                          style: TextStyle(
                              fontSize: 13 + 17 * e.value / topN,
                              fontWeight: e.value / topN > 0.6 ? FontWeight.w800 : FontWeight.w500,
                              color: Color.lerp(const Color(0xAAFFFFFF), const Color(0xFFFF9FC8), e.value / topN))),
                  ])),
        _section(
            '🏅 الشارات',
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in badges)
                Opacity(
                  opacity: b.$3 ? 1 : 0.35,
                  child: Chip(label: Text('${b.$1} ${b.$2}')),
                ),
            ])),
        _section(
            '🏆 لوحة شرف الألعاب',
            i.gamesPlayed == 0
                ? const Text('ما انلعبت ألعاب بعد.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('لعبتوا ${_Fmt.digits('${i.gamesPlayed}')} جولة'),
                    Text('أنا فزت: ${_Fmt.digits('${i.wins[me] ?? 0}')}'),
                    Text('هو فاز: ${_Fmt.digits('${i.wins.entries.where((e) => e.key != me).fold<int>(0, (a, e) => a + e.value)}')}'),
                  ])),
        const Text('كل الحسابات تتم على جوالك، ما ينرسل منها شي.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: _Fs.small, color: Color(0xB3FFFFFF))),
      ]),
    );
  }
}
