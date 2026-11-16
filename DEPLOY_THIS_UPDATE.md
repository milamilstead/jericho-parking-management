# Jericho Parking Management — staging release

## Important
This package was built from the uploaded staging branch. It has **not been deployed or tested against your live Supabase project**. Deploy and verify on `staging` before changing `main`.

## Changes
- Removes Legacy Tools and Legacy Assignments from navigation (their underlying code/files remain for safe rollback).
- Adds Profile menu, self-service email/password changes, Settings with light/dark/system mode.
- Adds manager employee management: invitations, email change, reset link, role and active status.
- Pending requests tab now shows only pending; approved/denied move into searchable History.
- Adds Active Assignments tab, with manager-only release action.
- Approving a request atomically marks the space unavailable and logs the action; release restores availability.
- History merges request reviews with activity logs and supports search/filter.
- Parking map only shows approved residents as occupants; pending requests do not occupy a spot.
- Preserves the 278-space map and layout editor.

## Deployment order
1. In **Supabase SQL Editor**, run `05_requests_history_security.sql` **once**. Keep migrations `01`–`04` as already installed. If SQL reports an error, stop and share it before testing approvals.
2. In **Supabase Edge Functions**, create/deploy `manage-employee` using `edge-functions/manage-employee/index.ts`. Enable JWT verification and ensure server-side `SUPABASE_SERVICE_ROLE_KEY` is configured. The existing `invite-employee` function must also be deployed for invitations.
3. In GitHub, switch to **staging**, upload the updated **root `index.html`** and **`parking-v2/index.html` into its existing `parking-v2` folder**. Do not upload the ZIP as a repository file; do not overwrite root `index.html` with the parking child page. Commit on staging only.
4. Open the Cloudflare staging preview and hard refresh.
5. Test with a *test* spot and resident: create request, approve, check spot red/occupied and count lower, check it disappears from Requests and appears in History and Active Assignments; release, check it returns to green and appears as released in History. Test deny on another request.
6. Verify saved map edits survive refresh; search works; History search works; Profile menu and light/dark mode work. Test staff versus manager permissions and employee reset/email controls with a test employee.
7. Only after successful verification, merge staging to main.

## Known operational notes
- Account email changes through Supabase Auth may require confirmation; profile email is synchronized after confirmation.
- Manager-initiated employee email changes use the protected Edge Function and immediately confirm the new email; use this only after verifying the requested address belongs to the employee.
- Appearance preference is stored on the current device (not synced between devices).
- History loads the latest 500 activity records and 500 completed requests, not an unlimited archive.
- Existing legacy map code is retained in the source for safe rollback but its tabs are removed.
- The request approval transaction and release are server-side; never add a service-role key to `config.js` or client HTML.
- If a spot has an approved request from before this update, the SQL does not automatically change old `jericho_spaces.unavailable` rows. The app treats approved requests as occupied; new approvals mark unavailable automatically.
