-- Project Home backend hardening.
-- Keeps the initial migration intact and closes cross-household integrity gaps,
-- adds safer atomic financial/task RPCs, and configures private household Broadcast.

-- Composite uniqueness lets household_id participate in integrity FKs.
alter table public.household_members
  add constraint household_members_household_id_id_key unique (household_id, id);
alter table public.shopping_lists
  add constraint shopping_lists_household_id_id_key unique (household_id, id);
alter table public.tasks
  add constraint tasks_household_id_id_key unique (household_id, id);
alter table public.expenses
  add constraint expenses_household_id_id_key unique (household_id, id);
alter table public.bills
  add constraint bills_household_id_id_key unique (household_id, id);

-- Enforce that referenced members/entities belong to the same household.
alter table public.tasks
  add constraint tasks_assignee_same_household_fk
  foreign key (household_id, assigned_member_id)
  references public.household_members(household_id, id);
alter table public.tasks
  add constraint tasks_completer_same_household_fk
  foreign key (household_id, completed_by_member_id)
  references public.household_members(household_id, id);
alter table public.task_completions
  add constraint task_completions_task_same_household_fk
  foreign key (household_id, task_id)
  references public.tasks(household_id, id);
alter table public.task_completions
  add constraint task_completions_member_same_household_fk
  foreign key (household_id, completed_by_member_id)
  references public.household_members(household_id, id);
alter table public.shopping_items
  add constraint shopping_items_list_same_household_fk
  foreign key (household_id, list_id)
  references public.shopping_lists(household_id, id);
alter table public.shopping_items
  add constraint shopping_items_creator_same_household_fk
  foreign key (household_id, created_by_member_id)
  references public.household_members(household_id, id);
alter table public.shopping_items
  add constraint shopping_items_completer_same_household_fk
  foreign key (household_id, completed_by_member_id)
  references public.household_members(household_id, id);
alter table public.expenses
  add constraint expenses_payer_same_household_fk
  foreign key (household_id, paid_by_member_id)
  references public.household_members(household_id, id);
alter table public.expense_splits
  add constraint expense_splits_expense_same_household_fk
  foreign key (household_id, expense_id)
  references public.expenses(household_id, id);
alter table public.expense_splits
  add constraint expense_splits_member_same_household_fk
  foreign key (household_id, member_id)
  references public.household_members(household_id, id);
alter table public.settlements
  add constraint settlements_from_same_household_fk
  foreign key (household_id, from_member_id)
  references public.household_members(household_id, id);
alter table public.settlements
  add constraint settlements_to_same_household_fk
  foreign key (household_id, to_member_id)
  references public.household_members(household_id, id);
alter table public.bills
  add constraint bills_assignee_same_household_fk
  foreign key (household_id, assigned_member_id)
  references public.household_members(household_id, id);
alter table public.bill_payments
  add constraint bill_payments_bill_same_household_fk
  foreign key (household_id, bill_id)
  references public.bills(household_id, id);
alter table public.bill_payments
  add constraint bill_payments_member_same_household_fk
  foreign key (household_id, paid_by_member_id)
  references public.household_members(household_id, id);
alter table public.activity_events
  add constraint activity_actor_same_household_fk
  foreign key (household_id, actor_member_id)
  references public.household_members(household_id, id);

-- Expense retries need the same idempotency protection as task/bill/settlement mutations.
alter table public.expenses add column client_mutation_id uuid;
create unique index expenses_client_mutation_id_unique
  on public.expenses(client_mutation_id)
  where client_mutation_id is not null;

-- Tighten private helper functions: private schema + empty search_path + explicit qualification.
create or replace function app_private.is_member(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.household_members m
    join public.households h on h.id = m.household_id
    where m.household_id = target_household
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and h.deleted_at is null
  )
$$;

create or replace function app_private.is_adult(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.household_members m
    join public.households h on h.id = m.household_id
    where m.household_id = target_household
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role in ('owner','adult')
      and h.deleted_at is null
  )
$$;

create or replace function app_private.is_owner(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.household_members m
    join public.households h on h.id = m.household_id
    where m.household_id = target_household
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role = 'owner'
      and h.deleted_at is null
  )
