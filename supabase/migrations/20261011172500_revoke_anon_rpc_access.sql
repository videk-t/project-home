-- Explicitly prevent unauthenticated callers from invoking privileged household RPCs.
revoke all on function public.create_household(text,text,char) from anon, public;
revoke all on function public.accept_household_invite(text) from anon, public;

grant execute on function public.create_household(text,text,char) to authenticated;
grant execute on function public.accept_household_invite(text) to authenticated;
