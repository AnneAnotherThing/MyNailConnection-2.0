# admin-reset-passwords

Edge Function that bulk-resets every user's password to match their email.

## Why this exists

Previously the admin panel asked you to paste the Supabase `service_role` key
into a text field in the browser. That key grants full DB access — putting it
in a form was a serious risk. This function moves the operation server-side:
the `service_role` key lives only in Supabase's secret store, and access is
gated by verifying the caller's JWT against an admin allow-list.

## How it works

1. Client calls this function with the admin's own auth token (Bearer JWT).
2. Function verifies the JWT via `auth.getUser()` and checks the email
   against the hardcoded `ADMIN_EMAILS` set.
3. If allowed, uses `SUPABASE_SERVICE_ROLE_KEY` (auto-injected by the runtime)
   to list auth users and bulk-reset passwords.

## Deploy

```
supabase functions deploy admin-reset-passwords
```

No extra secrets needed — `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` are populated automatically.

## Admin allow-list

Hardcoded at the top of `index.ts`:

```ts
const ADMIN_EMAILS = new Set<string>([
  'annewilson1021@gmail.com',
]);
```

Keep this in sync with the `public.is_admin()` function in your RLS policies.

## Endpoints

### Dry run — preview the email list

```bash
POST /functions/v1/admin-reset-passwords
Authorization: Bearer <admin_user_jwt>
Content-Type: application/json

{"dryRun": true}
```

Response:
```json
{ "dryRun": true, "count": 42, "emails": ["..."] }
```

### Execute — reset every password to match its email

```bash
POST /functions/v1/admin-reset-passwords
Authorization: Bearer <admin_user_jwt>
```

Response:
```json
{ "done": 40, "failed": 2, "failures": ["no-auth-row@example.com", "..."] }
```

## Failure modes

- `401 missing auth token` — no Bearer header
- `401 invalid token` — token doesn't validate against Supabase auth
- `403 not an admin` — caller is authenticated but not in `ADMIN_EMAILS`
- `500` — unexpected error (see body for detail)

## Security notes

- The admin list is duplicated in two places (this file + `public.is_admin()`).
  If that drift becomes a pain, consider a `user_roles` table and read from it
  here.
- Passwords reset to the user's email — intentional for onboarding convenience,
  but tell users to change their password on next login.
