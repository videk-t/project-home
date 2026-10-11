-- Avoid per-row auth.uid() re-evaluation in self-service RLS policies.
drop policy if exists tokens_self on public.device_tokens;
create policy tokens_self
on public.device_tokens for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists preferences_self on public.notification_preferences;
create policy preferences_self
on public.notification_preferences for all to authenticated
using (
  user_id = (select auth.uid())
  and (select app_private.is_member(household_id))
)
with check (
  user_id = (select auth.uid())
  and (select app_private.is_member(household_id))
);
