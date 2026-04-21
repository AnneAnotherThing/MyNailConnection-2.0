MNC Deploy Bundle — Marketing + App (separated)
================================================

This bundle has two folders. Deploy them to two different places (or two
different paths) — they should stay separate.

/marketing  — the public-facing www.mynailconnection.com landing page
              (index.html, screenshots, brand images, SEO files).
              Note: this file is called "marketing.html" in the source
              repo to distinguish it from the app's index.html, but is
              shipped here as index.html so it serves at the domain root
              with no rename step.

/app        — the My Nail Connection web app itself (index.html, the
              branded password-reset page, and the logo/icons it uses).


/marketing contents
-------------------
index.html            The public landing page (called "marketing.html"
                      in source; renamed here so it serves at the domain
                      root with no manual rename step).
images/               Logo in various sizes (webp + PNG) used by marketing.
app-screens/          Phone screenshots shown on the landing page.
favicon.ico, favicon-32.png, apple-touch-icon.png   Icons.
manifest.json         PWA manifest so mobile visitors can install the
                      marketing site.
sitemap.xml, robots.txt   SEO files.
privacy.html, terms.html   Shared legal pages (linked from the footer).
tech-guide.html       Tech onboarding guide (marketing links to it).

Deploying marketing
-------------------
Just drag the contents of /marketing/ to your marketing host. The file
is already named index.html, so it'll serve at https://mynailconnection.com/
with no further renames. Keep the subfolders (images/, app-screens/)
intact — they're referenced by relative paths.


/app contents
-------------
index.html            The single-page MNC app (splash, sign-in, tech
                      dashboard, client browse, etc.) — UPDATED in this
                      pass. See "What changed in the app" below.
reset-password.html   Branded password-reset landing page.
mncLogo-transparent.png   Transparent logo used by the reset page.
favicon.ico, favicon-32.png, apple-touch-icon.png   Icons.
privacy.html, terms.html   Duplicated here so the app can link to them
                      locally without depending on marketing's deploy.

Deploying the app
-----------------
Deploy /app to wherever your app lives — for example:
  https://app.mynailconnection.com/
  or  https://mynailconnection.com/app/
Keep index.html as the root file of whichever location you pick.

What changed in the app (index.html)
------------------------------------
Splash:      New "Forgot your password?" link under the sign-in buttons.
Tech dash:   Subtitle "Tech Dashboard" -> "Your Business".
             Greeting copy reframed as ownership ("Your business - at a glance").
             New "Need a hand?" card at the bottom of the dashboard with
             a Contact Anne button.
Contact Anne: New modal. Short-note textarea, consent checkbox, uses the
             tech's signed-in email to route the reply (no phone re-entry).
             Pushes you a notification with their email + note + timestamp.
             Language uses "ASAP," never "text."

What changed in reset-password.html
-----------------------------------
Branded welcome-back hero (logo ring, Playfair heading, ornament divider),
animated success checkmark, invalid-link fallback state. Parses the
Supabase recovery token from the URL hash, updates the password via
/auth/v1/user, and redirects back to sign in on success. No help link
(a user who's here already got what they needed).


Before the Contact Anne push will reach you
-------------------------------------------
Open /app/index.html, find:
    const ANNE_USER_ID = 'REPLACE_WITH_ANNE_AUTH_USER_UUID';
(near the top of the main script block) and paste your auth.users UUID
from Supabase Dashboard -> Authentication -> Users -> your row ->
"User UID."

You also need push enabled in MNC on whatever device you want pings to
reach (sign in on that device and accept the notification prompt).


Before sending real password-reset emails
-----------------------------------------
Supabase Dashboard -> Authentication -> URL Configuration:
  - Set Site URL to: https://<wherever-app-is-deployed>/reset-password.html
  - Add the same URL to the Redirect URLs allow-list
  - Save

Then dry-run a reset on your own account first and confirm the link lands
on the new reset-password.html before batch-sending to the 19 techs.


Sorry about the earlier bundle! It mixed the two without labeling them,
which is what caused the confusion. This one keeps them cleanly separated.
