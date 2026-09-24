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
* **From a photo.** Point the camera at a delivery receipt, a price list or
  the day written on paper, and the lines come back as rows you check and
  correct before anything is saved. It works out for itself whether it is
  looking at a delivery (quantities) or a price list (prices only), matches
  names against what you already stock, and reads "3 strips 150" as three at
  fifty rather than three at a hundred and fifty. See below for what it is
  good at and what it is not.
* **Reports** for today, the week, the month, the year or all time: revenue,
  profit, units, best sellers, how people paid. Print it, or export the CSV.
* **Light and dark**, following the phone or forced either way.
* **Built for the phone.** Laid out against an iPhone 16 Pro (402 pt) and
  16 Pro Max (440 pt) — safe areas, bottom nav, sheets that slide up. On a
  desktop it grows an icon rail and a wider grid.

## What the photo reading can and cannot do

The text is read by Tesseract, in this browser. Nothing is uploaded, it costs
nothing per photo, and after the first scan the language data is cached so it
works offline. The first scan downloads about 4 MB.

Measured on a simulated phone photo — angled, unevenly lit, noisy — it read the
receipt **perfectly**. On a blurred, faded one it read essentially nothing, and
no amount of cleaning up the image rescued it. Two things follow, and both are
built in:

* **It tells you when a photo was poor** instead of handing you plausible
  nonsense. Below 45% confidence nothing arrives ticked — you tick what is
  right, or take a better photo.
* **Nothing saves without your say-so.** Every line is editable, every line has
  a tick, and the button tells you exactly what is about to happen — including
  capping a sale to the stock you actually have, so the total on the button is
  the total that gets saved.

For the best read: lay the paper flat, fill the frame with just the list, and
keep the light even. Glare and a steep angle hurt more than poor handwriting.

The images are deliberately only downscaled and desaturated before reading.
Thresholding them first was measurably worse — 69.6% against 100% — because
Tesseract binarises better on its own.

## Setting it up

**1. Make the tables.** Supabase dashboard → **SQL Editor**, paste all of
[`supabase/schema.sql`](supabase/schema.sql) and run it. It is safe to run over
an existing database — that is how you upgrade it — and everything it makes is
prefixed `salesinv_`, so it sits beside the other projects here untouched.

**2. Point the links back at the app.** Dashboard → **Authentication → URL
Configuration**. Set **Site URL** to `https://mixelorg-arch.github.io/sales-inventory/`
and add the same address under **Redirect URLs**. Without this, the confirm and
reset e-mails send you to `localhost` and appear to do nothing.

**3. Open the app and choose a password.** The first load asks you to set one.
That is the whole of the setup — after that the app never asks again on that
device, and the same password opens it on any other.

**Do step 3 now, before you give the address to anyone.** The page is public, so
whoever loads it first is offered the chance to set the password. If Supabase's
**Confirm email** setting is on — leave it on — a stranger who tries gets
nowhere, because the confirmation link goes to your address, not theirs, and
setting your own password afterwards simply overwrites the attempt. Leaving it
on costs you one click on one e-mail, once, the first time.

## The password

One password, no username, no login screen. Change it in **Settings →
Password**, or press **Forgot it** on the lock screen to have a reset link
e-mailed to the owner address.

The owner address is `mixel.org@gmail.com`. It is where reset links go, and it
is the only address the database will show anything to. To use a different one,
change the seed at the foot of `schema.sql`, or run:

```sql
update public.salesinv_meta
   set value = jsonb_build_object('email','you@example.com')
 where key = 'owner';
```

Supabase's built-in mail service is rate limited to a handful of messages an
hour. That is ample for the odd reset; if you ever hit it, add your own SMTP in
the dashboard.

## Why the key in `config.js` is safe to have in a public repo

It is a *publishable* key — it is in the page source of every Supabase web app
and is meant to be read.

**The password is not checked in this page.** It could not be: anyone can read
the page source. It is a real credential that Supabase verifies, and what
protects the figures is the row level security in `schema.sql`:

* every policy demands not merely a signed-in visitor but *the owner* — the
  address on the token has to match the one held in `salesinv_meta`. Signing up
  is open, so that the app can set its own password on first run; anyone else
  who signs up gets an account that sees nothing at all.
* `anon` is revoked from every data table. The only thing a stranger can read
  anywhere is two rows of `salesinv_meta` — whether a password has been set and
  which address it belongs to — because the lock screen has to know which
  question to ask before anybody is signed in. Neither row opens anything.
* `salesinv_items.stock` is not grantable to the client at all, on insert or on
  update. Only the movements trigger writes it.

Checked, not assumed. The schema runs on a scratch Postgres 17 with
Supabase-like roles and default grants, and **34 assertions pass**: a signed-in
stranger reads zero rows from all six tables and their attempts to seize
ownership, rewrite prices or delete the shops change zero rows; `anon` is
refused outright on all five data tables and can neither write the two rows it
can read nor call the ownership function; the stock column resists being
written by hand; and the trigger arithmetic is right for insert, update and
delete, with a voided sale putting the exact stock back.

## If Supabase is unreachable

Press **Use this device only** on the lock screen and the app runs on
`localStorage` with the same two shops. Nothing leaves the browser. Settings →
**Download backup** writes a JSON file; **Restore** reads one back.

On-device data and Supabase data are separate — the on-device mode is a
fallback and a sandbox, not an offline mirror that syncs later.

## Files

| | |
|---|---|
| `index.html` | the whole app — styles, markup, logic |
| `config.js` | Supabase URL, publishable key, table prefix |
| `supabase/schema.sql` | tables, trigger, grants, owner policies, seed |

## The data

```
salesinv_shops       name, currency, low-stock level, payment methods
salesinv_items       cost, price, sku, category, stock, reorder level
salesinv_sales       total, profit, discount, payment, note
salesinv_sale_lines  one row per item on a sale, with its price and cost
salesinv_movements   every change in stock, and what caused it
salesinv_meta        who owns this shop book, and whether a password is set
```

Sales keep their own copy of each item's name, price and cost, so deleting an
item later never rewrites what you earned last month.
