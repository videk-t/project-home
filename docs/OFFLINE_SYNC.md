# Offline sync

SQLite persists a mutation queue with an ID, mutation/entity types, entity ID, JSON payload, timestamp, attempts, and status. Supported offline core actions are task completion and shopping item creation/completion. Each retriable financial or completion operation carries a UUID client mutation ID.

Queue lifecycle: pending → syncing → removed on acknowledged success; recoverable failures become failed and are retried on reconnect. Optimistic UI must remain visible while queued, and stale version edits must ask the user rather than silently overwrite finance data.