$$;

revoke execute on all functions in schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated;
grant execute on function app_private.is_member(uuid) to authenticated;
grant execute on function app_private.is_adult(uuid) to authenticated;
grant execute on function app_private.is_owner(uuid) to authenticated;

-- Links without household_id get trigger-level household integrity checks.
create or replace function app_private.enforce_rotation_member_household()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_household uuid;
begin
  select t.household_id into v_household
  from public.tasks t
  where t.id = new.task_id;

  if v_household is null or not exists (
    select 1 from public.household_members m
    where m.id = new.member_id
      and m.household_id = v_household
      and m.status = 'active'
  ) then
    raise exception 'Rotation member must be active in the task household';
  end if;
  return new;
end;
$$;

create or replace function app_private.enforce_event_member_household()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_household uuid;
begin
  select e.household_id into v_household
  from public.events e
  where e.id = new.event_id;

  if v_household is null or not exists (
    select 1 from public.household_members m
    where m.id = new.member_id
      and m.household_id = v_household
      and m.status = 'active'
  ) then
    raise exception 'Event member must be active in the event household';
  end if;
  return new;
end;
$$;

create trigger enforce_rotation_member_household_trigger
before insert or update on public.task_rotation_members
for each row execute function app_private.enforce_rotation_member_household();

create trigger enforce_event_member_household_trigger
before insert or update on public.event_members
for each row execute function app_private.enforce_event_member_household();

-- Old task/bill RPCs lack stale-version protection. Keep them inaccessible to clients.
revoke execute on function public.complete_task(uuid,uuid,uuid,timestamptz) from authenticated, anon, public;
revoke execute on function public.mark_bill_paid(uuid,uuid,uuid,timestamptz) from authenticated, anon, public;

