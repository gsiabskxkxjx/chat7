part of 'main.dart';

// عمليات المحادثة: إرسال، مكالمات، صور، تسجيل، إبلاغ، حظر
extension _ChatActions on _ChatState {
  void _partnerInfo() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(_Sp.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Avatar(path: _pAvatar, radius: 48, gender: _pGender),
            const SizedBox(height: _Sp.md),
            Text(_title(),
                style:
                    const TextStyle(fontSize: _Fs.display, fontWeight: FontWeight.w700)),
            const SizedBox(height: _Sp.xs),
            Text('@${widget.chat.partner}',
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Color(0xAAFFFFFF))),
            const SizedBox(height: _Sp.sm),
            _PartnerVerified(chatId: widget.chat.id),
            Text(_status(),
                style: TextStyle(
                    color: _online
                        ? const Color(0xFF5BE584)
                        : const Color(0xAAFFFFFF))),
            const SizedBox(height: _Sp.md),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _reportPartner();
                },
                icon: const Icon(Icons.flag_rounded, size: 18),
                label: const Text('إبلاغ'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _blockPartner();
                },
                icon: const Icon(Icons.block_rounded,
                    size: 18, color: Color(0xFFFF6B60)),
                label: const Text('حظر',
                    style: TextStyle(color: Color(0xFFFF6B60))),
              ),
            ]),
            const SizedBox(height: _Sp.md),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MemoriesScreen(chatId: widget.chat.id)));
              },
              icon: const Icon(Icons.photo_library_rounded),
              label: const Text('معرض الذكريات'),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _reportPartner() async {
    const reasons = [
      'محتوى مسيء',
      'مضايقة أو تهديد',
      'انتحال شخصية',
      'احتيال أو إزعاج',
      'سبب آخر',
    ];
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('سبب الإبلاغ'),
        children: [
          for (final x in reasons)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, x), child: Text(x)),
        ],
      ),
    );
    if (r == null || !mounted) return;
    try {
      await _db.rpc('report_partner',
          params: {'p_reason': r, 'p_details': null});
      if (mounted) _toast(context, 'وصل بلاغك، شكراً.');
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال البلاغ.');
    }
  }

  Future<void> _blockPartner() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حظر @${widget.chat.partner}؟'),
        content: const Text(
            'راح تنحذف المحادثة عند الطرفين، وما يقدر يرتبط معك مرة ثانية.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حظر',
                  style: TextStyle(color: Color(0xFFFF6B60)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      try {
        final files =
            await _db.storage.from('chat-media').list(path: widget.chat.id);
        if (files.isNotEmpty) {
          await _db.storage.from('chat-media').remove(
              files.map((f) => '${widget.chat.id}/${f.name}').toList());
        }
      } catch (_) {}
      await _wipeChatBg(widget.chat.id);
      await _db.rpc('block_partner');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => PairScreen(me: widget.chat.me)),
        (_) => false,
      );
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الحظر، جرّب مرة ثانية.');
    }
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(chat: widget.chat)));
    // رجعنا من الإعدادات: نحدّث جنسي إذا تغيّر، ونعيد تحميل الرسائل (إذا انمسح السجل)
    if (mounted) {
      setState(() => _stream = _makeStream());
      unawaited(_reloadMyGender());
    }
  }

  Future<void> _markRead() async {
    if (_markBusy || !_pulse.foreground || !mounted) return;
    _markBusy = true;
    try {
      await _db.rpc('mark_read', params: {'p_chat': widget.chat.id});
    } catch (_) {}
    _markBusy = false;
  }

  void _checkUnread(List<Map<String, dynamic>> rows) {
    var newest = -1;
    for (final r in rows) {
      if (r['sender_id'] != _uid && r['read_at'] == null) {
        final id = (r['id'] as num).toInt();
        if (id > newest) newest = id;
      }
    }
    if (newest > _markedUpTo) {
      _markedUpTo = newest;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_markRead()));
    }
  }

  void _incoming(CallSession s) {
    if (!mounted) {
      unawaited(s.end('مكالمة فائتة.', send: 'decline'));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            IncomingCallScreen(session: s, partner: widget.chat.partner)));
  }

  Future<void> _call(bool video) async {
    if (_hub.current != null) return;
    if (_blockedByTrust()) return;
    final okExplain = await _explainOnce(context,
        key: video ? 'camera_call' : 'mic_call',
        icon: video ? Icons.videocam_rounded : Icons.mic_rounded,
        title: video ? 'الكاميرا والمايك' : 'المايك',
        text: video
            ? 'نحتاج الكاميرا والمايك حتى يشوفك ويسمعك الطرف الثاني. المكالمة بينكم بس وما تنحفظ.'
            : 'نحتاج المايك حتى يسمعك الطرف الثاني. المكالمة بينكم بس وما تنحفظ.');
    if (!okExplain || !mounted) return;
    if (!_hub.ready) {
      _toast(context, 'الاتصال بالسيرفر غير جاهز، جرّب بعد ثواني.');
      return;
    }
    final s = CallSession.outgoing(_hub, video);
    s.hint =
        _online ? null : 'الطرف الثاني غير متصل الآن، أرسلنا له إشعار مكالمة.';
    _hub.current = s;
    try {
      await s.startOutgoing();
    } catch (_) {
      await s.end(
          'تعذر بدء المكالمة. اسمح للتطبيق بالمايك والكاميرا من إعدادات الجوال.');
      if (mounted) _toast(context, s.endReason ?? 'تعذر بدء المكالمة.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(session: s, partner: widget.chat.partner)));
  }

  Future<void> _send({String? effect}) async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    final reply = _replyTo;
    _c.clear();
    setState(() => _replyTo = null);
    final row = <String, dynamic>{
      'chat_id': widget.chat.id,
      'body': t,
      'client_id': _uuid4(),
      if (reply != null) 'reply_to_id': reply.id,
      if (reply != null) 'reply_quote': _quoteSnippet(reply),
      if (effect != null) 'effect': effect,
    };
    try {
      try {
        await _db.from('messages').insert(row);
      } on PostgrestException catch (e) {
        // السيرفر قديم وما فيه عمود التأثير: نرسلها بدونه
        if (effect == null || !e.message.contains('effect')) rethrow;
        row.remove('effect');
        await _db.from('messages').insert(row);
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // وصلت من قبل (إعادة إرسال)
      if (!mounted) return;
      _c.text = t;
      setState(() => _replyTo = reply);
      _toast(context, _friendlyError(e, fallback: 'تعذر الإرسال، حاول مرة ثانية.'));
    } catch (_) {
      // غالباً انقطع الإنترنت: تنحط بالصندوق وتنعاد لحالها
      if (mounted) _queueOutbox(row);
    }
  }

  Future<String?> _attachSheet() => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('صورة من المعرض'),
              onTap: () => Navigator.pop(ctx, 'photo_gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('تصوير صورة'),
              onTap: () => Navigator.pop(ctx, 'photo_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_rounded),
              title: const Text('فيديو من المعرض'),
              onTap: () => Navigator.pop(ctx, 'video_gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded),
              title: const Text('تسجيل فيديو'),
              onTap: () => Navigator.pop(ctx, 'video_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.brush_rounded),
              title: const Text('ارسم وأرسل'),
              onTap: () => Navigator.pop(ctx, 'draw'),
            ),
            ListTile(
              leading: const Icon(Icons.radio_button_checked_rounded),
              title: const Text('فيديو دائري'),
              subtitle: const Text('لين 30 ثانية بالكاميرا الأمامية'),
              onTap: () => Navigator.pop(ctx, 'vnote'),
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq_rounded),
              title: const Text('نبضة'),
              subtitle: const Text('صوتك 5 ثواني وينرسل لحاله'),
              onTap: () => Navigator.pop(ctx, 'pulse'),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_rounded),
              title: const Text('ملصقات بيناتنا'),
              onTap: () => Navigator.pop(ctx, 'sticker'),
            ),
            ListTile(
              leading: const Icon(Icons.style_rounded),
              title: const Text('بطاقة ملوّنة'),
              subtitle: const Text('رسالة مهمة كبيرة وملوّنة'),
              onTap: () => Navigator.pop(ctx, 'card'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('ملف أو PDF'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.poll_rounded),
              title: const Text('تصويت سريع'),
              subtitle: const Text('سؤال وخيارات، وكل واحد يصوّت'),
              onTap: () => Navigator.pop(ctx, 'poll'),
            ),
          ]),
          ),
        ),
      );

  Future<void> _attach({String? preset}) async {
    final act = preset ?? await _attachSheet();
    if (!mounted || act == null) return;
    if (act == 'card') {
      await _sendCard();
      return;
    }
    if (act == 'poll') {
      await _sendPoll();
      return;
    }
    if (act == 'sticker') {
      if (_blockedByTrust()) return;
      await _showStickers(context, widget.chat.id);
      return;
    }
    if (_blockedByTrust()) return;
    if (act == 'pulse') {
      await _sendPulse();
      return;
    }
    if (act == 'vnote') {
      await _recordVideoNote();
      return;
    }
    if (act == 'file') {
      await _sendFile();
      return;
    }
    if (act == 'draw') {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DrawScreen(chatId: widget.chat.id)));
      return;
    }
    if (act.endsWith('camera')) {
      final okExplain = await _explainOnce(context,
          key: 'camera',
          icon: Icons.photo_camera_rounded,
          title: 'الكاميرا',
          text: 'نحتاج الكاميرا حتى تصوّر وترسل للطرف الثاني مباشرة.');
      if (!okExplain || !mounted) return;
    }
    setState(() => _uploading = true);
    try {
      final camera = act.endsWith('camera');
      final src = camera ? ImageSource.camera : ImageSource.gallery;
      if (act.startsWith('photo')) {
        final List<XFile> picked;
        if (camera) {
          final one = await _picker.pickImage(
              source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
          picked = one == null ? const [] : [one];
        } else {
          picked = await _picker.pickMultiImage(
              maxWidth: 1600, maxHeight: 1600, imageQuality: 82, limit: 10);
        }
        var files = picked.take(10).map((x) => File(x.path)).toList();
        // صورة وحدة: نفتح شاشة التعديل (فلاتر، تدوير، قص)
        if (files.length == 1 && mounted) {
          final edited = await Navigator.of(context).push<File>(MaterialPageRoute(
              builder: (_) => _ImageEditScreen(file: files.first)));
          files = edited == null ? <File>[] : [edited];
        }
        for (final f in files) {
          await _sendMedia(
              chatId: widget.chat.id,
              file: f,
              kind: 'image',
              ext: _extFor(f.path),
              mime: _mimeFor(f.path));
        }
      } else {
        final x = await _picker.pickVideo(
            source: src, maxDuration: const Duration(minutes: 2));
        if (x != null) {
          final original = File(x.path);
          if (await original.length() > 6 * 1024 * 1024 && mounted) {
            _toast(context, 'نضغط الفيديو قبل الإرسال...');
          }
          final file = await _compressVideo(original);
          if (await file.length() > 50 * 1024 * 1024) {
            if (mounted) _toast(context, 'الفيديو كبير، الحد الأقصى 50 ميجا.');
          } else {
            await _sendMedia(
                chatId: widget.chat.id,
                file: file,
                kind: 'video',
                ext: _extOf(file.path),
                mime: _mimeForVideo(file.path));
          }
          await _dropTemp(file, original);
        }
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال. جرّب مرة ثانية.');
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _startRec() async {
    if (_recording || _uploading) return;
    if (_blockedByTrust()) return;
    final okExplain = await _explainOnce(context,
        key: 'mic_voice',
        icon: Icons.mic_rounded,
        title: 'رسالة صوتية',
        text: 'نحتاج المايك حتى تسجل رسالة صوتية. التسجيل يبدأ لما تضغط ويوقف لما تضغط إرسال.');
    if (!okExplain || !mounted) return;
    try {
      final ok = await _rec.start();
      if (!ok) {
        if (mounted) _toast(context, 'اسمح للتطبيق بالمايك من إعدادات الجوال.');
        return;
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر بدء التسجيل.');
      return;
    }
    if (!mounted) {
      await _rec.cancel();
      return;
    }
    _recSecs = 0;
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recSecs++);
      if (_recSecs >= 300) unawaited(_finishRec(true));
    });
    setState(() => _recording = true);
  }

  Future<void> _finishRec(bool send) async {
    if (!_recording) return;
    _recTimer?.cancel();
    if (mounted) setState(() => _recording = false);
    if (!send) {
      await _rec.cancel();
      return;
    }
    final clip = await _rec.stop();
    if (clip == null || clip.ms < 800) {
      if (mounted) _toast(context, 'التسجيل قصير جداً.');
      return;
    }
    if (mounted) setState(() => _uploading = true);
    try {
      await _sendMedia(
          chatId: widget.chat.id,
          file: clip.file,
          kind: 'audio',
          ext: 'm4a',
          mime: 'audio/mp4',
          durationMs: clip.ms);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال الرسالة الصوتية.');
    }
    try {
      await clip.file.delete();
    } catch (_) {}
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _msgMenu(Msg m) async {
    if (m.kind == 'call') return;
    final times = _timesOf(m);
    final act = await showModalBottomSheet<String>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (times.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
              child: Text(times,
                  style: const TextStyle(fontSize: _Fs.small, color: Color(0x99FFFFFF))),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              for (final e in _reactEmojis)
                InkWell(
                  onTap: () => Navigator.pop(ctx, 'react:$e'),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.reply_rounded),
            title: const Text('رد'),
            onTap: () => Navigator.pop(ctx, 'reply'),
          ),
          if (m.kind == 'text')
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('نسخ'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          if (m.kind == 'audio' && m.mediaPath != null)
            ListTile(
              leading: const Icon(Icons.subtitles_rounded),
              title: const Text('حوّلها لنص'),
              subtitle: const Text('تنرسل لخدمة تحويل خارجية'),
              onTap: () => Navigator.pop(ctx, 'transcribe'),
            ),
          if (m.kind == 'text' && _isMusicLink(m.text))
            ListTile(
              leading: const Icon(Icons.headphones_rounded),
              title: const Text('نسمعها سوا'),
              subtitle: const Text('تنفتح عندكم الاثنين بنفس اللحظة'),
              onTap: () => Navigator.pop(ctx, 'listen'),
            ),
          ListTile(
            leading: Icon(
                _stars.contains(m.id) ? Icons.star_rounded : Icons.star_border_rounded,
                color: const Color(0xFFFFD60A)),
            title: Text(_stars.contains(m.id) ? 'إزالة من المفضلة' : 'نجمة (المفضلة)'),
            onTap: () => Navigator.pop(ctx, 'star'),
          ),
          if (m.kind == 'text' && m.text.trim().isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: const Text('ترجمة'),
              onTap: () => Navigator.pop(ctx, 'translate'),
            ),
            if (!m.mine)
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded),
                title: const Text('اقترح ردّ'),
                onTap: () => Navigator.pop(ctx, 'aireply'),
              ),
            if (_findAppointment(m.text) != null)
              ListTile(
                leading: const Icon(Icons.event_available_rounded),
                title: const Text('أضفه للتقويم'),
                subtitle: Text('لقينا موعد: ${_findAppointment(m.text)!.label}'),
                onTap: () => Navigator.pop(ctx, 'appt'),
              ),
          ],
          if (m.kind != 'call')
            ListTile(
              leading: Icon(_pinIds.contains(m.id) ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(_pinIds.contains(m.id) ? 'فك التثبيت' : 'تثبيت'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
          if (_canEdit(m))
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('تعديل'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
          ListTile(
            leading: const Icon(Icons.checklist_rounded),
            title: const Text('تحديد'),
            onTap: () => Navigator.pop(ctx, 'select'),
          ),
          ListTile(
            leading:
                const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B60)),
            title: const Text('حذف'),
            onTap: () => Navigator.pop(ctx, 'del'),
          ),
        ]),
        ),
      ),
    );
    if (!mounted || act == null) return;
    if (act.startsWith('react:')) {
      await _react(m.id, act.substring(6));
    } else if (act == 'reply') {
      setState(() => _replyTo = m);
    } else if (act == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) _toast(context, 'تم النسخ');
    } else if (act == 'del') {
      await _deleteMsgs([m], m.mine);
    } else if (act == 'transcribe') {
      await _transcribe(m);
    } else if (act == 'listen') {
      await _listenTogether(m);
    } else if (act == 'select') {
      setState(() => _selected = {m.id});
    } else if (act == 'star') {
      await _toggleStar(m);
    } else if (act == 'edit') {
      await _editMsg(m);
    } else if (act == 'pin') {
      await _togglePin(m);
    } else if (act == 'translate') {
      await _aiTranslate(m);
    } else if (act == 'aireply') {
      await _aiReplies(m);
    } else if (act == 'appt') {
      final a = _findAppointment(m.text);
      if (a != null) await _addAppointment(a, m.text);
    }
  }

  Future<void> _delete(Msg m) async {
    setState(() => _hidden.add(m.id));
    try {
      final path = m.mediaPath;
      if (path != null) {
        try {
          await _db.storage.from('chat-media').remove([path]);
        } catch (_) {}
      }
      await _db.from('messages').delete().eq('id', m.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hidden.remove(m.id));
      _toast(context, 'تعذر الحذف.');
    }
  }
}
