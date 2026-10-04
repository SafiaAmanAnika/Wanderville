# Google login, email and shared hosting

Updated 4 October 2026. Your current database is **local**, not publicly hosted. The read-only audit found PostgreSQL 18.6 at `127.0.0.1:5433`, database `wanderville_dev`, migration `0004_boolean_defaults`, 42 tables, and 22 catalog definitions. Fresh full seeding creates 51 definitions. No live data or credentials were changed.

## 1. Finish Google sign-in

You have already created the Google project and consent screen. Continue in that same project:

1. Open [Google Auth Platform → Clients](https://console.cloud.google.com/auth/clients).
2. Click **Create client → Application type: Desktop app**. Name it `Wanderville Desktop` and create it. The implemented Godot flow is a Windows/desktop browser flow, so do not choose Web application.
3. Download the client JSON to your Downloads folder. Keep it outside Git. If the consent screen is in Testing and requires test users, add your and your friends' Google addresses under Audience.
4. Run these PowerShell commands, replacing only the downloaded filename:

```powershell
Set-Location D:\GitHubProjects\Wanderville\code\server
.\.venv312\Scripts\python.exe scripts\configure_auth.py --google-json "$HOME\Downloads\client_secret_YOUR_FILE.apps.googleusercontent.com.json"
```

The helper validates that this is a Desktop app client and writes `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` to the existing local `.env`. It never prints either credential or changes the database connection. **Restart your backend after running it.**

```powershell
.\.venv312\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1 --no-access-log
```

Stop the old backend with Ctrl+C in its own terminal first if port 8000 is already occupied. In another terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/auth/config
```

This endpoint exposes only the public client ID and delivery mode. In the game, click **Google sign-in**, choose your Google account in the system browser, approve, and return to Godot. The game checks state and nonce, uses PKCE and a random loopback port, and the server exchanges the code and validates Google's signed identity token. The Google callback is local `http://127.0.0.1:<random-port>/oauth/callback`; Desktop clients do not require you to enter a fixed Render callback URL.

Players do **not** need app passwords. This sign-in uses basic identity scopes and does not read their Gmail inbox or grant the game mailbox access. Provider sign-in still needs the player to choose/approve an account when Google requires it. See [Google's desktop OAuth instructions](https://developers.google.com/identity/protocols/oauth2/native-app).

## 2. Choose how verification emails are sent

Google sign-in and verification email delivery are separate configurations. The current default `EMAIL_DELIVERY=auto` saves development messages in `code/server/.dev-mail/`; it does not send them to Gmail. A password signup needs its verification link; Google sign-in uses Google's verified identity.

**Local Gmail SMTP option:** enable [2-Step Verification and create an app password](https://support.google.com/mail/answer/185833) yourself in your Google Account. Google calls it a 16-digit passcode, but it is normally shown as 16 characters. The normal Google password is not appropriate here. Then run:

```powershell
Set-Location D:\GitHubProjects\Wanderville\code\server
.\.venv312\Scripts\python.exe scripts\configure_auth.py --gmail
```

It prompts for the sending address and app password with hidden input, then configures Gmail STARTTLS on port 587. Restart the backend. This lets the **server** automatically send verification/reset messages using that one sender; it does not sign every player into that sender's Gmail account. Creating the app password and enabling 2FA are account actions you must do in Google's website. Some managed/Advanced Protection accounts do not offer app passwords.

**Recommended free-hosting option: Brevo HTTPS.** Render Free blocks SMTP ports, including Gmail's port 587. The backend therefore also supports Brevo's transactional HTTP API:

1. Create a [Brevo Free account](https://www.brevo.com/).
2. Add and verify a sender under Settings → Senders, Domains & Dedicated IPs. Finish any requested transactional-account activation. A verified Gmail sender may work, but Brevo can rewrite public-domain sender addresses for deliverability; a domain you own gives more control. See [Brevo sender requirements](https://help.brevo.com/hc/en-us/articles/35852083084178-Domain-setup-for-better-email-deliverability).
3. In **SMTP & API → API Keys**, create an API key, not an SMTP key.
4. For local testing, run `.\.venv312\Scripts\python.exe scripts\configure_auth.py --brevo`, enter the verified sender and hidden API key, and restart the backend. For cloud hosting, enter the values directly in Render's private environment settings below.

Verification and reset links open normal browser pages; no custom OS URL-handler installation is needed. Signup reports delivery failure honestly and allows resend. Forgot-password/resend responses stay generic to prevent account enumeration; inspect provider delivery logs if mail is missing. API acceptance is not a guarantee that a message reaches the recipient's inbox.

## 3. Ongoing free hosting, without a trial database

No provider promises that a free plan will exist forever. These are ongoing free tiers, rather than a database that expires after a fixed trial:

| Part | Recommended plan | Practical limit |
| --- | --- | --- |
| Python API + WebSockets | Render Free web service | Sleeps after 15 minutes idle; waking can take about a minute; 750 free instance hours per workspace/month and bandwidth/build quotas. [Render limits](https://render.com/docs/free) |
| PostgreSQL | Neon Free | Quota-based persistent database; currently advertised 1 GB storage/project and 100 CU-hours/project/month. Compute scales to zero. Check the dashboard before creating it. [Neon announcement](https://neon.com/blog/neon-free-plan-1-gb-per-project) |
| Verification/reset email | Brevo Free | No time limit, 300 email sends/day; sender/account approval required. [Brevo limits](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan) |

Render Free PostgreSQL expires after 30 days, so **do not create that database**. The repository's `render.yaml` now declares only one free web service and uses external Neon. There are no paid database or worker resources in it. This setup suits a small friends/hobby game; it is not guaranteed always-on hosting.

An alternative database is [Supabase Free](https://supabase.com/pricing), but inactive free projects can be paused. An [Oracle Always Free VM](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) can host Python and PostgreSQL together, but requires Linux/firewall/backup administration, available capacity, and account verification; idle resources may be reclaimed. Neither alternative was deployed or configured here.

### Your account setup steps

1. **Neon:** create a Free project and PostgreSQL database. Choose a region close to your Render region. Copy its full PostgreSQL connection URI from Connect, retaining `sslmode=require`. Use the direct connection for this small single-process deployment. Put it only in server secrets, never in Godot or chat.
2. **Brevo:** complete the sender/API-key steps above.
3. **Google:** complete the Desktop client steps above. Use the same downloaded JSON's `client_id` and `client_secret` in Render.
4. **Repository:** the changes must be committed and pushed to the GitHub repository you connect to Render. They are currently local, uncommitted changes; review and push them using your normal Git workflow. No push was performed for you.
5. **Render:** New → Blueprint → connect your repository/branch → use the root `render.yaml`. Confirm the plan is **Free** and there is **one web service**, then supply these prompted environment values:

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | Neon PostgreSQL URI, including SSL parameters |
| `BREVO_API_KEY` | Your private Brevo API key |
| `EMAIL_FROM` | The sender address verified in Brevo |
| `GOOGLE_CLIENT_ID` | Desktop OAuth JSON's `client_id` |
| `GOOGLE_CLIENT_SECRET` | Desktop OAuth JSON's `client_secret` |

The blueprint generates the JWT secret, selects Brevo, and enables the existing world worker inside the API process. `EMAIL_BASE_URL` defaults to Render's public `RENDER_EXTERNAL_URL`; set it explicitly to your HTTPS public API URL if using a custom hostname. The start command runs migrations and idempotent reference seeding, then Uvicorn. Use a **new empty Neon database** unless you have separately planned an existing-data migration.

Use **one Uvicorn worker and one instance**: realtime socket ownership is process-local. The embedded world worker runs while Render is awake; timed notifications/events are delayed while it sleeps. Time and crop growth derive from persisted timestamps and are projected again when the service wakes. This is not a keep-alive workaround.

### Check the public deployment

Replace `YOUR-SERVICE` with your actual Render service hostname:

```powershell
$wandervilleApi = 'https://YOUR-SERVICE.onrender.com'
Invoke-RestMethod "$wandervilleApi/health" -TimeoutSec 120
Invoke-RestMethod "$wandervilleApi/ready" -TimeoutSec 120
Invoke-RestMethod "$wandervilleApi/auth/config" -TimeoutSec 120
```

`/health` only confirms the API process. `/ready` also queries the database, checks the current migration and required seeded gameplay data. A failed readiness check is not a working deployment. Open `/health` and wait for Render to wake before logging in after a long idle period; Godot requests have bounded timeouts and can need a retry during cold start.

The hosted database starts fresh. Existing local players/progress are not automatically copied to Neon. Ask for a separate, backed-up migration if you want to retain them.

## 4. Let friends use the same database

For development, launch Godot from a PowerShell terminal with the public API address:

```powershell
$env:WANDERVILLE_API_URL = 'https://YOUR-SERVICE.onrender.com'
& 'E:\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe' --path 'D:\GitHubProjects\Wanderville\code\client'
```

For a distributed desktop build, in Godot **Project → Project Settings → Advanced Settings**, add the String setting `network/wanderville_api_url` with that same HTTPS URL before exporting. `APIClient` reads the environment override first, then this project setting, then localhost. Your friends install/run the exported game and create/login to their own accounts. They need no database setup and receive no database credentials. All clients call the same server, which accesses Neon and enforces player ownership. HTTPS automatically becomes WSS for realtime.

After you create the accounts and deploy, share **only the public API URL**. Live readiness, browser Google sign-in, and actual email delivery can then be checked against that deployment. Those external results cannot be verified before credentials and hosting exist.

## 5. Local startup and existing local database

Run these only when you choose to update the configured local database's schema/reference data; they were not run on your existing database during this task:

```powershell
Set-Location D:\GitHubProjects\Wanderville\code\server
.\.venv312\Scripts\python.exe -m pip install -r requirements.txt
.\.venv312\Scripts\python.exe -m alembic upgrade head
.\.venv312\Scripts\python.exe -m app.db.seed
.\.venv312\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1 --no-access-log
```

In a second terminal, run the existing worker for timed events/notifications:

```powershell
Set-Location D:\GitHubProjects\Wanderville\code\server
.\.venv312\Scripts\python.exe -m app.modules.world.worker
```

Alternatively set `WORLD_WORKER_ENABLED=true` on the local API and run only Uvicorn. Do not also launch a standalone worker unnecessarily. Then run `code/client/project.godot`. The existing PostgreSQL service on port 5433 must be running.
