# Morning Checklist — Launch Day

Hey, past-Anne here. Handbook's shipped, code is in a good place.
Today is two parallel tracks — either order.

Coffee first. Then:

---

## TRACK A — Stripe setup (~45 min)

- [ ] **Text Leslie first:** "Running Stripe 2FA today — if you get a code text, ignore it, they're going to my phone"
- [ ] Open Stripe Dashboard → Products → create the 3 products
      (1 photo / $1, 5 photos / $4, Glow Up / $9/mo recurring)
- [ ] Payment Links → create one for each product
- [ ] Add `?client_reference_id={email}` to each link (so webhook knows who paid)
- [ ] Paste the 3 URLs into `STRIPE_CONFIG` in `index.html`
      (lines ~2600 — `link_1_photo`, `link_5_photos`, `link_unlimited`)
- [ ] Redeploy both folders from `deploy/` to Netlify
- [ ] Do a test purchase on your own account ($1) → confirm webhook flipped
      the `subscription_tier` field in Supabase

---

## TRACK B — Tech logins (~45 min)

- [ ] **Dry-run on your own account first** — trigger a password reset for
      yourself, check the email looks OK, walk through the flow end-to-end
- [ ] Text all 17 techs: *"Hey! Sending your MNC login setup email in the
      next hour. It'll come from **supabase.co** — don't mistake for spam.
      Click the link, set a password, you're in."*
- [ ] Supabase Dashboard → Authentication → Users → send password reset
      to each of the 17 (per-user, not bulk — bulk UI is gone for security)
- [ ] Set a 60-min timer. Stay in the inbox. Use Handbook Ch. 8 playbook
      for any "can't sign in" tickets

---

## TIGHT REFERENCE

| Thing | Where |
|---|---|
| Handbook | `MNC/docs/MNC-Co-Admin-Handbook.docx` |
| Supabase | [supabase.com/dashboard/project/ktiztunuifzbzwzyqrrq](https://supabase.com/dashboard/project/ktiztunuifzbzwzyqrrq) |
| Stripe | [dashboard.stripe.com](https://dashboard.stripe.com) |
| Punch list | `MNC/punch-list.html` |
| Ch. 8 "can't sign in" playbook | Handbook, page ~15 |

---

## IF TIME (nice-to-have, skip if tired)

- [ ] Confirm the ~18 "For Review" items in the punch list
- [ ] Post the soft-launch announcement to IG

---

## WINS BANKED FROM LAST NIGHT

- Handbook for Leslie, 28 pages, shipped
- International Phase 2 fully documented in Handbook Ch. 10 (don't go
  international immediately — geo-block EU/UK + build a waitlist first)
- Consent banner deferred — US-only soft launch = not urgent
- Branded auth emails queued for Phase 3

---

## DONE = 

Stripe live. 17 techs signed in. One real paying customer test.
That's the whole game today.

You got this. 🌸

*(Delete this file when the day's done.)*
