part of 'main.dart';

// ---------- لوحة الإحصائيات ----------

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _Async<Map<String, dynamic>>(
      load: () async => _map(await _rpc('admin_overview')),
      builder: (context, d, reload) {
        final series = _list(d['series']);
        final versions = _map(d['versions']);
        final vKeys = versions.keys.toList()
          ..sort((a, b) => _int(versions[b]).compareTo(_int(versions[a])));
        final stats = <(String, String, IconData)>[
          ('المستخدمين', _s(d['users'], '0'), Icons.people_rounded),
          ('أونلاين الحين', _s(d['online'], '0'), Icons.circle),
          ('نشطين آخر 24 ساعة', _s(d['active_24h'], '0'), Icons.bolt_rounded),
          ('جدد آخر 24 ساعة', _s(d['new_24h'], '0'), Icons.person_add_alt_1_rounded),
          ('جدد آخر 7 أيام', _s(d['new_7d'], '0'), Icons.trending_up_rounded),
          ('المحادثات', _s(d['chats'], '0'), Icons.forum_rounded),
          ('رسائل آخر 24 ساعة', _s(d['msgs_24h'], '0'), Icons.chat_bubble_rounded),
          ('كل الرسائل', _s(d['msgs_total'], '0'), Icons.all_inbox_rounded),
          ('مشفّرين E2EE', _s(d['e2e_users'], '0'), Icons.lock_rounded),
          ('موثّقين بالرقم', _s(d['phone_verified'], '0'), Icons.verified_rounded),
          ('أجهزة تستقبل إشعارات', _s(d['push_tokens'], '0'), Icons.notifications_active_rounded),
          ('محظورين', _s(d['banned'], '0'), Icons.block_rounded),
        ];
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            children: [
              _alerts(d),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final s in stats) _StatCard(width: w, label: s.$1, value: s.$2, icon: s.$3)],
                );
              }),
              const SizedBox(height: 8),
              _Section('مسجّلين جدد (آخر 14 يوم)', children: [
                _Bars(
                  values: [for (final s in series) _int(s['users'])],
                  labels: [for (final s in series) _s(s['d']).split('-').last],
                  color: const Color(0xFF7C4DFF),
                ),
              ]),
              _Section('عدد الرسائل (آخر 14 يوم، بدون محتوى)', children: [
                _Bars(
                  values: [for (final s in series) _int(s['msgs'])],
                  labels: [for (final s in series) _s(s['d']).split('-').last],
                  color: const Color(0xFF26A69A),
                ),
              ]),
              _Section('إصدارات التطبيق (آخر 30 يوم)', children: [
                if (vKeys.isEmpty) const _Empty('ما في بيانات'),
                for (final k in vKeys) _KV(k, '${_int(versions[k])} مستخدم'),
              ]),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 0),
                child: Text(
                  'الرسائل مشفّرة من طرف لطرف، فالأدمن يشوف أعدادها بس مو محتواها.',
                  style: TextStyle(fontSize: 12, color: Color(0x80FFFFFF)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _alerts(Map<String, dynamic> d) {
    final items = <(String, int, Color)>[
      ('بلاغات مفتوحة', _int(d['reports_open']), const Color(0xFFEF5350)),
      ('ملاحظات جديدة', _int(d['feedback_open']), const Color(0xFFFFA726)),
      ('أخطاء آخر 24س', _int(d['errors_24h']), const Color(0xFF42A5F5)),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              decoration: BoxDecoration(
                color: items[i].$3.withAlpha(items[i].$2 > 0 ? 50 : 20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: items[i].$3.withAlpha(items[i].$2 > 0 ? 150 : 50)),
              ),
              child: Column(
                children: [
                  Text('${items[i].$2}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(items[i].$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.width, required this.label, required this.value, required this.icon});
  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      Text(label, maxLines: 2, style: const TextStyle(fontSize: 11, color: Color(0xB3FFFFFF))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// أعمدة بسيطة (بدون مكتبات)
class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, required this.color});
  final List<int> values;
  final List<String> labels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    var maxV = 1;
    for (final v in values) {
      if (v > maxV) maxV = v;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${values[i]}', style: const TextStyle(fontSize: 9)),
                      const SizedBox(height: 2),
                      Container(
                        height: 4 + 76 * values[i] / maxV,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(i < labels.length ? labels[i] : '', style: const TextStyle(fontSize: 9, color: Color(0x99FFFFFF))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
