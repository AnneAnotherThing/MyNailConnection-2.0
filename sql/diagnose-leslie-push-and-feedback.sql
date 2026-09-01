-- ============================================================================
-- diagnose-leslie-push-and-feedback.sql  (2026-08-25)
--
-- Two live reports from Leslie's iPhone test:
--   A. The "Say yes to notifications" step never ticked, with iOS
--      notifications plainly ON.
--   B. She received no notifications.
--   C. (Anne) Two bug reports filed from the floating pill, no email.
--
-- A and B are almost certainly ONE cause. That checkbox is not reading the
-- iOS permission -- it reads "does this account have a row in
-- push_subscriptions". No row means the box cannot tick AND send-push has
-- nothing to send to. Section 1 settles it in one look.
--
-- READ-ONLY. Replace LESLIE_DIGITS with her 10-digit number, digits only.
-- ============================================================================


-- NOTE (2026-08-27): push_subscriptions has updated_at, NOT created_at --
-- the row is rewritten on every re-registration. Sections 3 and 4 below
-- query feedback / contact_anne_messages, which do have created_at.
-- ── 1. DOES SHE HAVE A PUSH ROW, AND UNDER WHICH KEY? ───────────────────────
-- The app keys push_subscriptions.user_id off mncIdentity(): the auth email
-- when there is one, otherwise E.164. Leslie's real rows carry an email
-- (see fix-leslie-phone-login.sql), so hers should be the EMAIL even though
-- she signs in by phone. A row filed under the phone instead would explain
-- silence: the booking senders address her with pushKeyFor(tech.email,
-- tech.phone), which prefers the email.
with target (digits) as (values ('LESLIE_DIGITS'))
select
  t.name,
  t.email                             as tech_email,
  t.phone                             as tech_phone,
  au.email                            as auth_email,
  au.phone                            as auth_phone,
  coalesce(t.email, '+1' || (select digits from target)) as key_senders_will_use,
  ps.user_id                          as key_actually_stored,
  ps.auth                             as platform,
  case when ps.p256dh = 'native' then 'native token' else 'web push' end as kind,
  left(ps.endpoint, 18) || '…'        as token_head,
  ps.updated_at                       as last_registered,
  case
    when ps.user_id is null then 'NO ROW — checkbox cannot tick, nothing to send to'
    when t.email is not null and lower(ps.user_id) <> lower(t.email)
         then 'KEY MISMATCH — stored under ' || ps.user_id || ', senders use ' || t.email
    else 'looks right'
  end                                 as verdict
from public.techs t
left join auth.users au
       on right(public.phone_digits(au.phone), 10) = right(public.phone_digits(t.phone), 10)
left join public.push_subscriptions ps
       on lower(ps.user_id) = lower(coalesce(t.email, ''))
       or public.phone_digits(ps.user_id) = public.phone_digits(t.phone)
where right(public.phone_digits(t.phone), 10) = (select digits from target);


-- ── 2. WHO HAS PUSH AT ALL, BY PLATFORM ─────────────────────────────────────
-- If ios is 0 across the whole table, this is not Leslie -- it is every
-- iPhone, and the cause is the build or APNs, not her account.
select
  coalesce(auth, 'web/unknown')                    as platform,
  count(*)                                         as rows,
  count(distinct user_id)                          as people,
  max(updated_at)                                  as newest
from public.push_subscriptions
group by 1
order by 2 desc;


-- ── 3. DID ANNE'S TWO BUG REPORTS SAVE? ─────────────────────────────────────
-- The row is inserted BEFORE the alert email is attempted, and the email was
-- fire-and-forget behind an empty .catch(). So "no email" does not mean "no
-- report" -- expect these to be present even though nothing arrived.
select created_at, user_email, user_role, category,
       left(message, 120) as message_head, current_screen, app_version
from public.feedback
order by created_at desc
limit 10;

-- Same for the Contact-the-developer form, which shares the mail function.
select created_at, name, user_email, left(note, 120) as note_head
from public.contact_anne_messages
order by created_at desc
limit 10;
