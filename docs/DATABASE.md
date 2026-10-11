# Database

The initial migration creates profiles, households, members, invites, tasks/completions/rotations, shopping, events, expenses/splits/settlements, bills/payments, activity, device tokens, and notification preferences. All identifiers are UUIDs and timestamps are `timestamptz`.

RPCs are `create_household`, `accept_household_invite`, `complete_task`, and `mark_bill_paid`. The latter two take a client mutation UUID to make retried operations idempotent. Invite raw tokens are never stored: clients hash them with SHA-256 only for server lookup. New public-schema tables receive explicit `authenticated` grants because current Supabase projects may not expose tables to the Data API automatically.

Seed data is intentionally kept out of production migrations. Add it to `supabase/seed.sql` only for local development.
