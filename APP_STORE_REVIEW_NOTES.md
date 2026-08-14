# App Store Review Notes — Chercharge

Paste into App Store Connect → App Review Information.

---

## Demo account (Sign-in required)

| Field | Value |
|--------|--------|
| **Username / Email** | `appreview@chercharge.com` |
| **Password** | `ReviewChercharge1!` |

Sign in with email/password on the Sign In screen (no in-app “review demo” button in the shipping build).

---

## Notes for App Review

```
Chercharge is a complete EV concierge customer app: garage, Founding Access rates, Book a Charge, Reservations, and Live Status.

SIGN-IN
Email: appreview@chercharge.com
Password: ReviewChercharge1!

COMPLETE FLOWS TO EXERCISE
1. Sign in with the credentials above.
2. Profile → Vehicles / Add Vehicle — manage garage and documents.
3. Profile → Founding Access — Accept & Pay presents Stripe PaymentSheet ($10 while lifetime spots remain). Founding is granted only after successful payment.
4. Home → Book a Charge — full multi-step booking (vehicle, pickup, payment, place request).
5. Reservations — upcoming / active / completed.
6. After placing a request, open Live Status / tracking.

IMPORTANT
• This is not a limited beta shell. Core concierge booking and tracking are available.
• Founding Access is an optional promotional rate lock, not a trial of an unfinished app.
• Account deletion: Profile → Settings / Privacy for normal accounts. The reserved review email cannot be deleted from the app (sign out instead).
• Photo permissions: registration / insurance documents and inspections.
• Payments: live Stripe PaymentSheet.

Contact: monitor App Store Connect messages during review.
```

---

## Pre-submit checklist

- [ ] Release build: Sign In has **no** Guest / App Review button / backend label
- [ ] Home CTA says **BOOK A CHARGE** (not Founding Access / Opening soon)
- [ ] Book a Charge completes end-to-end for the review account (add vehicle + approve docs as needed)
- [ ] Accept & Pay shows Stripe PaymentSheet; cancel does not grant Founding
- [ ] No “Opening soon” / “pre-launch” / “when we go live” on primary screens
