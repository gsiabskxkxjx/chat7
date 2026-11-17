-- E2EE core: public keys + key backups (client-encrypted), partner key lookup,
-- wider length limits for ciphertext, legacy-message migration, plaintext guard.

create table if not exists public.e2e_keys (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pub text not null check (char_length(pub) between 40 and 60),
  backup text check (backup is null or char_length(backup) < 400),
  backup_salt text check (backup_salt is null or char_length(backup_salt) < 64),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table public.e2e_keys enable row level security;
revoke all on public.e2e_keys from anon, authenticated;
grant select on public.e2e_keys to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='e2e_keys' and policyname='e2e_keys_own') then
    create policy e2e_keys_own on public.e2e_keys for select to authenticated
      using (user_id = (select auth.uid()));
  end if;
end $$;

create or replace function public.e2e_publish(p_pub text, p_backup text, p_salt text, p_replace boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare cur text;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select pub into cur from e2e_keys where user_id = auth.uid();
  if cur is null then
    insert into e2e_keys (user_id, pub, backup, backup_salt) values (auth.uid(), p_pub, p_backup, p_salt);
  elsif cur = p_pub then
    update e2e_keys set backup = coalesce(p_backup, backup), backup_salt = coalesce(p_salt, backup_salt),
      updated_at = now() where user_id = auth.uid();
  elsif p_replace then
    update e2e_keys set pub = p_pub, backup = p_backup, backup_salt = p_salt, updated_at = now()
      where user_id = auth.uid();
  else
    raise exception 'key_exists';
  end if;
end $$;

create or replace function public.e2e_partner_pub(p_chat uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when k.user_id is null then null
              else jsonb_build_object('pub', k.pub, 'updated_at', k.updated_at) end
  from chats c
  left join e2e_keys k on k.user_id = case when c.user_a = auth.uid() then c.user_b else c.user_a end
  where c.id = p_chat and auth.uid() in (c.user_a, c.user_b);
$$;

-- re-encrypt my own legacy rows (client sends ciphertext; server only swaps plaintext for ciphertext)
create or replace function public.e2e_migrate(p_table text, p_rows jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0; c int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 200 then raise exception 'bad_rows'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if p_table = 'messages' then
      update messages set
        body = case when r->>'body' like 'e2e1:%' then r->>'body' else body end,
        reply_quote = case when r->>'reply_quote' like 'e2e1:%' then r->>'reply_quote' else reply_quote end,
        alt = case when r->>'alt' like 'e2e1:%' then r->>'alt' else alt end
      where id = (r->>'id')::bigint and sender_id = auth.uid();
    elsif p_table = 'love_notes' then
      update love_notes set body = r->>'body'
      where id = (r->>'id')::bigint and author = auth.uid() and r->>'body' like 'e2e1:%';
    elsif p_table = 'diary_entries' then
      update diary_entries set body = r->>'body'
      where id = (r->>'id')::bigint and author = auth.uid() and r->>'body' like 'e2e1:%';
    else
      raise exception 'bad_table';
    end if;
    get diagnostics c = row_count;
    n := n + c;
  end loop;
  return n;
end $$;

revoke execute on function public.e2e_publish(text, text, text, boolean) from public, anon;
revoke execute on function public.e2e_partner_pub(uuid) from public, anon;
revoke execute on function public.e2e_migrate(text, jsonb) from public, anon;
grant execute on function public.e2e_publish(text, text, text, boolean) to authenticated;
grant execute on function public.e2e_partner_pub(uuid) to authenticated;
grant execute on function public.e2e_migrate(text, jsonb) to authenticated;

-- ciphertext is longer than plaintext: widen the limits (the app still enforces the real limits)
alter table public.messages drop constraint if exists messages_body_len;
alter table public.messages add constraint messages_body_len
  check (char_length(body) <= 24000 and (kind <> 'text' or char_length(body) >= 1));
alter table public.messages drop constraint if exists messages_alt_check;
alter table public.messages add constraint messages_alt_check check (alt is null or char_length(alt) <= 1500);
alter table public.messages drop constraint if exists messages_reply_quote_check;
alter table public.messages add constraint messages_reply_quote_check check (reply_quote is null or char_length(reply_quote) <= 1500);
alter table public.scheduled_messages drop constraint if exists scheduled_messages_body_check;
alter table public.scheduled_messages add constraint scheduled_messages_body_check check (char_length(body) between 1 and 24000);
alter table public.love_notes drop constraint if exists love_notes_body_check;
alter table public.love_notes add constraint love_notes_body_check check (char_length(btrim(body)) between 1 and 1500);
alter table public.diary_entries drop constraint if exists diary_entries_body_check;
alter table public.diary_entries add constraint diary_entries_body_check check (char_length(btrim(body)) between 1 and 12000);
alter table public.time_capsules drop constraint if exists time_capsules_body_check;
alter table public.time_capsules add constraint time_capsules_body_check check (char_length(body) <= 20000);
alter table public.shared_items drop constraint if exists shared_items_body_check;
alter table public.shared_items add constraint shared_items_body_check check (char_length(body) between 1 and 1500);
alter table public.daily_answers drop constraint if exists daily_answers_answer_check;
alter table public.daily_answers add constraint daily_answers_answer_check check (char_length(answer) between 1 and 4000);
alter table public.daily_needs drop constraint if exists daily_needs_need_check;
alter table public.daily_needs add constraint daily_needs_need_check check (char_length(btrim(need)) between 1 and 600);
alter table public.call_signals drop constraint if exists call_signals_data_check;
alter table public.call_signals add constraint call_signals_data_check check (octet_length((data)::text) < 120000);

create or replace function public.daily_answer(p_chat uuid, p_day date, p_answer text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from chats where id = p_chat and auth.uid() in (user_a, user_b)) then raise exception 'not_member'; end if;
  if abs(p_day - current_date) > 1 then raise exception 'bad_day'; end if;
  insert into daily_answers (chat_id, day, user_id, answer)
    values (p_chat, p_day, auth.uid(), left(btrim(p_answer), 4000)) on conflict do nothing;
end; $$;

create or replace function public.edit_message(p_id bigint, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if char_length(btrim(p_body)) not between 1 and 24000 then raise exception 'bad_body'; end if;
  update messages set body = btrim(p_body), edited_at = now()
    where id = p_id and sender_id = auth.uid() and kind = 'text' and created_at > now() - interval '15 minutes';
  if not found then raise exception 'too_late'; end if;
end; $$;

-- plaintext guard: once both people have keys, a client cannot store readable message text
create or replace function public.messages_require_e2e() returns trigger
language plpgsql security definer set search_path = public as $$
declare ka boolean; kb boolean;
begin
  if auth.uid() is null then return new; end if;
  if new.kind not in ('text', 'card', 'location', 'ref', 'file', 'alert') then return new; end if;
  if coalesce(new.body, '') = '' or new.body like 'e2e1:%' then return new; end if;
  select exists (select 1 from e2e_keys k where k.user_id = c.user_a),
         exists (select 1 from e2e_keys k where k.user_id = c.user_b)
    into ka, kb from chats c where c.id = new.chat_id;
  if coalesce(ka, false) and coalesce(kb, false) then raise exception 'e2e_required'; end if;
  return new;
end $$;
revoke execute on function public.messages_require_e2e() from public, anon, authenticated;
create or replace trigger messages_require_e2e before insert on public.messages
  for each row execute function public.messages_require_e2e();

-- push: never put encrypted notes in notifications
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
    note := case when new.body like 'e2e1:%' then null else nullif(btrim(coalesce(new.body, '')), '') end;
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
    else '🔒 رسالة جديدة' end;
  perform net.http_post(
    url := 'https://tbmrikxmlnpbcqycjvco.supabase.co/functions/v1/push',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(jwt, ''), 'x-push-secret', coalesce(sec, '')),
    body := jsonb_build_object('tokens', toks, 'title', coalesce(t, 'بيناتنا'), 'body', b, 'chat', new.chat_id));
  return new;
exception when others then return new;
end $body$;
revoke execute on function public.notify_push() from public, anon, authenticated;
