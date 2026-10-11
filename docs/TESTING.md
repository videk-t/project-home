# Testing

Unit tests cover recurrence anchors, rotation, snooze, equal rounding, custom splits, and balance effects. Add database tests against local Supabase for cross-household read/write, role escalation, managed ownership, invite expiry/revocation, member removal, and duplicate mutations.

CI runs install, lint, typecheck, unit tests, and Expo diagnostics. Local Supabase security and multi-user E2E tests need Docker and test credentials.
