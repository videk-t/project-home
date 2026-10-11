# Security

Every exposed table has RLS enabled. Access is based on the active `household_members` row, never editable auth metadata. Direct membership mutation is not allowed by a policy; privileged membership creation occurs in atomic RPCs. Managed people have no user ID and cannot be owners.

Security-definer functions pin `search_path`, authenticate with `auth.uid()`, and have `PUBLIC` execution revoked before `authenticated` is granted. Do not add a service-role key to Expo environment variables. On membership removal, revoke access in the database first, then clear local cache as UX cleanup.
