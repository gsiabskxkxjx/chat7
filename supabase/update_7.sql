-- بيناتنا تحديث 7: توثيق الرقم عبر تلغرام (مجاني)، وتنظيف ملفات الوسائط اليتيمة
-- شغّله بعد update_1 إلى update_6. آمن لو انعاد.
-- الفكرة: تلغرام نفسه يتأكد إن الرقم لصاحب الحساب. السيرفر ما يشوف الرقم، يحفظ بصمة مشفّرة بس عشان ما ينربط رقم بحسابين.

-- 1) علامة التوثيق: ما أحد يغيّرها إلا الدوال تحت
alter table public.profiles add column if not exists phone_verified boolean not null default false;

create or replace function public.guard_phone_verified() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.phone_verified := false;
    return new;
  end if;
  if new.phone_verified is distinct from old.phone_verified
     and coalesce(current_setting('app.phone_ok', true), '') <> '1' then
    raise exception 'phone_locked';
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard_phone on public.profiles;
create trigger profiles_guard_phone before insert or update on public.profiles
  for each row execute function public.guard_phone_verified();

-- 2) جداول خاصة (ما أحد من التطبيق يقدر يقراها)
create table if not exists public.phone_links (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  phone_hash text not null unique,
  verified_at timestamptz not null default now()
);
alter table public.phone_links enable row level security;
revoke all on public.phone_links from anon, authenticated;

create table if not exists public.phone_codes (
  code text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  tg_id bigint,
  expires_at timestamptz not null default now() + interval '15 minutes'
);
alter table public.phone_codes enable row level security;
revoke all on public.phone_codes from anon, authenticated;

-- 3) التطبيق يطلب رمز لمرة وحدة (صالح 15 دقيقة) ويفتح بوت تلغرام فيه
create or replace function public.phone_verify_start() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c text; bot text;
begin
  if uid is null then raise exception 'not_signed_in'; end if;
  select v into bot from app_config where k = 'tg_bot';
  if bot is null or btrim(bot) = '' then
    return jsonb_build_object('bot', null);
  end if;
  delete from phone_codes where user_id = uid or expires_at < now();
  c := replace(gen_random_uuid()::text, '-', '');
  insert into phone_codes (code, user_id) values (c, uid);
  return jsonb_build_object('bot', btrim(bot), 'code', c);
end $$;
revoke execute on function public.phone_verify_start() from public, anon;
grant execute on function public.phone_verify_start() to authenticated;

-- 4) دوال البوت (service_role بس): نربط الرمز بحساب تلغرام، وبعدين نثبّت التوثيق
create or replace function public.phone_verify_bind(p_code text, p_tg bigint) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update phone_codes set tg_id = p_tg where code = p_code and expires_at > now();
  return found;
end $$;

create or replace function public.phone_verify_finish(p_tg bigint, p_hash text) returns text
language plpgsql security definer set search_path = public as $$
declare c phone_codes%rowtype;
begin
  select * into c from phone_codes where tg_id = p_tg and expires_at > now()
  order by expires_at desc limit 1;
  if not found then return 'no_code'; end if;
  if exists (select 1 from phone_links where phone_hash = p_hash and user_id <> c.user_id) then
    delete from phone_codes where code = c.code;
    return 'taken';
  end if;
  insert into phone_links (user_id, phone_hash) values (c.user_id, p_hash)
  on conflict (user_id) do update set phone_hash = excluded.phone_hash, verified_at = now();
  perform set_config('app.phone_ok', '1', true);
  update profiles set phone_verified = true where id = c.user_id;
  delete from phone_codes where code = c.code;
  return 'ok';
end $$;
revoke execute on function public.phone_verify_bind(text, bigint), public.phone_verify_finish(bigint, text)
  from public, anon, authenticated;
grant execute on function public.phone_verify_bind(text, bigint), public.phone_verify_finish(bigint, text)
  to service_role;

-- 5) إلغاء التوثيق (صاحب الحساب)
create or replace function public.phone_unlink() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  delete from phone_links where user_id = auth.uid();
  perform set_config('app.phone_ok', '1', true);
  update profiles set phone_verified = false where id = auth.uid();
end $$;
revoke execute on function public.phone_unlink() from public, anon;
grant execute on function public.phone_unlink() to authenticated;

-- 6) هل الطرف الثاني موثّق؟ (يظهر بمعلوماته)
create or replace function public.partner_verified(p_chat uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.phone_verified from chats c
    join profiles p on p.id = case when c.user_a = auth.uid() then c.user_b else c.user_a end
    where c.id = p_chat and auth.uid() in (c.user_a, c.user_b)), false)
$$;
revoke execute on function public.partner_verified(uuid) from public, anon;
grant execute on function public.partner_verified(uuid) to authenticated;

-- 7) اسم بوت تلغرام (بدل YOUR_BOT_USERNAME اسم البوت اللي سويته من BotFather، بدون @)
--    شيل علامتي التعليق عن السطرين تحت بعد ما تغيّر الاسم:
-- delete from public.app_config where k = 'tg_bot';
-- insert into public.app_config (k, v) values ('tg_bot', 'YOUR_BOT_USERNAME');

-- 8) تنظيف دوري: ملفات الوسائط اللي ما لها رسالة (مثل رفع انقطع قبل الإرسال)
--    ما نحذف إلا الأقدم من يومين، وما نحذف أي ملف مرتبط برسالة أو بتحدي الصورة.
create or replace function public.orphan_media(p_chat uuid) returns setof text
language sql stable security definer set search_path = public, storage as $$
  select o.name
  from storage.objects o
  where public.is_member(p_chat)
    and o.bucket_id = 'chat-media'
    and o.name like p_chat::text || '/%'
    and o.created_at < now() - interval '2 days'
    and not exists (select 1 from public.messages m where m.chat_id = p_chat and m.media_path = o.name)
    and not exists (select 1 from public.photo_challenge c where c.chat_id = p_chat and c.media_path = o.name)
  limit 200
$$;
revoke execute on function public.orphan_media(uuid) from public, anon;
grant execute on function public.orphan_media(uuid) to authenticated;

-- فحص: لازم يطلع true
select
  (select count(*) from information_schema.tables where table_schema = 'public'
     and table_name in ('phone_links', 'phone_codes')) = 2 as tables_ok;
