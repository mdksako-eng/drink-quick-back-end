-- sql/inventory_drink_fk.sql
--
-- WHY
--   inventory.drink_id is a plain text column with NO foreign key, and two code
--   paths used to leave stock rows pointing at a drink that does not exist:
--     1. DELETE /data/drinks/:id removed the drink but not its stock row;
--     2. the app's "delete inventory item" called deleteDrink(), so it deleted
--        the DRINK and left the stock row behind.
--   Live example: company 42, drink_id 1792870970398, drink_name "music",
--   quantity 0, created 2026-10-24.
--
--   Both are fixed in code (the drink delete now takes its stock line with it,
--   and DELETE /data/inventory/:drinkId deletes the stock line only). This script
--   makes the invariant structural so a future code path cannot break it again.
--
-- WHAT IT DOES
--   1. deletes inventory rows whose drink no longer exists (the orphans),
--   2. adds inventory.drink_id -> drinks(id) ON DELETE CASCADE, once.
--
-- Run in the Supabase SQL editor. Safe to re-run.
--
-- NOTE  inventory_transactions deliberately gets no foreign key: it is the audit
--       trail and keeps its own drink_name so history survives a deleted drink.

begin;

-- 1. Orphans first: the constraint cannot be added while any exist.
delete from public.inventory i
 where not exists (
   select 1 from public.drinks d
    where d.id = i.drink_id and d.company_id = i.company_id
 );

-- 2. The constraint, once. ON DELETE CASCADE because a stock line for a deleted
--    drink is meaningless: the drink is the parent, the quantity is its child.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'inventory_drink_id_fkey'
       and conrelid = 'public.inventory'::regclass
  ) then
    alter table public.inventory
      add constraint inventory_drink_id_fkey
      foreign key (drink_id) references public.drinks (id) on delete cascade;
  end if;
end $$;

commit;

-- Verify (both must be 0):
--   select count(*) from public.inventory i
--    where not exists (select 1 from public.drinks d
--                       where d.id = i.drink_id and d.company_id = i.company_id);
--   select count(*) from pg_constraint
--    where conname = 'inventory_drink_id_fkey'
--      and conrelid = 'public.inventory'::regclass;
