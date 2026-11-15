# GrowthMonk backend setup (Supabase)

1. Create a free project at https://supabase.com (region: Mumbai, ap-south-1).
2. Open **SQL Editor**, paste `supabase/schema.sql`, and run it.
3. **Authentication › URL Configuration**: set Site URL and add a redirect URL `https://growthmonk25007.github.io/growthmonk777/`.
4. **Project Settings › API**: copy the Project URL and the `anon` public key into `config.js`.

The anon key is safe in the frontend because row-level security limits every user to their own workspace. Never put the `service_role` key in this repo.
