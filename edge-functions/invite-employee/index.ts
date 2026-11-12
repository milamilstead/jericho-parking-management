// Supabase Edge Function: invite-employee
// Deploy with JWT verification on. Service-role key is provided by the Supabase
// server environment and must NEVER be put in browser files.
import { createClient } from 'npm:@supabase/supabase-js@2';

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};
function reply(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers });
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return reply(405, { error: 'Method not allowed' });
  const accessToken = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!accessToken) return reply(401, { error: 'Sign in required' });

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return reply(500, { error: 'Server configuration missing' });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  const { data: identity, error: authError } = await admin.auth.getUser(accessToken);
  if (authError || !identity.user) return reply(401, { error: 'Invalid session' });
  const { data: manager, error: managerError } = await admin.from('profiles')
    .select('id').eq('id', identity.user.id).eq('role', 'manager').eq('active', true).maybeSingle();
  if (managerError || !manager) return reply(403, { error: 'Managers only' });

  let payload: { email?: unknown };
  try { payload = await req.json(); } catch { return reply(400, { error: 'Invalid JSON' }); }
  const email = typeof payload.email === 'string' ? payload.email.trim().toLowerCase() : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
    return reply(400, { error: 'Enter a valid employee email' });

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email);
  if (inviteError || !invited.user) return reply(400, { error: inviteError?.message ?? 'Invitation failed' });
  const { error: profileError } = await admin.from('profiles').upsert({
    id: invited.user.id, email, role: 'employee', active: true,
  }, { onConflict: 'id' });
  if (profileError) {
    // Don't claim success when the invite was sent but the authorization profile failed.
    return reply(500, { error: 'Invitation sent but employee profile failed. Contact administrator.' });
  }
  await admin.from('activity_logs').insert({
    actor_id: identity.user.id, action: 'employee_invited',
    entity_type: 'profile', entity_id: invited.user.id,
    details: { email },
  });
  return reply(200, { success: true, email });
});
