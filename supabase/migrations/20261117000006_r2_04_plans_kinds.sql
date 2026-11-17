alter table public.plans drop constraint if exists plans_kind_check;
alter table public.plans add constraint plans_kind_check check (kind in (
  'trip','savings','chore','poll','sticky','reason','food','book','bingo','photo','meet','wake','goal','wish','weekly','qa','story','quiz'));
