-- Project Home access-control hardening and auth profile bootstrap.

-- Create a profile automatically for every new Supabase Auth user.
create or replace function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, email, display_name, avatar_url)
  values(
    new.id,
    coalesce(new.email, new.id::text || '@placeholder.invalid'),
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'full_name'), ''),
      nullif(btrim(new.raw_user_meta_data->>'name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Member'
    ),
    nullif(new.raw_user_meta_data->>'avatar_url', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function app_private.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function app_private.handle_new_user();

-- Profiles should not be directly deletable from the mobile client.
drop policy if exists profile_self on public.profiles;
create policy profile_select_self
on public.profiles for select to authenticated
using (id = (select auth.uid()));
create policy profile_insert_self
on public.profiles for insert to authenticated
with check (id = (select auth.uid()));
create policy profile_update_self
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));
revoke delete on public.profiles from authenticated;

-- Invite rows can be inspected by adults, but raw mutation is server-controlled.
drop policy if exists invite_admin on public.household_invites;
create policy invite_read_adult
on public.household_invites for select to authenticated
using ((select app_private.is_adult(household_id)));
revoke insert, update, delete on public.household_invites from authenticated;

create or replace function public.revoke_household_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_household uuid;
begin
  select household_id into v_household
  from public.household_invites
  where id = p_invite_id
  for update;

  if v_household is null or not app_private.is_adult(v_household) then
    raise exception 'Invite not found or access denied';
  end if;

  update public.household_invites
  set revoked_at = coalesce(revoked_at, now())
  where id = p_invite_id;
end;
$$;
revoke all on function public.revoke_household_invite(uuid) from public, anon;
grant execute on function public.revoke_household_invite(uuid) to authenticated;

-- Tasks are read directly, but writes go through controlled RPCs so clients cannot
-- forge completion state, version fields, household IDs, or rotation state.
drop policy if exists task_member on public.tasks;
create policy task_read_member
on public.tasks for select to authenticated
using ((select app_private.is_member(household_id)));
revoke insert, update, delete on public.tasks from authenticated;

