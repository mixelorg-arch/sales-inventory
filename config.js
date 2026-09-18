/* ---------------------------------------------------------------------------
   Where the data lives.

   This is a *publishable* key. It is meant to be readable — it is in the page
   source of every Supabase web app. What keeps the numbers private is the row
   level security in supabase/schema.sql: every table is granted to the
   "authenticated" role only, and anon is revoked from all of them. Someone who
   copies this key out of the repo still has to sign in as a real user, and
   users are created by hand in the Supabase dashboard.

   If you ever move shops to a different Supabase project, change it here and
   nowhere else.
   --------------------------------------------------------------------------- */
window.SALESINV_CONFIG = {
  supabaseUrl: 'https://snfukbofyadfrhuaggad.supabase.co',
  supabaseKey: 'sb_publishable_62VRVYDBE2Z5hu5BwEyXTQ_gmX_rbEn',

  // Every table this app owns carries this prefix, so it shares the "ledger"
  // project with the printshop_* tables without ever colliding with them.
  tablePrefix: 'salesinv_',
};
