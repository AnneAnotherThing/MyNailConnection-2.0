# Supabase email-template fix — direct-link verify

**What:** swap each auth email template's confirmation link from the default `{{ .ConfirmationURL }}` (which 302s through `supabase.co`) to a direct link to `mynailconnection.com/app/`. Pairs with the `consumeMagicLinkVerifyIfPresent()` handler in `index.html` that converts the `token_hash` query param into a session on load.

**Why:** the default link goes to `https://<project>.supabase.co/auth/v1/verify?token=...` which redirects to your Site URL. iOS Universal Links only fire on a *direct* tap to a domain in the AASA file, never on a redirect — so the email link opens Safari instead of the installed app every time. Anne hit this in TestFlight on 2026-04-27.

**Prerequisite:** the `consumeMagicLinkVerifyIfPresent` handler must already be deployed to `mynailconnection.com/app/`. Check by viewing the deployed `index.html` source and searching for `consumeMagicLinkVerifyIfPresent` — if it's there, you're good.

---

## Steps

1. Open Supabase Dashboard → **Authentication** → **Email Templates**.

2. For **each** of these templates (start with "Confirm signup", that's the one that bit Anne):
   - **Confirm signup**
   - **Magic Link**
   - **Reset Password**
   - **Invite User**
   - **Change Email Address**

   Find the line in the HTML that currently looks like one of these:

   ```html
   <a href="{{ .ConfirmationURL }}">Confirm your mail</a>
   ```

   Replace it with:

   ```html
   <a href="https://mynailconnection.com/app/?token_hash={{ .TokenHash }}&type={{ .EmailActionType }}">Confirm your mail</a>
   ```

   The `{{ .EmailActionType }}` variable resolves per template:
   - signup → `signup`
   - magiclink → `magiclink`
   - recovery → `recovery`
   - invite → `invite`
   - email_change_current / email_change_new → `email_change`

3. Save each template.

4. Test on a fresh signup with a never-used email:
   - Sign up in TestFlight on iPad.
   - Tap the link in the verification email.
   - Expected: the **app** opens (not Safari), you arrive on tech home (or client home, depending on your role).
   - On a desktop browser without the app, same link works — just lands in the browser version of `/app/`.

5. If something goes wrong and the link errors out, the `consumeMagicLinkVerifyIfPresent` handler shows a soft toast: `"That confirmation link has expired. Please sign in or request a new one."` Re-send the verify from the sign-in screen.

---

## Rollback

If anything goes sideways, revert each template to `{{ .ConfirmationURL }}`. Users will be back to the legacy 302-redirect-via-supabase.co flow. Web users will be unaffected; iOS users will land in Safari again.

---

## Notes

- The `consumeMagicLinkVerifyIfPresent` handler also runs on **web** clients (anyone hitting the URL in a desktop browser without the app), so this template change is universal — no separate handling needed for web vs native.
- Tokens are one-time and short-lived. The handler strips them from the URL via `history.replaceState` immediately after consuming, so a back-nav can't replay a failed verify.
- The legacy `consumeRedirectTokensIfPresent` (which handles `#access_token=...` hash fragments from OAuth) is still wired in — Google / Apple sign-in keeps working unchanged.
