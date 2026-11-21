part of 'main.dart';

// ---------- الأخطاء وسجل الإدارة ----------

class ErrorsPage extends StatelessWidget {
  const ErrorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: const [
          TabBar(tabs: [Tab(text: 'ملخص'), Tab(text: 'آخر الأخطاء'), Tab(text: 'سجل الإدارة')]),
          Expanded(child: TabBarView(children: [_ErrorsSummary(), _ErrorsRaw(), _AuditList()])),
        ],
      ),
    );
  }
}

class _ErrorsSummary extends StatefulWidget {
  const _ErrorsSummary();

  @override
  State<_ErrorsSummary> createState() => _ErrorsSummaryState();
}

class _ErrorsSummaryState extends State<_ErrorsSummary> {
  int _days = 7;

  Future<void> _clear(BuildContext context, Future<void> Function() reload) async {
    final ok = await _confirm(context,
        title: 'مسح الأخطاء القديمة',
        body: 'تنمسح الأخطاء الأقدم من 30 يوم من السيرفر.',
        ok: 'مسح',
        danger: true);
    if (!ok || !context.mounted) return;
    try {
      final n = _int(await _rpc('admin_errors_clear', {'p_days': 30}));
      if (context.mounted) _toast(context, 'انمسح $n خطأ');
      await reload();
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Async<List<Map<String, dynamic>>>(
      key: ValueKey(_days),
      load: () async => _list(await _rpc('admin_errors_summary', {'p_days': _days})),
      builder: (context, items, reload) {
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(value: 1, label: Text('يوم')),
                  ButtonSegment<int>(value: 7, label: Text('أسبوع')),
                  ButtonSegment<int>(value: 30, label: Text('شهر')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty) const _Empty('ما في أخطاء بهالفترة. ممتاز'),
              for (final e in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _Tag(_s(e['context'], 'عام'), color: const Color(0xFF42A5F5)),
                            const Spacer(),
                            Text('${_int(e['n'])} مرة', style: const TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(_s(e['message'], '—'), maxLines: 4),
                        const SizedBox(height: 6),
                        Text(
                          '${_int(e['users'])} مستخدم · آخر مرة ${_ago(e['last'])} · إصدارات: ${_versions(e['versions'])}',
                          style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF)),
                        ),
                      ],
                    ),
                  ),
                ),
              if (items.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_rounded),
                    label: const Text('مسح الأخطاء الأقدم من 30 يوم'),
                    onPressed: () => _clear(context, reload),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _versions(dynamic v) {
    if (v is List) {
      final xs = v.where((x) => x != null).map((x) => x.toString()).toList();
      if (xs.isNotEmpty) return xs.join('، ');
    }
    return '—';
  }
}

class _ErrorsRaw extends StatelessWidget {
  const _ErrorsRaw();

  @override
  Widget build(BuildContext context) {
    return _Async<List<Map<String, dynamic>>>(
      load: () async => _list(await _rpc('admin_errors', {'p_limit': 150, 'p_offset': 0})),
      builder: (context, items, reload) {
        if (items.isEmpty) {
          return RefreshIndicator(onRefresh: reload, child: ListView(children: const [_Empty('ما في أخطاء مسجّلة')]));
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 20),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final e = items[i];
              return Card(
                child: ExpansionTile(
                  title: Text(_s(e['message'], '—'), maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${_s(e['context'], 'عام')} · ${_s(e['app_version'], '?')} · ${_s(e['platform'])} · ${_ago(e['created_at'])}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(_s(e['message'])),
                    if (_s(e['stack']).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        _s(e['stack']),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ],
                    const SizedBox(height: 6),
                    TextButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('نسخ'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: '${_s(e['context'])} ${_s(e['app_version'])}\n${_s(e['message'])}\n${_s(e['stack'])}'));
                        _toast(context, 'تم النسخ');
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AuditList extends StatelessWidget {
  const _AuditList();

  String _detail(dynamic d) {
    if (d is! Map) return '';
    final parts = <String>[];
    d.forEach((k, v) {
      final t = v?.toString() ?? '';
      if (t.isNotEmpty) parts.add('$k: $t');
    });
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return _Async<List<Map<String, dynamic>>>(
      load: () async => _list(await _rpc('admin_audit_list', {'p_limit': 150})),
      builder: (context, items, reload) {
        if (items.isEmpty) {
          return RefreshIndicator(onRefresh: reload, child: ListView(children: const [_Empty('السجل فاضي')]));
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = items[i];
              final detail = _detail(a['detail']);
              final target = _s(a['target']);
              return ListTile(
                title: Text(_actionName(_s(a['action']))),
                subtitle: Text(
                  [
                    if (target.isNotEmpty && target != 'all') target.length > 8 ? target.substring(0, 8) : target,
                    if (target == 'all') 'الكل',
                    if (detail.isNotEmpty) detail,
                  ].join(' · '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(_ago(a['created_at']), style: const TextStyle(fontSize: 11)),
              );
            },
          ),
        );
      },
    );
  }
}
