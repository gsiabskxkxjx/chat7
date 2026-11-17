-- الجولة الثانية / 2أ: أعمدة وقيود جديدة على الجداول الموجودة

-- (303) رسائل تختفي: مدة بالثواني لكل محادثة
alter table public.chats add column if not exists expire_after_s integer
  check (expire_after_s is null or expire_after_s between 300 and 31536000);

-- (354) حالة قصيرة بمؤقت، (320) المنطقة الزمنية لوضع المسافة
alter table public.profiles add column if not exists status_text text
  check (status_text is null or char_length(status_text) <= 30);
alter table public.profiles add column if not exists status_until timestamptz;
alter table public.profiles add column if not exists tz text
  check (tz is null or char_length(tz) <= 64);

-- (224) اقتباس جزء من الرسالة، (279) وصف الصورة، (201) صورة مصغّرة
alter table public.messages add column if not exists reply_quote text
  check (reply_quote is null or char_length(reply_quote) <= 300);
alter table public.messages add column if not exists alt text
  check (alt is null or char_length(alt) <= 300);
alter table public.messages add column if not exists thumb_path text;

-- (306) موقع، (305) بطاقة إشارة، (307) تنبيه عاجل
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check check (kind = any (array[
  'text','image','video','audio','call','think','card','vnote','file','location','ref','alert']));

-- (346/347) موعد متكرر وتذكير قبل الموعد
alter table public.chat_events add column if not exists repeat_every text not null default 'none'
  check (repeat_every in ('none','weekly','monthly','yearly'));
alter table public.chat_events add column if not exists remind_before_h integer not null default 0
  check (remind_before_h between 0 and 720);
alter table public.chat_events add column if not exists last_reminded_for date;
drop policy if exists chat_events_update on public.chat_events;
create policy chat_events_update on public.chat_events for update to authenticated
  using (public.is_member(chat_id)) with check (public.is_member(chat_id));

-- (321-330) ألعاب جديدة
alter table public.chat_games drop constraint if exists chat_games_kind_check;
alter table public.chat_games add constraint chat_games_kind_check check (kind = any (array[
  'tictactoe','rps','quiz','whoof','truefalse','memory','guess20','emoji','checkers','chess',
  'connect4','battleship','wordle','whosaid','truthdare','wordchain','story','canvas','bingo','weekly']));

-- (332/333/338) ألبومات: غلاف، تعليق، ترتيب، وسوم
alter table public.albums add column if not exists cover_message_id bigint
  references public.messages(id) on delete set null;
create index if not exists albums_cover_idx on public.albums (cover_message_id);
alter table public.album_items add column if not exists caption text
  check (caption is null or char_length(caption) <= 200);
alter table public.album_items add column if not exists sort_order integer not null default 0;
alter table public.album_items add column if not exists tags text[] not null default '{}'
  check (cardinality(tags) <= 5);

-- (343) تقسيم المصاريف وتسوية
alter table public.budget_items add column if not exists split_mode text not null default 'equal'
  check (split_mode in ('equal','payer','other'));
alter table public.budget_items add column if not exists settled_at timestamptz;
drop policy if exists budget_update on public.budget_items;
create policy budget_update on public.budget_items for update to authenticated
  using (public.is_member(chat_id)) with check (public.is_member(chat_id));

-- (286) فحص نوع الملف المرفوع بالسيرفر
update storage.buckets set allowed_mime_types = array[
  'image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif',
  'video/mp4','video/quicktime','video/webm','video/3gpp','video/x-matroska',
  'audio/mp4','audio/aac','audio/mpeg','audio/ogg','audio/webm','audio/x-m4a','audio/m4a',
  'audio/wav','audio/x-wav','audio/3gpp','audio/amr',
  'application/pdf','application/zip','application/octet-stream','text/plain',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation']
 where id = 'chat-media';
