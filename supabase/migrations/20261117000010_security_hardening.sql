-- Security hardening: no hard-coded push secret inside function bodies (read it from app_config like notify_push does)
create or replace function public.notify_call() returns trigger
language plpgsql security definer set search_path = public as $function$
declare rcpt uuid; toks jsonb; t text; b text; jwt text; sec text;
begin
  if new.kind <> 'offer' then return new; end if;
  select case when c.user_a = new.sender_id then c.user_b else c.user_a end into rcpt
    from chats c where c.id = new.chat_id;
  if rcpt is null then return new; end if;
  select coalesce(jsonb_agg(token), '[]'::jsonb) into toks from push_tokens
    where user_id = rcpt and not coalesce((select mute_calls from profiles where id = rcpt), false);
  if jsonb_array_length(toks) = 0 then return new; end if;
  select coalesce(nullif(display_name, ''), '@' || username) into t from profiles where id = new.sender_id;
  select v into jwt from app_config where k = 'anon_jwt';
  select v into sec from app_config where k = 'push_secret';
  b := case when coalesce(new.data->>'video', 'false') = 'true' then '📹 مكالمة فيديو واردة' else '📞 مكالمة صوتية واردة' end;
  perform net.http_post(
    url := 'https://tbmrikxmlnpbcqycjvco.supabase.co/functions/v1/push',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(jwt, ''), 'x-push-secret', coalesce(sec, '')),
    body := jsonb_build_object('tokens', toks, 'title', coalesce(t, 'بيناتنا'), 'body', b,
      'chat', new.chat_id, 'channel', 'calls', 'ttl', 45, 'type', 'call'));
  return new;
exception when others then return new;
end;
$function$;
revoke execute on function public.notify_call() from public, anon, authenticated;