-- Complete a task atomically. expected_version prevents two devices from accidentally
-- completing two recurring cycles from one stale screen.
create or replace function public.complete_task_v2(
  p_task_id uuid,
  p_member_id uuid,
  p_client_mutation_id uuid,
  p_expected_version integer,
  p_completed_at timestamptz default now()
)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.tasks;
  v_next_due timestamptz;
  v_interval integer;
  v_unit text;
  v_rotation_count integer;
  v_expected_member uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select * into v_task
  from public.tasks
  where id = p_task_id
  for update;

  if not found or not app_private.is_member(v_task.household_id) then
    raise exception 'Task not found or access denied';
  end if;

  if exists (
    select 1 from public.task_completions
    where client_mutation_id = p_client_mutation_id
  ) then
    return v_task;
  end if;

  if v_task.version <> p_expected_version then
    raise exception 'Task changed on another device';
  end if;

  if v_task.status <> 'open' then
    raise exception 'Task is already completed';
  end if;

  if not exists (
    select 1 from public.household_members m
    where m.id = p_member_id
      and m.household_id = v_task.household_id
      and m.status = 'active'
  ) then
    raise exception 'Invalid completing member';
  end if;

  if v_task.assignment_type = 'member' and v_task.assigned_member_id is distinct from p_member_id then
    raise exception 'Task is assigned to another member';
  end if;

  if v_task.assignment_type = 'rotation' then
    select count(*) into v_rotation_count
    from public.task_rotation_members
    where task_id = v_task.id;

    if v_rotation_count < 1 then
      raise exception 'Rotation task has no members';
    end if;

    select trm.member_id into v_expected_member
    from public.task_rotation_members trm
    where trm.task_id = v_task.id
    order by trm.position
    offset (v_task.rotation_index % v_rotation_count)
    limit 1;

    if v_expected_member is distinct from p_member_id then
      raise exception 'Task is assigned to another rotation member';
    end if;
  end if;

  insert into public.task_completions(
    task_id, household_id, completed_by_member_id, completed_at,
    scheduled_due_at, client_mutation_id
  ) values (
    v_task.id, v_task.household_id, p_member_id, p_completed_at,
    v_task.due_at, p_client_mutation_id
  );

  if v_task.recurrence_type = 'none' then
    update public.tasks
    set status = 'completed',
        completed_at = p_completed_at,
        completed_by_member_id = p_member_id,
        snoozed_until = null
    where id = v_task.id
    returning * into v_task;
  else
    if v_task.due_at is null then
      raise exception 'Recurring tasks require a due date';
    end if;

    v_interval := greatest(coalesce((v_task.recurrence_config->>'interval')::integer, 1), 1);
    v_unit := coalesce(v_task.recurrence_config->>'unit', 'days');

    if v_task.recurrence_type = 'daily' then
      v_next_due := (case when v_task.recurrence_anchor = 'completion' then p_completed_at else v_task.due_at end)
                    + make_interval(days => v_interval);
    elsif v_task.recurrence_type = 'weekly' then
      v_next_due := (case when v_task.recurrence_anchor = 'completion' then p_completed_at else v_task.due_at end)
                    + make_interval(days => 7 * v_interval);
    elsif v_task.recurrence_type = 'monthly' then
      v_next_due := (case when v_task.recurrence_anchor = 'completion' then p_completed_at else v_task.due_at end)
                    + make_interval(months => v_interval);
    elsif v_task.recurrence_type = 'interval' then
      if v_unit = 'months' then
        v_next_due := (case when v_task.recurrence_anchor = 'completion' then p_completed_at else v_task.due_at end)
                      + make_interval(months => v_interval);
      elsif v_unit = 'weeks' then
        v_next_due := (case when v_task.recurrence_anchor = 'completion' then p_completed_at else v_task.due_at end)
                      + make_interval(days => 7 * v_interval);
      else
        v_next_due := (case when v_task.recurrence_anchor = 'completion' then p_completed_at else v_task.due_at end)
                      + make_interval(days => v_interval);
      end if;
    else
      raise exception 'Unsupported recurrence type';
    end if;

    update public.tasks
    set status = 'open',
        due_at = v_next_due,
        snoozed_until = null,
        completed_at = p_completed_at,
        completed_by_member_id = p_member_id,
        rotation_index = case
          when v_task.assignment_type = 'rotation' then (v_task.rotation_index + 1) % v_rotation_count
          else v_task.rotation_index
        end
    where id = v_task.id
    returning * into v_task;
  end if;

  insert into public.activity_events(household_id, actor_member_id, type, entity_type, entity_id)
  values(v_task.household_id, p_member_id, 'task.completed', 'task', v_task.id);

  return v_task;
end;
$$;

revoke all on function public.complete_task_v2(uuid,uuid,uuid,integer,timestamptz) from public, anon;
grant execute on function public.complete_task_v2(uuid,uuid,uuid,integer,timestamptz) to authenticated;

