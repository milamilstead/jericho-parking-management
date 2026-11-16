// Protected Supabase Edge Function. Deploy with JWT verification enabled.
// SUPABASE_SERVICE_ROLE_KEY must only be set in Supabase server secrets.
import { createClient } from 'npm:@supabase/supabase-js@2';
const headers = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const respond=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response(null,{headers});
 if(req.method!=='POST')return respond(405,{error:'Method not allowed'});
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!key)return respond(500,{error:'Server configuration missing'});
 const admin=createClient(url,key,{auth:{persistSession:false}});
 const token=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
 const {data:identity,error:authError}=await admin.auth.getUser(token);
 if(authError||!identity.user)return respond(401,{error:'Sign in required'});
 const {data:manager}=await admin.from('profiles').select('id').eq('id',identity.user.id).eq('role','manager').eq('active',true).maybeSingle();
 if(!manager)return respond(403,{error:'Managers only'});
 let body:{action?:string;userId?:string;email?:string;role?:string;active?:boolean};
 try{body=await req.json()}catch{return respond(400,{error:'Invalid JSON'})}
 if(!body.userId||!['reset','email','role','active'].includes(body.action||''))return respond(400,{error:'Invalid request'});
 const {data:target}=await admin.from('profiles').select('id,email,role,active').eq('id',body.userId).maybeSingle();
 if(!target)return respond(404,{error:'Employee not found'});
 if(target.id===identity.user.id)return respond(400,{error:'Use My Profile to update your own account'});
 let message='Employee updated';
 if(body.action==='reset'){
  const {error}=await admin.auth.resetPasswordForEmail(target.email);
  if(error)return respond(400,{error:error.message});message='Password reset email requested';
 }else if(body.action==='email'){
  const email=(body.email||'').trim().toLowerCase();
  if(email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return respond(400,{error:'Invalid email'});
  const {error}=await admin.auth.admin.updateUserById(target.id,{email,email_confirm:true});
  if(error)return respond(400,{error:error.message});
  // Profile email is synchronized by auth.users trigger in migration 05.
  message='Employee email updated';
 }else if(body.action==='role'){
  if(!['manager','employee'].includes(body.role||''))return respond(400,{error:'Invalid role'});
  const {error}=await admin.from('profiles').update({role:body.role}).eq('id',target.id);
  if(error)return respond(400,{error:error.message});
 }else if(body.action==='active'){
  if(typeof body.active!=='boolean')return respond(400,{error:'Invalid status'});
  const {error}=await admin.from('profiles').update({active:body.active}).eq('id',target.id);
  if(error)return respond(400,{error:error.message});
 }
 await admin.from('activity_logs').insert({actor_id:identity.user.id,action:'employee_'+body.action,entity_type:'profile',entity_id:target.id,details:{email:body.action==='email'?body.email:target.email,role:body.role,active:body.active}});
 return respond(200,{success:true,message});
});
