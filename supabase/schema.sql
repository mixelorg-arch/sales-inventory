-- ============================================================================
--  Sales & Inventory — schema for the shared "ledger" Supabase project
--  (snfukbofyadfrhuaggad)
--
--  Every object here is prefixed salesinv_ so it cannot collide with the
--  printshop_* tables or anything else already living in this project.
--
--  Safe to run more than once: it is idempotent end to end.
--  Paste it into the Supabase dashboard → SQL Editor → Run.
--
--  Security model:
--    * RLS on every table. The policy is not merely "signed in" but "signed in
--      AS THE OWNER" — the e-mail on the JWT has to match the one held in
--      salesinv_meta. Anyone else who signs up gets an account that can read
--      nothing, which is what makes it safe for the app to set its own
--      password on first run.
--    * anon is revoked from every data table, so the publishable key in
--      config.js can sit in a public repo and still hand a stranger nothing.
--    * anon may read exactly two rows of salesinv_meta — whether a password
--      has been set, and which address it belongs to — because the unlock
--      screen has to know which of the two questions to ask before anyone is
--      signed in. Neither row grants access to anything.
--
--  > THE OWNER ADDRESS IS SEEDED BELOW AS mixel.org@gmail.com.
--    It is the account the password belongs to and where a reset link goes.
--    For another address, change it in the seed at the foot of this file, or
--    afterwards with:
--      update public.salesinv_meta
--         set value = jsonb_build_object('email','you@example.com')
--       where key = 'owner';
-- ============================================================================

-- ---------------------------------------------------------------- tables ---

create table if not exists public.salesinv_shops (
  id              uuid primary key default gen_random_uuid(),
  name            text        not null,
  sort            integer     not null default 0,
  currency        text        not null default '₱',
  low_stock_at    integer     not null default 5,
  payment_methods text[]      not null default array['Cash','GCash','Card'],
  archived        boolean     not null default false,
  created_at      timestamptz not null default now()
);