-- Expense creation is one transaction and exact split totals are enforced server-side.
create or replace function public.create_expense(
  p_title text,
  p_amount_minor bigint,
  p_currency char(3),
  p_paid_by_member_id uuid,
  p_expense_date date,
  p_splits jsonb,
  p_client_mutation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_household uuid;
  v_expense_id uuid;
  v_split_total bigint;
  v_split jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if p_amount_minor <= 0 then raise exception 'Amount must be positive'; end if;
  if p_currency !~ '^[A-Z]{3}$' then raise exception 'Invalid currency'; end if;

  select m.household_id into v_household
  from public.household_members m
  where m.id = p_paid_by_member_id
    and m.status = 'active';

  if v_household is null or not app_private.is_member(v_household) then
    raise exception 'Invalid payer or access denied';
  end if;

  select id into v_expense_id
  from public.expenses
  where client_mutation_id = p_client_mutation_id;
  if v_expense_id is not null then return v_expense_id; end if;

  if jsonb_typeof(p_splits) <> 'array' or jsonb_array_length(p_splits) < 1 then
    raise exception 'At least one split is required';
  end if;

  select coalesce(sum((x->>'amount_minor')::bigint), 0)
    into v_split_total
  from jsonb_array_elements(p_splits) x;

  if v_split_total <> p_amount_minor then
    raise exception 'Split amounts must equal expense amount';
  end if;

  insert into public.expenses(
    household_id, title, amount_minor, currency, paid_by_member_id,
    expense_date, created_by, client_mutation_id
  ) values (
    v_household, btrim(p_title), p_amount_minor, p_currency,
    p_paid_by_member_id, coalesce(p_expense_date, current_date),
    (select auth.uid()), p_client_mutation_id
  ) returning id into v_expense_id;

  for v_split in select * from jsonb_array_elements(p_splits)
  loop
    if (v_split->>'amount_minor')::bigint < 0 then
      raise exception 'Split amount cannot be negative';
    end if;
    if not exists (
      select 1 from public.household_members m
      where m.id = (v_split->>'member_id')::uuid
        and m.household_id = v_household
        and m.status = 'active'
    ) then
      raise exception 'Split member is not active in this household';
    end if;

    insert into public.expense_splits(expense_id, household_id, member_id, amount_minor)
    values(
      v_expense_id,
      v_household,
      (v_split->>'member_id')::uuid,
      (v_split->>'amount_minor')::bigint
    );
  end loop;

  insert into public.activity_events(household_id, type, entity_type, entity_id)
  values(v_household, 'expense.created', 'expense', v_expense_id);

  return v_expense_id;
end;
$$;

revoke all on function public.create_expense(text,bigint,char,uuid,date,jsonb,uuid) from public, anon;
grant execute on function public.create_expense(text,bigint,char,uuid,date,jsonb,uuid) to authenticated;

create or replace function public.create_settlement(
  p_household_id uuid,
  p_from_member_id uuid,
  p_to_member_id uuid,
  p_amount_minor bigint,
  p_currency char(3),
  p_client_mutation_id uuid,
  p_settled_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not app_private.is_member(p_household_id) then raise exception 'Access denied'; end if;
  if p_from_member_id = p_to_member_id then raise exception 'Cannot settle with self'; end if;
  if p_amount_minor <= 0 then raise exception 'Amount must be positive'; end if;

  select id into v_id from public.settlements where client_mutation_id = p_client_mutation_id;
  if v_id is not null then return v_id; end if;

  if not exists (
    select 1 from public.household_members
    where id in (p_from_member_id, p_to_member_id)
      and household_id = p_household_id
      and status = 'active'
    group by household_id
    having count(*) = 2
  ) then
    raise exception 'Settlement members must be active in this household';
  end if;

  insert into public.settlements(
    household_id, from_member_id, to_member_id, amount_minor, currency,
    settled_at, created_by, client_mutation_id
  ) values (
    p_household_id, p_from_member_id, p_to_member_id, p_amount_minor,
    p_currency, p_settled_at, (select auth.uid()), p_client_mutation_id
  ) returning id into v_id;

  insert into public.activity_events(household_id, type, entity_type, entity_id)
  values(p_household_id, 'settlement.created', 'settlement', v_id);

  return v_id;
end;
$$;

revoke all on function public.create_settlement(uuid,uuid,uuid,bigint,char,uuid,timestamptz) from public, anon;
grant execute on function public.create_settlement(uuid,uuid,uuid,bigint,char,uuid,timestamptz) to authenticated;

-- Bill payment with stale-version protection.
create or replace function public.mark_bill_paid_v2(
  p_bill_id uuid,
  p_member_id uuid,
  p_client_mutation_id uuid,
  p_expected_version integer,
  p_paid_at timestamptz default now()
)
returns public.bills
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bill public.bills;
  v_existing uuid;
  v_interval integer;
  v_unit text;
begin
  select * into v_bill from public.bills where id = p_bill_id for update;
  if not found or not app_private.is_member(v_bill.household_id) then
    raise exception 'Bill not found or access denied';
  end if;

  select bill_id into v_existing
  from public.bill_payments
  where client_mutation_id = p_client_mutation_id;
  if v_existing is not null then return v_bill; end if;

  if v_bill.version <> p_expected_version then
    raise exception 'Bill changed on another device';
  end if;
  if v_bill.status <> 'active' then raise exception 'Bill is not active'; end if;
  if not exists (
    select 1 from public.household_members
    where id = p_member_id
      and household_id = v_bill.household_id
      and status = 'active'
  ) then raise exception 'Invalid paying member'; end if;

  insert into public.bill_payments(
    bill_id, household_id, amount_minor, due_at, paid_at,
    paid_by_member_id, client_mutation_id
  ) values (
    v_bill.id, v_bill.household_id, v_bill.amount_minor, v_bill.due_at,
    p_paid_at, p_member_id, p_client_mutation_id
  );

  v_interval := greatest(coalesce((v_bill.recurrence_config->>'interval')::integer, 1), 1);
  v_unit := coalesce(v_bill.recurrence_config->>'unit', 'days');

  if v_bill.recurrence_type = 'daily' then
    update public.bills set due_at = v_bill.due_at + make_interval(days => v_interval)
    where id = v_bill.id returning * into v_bill;
  elsif v_bill.recurrence_type = 'weekly' then
    update public.bills set due_at = v_bill.due_at + make_interval(days => 7 * v_interval)
    where id = v_bill.id returning * into v_bill;
  elsif v_bill.recurrence_type = 'monthly' then
    update public.bills set due_at = v_bill.due_at + make_interval(months => v_interval)
    where id = v_bill.id returning * into v_bill;
  elsif v_bill.recurrence_type = 'yearly' then
    update public.bills set due_at = v_bill.due_at + make_interval(years => v_interval)
    where id = v_bill.id returning * into v_bill;
  elsif v_bill.recurrence_type = 'interval' then
    if v_unit = 'months' then
      update public.bills set due_at = v_bill.due_at + make_interval(months => v_interval)
      where id = v_bill.id returning * into v_bill;
    elsif v_unit = 'weeks' then
      update public.bills set due_at = v_bill.due_at + make_interval(days => 7 * v_interval)
      where id = v_bill.id returning * into v_bill;
    else
      update public.bills set due_at = v_bill.due_at + make_interval(days => v_interval)
      where id = v_bill.id returning * into v_bill;
    end if;
  else
    update public.bills set status = 'paused'
    where id = v_bill.id returning * into v_bill;
  end if;

  insert into public.activity_events(household_id, actor_member_id, type, entity_type, entity_id)
  values(v_bill.household_id, p_member_id, 'bill.paid', 'bill', v_bill.id);

  return v_bill;
end;
$$;

revoke all on function public.mark_bill_paid_v2(uuid,uuid,uuid,integer,timestamptz) from public, anon;
grant execute on function public.mark_bill_paid_v2(uuid,uuid,uuid,integer,timestamptz) to authenticated;

-- Managed member and ownership-sensitive operations.
create or replace function public.create_managed_member(
  p_household_id uuid,
  p_display_name text,
  p_role public.household_role default 'managed'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if not app_private.is_adult(p_household_id) then raise exception 'Adult access required'; end if;
  if p_role = 'owner' then raise exception 'Managed members cannot be owners'; end if;
  insert into public.household_members(
    household_id, user_id, display_name, member_type, role, created_by
  ) values (
    p_household_id, null, btrim(p_display_name), 'managed', p_role, (select auth.uid())
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.create_managed_member(uuid,text,public.household_role) from public, anon;
grant execute on function public.create_managed_member(uuid,text,public.household_role) to authenticated;

create or replace function public.transfer_ownership(
  p_household_id uuid,
  p_new_owner_member_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_current_member uuid;
begin
  if not app_private.is_owner(p_household_id) then raise exception 'Owner access required'; end if;

  select id into v_current_member
  from public.household_members
  where household_id = p_household_id
    and user_id = (select auth.uid())
    and status = 'active'
    and role = 'owner'
  for update;

  if not exists (
    select 1 from public.household_members
    where id = p_new_owner_member_id
      and household_id = p_household_id
      and status = 'active'
      and member_type = 'account'
  ) then raise exception 'New owner must be an active account member'; end if;

  update public.household_members
    set role = 'adult'
    where id = v_current_member;
  update public.household_members
    set role = 'owner'
    where id = p_new_owner_member_id;
end;
$$;

revoke all on function public.transfer_ownership(uuid,uuid) from public, anon;
grant execute on function public.transfer_ownership(uuid,uuid) to authenticated;

create or replace function public.remove_household_member(
  p_household_id uuid,
  p_member_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_target public.household_members;
begin
  if not app_private.is_adult(p_household_id) then raise exception 'Adult access required'; end if;
  select * into v_target
  from public.household_members
  where id = p_member_id and household_id = p_household_id
  for update;
  if not found or v_target.status <> 'active' then raise exception 'Member not found'; end if;
  if v_target.role = 'owner' then raise exception 'Transfer ownership before removing an owner'; end if;

  update public.household_members
    set status = 'removed', removed_at = now()
    where id = p_member_id;

  insert into public.activity_events(household_id, type, entity_type, entity_id)
  values(p_household_id, 'member.removed', 'member', p_member_id);
end;
$$;

revoke all on function public.remove_household_member(uuid,uuid) from public, anon;
grant execute on function public.remove_household_member(uuid,uuid) to authenticated;

-- Server-generated invite token. The database stores only SHA-256.
create or replace function public.create_household_invite(
  p_household_id uuid,
  p_role public.household_role default 'member',
  p_expires_at timestamptz default (now() + interval '7 days'),
  p_max_uses integer default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare v_token text;
begin
  if not app_private.is_adult(p_household_id) then raise exception 'Adult access required'; end if;
  if p_role = 'owner' then raise exception 'Invite cannot grant owner'; end if;
  if p_expires_at <= now() then raise exception 'Invite expiry must be in the future'; end if;
  if p_max_uses is not null and p_max_uses < 1 then raise exception 'max_uses must be positive'; end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.household_invites(
    household_id, token_hash, created_by, role, expires_at, max_uses
  ) values (
    p_household_id,
    encode(digest(v_token, 'sha256'), 'hex'),
    (select auth.uid()),
    p_role,
    p_expires_at,
    p_max_uses
  );
  return v_token;
end;
$$;

revoke all on function public.create_household_invite(uuid,public.household_role,timestamptz,integer) from public, anon;
grant execute on function public.create_household_invite(uuid,public.household_role,timestamptz,integer) to authenticated;

-- Household-scoped private Realtime Broadcast authorization.
create or replace function app_private.can_receive_household_topic(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.household_members m
    join public.households h on h.id = m.household_id
    where m.user_id = (select auth.uid())
      and m.status = 'active'
      and h.deleted_at is null
      and p_topic = 'household:' || m.household_id::text
  )
$$;

revoke all on function app_private.can_receive_household_topic(text) from public, anon;
grant execute on function app_private.can_receive_household_topic(text) to authenticated;

create policy project_home_household_broadcast_read
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (select app_private.can_receive_household_topic(realtime.topic()))
);

create or replace function app_private.broadcast_household_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_household uuid;
begin
  if tg_op = 'DELETE' then
    v_household := old.household_id;
  else
    v_household := new.household_id;
  end if;

  perform realtime.broadcast_changes(
    'household:' || v_household::text,
    tg_op,
    tg_op,
    tg_table_name,
    tg_table_schema,
    new,
    old
  );
  return null;
end;
$$;

create trigger broadcast_household_members_change
after insert or update or delete on public.household_members
for each row execute function app_private.broadcast_household_change();
create trigger broadcast_tasks_change
after insert or update or delete on public.tasks
for each row execute function app_private.broadcast_household_change();
create trigger broadcast_shopping_items_change
after insert or update or delete on public.shopping_items
for each row execute function app_private.broadcast_household_change();
create trigger broadcast_events_change
after insert or update or delete on public.events
for each row execute function app_private.broadcast_household_change();
create trigger broadcast_expenses_change
after insert or update or delete on public.expenses
for each row execute function app_private.broadcast_household_change();
create trigger broadcast_settlements_change
after insert or update or delete on public.settlements
for each row execute function app_private.broadcast_household_change();
create trigger broadcast_bills_change
after insert or update or delete on public.bills
for each row execute function app_private.broadcast_household_change();
