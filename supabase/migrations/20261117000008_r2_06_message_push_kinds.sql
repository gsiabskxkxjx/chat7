-- Round 2: previews for new message kinds, and "أحتاجك" (alert) sent as a high-priority push
create or replace function public.notify_push() returns trigger
language plpgsql security definer set search_path = public as $body$
declare rcpt uuid; toks jsonb; t text; b text; jwt text; sec text; note text;
begin
  if new.kind = 'call' then return new; end if;
  select case when c.user_a = new.sender_id then c.user_b else c.user_a end into rcpt
    from chats c where c.id = new.chat_id;
  if rcpt is null then return new; end if;
  select coalesce(nullif(display_name, ''), '@' || username) into t from profiles where id = new.sender_id;
  if new.kind = 'alert' then
    note := nullif(btrim(coalesce(new.body, '')), '');
    perform public.push_user(rcpt, coalesce(t, 'بيناتنا'),
      case when note is null or note = 'أحتاجك' then '🆘 أحتاجك' else '🆘 أحتاجك: ' || left(note, 80) end,
      'alert', new.chat_id);
    return new;
  end if;
  select coalesce(jsonb_agg(token), '[]'::jsonb) into toks from push_tokens
    where user_id = rcpt and not coalesce((select mute_messages from profiles where id = rcpt), false);
  if jsonb_array_length(toks) = 0 then return new; end if;
  select v into jwt from app_config where k = 'anon_jwt';
  select v into sec from app_config where k = 'push_secret';
  b := case new.kind
    when 'image' then '📷 صورة'
    when 'video' then '🎬 فيديو'
    when 'audio' then '🎤 رسالة صوتية'
    when 'think' then '❤️ أفكر فيك'
    when 'card' then '💌 بطاقة'
    when 'vnote' then '⭕ فيديو دائري'
    when 'file' then '📎 ملف'
    when 'location' then '📍 موقع'
    when 'ref' then '🔖 بطاقة مرجع'
    else 'رسالة جديدة' end;
  perform net.http_post(
    url := 'https://tbmrikxmlnpbcqycjvco.supabase.co/functions/v1/push',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(jwt, ''), 'x-push-secret', coalesce(sec, '')),
    body := jsonb_build_object('tokens', toks, 'title', coalesce(t, 'بيناتنا'), 'body', b, 'chat', new.chat_id));
  return new;
exception when others then return new;
end $body$;
revoke execute on function public.notify_push() from public, anon, authenticated;
