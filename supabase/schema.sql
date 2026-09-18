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
--  Security model (the same one the photobooth app uses):
--    * RLS on every table, one policy, "to authenticated".
--    * anon is revoked from everything, so the publishable key in config.js
--      can sit in a public repo and still return nothing to a stranger.
--    * there is no sign-up screen on purpose — create users by hand in
--      Authentication → Users.
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

create index if not exists salesinv_items_shop_idx      on public.salesinv_items(shop_id);
create index if not exists salesinv_sales_shop_idx      on public.salesinv_sales(shop_id, sold_at desc);
create index if not exists salesinv_sale_lines_sale_idx on public.salesinv_sale_lines(sale_id);
create index if not exists salesinv_movements_item_idx  on public.salesinv_movements(item_id, created_at desc);
create index if not exists salesinv_movements_sale_idx  on public.salesinv_movements(sale_id);

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
              public.salesinv_movements
  from anon, authenticated, public;

grant select, insert, update, delete on
  public.salesinv_shops,
  public.salesinv_sales,
  public.salesinv_sale_lines,
  public.salesinv_movements
  to authenticated;

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

do $$
declare t text;
begin
  foreach t in array array['salesinv_shops','salesinv_items','salesinv_sales',
                           'salesinv_sale_lines','salesinv_movements']
  loop
    execute format('drop policy if exists %I on public.%I', t || '_rw', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (true) with check (true)',
      t || '_rw', t);
  end loop;
end $$;

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
