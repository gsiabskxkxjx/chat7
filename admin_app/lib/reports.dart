part of 'main.dart';

// ---------- البلاغات والملاحظات ----------

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          TabBar(tabs: [Tab(text: 'البلاغات'), Tab(text: 'الملاحظات')]),
          Expanded(child: TabBarView(children: [_ReportsList(), _FeedbackList()])),
        ],
      ),
    );
  }
}

class _OpenFilter extends StatelessWidget {
  const _OpenFilter({required this.open, required this.onChanged});
  final bool open;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(value: true, label: Text('المفتوحة')),
            ButtonSegment<bool>(value: false, label: Text('الكل')),
          ],
          selected: {open},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      );
}

class _ReportsList extends StatefulWidget {
  const _ReportsList();

  @override
  State<_ReportsList> createState() => _ReportsListState();
}

class _ReportsListState extends State<_ReportsList> {
  bool _open = true;

  Future<void> _handle(BuildContext context, Map<String, dynamic> r, Future<void> Function() reload) async {
    final done = r['handled_at'] == null;
    try {
      await _rpc('admin_report_handle', {'p_id': r['id'], 'p_handled': done});
      await reload();
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  Future<void> _ban(BuildContext context, Map<String, dynamic> r, Future<void> Function() reload) async {
    final ok = await _confirm(context,
        title: 'حظر @${_s(r['reported_name'])}',
        body: 'يتحظر الحساب وينطرد من كل أجهزته، ويتسجّل البلاغ كمنتهي.',
        ok: 'حظر',
        danger: true);
    if (!ok || !context.mounted) return;
    try {
      await _rpc('admin_ban', {'p_id': r['reported_id'], 'p_ban': true, 'p_reason': 'بلاغ: ${_s(r['reason'])}'});
      await _rpc('admin_report_handle', {'p_id': r['id'], 'p_handled': true});
      if (context.mounted) _toast(context, 'تم الحظر');
      await reload();
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OpenFilter(open: _open, onChanged: (v) => setState(() => _open = v)),
        Expanded(
          child: _Async<List<Map<String, dynamic>>>(
            key: ValueKey(_open),
            load: () async => _list(await _rpc('admin_reports', {'p_open': _open, 'p_limit': 100, 'p_offset': 0})),
            builder: (context, items, reload) {
              if (items.isEmpty) {
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(children: const [_Empty('ما في بلاغات')]),
                );
              }
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final r = items[i];
                    final done = r['handled_at'] != null;
                    final reportedId = _s(r['reported_id']);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '@${_s(r['reporter_name'], '؟')} بلّغ عن @${_s(r['reported_name'], 'محذوف')}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (done) const _Tag('منتهي', color: Color(0xFF66BB6A)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              _Tag(_s(r['reason'], 'بدون سبب'), color: const Color(0xFFFFA726)),
                              _Tag('${_int(r['reported_total'])} بلاغ عليه'),
                              if (r['reported_banned'] == true) const _Tag('محظور', color: Color(0xFFEF5350)),
                            ]),
                            if (_s(r['details']).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SelectableText(_s(r['details'])),
                            ],
                            const SizedBox(height: 6),
                            Text(_ago(r['created_at']), style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF))),
                            const SizedBox(height: 4),
                            Wrap(spacing: 8, children: [
                              if (reportedId.isNotEmpty)
                                TextButton.icon(
                                  icon: const Icon(Icons.person_search_rounded, size: 18),
                                  label: const Text('فتح المستخدم'),
                                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (_) => UserDetailScreen(id: reportedId, username: _s(r['reported_name'])),
                                  )).then((_) => reload()),
                                ),
                              if (reportedId.isNotEmpty && r['reported_banned'] != true)
                                TextButton.icon(
                                  icon: const Icon(Icons.block_rounded, size: 18),
                                  label: const Text('حظر'),
                                  onPressed: () => _ban(context, r, reload),
                                ),
                              TextButton.icon(
                                icon: Icon(done ? Icons.undo_rounded : Icons.check_rounded, size: 18),
                                label: Text(done ? 'إعادة فتح' : 'تم'),
                                onPressed: () => _handle(context, r, reload),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FeedbackList extends StatefulWidget {
  const _FeedbackList();

  @override
  State<_FeedbackList> createState() => _FeedbackListState();
}

class _FeedbackListState extends State<_FeedbackList> {
  bool _open = true;

  Future<void> _handle(BuildContext context, Map<String, dynamic> f, Future<void> Function() reload) async {
    final done = f['handled_at'] == null;
    try {
      await _rpc('admin_feedback_handle', {'p_id': f['id'], 'p_handled': done});
      await reload();
    } catch (e) {
      if (context.mounted) _toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OpenFilter(open: _open, onChanged: (v) => setState(() => _open = v)),
        Expanded(
          child: _Async<List<Map<String, dynamic>>>(
            key: ValueKey(_open),
            load: () async => _list(await _rpc('admin_feedback', {'p_open': _open, 'p_limit': 100, 'p_offset': 0})),
            builder: (context, items, reload) {
              if (items.isEmpty) {
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(children: const [_Empty('ما في ملاحظات')]),
                );
              }
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final f = items[i];
                    final done = f['handled_at'] != null;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _Tag(_s(f['kind'], 'ملاحظة'), color: const Color(0xFF42A5F5)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_s(f['username']).isEmpty ? 'مستخدم محذوف' : '@${_s(f['username'])}',
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                                if (done) const _Tag('منتهي', color: Color(0xFF66BB6A)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(_s(f['body'])),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(_ago(f['created_at']), style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF))),
                                const Spacer(),
                                TextButton.icon(
                                  icon: Icon(done ? Icons.undo_rounded : Icons.check_rounded, size: 18),
                                  label: Text(done ? 'إعادة فتح' : 'تم'),
                                  onPressed: () => _handle(context, f, reload),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
