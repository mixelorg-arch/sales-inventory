# Sales & Inventory

Two shops — **Project Drex** and **Mixel** — in one page. Ring up a sale and the
stock comes off by itself. Add a third shop whenever you open one.

Live: https://mixelorg-arch.github.io/sales-inventory/

It is one HTML file. No build step, no npm, no framework.

---

## What it does

* **A tab per shop.** Project Drex and Mixel to start; the **+** adds another,
  and it gets its own items, sales and reports.
* **Sales.** Pick items, set quantities, add a discount, choose how they paid.
  The total, the profit and the stock all follow.
* **Inventory.** Cost, price, SKU, category, stock and a low-stock level per
  item. Restock, or correct the count when the shelf disagrees with the app.
* **Stock you can trust.** Nothing writes a stock figure directly. Every unit
  arrives or leaves as a *movement* — opening, restock, sale or count — so the
  number on screen always has a history behind it. Void a sale and the items go
  back on the shelf.
* **Reports** for today, the week, the month, the year or all time: revenue,
  profit, units, best sellers, how people paid. Print it, or export the CSV.
* **Light and dark**, following the phone or forced either way.
* **Built for the phone.** Laid out against an iPhone 16 Pro (402 pt) and
  16 Pro Max (440 pt) — safe areas, bottom nav, sheets that slide up. On a
  desktop it grows an icon rail and a wider grid.

## Setting it up

**1. Create the tables.** Open the Supabase dashboard → **SQL Editor**, paste
all of [`supabase/schema.sql`](supabase/schema.sql), and run it. It is safe to
run twice. Everything it makes is prefixed `salesinv_`, so it sits beside the
other projects in this database without touching them.

**2. Create yourself a user.** Dashboard → **Authentication → Users → Add
user**, with a password. There is no sign-up screen on purpose — the only
people who get in are the ones you add.

**3. Open the site and sign in.** The two shops are already there.

## Why the key in `config.js` is safe to have in a public repo

It is a *publishable* key — it is in the page source of every Supabase web app
and is meant to be read. What protects the numbers is the row level security in
`schema.sql`:

* every table is granted to the `authenticated` role only, and `anon` is
  explicitly revoked from all five;
* `salesinv_items.stock` is not grantable to the client at all — not on insert,
  not on update. Only the movements trigger writes it.

That was checked, not assumed: the schema was run on a scratch Postgres 17 with
Supabase-like roles and default grants, and **24 assertions pass** — anon is
refused on every table, a signed-in client cannot set `stock` by hand, the
trigger arithmetic is right for insert, update and delete, and voiding a sale
puts the exact stock back.

## If Supabase is unreachable

Press **Use this device only** on the sign-in screen and the app runs on
`localStorage` with the same two shops. Nothing leaves the browser. Settings →
**Download backup** writes a JSON file; **Restore** reads one back.

On-device data and Supabase data are separate — the on-device mode is a
fallback and a sandbox, not an offline mirror that syncs later.

## Files

| | |
|---|---|
| `index.html` | the whole app — styles, markup, logic |
| `config.js` | Supabase URL, publishable key, table prefix |
| `supabase/schema.sql` | tables, trigger, grants, policies, seed |

## The data

```
salesinv_shops       name, currency, low-stock level, payment methods
salesinv_items       cost, price, sku, category, stock, reorder level
salesinv_sales       total, profit, discount, payment, note
salesinv_sale_lines  one row per item on a sale, with its price and cost
salesinv_movements   every change in stock, and what caused it
```

Sales keep their own copy of each item's name, price and cost, so deleting an
item later never rewrites what you earned last month.
