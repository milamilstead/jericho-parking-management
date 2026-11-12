# Jericho Residences — Shared Parking Manager (v2)

This version uses **the property image from the earlier prototype**, plus Supabase for shared records, staff sign-in, assignments, and activity history. It is *not* ready for live resident use until its security and parking coordinates have been verified.

## 1. Run the next SQL migration

You already ran `01_database_existing.sql` and `02_secure_assignments_existing.sql`. **Do not run them again.**

Open Supabase → SQL Editor → New Query. Copy/paste and run **`03_manager_spot_functions.sql`**. This provides audited, manager-only functions to create and edit parking spaces.

These functions respect the existing tables and do **not** seed guessed parking positions as real spaces. The database begins with no physical spaces until a manager explicitly adds them. Existing assignments are never silently overwritten.

## 2. Configure the website

Edit `config.js` (using TextEdit in plain text mode or VS Code):

```js
window.JERICHO_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT_REF.supabase.co',
  supabasePublishableKey: 'sb_publishable_YOUR_KEY'
};
```

Get both values from **Supabase Dashboard → Connect → `.env.local`**. Use the two values after the equals signs (`NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`).

**Never place your service-role key, secret API key, or database password in browser code.** Supabase's publishable key is intended to be public. Row Level Security and audited RPC functions provide database authorization.

## 3. Run the site locally for testing

The website imports Supabase's JavaScript SDK from a CDN, so the browser needs internet access. Running it through a local web server is more reliable than `file://`:

```bash
cd jericho
python3 -m http.server 8000
```

Then visit `http://localhost:8000` in your browser. On a Mac, Terminal has Python if installed; otherwise use a local web server in VS Code (Live Server) or deploy to a private staging host.

Sign in using your **existing manager email and password**. If login works but your profile is rejected, check that `public.profiles` has the same Auth UID as the account, `role='manager'` and `active=true`.

## 4. Set up physical parking spaces

Your handwritten diagrams are valuable source material, but their labels and geometric locations have not been verified. The dashed sections on the map are only **approximate guides**.

A manager clicks **+ Place space**, clicks its correct position on the property map, enters a *unique physical spot ID* (not the apartment number), selects the section, type and availability, and saves. New spaces start **Unavailable / not verified** for safety; enable them only after confirming the physical space is correct. Employees can assign only verified spaces with `Available` status.

Select a space and check **Move space on map by dragging**, then **Save space**, to adjust its map location. Every layout change is recorded in `activity_logs`.

Employee and manager assignments both go through the earlier secure `assign_parking_spot` and `release_parking_spot` functions. Those check staff membership and lock rows, so simultaneous reservations cannot double-book the same space.

Data refreshes about every 15 seconds while the browser tab is active, plus after saves and on demand. This is **near-real-time polling**, not a promise of instantaneous WebSocket synchronization.

## 5. Employee invitations (optional deployment step)

The **Employee access** tab is for managers only. To make the Invite button work, deploy the included Supabase Edge Function `edge-functions/invite-employee/index.ts` as **`invite-employee`**, with JWT verification enabled. Supabase's default server environment supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`; do not add these to browser config.

You can use the Supabase Dashboard's Edge Functions editor (create a function with the exact name and paste the TypeScript) or the Supabase CLI. Before inviting real staff, verify the project's **Authentication → URL Configuration → Site URL** and **Redirect URLs** are set to the final staff website, so invitation links land at the right place. Invitation recipients may need an auth callback/password-setup route depending on the Supabase email invite template. This prototype does **not** yet implement a full invitation acceptance/password setup page; verify the invitation flow end-to-end in staging before rolling it out. The function intentionally invites **employee** accounts only, not new managers.

The function is intentionally separate from the browser because only Supabase's server side may use the service-role key. It verifies the caller's authenticated session and manager profile before inviting a user and writes an audit log.

## 6. Before production use

- Confirm all four physical parking sections, space counts, accurate locations and accessible/visitor/loading restrictions on site.
- Test with a separate employee account that cannot edit layouts, list other staff, or read activity logs.
- Verify a second employee cannot reserve a spot that's already taken.
- Review data retention, resident privacy, secure hosting (HTTPS), account recovery, backups, manager access control, and employer approval.
- Configure a production backup strategy. Supabase's free tier can pause unused projects and does not provide the same backup guarantees as a paid plan.
- Arrange hosting; opening a local file **does not** create a shared public website. Staff should only access a trusted hosted deployment.

### Important limitations

This is an **upgraded working front-end and migration package**, not a live deployed application. The supplied apartment numbers in the PDF have **not** been transcribed or loaded; importing them without careful review would risk assigning the wrong spaces. Site layout and assignment changes should be validated in a test project before moving real resident data.


## P2 West parking reference view (v3)
Select **Page 2 · West (P2)** from the section filter to reveal the original handwritten diagram marked ② on PDF page 3, with zoom controls. The aerial property map remains underneath and retains existing Supabase-backed editing. This reference is **not** an imported list of verified parking stalls; it does not automatically assign apartment numbers or modify database records. To reposition an existing mapped space, select it on the aerial map, check Move space, drag, then click Save space. Refresh reloads records; it does not move spaces.

## Version 4: edit parking area outlines
Managers can use **Edit parking area outlines** on the Map page. Choose P1/P2/P3/P4, check **Edit outlines**, then drag the selected shaded rectangle to move the entire area, or drag its white corner circles to resize it. Click **Save outlines**. The changes are stored in the browser's localStorage; they are **not shared through Supabase**. Export/import JSON to transfer these guides to another browser. This does not move parking stalls, change resident assignments, or change Supabase records. The original outlines are only approximate; field verification is still necessary. The detailed P2 scanned reference remains viewable.

To install: unzip into a new folder, copy your working `config.js` into the new `jericho` folder, restart the local web server from that folder and hard-refresh the browser. Because area outlines are local to the browser origin, if you use the same localhost port the saved outlines may carry over.
