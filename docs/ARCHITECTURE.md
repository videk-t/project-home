# Architecture

`app/` contains route composition; `src/features/` contains feature state; `src/domain/` contains pure business rules; `src/lib/` owns Supabase, offline persistence, notifications, query configuration, and analytics boundaries. Screens must not calculate recurrence or money values.

Startup loads SQLite cache, renders immediately, refreshes the active household, connects private realtime, then flushes queued core mutations. A removal event must disconnect realtime, clear household cache, and navigate away; RLS remains the real boundary.

Realtime should use household-scoped private broadcast channels (`household:<id>`) for scalable shared invalidation, with database RLS still governing table data. The current Supabase documentation recommends Broadcast over Postgres Changes at scale.
