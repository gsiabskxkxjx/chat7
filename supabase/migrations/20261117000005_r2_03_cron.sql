create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('dispatch-scheduled', '* * * * *', $$select public.dispatch_scheduled()$$);
select cron.schedule('dispatch-reminders', '*/10 * * * *', $$select public.dispatch_reminders()$$);
select cron.schedule('purge-expired', '17 * * * *', $$select public.purge_expired()$$);
