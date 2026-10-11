# Project Home

Project Home is a calm, today-first shared household organizer built with Expo, TypeScript, and Supabase.

## Run locally

1. Copy `.env.example` to `.env` and supply a Supabase URL and publishable key.
2. `npm install`
3. `npm run start`

Use `npm run lint`, `npm run typecheck`, and `npm test` before merging. `npx supabase start` requires Docker; apply migrations with `npx supabase db reset` once local Supabase is running.

## Architecture

The Expo Router app uses domain modules for recurrence and integer-money logic, React Query for server state, Zustand only for transient UI state, and SQLite for the persisted mutation queue. All financial values are integer minor units. The database is the authorization authority: frontend state is never trusted for household access.

See [architecture](docs/ARCHITECTURE.md), [database](docs/DATABASE.md), [security](docs/SECURITY.md), [offline sync](docs/OFFLINE_SYNC.md), and [testing](docs/TESTING.md).