create table if not exists public.salesinv_items (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid        not null references public.salesinv_shops(id) on delete cascade,
  name        text        not null,
  sku         text,
  category    text,
  cost        numeric(12,2) not null default 0,
  price       numeric(12,2) not null default 0,
  -- stock is maintained ONLY by the movements trigger below. The client is
  -- not granted update on this column; write a movement instead.
  stock       numeric(12,2) not null default 0,
  reorder_at  integer,
  archived    boolean     not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.salesinv_sales (
  id         uuid primary key default gen_random_uuid(),
  shop_id    uuid        not null references public.salesinv_shops(id) on delete cascade,
  sold_at    timestamptz not null default now(),
  discount   numeric(12,2) not null default 0,
  payment    text,
  note       text,
  total      numeric(12,2) not null default 0,
  profit     numeric(12,2) not null default 0,
  created_by uuid        default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.salesinv_sale_lines (
  id      uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.salesinv_sales(id) on delete cascade,
  item_id uuid references public.salesinv_items(id) on delete set null,
  name    text not null,
  qty     numeric(12,2) not null,
  price   numeric(12,2) not null,
  cost    numeric(12,2) not null default 0
);

create table if not exists public.salesinv_movements (
  id         uuid primary key default gen_random_uuid(),
  item_id    uuid        not null references public.salesinv_items(id) on delete cascade,
  sale_id    uuid        references public.salesinv_sales(id) on delete cascade,
  delta      numeric(12,2) not null,
  reason     text        not null default 'adjust',
  note       text,
  created_at timestamptz not null default now()
);

-- A small key/value table: who this shop book belongs to, and whether the
-- password has been chosen yet.
create table if not exists public.salesinv_meta (
  key        text primary key,
  value      jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists salesinv_items_shop_idx      on public.salesinv_items(shop_id);
create index if not exists salesinv_sales_shop_idx      on public.salesinv_sales(shop_id, sold_at desc);
create index if not exists salesinv_sale_lines_sale_idx on public.salesinv_sale_lines(sale_id);
create index if not exists salesinv_movements_item_idx  on public.salesinv_movements(item_id, created_at desc);
create index if not exists salesinv_movements_sale_idx  on public.salesinv_movements(sale_id);

-- ------------------------------------------------------------ who is this ---

-- True only for the one account this shop book belongs to. security definer so
-- it can read salesinv_meta without tripping that table's own policy, which
-- calls this function — without it the two recurse.
create or replace function public.salesinv_is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.salesinv_meta m
     where m.key = 'owner'
       and lower(m.value ->> 'email') = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

revoke all on function public.salesinv_is_owner() from public, anon;
grant execute on function public.salesinv_is_owner() to authenticated;

-- --------------------------------------------------------------- triggers ---

-- The one and only writer of salesinv_items.stock. Handles INSERT, UPDATE and
-- DELETE, so voiding a sale (which cascades its movements away) puts the stock
-- back by itself. security definer because the client role is deliberately not
-- allowed to touch the stock column.
create or replace function public.salesinv_apply_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    update public.salesinv_items
       set stock = stock + new.delta, updated_at = now()
     where id = new.item_id;
    return new;

  elsif (tg_op = 'UPDATE') then
    if (old.item_id = new.item_id) then
      update public.salesinv_items
         set stock = stock - old.delta + new.delta, updated_at = now()
       where id = new.item_id;
    else
      update public.salesinv_items
         set stock = stock - old.delta, updated_at = now()
       where id = old.item_id;
      update public.salesinv_items
         set stock = stock + new.delta, updated_at = now()
       where id = new.item_id;
    end if;
    return new;

  else -- DELETE
    update public.salesinv_items
       set stock = stock - old.delta, updated_at = now()
     where id = old.item_id;
    return old;
  end if;
end;
$$;

drop trigger if exists salesinv_movements_apply on public.salesinv_movements;
create trigger salesinv_movements_apply
  after insert or update or delete on public.salesinv_movements
  for each row execute function public.salesinv_apply_movement();

-- Keep updated_at honest on hand edits.
create or replace function public.salesinv_touch()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists salesinv_items_touch on public.salesinv_items;
create trigger salesinv_items_touch
  before update on public.salesinv_items
  for each row execute function public.salesinv_touch();

-- -------------------------------------------------------------- privileges ---

-- Supabase hands new public tables to anon and authenticated by default.
-- Take it all back, then hand out exactly what the app needs.
revoke all on public.salesinv_shops,
              public.salesinv_items,
              public.salesinv_sales,
              public.salesinv_sale_lines,
              public.salesinv_movements,
              public.salesinv_meta
  from anon, authenticated, public;

grant select, insert, update, delete on
  public.salesinv_shops,
  public.salesinv_sales,
  public.salesinv_sale_lines,
  public.salesinv_movements
  to authenticated;

-- The unlock screen asks one of two questions and must know which before
-- anybody is signed in, so anon may read — never write — the two rows the
-- gate policy below allows.
grant select on public.salesinv_meta to anon;
grant select, insert, update on public.salesinv_meta to authenticated;

-- Note the missing "stock" in both lists: movements own that column, and a
-- table-wide insert grant would have covered it, letting a client open an item
-- at any stock level it liked.
grant select, delete on public.salesinv_items to authenticated;
grant insert (id, shop_id, name, sku, category, cost, price, reorder_at,
              archived, created_at, updated_at)
  on public.salesinv_items to authenticated;
grant update (name, sku, category, cost, price, reorder_at, archived, updated_at)
  on public.salesinv_items to authenticated;

-- ---------------------------------------------------------------- policies ---

alter table public.salesinv_shops      enable row level security;
alter table public.salesinv_items      enable row level security;
alter table public.salesinv_sales      enable row level security;
alter table public.salesinv_sale_lines enable row level security;
alter table public.salesinv_movements  enable row level security;
alter table public.salesinv_meta       enable row level security;

-- Being signed in is not enough. Signing up is open, so that the app can set
-- its own password on first run — which means a stranger may create an account
-- whenever they like. They simply get one that sees nothing.
do $$
declare t text;
begin
  foreach t in array array['salesinv_shops','salesinv_items','salesinv_sales',
                           'salesinv_sale_lines','salesinv_movements','salesinv_meta']
  loop
    execute format('drop policy if exists %I on public.%I', t || '_rw', t);
    execute format(
      'create policy %I on public.%I for all to authenticated '
      'using (public.salesinv_is_owner()) with check (public.salesinv_is_owner())',
      t || '_rw', t);
  end loop;
end $$;

-- The only thing a stranger may read: whether a password has been set, and the
-- address it belongs to. Read-only, and only those two keys.
drop policy if exists salesinv_meta_gate on public.salesinv_meta;
create policy salesinv_meta_gate on public.salesinv_meta
  for select to anon using (key in ('setup','owner'));

-- ---------------------------------------------------------------- realtime ---
-- So a second phone or the till sees a sale the moment it is rung up.
-- Wrapped because adding a table twice raises duplicate_object.
do $$
declare t text;
begin
  foreach t in array array['salesinv_shops','salesinv_items','salesinv_sales',
                           'salesinv_sale_lines','salesinv_movements']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception
      when duplicate_object then null;
      when undefined_object then null;
    end;
  end loop;
end $$;

-- -------------------------------------------------------------------- seed ---
-- The two shops, once. Re-running this file will not duplicate them.
insert into public.salesinv_shops (name, sort)
select 'Project Drex', 0
where not exists (select 1 from public.salesinv_shops where name = 'Project Drex');

insert into public.salesinv_shops (name, sort)
select 'Mixel', 1
where not exists (select 1 from public.salesinv_shops where name = 'Mixel');

-- Who this shop book belongs to.
insert into public.salesinv_meta (key, value)
select 'owner', jsonb_build_object('email', 'mixel.org@gmail.com')
where not exists (select 1 from public.salesinv_meta where key = 'owner');

-- Flipped to true by the app the first time the owner gets in, so the unlock
-- screen knows whether to ask for a new password or for the existing one.
insert into public.salesinv_meta (key, value)
select 'setup', jsonb_build_object('done', false)
where not exists (select 1 from public.salesinv_meta where key = 'setup');
