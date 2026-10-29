# Setting up Supabase, Vercel and your first login

Five short tasks, all in web dashboards or the app. Nothing here needs code. Keep the values you copy in a password manager; do not paste them into chat.

## 1. Create the Supabase project (database and logins)

1. Go to <https://supabase.com/dashboard> and click **New project**.
2. Name it `barangay-accounting`, choose the **Southeast Asia (Singapore)** region, and set a strong **database password**. Save that password; you will need it in step 2.
3. When the project is ready, open **Project Settings → API** and copy two values:
   - **Project URL** (looks like `https://abcdefghij.supabase.co`)
   - the **anon public** key (some dashboards label it **publishable**). It is safe to use in a browser; row-level security decides what it can see.
4. The project ref is the `abcdefghij` part of the URL. Note it too.

## 2. Let GitHub apply the database for you

The repository contains an action that builds the database from `supabase/migrations` and loads the chart of accounts. It runs by itself after every change once it has three secrets.

1. Make a personal access token at <https://supabase.com/dashboard/account/tokens> (name it `github-actions`).
2. In GitHub, open the repository → **Settings → Secrets and variables → Actions → New repository secret**, and add:
   - `SUPABASE_ACCESS_TOKEN` = the token from the previous step
   - `SUPABASE_PROJECT_ID` = the project ref from step 1.4
   - `SUPABASE_DB_PASSWORD` = the database password from step 1.2
3. Open the repository's **Actions** tab → **Apply database migrations** → **Run workflow**. It should finish green in about a minute. Afterwards, **Table Editor** in Supabase shows tables such as `account` (280 rows), `lgu`, `barangay`, `journal_entry`.

If you would rather not use secrets, you can instead open **SQL Editor** in Supabase and paste the files in `supabase/migrations/` one at a time in name order, then `supabase/seed.sql`.

## 3. Deploy the app on Vercel

1. Go to <https://vercel.com/new>, pick **Import Git Repository** and choose `Barangay-Accounting-System-Philippines`. Vercel detects Next.js by itself.
2. Before clicking Deploy, open **Environment Variables** and add:
   - `NEXT_PUBLIC_SUPABASE_URL` = the Project URL from step 1.3
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` = the anon key from step 1.3
3. Click **Deploy**. Vercel gives you a URL such as `https://barangay-accounting-system-philippines.vercel.app`. Every push to `main` redeploys it.

## 4. Create your login and the first LGU

1. In Supabase, open **Authentication → Users → Add user → Create new user**. Enter your email and a password and tick **Auto Confirm User**.
2. Open **SQL Editor → New query**, paste the contents of `supabase/bootstrap/first_lgu.sql`, change the email, LGU name and barangay names at the top, and click **Run**. This creates the LGU, its barangays (each with the five standard funds) and gives your login the LGU administrator and Accountant roles.
3. Open the Vercel URL and sign in. The home page lists your roles, the barangays you can see with their funds, and the 280 loaded accounts.

## 5. Get the pilot barangay ready

All of this is done in the app, signed in as the LGU administrator. Pick the barangay in the top bar first.

1. **Setup → Officials:** add the Punong Barangay, the Barangay Treasurer and the Chairman of the Committee on Appropriations (and any Deputized Barangay Collectors). Their names print in the signature boxes.
2. **Setup → Depository bank account:** record the barangay's current account.
3. **Accountable forms:** record each OR booklet and checkbook on hand, starting at the next unused number.
4. **People and access:** for each officer who will sign in, first create their login in Supabase (**Authentication → Users → Add user → Create new user**, tick **Auto Confirm User**), then enter the same email in the app with their role and barangay. Give them their password privately.

## Working locally with Claude Code (optional)

```bash
npm install
cp .env.example .env.local      # paste the same two values as in step 3
npm run dev                     # http://localhost:3000
```

The database tests (`npm run db:test`) need either Docker with local Supabase (`npm run db:start`) or any PostgreSQL 15+ you can reach as a superuser.
