-- الجولة الثانية / 1: أمان وأداء
-- (287/288) دوال الـ trigger ما لازم تنطلب كـ RPC
revoke execute on function public.guard_match_call() from public, anon, authenticated;
revoke execute on function public.guard_match_media() from public, anon, authenticated;
revoke execute on function public.notify_push() from public, anon, authenticated;
revoke execute on function public.notify_call() from public, anon, authenticated;

alter function public.lock_profile_fields() set search_path = public;
alter function public.guard_chat_flags() set search_path = public;
alter function public.guard_continue() set search_path = public;
alter function public.guard_phone_verified() set search_path = public;

-- (204) فهرس مركّب للرسائل حسب المرسل + استعمله حد المعدل
create index if not exists messages_sender_created_idx on public.messages (sender_id, created_at desc);

-- (204) فهارس لكل المفاتيح الأجنبية الناقصة
do $$
declare r record;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname,
           (select string_agg(quote_ident(a.attname), ', ' order by k.ord)
              from unnest(c.conkey) with ordinality k(attnum, ord)
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum) as cols
      from pg_constraint c
     where c.contype = 'f' and c.connamespace = 'public'::regnamespace
       and not exists (
         select 1 from pg_index i
          where i.indrelid = c.conrelid
            and (string_to_array(i.indkey::text, ' ')::int2[])[1:cardinality(c.conkey)] = c.conkey)
  loop
    execute format('create index if not exists %I on %s (%s)',
      left('fk_' || replace(r.conname, '_fkey', '') || '_idx', 63), r.tbl, r.cols);
  end loop;
end $$;

-- جداول المحاولات بدون مفتاح أساسي
alter table public.invite_attempts add column if not exists id bigint generated always as identity primary key;
alter table public.recovery_attempts add column if not exists id bigint generated always as identity primary key;
alter table public.match_attempts add column if not exists id bigint generated always as identity primary key;

-- سياسات ALL المتداخلة (SELECT مرتين) تتفكك لأوامر مستقلة
drop policy if exists games_write_member on public.chat_games;
create policy games_insert_member on public.chat_games for insert to authenticated
  with check (public.is_member(chat_id));
create policy games_update_member on public.chat_games for update to authenticated
  using (public.is_member(chat_id)) with check (public.is_member(chat_id));
create policy games_delete_member on public.chat_games for delete to authenticated
  using (public.is_member(chat_id));

drop policy if exists reactions_write_own on public.reactions;
create policy reactions_insert_own on public.reactions for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (
    select 1 from public.messages m where m.id = reactions.message_id and public.is_member(m.chat_id)));
create policy reactions_update_own on public.reactions for update to authenticated
  using (user_id = (select auth.uid()) and exists (
    select 1 from public.messages m where m.id = reactions.message_id and public.is_member(m.chat_id)))
  with check (user_id = (select auth.uid()) and exists (
    select 1 from public.messages m where m.id = reactions.message_id and public.is_member(m.chat_id)));
create policy reactions_delete_own on public.reactions for delete to authenticated
  using (user_id = (select auth.uid()));

-- (204) auth.uid() داخل select حتى ما ينعاد حسابه لكل صف
do $$
declare p record; q text; w text; stmt text;
begin
  for p in
    select * from pg_policies
     where schemaname = 'public'
       and (coalesce(qual, '') ~ 'auth\.uid\(\)' or coalesce(with_check, '') ~ 'auth\.uid\(\)')
       and (coalesce(qual, '') || coalesce(with_check, '')) !~* 'select auth\.uid\(\)'
  loop
    q := regexp_replace(p.qual, 'auth\.uid\(\)', '(select auth.uid())', 'g');
    w := regexp_replace(p.with_check, 'auth\.uid\(\)', '(select auth.uid())', 'g');
    stmt := format('alter policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
    if p.cmd in ('SELECT', 'DELETE') then
      stmt := stmt || ' using (' || q || ')';
    elsif p.cmd = 'INSERT' then
      stmt := stmt || ' with check (' || w || ')';
    else
      if q is not null then stmt := stmt || ' using (' || q || ')'; end if;
      if w is not null then stmt := stmt || ' with check (' || w || ')'; end if;
    end if;
    execute stmt;
  end loop;
end $$;

-- (214) معرّف عميل لمنع تكرار الرسالة عند إعادة المحاولة
alter table public.messages add column if not exists client_id uuid;
create unique index if not exists messages_client_uniq on public.messages (sender_id, client_id);

-- (285) حد معدل الإرسال: 40 رسالة لكل 10 ثواني
create or replace function public.messages_rate_limit() returns trigger
language plpgsql set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then return new; end if;
  select count(*) into n from public.messages
   where sender_id = new.sender_id and created_at > now() - interval '10 seconds';
  if n >= 40 then raise exception 'rate_limited'; end if;
  return new;
end $$;
revoke execute on function public.messages_rate_limit() from public, anon, authenticated;
drop trigger if exists messages_a_rate on public.messages;
create trigger messages_a_rate before insert on public.messages
  for each row execute function public.messages_rate_limit();
