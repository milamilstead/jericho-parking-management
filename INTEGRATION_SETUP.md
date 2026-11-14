# Jericho Residences — integrated staging build

This package merges the approved 278-space map with the existing Supabase-authenticated staff website. **Do not replace the live site until tested.**

## Before deployment
1. Back up your existing GitHub repository and Supabase database.
2. Confirm existing SQL migrations 01, 02, and 03 have been applied. **Do not rerun the initial migrations.**
3. Open Supabase SQL Editor and run `04_jericho_278_migration.sql` once. It creates new `jericho_spaces` and `jericho_requests` tables, RLS policies, and 278 unassigned parking-space IDs without modifying the legacy parking records.
4. Verify `select lot,count(*) from public.jericho_spaces group by lot order by lot;` gives 100=24, 200=47, 300=18, 400=42, 500=147.
5. Test with an existing **manager** account and separate **employee** account on a staging URL. The existing `config.js` uses the public Supabase publishable key, not a secret.
6. Verify sign-in, sign-out, requests, manager approval/rejection, shared layout save, read-only employee access, and refresh across two browsers.
7. Deploy by uploading the contents of this folder to the existing GitHub repository only after staging verification; Cloudflare Pages should rebuild from the linked repository.

## How it works
- The original real Supabase authentication/profile validation remains the login gate.
- The new parking interface is served from `parking-v2/index.html` in a same-origin iframe. The authenticated parent reads and writes Supabase and sends state to the iframe.
- Manager layout changes are saved by **Settings → Save Changes**; the Save button writes geometry, names, and unavailable flags to the shared database.
- Employee requests are inserted as `pending`. Manager review is available in the new **Resident requests** tab.
- Existing legacy `parking_spots`/`assignments` remain intact and separate. **Approving a request does not create a legacy assignment**, and the new request list does not include the old legacy assignments.
- The new map's resident information reflects pending/approved requests, not verified lease records.
- Diagram positions are approximate until a manager checks them against the physical parking spaces.

## Important production limitations
- No automated browser/end-to-end test against your actual Supabase instance was possible here.
- This package has NOT been deployed or verified with your real database.
- The new requests workflow is separate from the legacy assignment RPCs; reconciling them is necessary if you need one authoritative assignment system.
- The existing employee invite function and its deployment/configuration still require verification.
- Use a staging deployment and test security policies before real resident data is entered.
- Layout save currently updates all 278 rows individually; avoid concurrent manager editing.
- Your original supplied logo asset from the approved preview is included without generating a replacement.
