-- بيناتنا تحديث 3: الاهتمامات (تظهر بالمطابقة وتقدّم الناس المتشابهين) + تاريخ بداية العلاقة
-- شغّله بعد update_1 و update_2. آمن لو انعاد.

alter table public.profiles add column if not exists interests text[] not null default '{}';
alter table public.profiles drop constraint if exists profiles_interests_len;
alter table public.profiles add constraint profiles_interests_len check (cardinality(interests) <= 3);

alter table public.chats add column if not exists started_on date;
alter table public.chats drop constraint if exists chats_started_on_past;
alter table public.chats add constraint chats_started_on_past
  check (started_on is null or (started_on <= current_date + 1 and started_on >= date '1950-01-01'));

-- البحث يقدّم اللي عندهم اهتمامات مشتركة أكثر
create or replace function public.match_start() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  me profiles%rowtype;
  other uuid;
  oid bigint;
  n int;
  pend match_offers%rowtype;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  perform pg_advisory_xact_lock(424242);
  select * into me from profiles where id = uid;
  if not found then raise exception 'no_profile'; end if;
  if me.gender is null or coalesce(btrim(me.display_name), '') = '' then
    raise exception 'profile_incomplete';
  end if;
  if not public.is_adult(uid) then raise exception 'under_18'; end if;
  if exists (select 1 from chats where uid in (user_a, user_b)) then raise exception 'already_paired'; end if;

  update match_offers set status = 'expired'
    where status = 'pending' and created_at < now() - interval '2 minutes';
  select * into pend from match_offers
    where status = 'pending' and uid in (user_a, user_b) order by id desc limit 1;
  if found then
    delete from match_queue where user_id = uid;
    return jsonb_build_object('status', 'offer', 'offer_id', pend.id);
  end if;

  if not exists (select 1 from match_queue where user_id = uid) then
    delete from match_attempts where at < now() - interval '1 day';
    select count(*) into n from match_attempts where user_id = uid;
    if n >= 10 then raise exception 'daily_limit'; end if;
    insert into match_attempts (user_id) values (uid);
    insert into match_queue (user_id, gender) values (uid, me.gender);
  else
    update match_queue set seen_at = now() where user_id = uid;
  end if;

  select q.user_id into other from match_queue q
    join profiles op on op.id = q.user_id
    where q.user_id <> uid
      and q.gender <> me.gender
      and q.seen_at > now() - interval '45 seconds'
      and not exists (select 1 from chats c where q.user_id in (c.user_a, c.user_b))
      and not exists (select 1 from match_skips s
                      where (s.user_id = uid and s.other_id = q.user_id)
                         or (s.user_id = q.user_id and s.other_id = uid))
      and not exists (select 1 from blocks b
                      where (b.blocker = uid and b.blocked = q.user_id)
                         or (b.blocker = q.user_id and b.blocked = uid))
      and public.is_adult(q.user_id)
    order by cardinality(array(select unnest(op.interests) intersect select unnest(me.interests))) desc,
             q.created_at
    limit 1;
  if other is null then
    return jsonb_build_object('status', 'waiting');
  end if;

  delete from match_queue where user_id in (uid, other);
  insert into match_offers (user_a, user_b) values (other, uid) returning id into oid;
  return jsonb_build_object('status', 'offer', 'offer_id', oid);
end; $$;

-- بطاقة العرض: تضيف الاهتمامات والمشتركة منها
create or replace function public.match_card(p_offer bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  o match_offers%rowtype;
  other uuid;
  p profiles%rowtype;
begin
  select * into o from match_offers where id = p_offer and uid in (user_a, user_b);
  if not found then return null; end if;
  other := case when o.user_a = uid then o.user_b else o.user_a end;
  select * into p from profiles where id = other;
  return jsonb_build_object(
    'name', p.display_name,
    'avatar', p.avatar_path,
    'gender', p.gender,
    'interests', to_jsonb(p.interests),
    'common', to_jsonb(array(select unnest(p.interests) intersect
                             select unnest((select interests from profiles where id = uid)))),
    'status', case when o.status = 'pending' and o.created_at < now() - interval '2 minutes'
                   then 'expired' else o.status end,
    'seconds_left', greatest(0, extract(epoch from (o.created_at + interval '2 minutes' - now()))::int),
    'my_ok', case when o.user_a = uid then o.a_ok else o.b_ok end,
    'their_ok', case when o.user_a = uid then o.b_ok else o.a_ok end,
    'chat_id', o.chat_id);
end; $$;

revoke execute on function public.match_start(), public.match_card(bigint) from public, anon;
grant execute on function public.match_start(), public.match_card(bigint) to authenticated;

-- تأكيد: لازم يطلع 1 بكل عمود
select
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'interests') as interests,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'chats' and column_name = 'started_on') as started_on;
