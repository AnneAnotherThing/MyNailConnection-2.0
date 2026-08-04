-- Diagnostics, 2026-08-03. Read-only — safe to run any time.
-- Run in: Supabase dashboard → nwqnakoongrorbwnrqzc → SQL editor.
-- Paste ALL of it and send Claude the full output.
--
-- Covers three open questions from the launch lap:
--   1. Confirm bug — what UPDATE policies actually live on bookings, and do
--      the pending rows / tech identity line up with them?
--   2. Push — what does push_subscriptions really use as the user key?
--   3. Task #11 — are the reminder cron jobs even scheduled here?

-- 1a. Every policy on bookings, with its actual predicate text.
select policyname, cmd, permissive, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'bookings'
order by cmd, policyname;

-- 1b. The tech row for 480-440-2314 — exact stored phone format matters.
select id, name, email, phone, public.phone_digits(phone) as phone_digits
from public.techs
where public.phone_digits(phone) like '%4804402314';

-- 1c. The auth identity — what the JWT 'phone' claim will contain.
select id, email, phone, created_at
from auth.users
where regexp_replace(coalesce(phone,''), '\D', '', 'g') like '%4804402314'
   or lower(coalesce(email,'')) like '%anne%';

-- 1d. Live pending/confirmed bookings for that tech: whose client_id, what status.
select b.id, b.status, b.client_id, b.client_email, b.client_phone,
       b.tech_id, b.starts_at, b.created_at
from public.bookings b
where b.tech_id in (select id from public.techs
                    where public.phone_digits(phone) like '%4804402314')
order by b.created_at desc
limit 10;

-- 1e. Does the phone leg of the policy actually match? Simulates the
--     comparison the RLS does, using the auth.users phone from 1c.
select t.id as tech_id,
       public.phone_digits(t.phone) as techs_side,
       regexp_replace(coalesce(u.phone,''), '\D', '', 'g') as jwt_side,
       public.phone_digits(t.phone) = regexp_replace(coalesce(u.phone,''), '\D', '', 'g') as rls_phone_leg_matches
from public.techs t
cross join auth.users u
where public.phone_digits(t.phone) like '%4804402314'
  and regexp_replace(coalesce(u.phone,''), '\D', '', 'g') like '%4804402314';

-- 2. Push subscriptions: the real key format (answers which user_ids
--    variant send-push should be fired with).
select user_id, left(endpoint, 45) as endpoint_start, updated_at
from public.push_subscriptions
order by updated_at desc
limit 10;

-- 3. Cron jobs on this project — reminder jobs should appear here.
--    (Errors if pg_cron isn't installed; that itself is the answer.)
select jobid, jobname, schedule, command
from cron.job
order by jobid;