create or replace function public.create_task(
  p_household_id uuid,
  p_title text,
  p_notes text default null,
  p_assignment_type public.task_assignment default 'anyone',
  p_assigned_member_id uuid default null,
  p_due_at timestamptz default null,
  p_recurrence_type text default 'none',
  p_recurrence_anchor public.recurrence_anchor default 'scheduled',
  p_recurrence_config jsonb default null,
  p_rotation_member_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_id uuid;
  v_member uuid;
  v_pos integer := 0;
begin
  if not app_private.is_member(p_household_id) then raise exception 'Access denied'; end if;
  if btrim(coalesce(p_title,'')) = '' then raise exception 'Task title is required'; end if;
  if p_recurrence_type not in ('none','daily','weekly','monthly','interval') then raise exception 'Invalid recurrence type'; end if;
  if p_recurrence_type <> 'none' and p_due_at is null then raise exception 'Recurring tasks require a due date'; end if;

  if p_assignment_type = 'member' then
    if p_assigned_member_id is null or not exists (
      select 1 from public.household_members
      where id = p_assigned_member_id and household_id = p_household_id and status = 'active'
    ) then raise exception 'Invalid assignee'; end if;
  elsif p_assignment_type = 'anyone' then
    p_assigned_member_id := null;
  elsif p_assignment_type = 'rotation' then
    p_assigned_member_id := null;
    if p_rotation_member_ids is null or cardinality(p_rotation_member_ids) < 1 then
      raise exception 'Rotation needs at least one member';
    end if;
  end if;

  insert into public.tasks(
    household_id,title,notes,assignment_type,assigned_member_id,due_at,
    recurrence_type,recurrence_anchor,recurrence_config,created_by
  ) values (
    p_household_id,btrim(p_title),p_notes,p_assignment_type,p_assigned_member_id,p_due_at,
    p_recurrence_type,p_recurrence_anchor,p_recurrence_config,(select auth.uid())
  ) returning id into v_task_id;

  if p_assignment_type = 'rotation' then
    foreach v_member in array p_rotation_member_ids loop
      if not exists (
        select 1 from public.household_members
        where id = v_member and household_id = p_household_id and status = 'active'
      ) then raise exception 'Invalid rotation member'; end if;
      insert into public.task_rotation_members(task_id,member_id,position)
      values(v_task_id,v_member,v_pos);
      v_pos := v_pos + 1;
    end loop;
  end if;

  insert into public.activity_events(household_id,type,entity_type,entity_id)
  values(p_household_id,'task.created','task',v_task_id);
  return v_task_id;
end;
$$;
revoke all on function public.create_task(uuid,text,text,public.task_assignment,uuid,timestamptz,text,public.recurrence_anchor,jsonb,uuid[]) from public, anon;
grant execute on function public.create_task(uuid,text,text,public.task_assignment,uuid,timestamptz,text,public.recurrence_anchor,jsonb,uuid[]) to authenticated;

create or replace function public.update_task(
  p_task_id uuid,
  p_expected_version integer,
  p_title text,
  p_notes text,
  p_due_at timestamptz,
  p_assignment_type public.task_assignment,
  p_assigned_member_id uuid,
  p_recurrence_type text,
  p_recurrence_anchor public.recurrence_anchor,
  p_recurrence_config jsonb
)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare v_task public.tasks;
begin
  select * into v_task from public.tasks where id = p_task_id for update;
  if not found or not app_private.is_member(v_task.household_id) then raise exception 'Task not found or access denied'; end if;
  if v_task.version <> p_expected_version then raise exception 'Task changed on another device'; end if;
  if v_task.status <> 'open' then raise exception 'Completed tasks cannot be edited'; end if;
  if btrim(coalesce(p_title,'')) = '' then raise exception 'Task title is required'; end if;
  if p_recurrence_type not in ('none','daily','weekly','monthly','interval') then raise exception 'Invalid recurrence type'; end if;
  if p_recurrence_type <> 'none' and p_due_at is null then raise exception 'Recurring tasks require a due date'; end if;
  if p_assignment_type = 'rotation' then raise exception 'Edit rotation membership through a dedicated rotation flow'; end if;
  if p_assignment_type = 'member' and not exists (
    select 1 from public.household_members where id = p_assigned_member_id and household_id = v_task.household_id and status = 'active'
  ) then raise exception 'Invalid assignee'; end if;

  update public.tasks
  set title=btrim(p_title), notes=p_notes, due_at=p_due_at,
      assignment_type=p_assignment_type,
      assigned_member_id=case when p_assignment_type='member' then p_assigned_member_id else null end,
      recurrence_type=p_recurrence_type,
      recurrence_anchor=p_recurrence_anchor,
      recurrence_config=p_recurrence_config
  where id=p_task_id
  returning * into v_task;
  return v_task;
end;
$$;
revoke all on function public.update_task(uuid,integer,text,text,timestamptz,public.task_assignment,uuid,text,public.recurrence_anchor,jsonb) from public, anon;
grant execute on function public.update_task(uuid,integer,text,text,timestamptz,public.task_assignment,uuid,text,public.recurrence_anchor,jsonb) to authenticated;

create or replace function public.snooze_task(
  p_task_id uuid,
  p_expected_version integer,
  p_snoozed_until timestamptz
)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare v_task public.tasks;
begin
  select * into v_task from public.tasks where id=p_task_id for update;
  if not found or not app_private.is_member(v_task.household_id) then raise exception 'Task not found or access denied'; end if;
  if v_task.version <> p_expected_version then raise exception 'Task changed on another device'; end if;
  if v_task.status <> 'open' then raise exception 'Only open tasks can be snoozed'; end if;
  if p_snoozed_until <= now() then raise exception 'Snooze must be in the future'; end if;
  update public.tasks set snoozed_until=p_snoozed_until where id=p_task_id returning * into v_task;
  return v_task;
end;
$$;
revoke all on function public.snooze_task(uuid,integer,timestamptz) from public, anon;
grant execute on function public.snooze_task(uuid,integer,timestamptz) to authenticated;

create or replace function public.cancel_task(p_task_id uuid, p_expected_version integer)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare v_task public.tasks;
begin
  select * into v_task from public.tasks where id=p_task_id for update;
  if not found or not app_private.is_member(v_task.household_id) then raise exception 'Task not found or access denied'; end if;
  if v_task.version <> p_expected_version then raise exception 'Task changed on another device'; end if;
  update public.tasks set status='cancelled' where id=p_task_id returning * into v_task;
  return v_task;
end;
$$;
revoke all on function public.cancel_task(uuid,integer) from public, anon;
grant execute on function public.cancel_task(uuid,integer) to authenticated;

-- Household settings are controlled; direct table writes stay unavailable.
create or replace function public.update_household_settings(
  p_household_id uuid,
  p_name text,
  p_timezone text,
  p_currency char(3)
)
returns public.households
language plpgsql
security definer
set search_path = ''
as $$
declare v_household public.households;
begin
  if not app_private.is_adult(p_household_id) then raise exception 'Adult access required'; end if;
  if btrim(coalesce(p_name,''))='' then raise exception 'Household name is required'; end if;
  if p_currency !~ '^[A-Z]{3}$' then raise exception 'Invalid currency'; end if;
  update public.households
  set name=btrim(p_name), timezone=p_timezone, currency=p_currency, updated_at=now()
  where id=p_household_id and deleted_at is null
  returning * into v_household;
  return v_household;
end;
$$;
revoke all on function public.update_household_settings(uuid,text,text,char) from public, anon;
grant execute on function public.update_household_settings(uuid,text,text,char) to authenticated;

-- Prevent automatic future exposure of newly-created public objects.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, public;
