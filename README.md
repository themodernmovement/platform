# Modern Movement Platform

**YouCanSayNo.org + ICanSayYes.org — Community Engine**

A full-stack civic engagement platform with real-time voting, AI content moderation, member management, and a flag/review system. Built on Supabase (Postgres + Auth + Realtime) and deployable to Vercel in one click.

---

## What's in this repo

```
/
├── platform.html        ← Admin/community platform (Supabase-powered)
├── youcansayno.html     ← Public-facing SayNo campaign site
├── icansayyes.html      ← Public-facing SayYes campaign site
├── schema.sql           ← Complete database schema — run this once in Supabase
├── vercel.json          ← Vercel deployment config
└── README.md            ← You are here
```

---

## Prerequisites

- A free [Supabase](https://supabase.com) account
- A free [Vercel](https://vercel.com) account
- A free [GitHub](https://github.com) account
- That's it. No Node.js, no build tools, no terminal required.

---

## Step 1 — Create your Supabase project

1. Go to [supabase.com](https://supabase.com) → **New Project**
2. Choose a name (e.g., `modern-movement`)
3. Choose a database password (save this somewhere safe)
4. Choose **US East** or the region closest to most of your users
5. Wait ~2 minutes for the project to spin up

---

## Step 2 — Run the database schema

1. In your Supabase project, click **SQL Editor** in the left sidebar
2. Click **New Query**
3. Open `schema.sql` from this repo and copy the entire contents
4. Paste it into the SQL Editor
5. Click **Run** (the green button)
6. You should see: `Success. No rows returned`

This creates:
- All tables (`profiles`, `initiatives`, `votes`, `flags`, `activity_log`)
- Views for efficient vote counting
- Row Level Security policies (your data is protected)
- A trigger that auto-creates a profile when someone signs up
- 6 sample initiatives to start the feed

---

## Step 3 — Enable Realtime (live vote streaming)

1. In Supabase, go to **Database → Replication** (in the left sidebar under "Database")
2. Find the **supabase_realtime** publication
3. Toggle ON: `votes`, `initiatives`, `flags`
4. Click **Save**

This is what makes votes update live on everyone's screen without refreshing.

---

## Step 4 — Get your API credentials

1. In Supabase, go to **Project Settings → API** (gear icon → API)
2. Copy two values:
   - **Project URL** — looks like `https://abcdefghijklm.supabase.co`
   - **anon / public key** — the long `eyJhbG...` string (this is safe to expose publicly)

---

## Step 5 — Configure the platform

**Option A — Enter in the browser (easiest)**
1. Open `platform.html` in a browser
2. The setup wizard will appear automatically
3. Paste your Project URL and anon key
4. Click **Test Connection** then **Save & Continue**

**Option B — Hardcode for deployment (recommended for production)**
Open `platform.html` in a text editor. Find these two lines near the top of the `<script>` block:

```javascript
const DEFAULT_URL = '';   // Replace with your Supabase URL
const DEFAULT_KEY = '';   // Replace with your anon key
```

Change them to:
```javascript
const DEFAULT_URL = 'https://YOUR-PROJECT-ID.supabase.co';
const DEFAULT_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
```

---

## Step 6 — Make yourself an admin

1. Open `platform.html` and create an account with your real email
2. Check your email and confirm your account (Supabase sends a confirmation link)
3. Sign in to the platform
4. Go back to **Supabase → SQL Editor** and run:

```sql
select public.set_user_role('your@email.com', 'admin');
```

5. Refresh the platform — you'll now see the Moderation section in the sidebar

To promote a moderator later:
```sql
select public.set_user_role('moderator@email.com', 'mod');
```

---

## Step 7 — Deploy to Vercel (one-click)

### First: Push to GitHub

1. Create a new repository at [github.com/new](https://github.com/new)
2. Name it `modern-movement-platform` (or anything you like)
3. Upload all files from this folder (drag and drop in the GitHub interface)
4. Click **Commit changes**

### Then: Deploy on Vercel

1. Go to [vercel.com](https://vercel.com) → **New Project**
2. Import your GitHub repository
3. Vercel will auto-detect this as a static site — **no configuration needed**
4. Click **Deploy**
5. Done. Your platform is live at `https://your-project.vercel.app`

### Custom domains
In Vercel → your project → **Settings → Domains**:
- Add `platform.youcansayno.org` or whatever subdomain you want
- Vercel gives you the DNS records to add at your domain registrar

---

## Step 8 — Configure Email (optional but recommended)

By default Supabase sends confirmation emails from `noreply@mail.supabase.io`. For production:

1. Supabase → **Project Settings → Auth → Email Templates**
2. Customize the confirmation and password reset emails with your branding

For custom email sending with your own domain:
1. Supabase → **Project Settings → Auth → SMTP Settings**
2. Enter your SMTP credentials (Gmail, SendGrid, Postmark, etc.)

---

## Running locally (no server required)

Since this is static HTML, you can run it locally with any simple server:

```bash
# If you have Python installed:
python -m http.server 8080

# If you have Node.js installed:
npx serve .

# Then open: http://localhost:8080/platform.html
```

Or just open `platform.html` directly in a browser — most features work fine.

---

## Platform Roles

| Role | Can Do |
|------|--------|
| **member** | Sign up, submit initiatives, vote, flag content |
| **mod** | Everything above + approve/reject pending submissions, clear flags, hide content |
| **admin** | Everything above + remove content, promote/demote members, view full audit log |

---

## Architecture Overview

```
Browser (HTML/CSS/JS)
    │
    ├── Auth: Supabase Auth (email/password, JWT tokens)
    │
    ├── Database: Supabase Postgres
    │       ├── profiles (users)
    │       ├── initiatives (submissions)
    │       ├── votes (one per user per initiative)
    │       ├── flags (content reports)
    │       └── activity_log (audit trail)
    │
    ├── Realtime: Supabase Realtime (WebSocket)
    │       └── Votes stream live to all connected browsers
    │
    └── AI Review: Anthropic Claude API
            └── Content quality scoring on submission
```

**No backend server.** Everything runs browser-side with direct Supabase calls, secured by Row Level Security policies in Postgres. The only server-side code is Supabase's own infrastructure.

---

## Security Model

- **Row Level Security** is enabled on all tables — users can only read/write what they're allowed to
- The anon key is safe to expose publicly — it has no write access beyond what RLS allows
- Votes are unique-constrained at the database level — double voting is impossible even with API manipulation
- All moderation actions are logged to `activity_log` with timestamps

---

## Scaling

| Users | Estimated Cost | Notes |
|-------|---------------|-------|
| 0–50,000 | $0/mo | Supabase free tier |
| 50k–100k | $25/mo | Supabase Pro |
| 100k+ | $25+/mo | Upgrade DB compute as needed |
| Vercel hosting | $0–20/mo | Free tier handles most traffic |

Supabase's free tier includes 50,000 monthly active users, 500MB database, and unlimited API requests. Most community platforms stay free for months.

---

## Adding the Public Sites to Vercel

The `youcansayno.html` and `icansayyes.html` files are standalone — they can live in the same Vercel project. Vercel serves any `.html` file at its own URL automatically:

- `your-project.vercel.app/youcansayno.html`
- `your-project.vercel.app/icansayyes.html`
- `your-project.vercel.app/platform.html`

With custom domains, you'd map:
- `youcansayno.org` → the Vercel project
- `icansayyes.org`  → the same Vercel project
- Vercel handles both from the same deploy

---

## Next Steps (future builds)

- [ ] Email notifications when your initiative gets votes
- [ ] Weekly digest email to all members
- [ ] Public API for embedding vote counts on other sites
- [ ] CSV export of vote results for commission meetings
- [ ] Social sharing cards for each initiative
- [ ] SMS alerts for urgent initiatives (Twilio)
- [ ] Map view of initiatives by location

---

## Support

Questions? Open an issue on GitHub or email the platform team.

**This platform is nonpartisan, community-owned, and has no corporate funding.**
