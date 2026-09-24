import { createClient } from 'npm:@supabase/supabase-js@2';
import { sendPushNotification } from 'npm:@mmmike/web-push/send';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const VAPID_PUBLIC_KEY='BBTmkscLo3MjwNDIl0hXR-PxOfDObQ8IUWQpZ8Sqb8EW8cMsUIWBIXFoNXwsJlx3kWznBpx-jTRKLh_dJmmCw-0';
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:cors});
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return json({error:'Method not allowed'},405);
 const url=Deno.env.get('SUPABASE_URL');
 const pub=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}').default;
 const secret=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default;
 const priv=Deno.env.get('VAPID_PRIVATE_KEY');const subject=Deno.env.get('VAPID_SUBJECT');const auth=req.headers.get('Authorization')||'';
 if(!url||!pub||!secret||!priv||!subject)return json({error:'Server configuration incomplete'},500);
 if(!auth.startsWith('Bearer '))return json({error:'Unauthorized'},401);
 const user=createClient(url,pub,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
 const {data:isAdmin}=await user.rpc('is_dock_admin');if(!isAdmin)return json({error:'Forbidden'},403);
 const body=await req.json().catch(()=>({}));if(!body.ticket_id||!body.dock)return json({error:'ticket_id and dock are required'},400);
 const admin=createClient(url,secret,{auth:{persistSession:false}});
 const {data:t}=await admin.from('loading_tickets').select('id,number,plate,load_number,tracking_token,status').eq('id',body.ticket_id).single();
 if(!t||t.status!=='called')return json({error:'Ticket not called'},409);
 const {data:subs}=await admin.from('loading_push_subscriptions').select('id,endpoint,p256dh,auth').eq('ticket_id',body.ticket_id);
 if(!subs?.length)return json({ok:true,sent:0,reason:'no_subscription'});
 const base=(body.app_url||'').replace(/\?.*$/,'').replace(/#.*$/,'');const click=base?`${base}?ticket=${t.tracking_token}`:undefined;
 const payload={title:'LoadFlow — Sua doca está liberada',body:`Dirija-se à ${body.dock}. Load ${t.load_number} · Placa ${t.plate}.`,url:click,tag:`loadflow-call-${t.id}`};
 let sent=0;const bad:number[]=[];
 for(const s of subs){try{const ok=await sendPushNotification({endpoint:s.endpoint,keys:{p256dh:s.p256dh,auth:s.auth}},payload,{subject,publicKey:VAPID_PUBLIC_KEY,privateKey:priv},{ttl:3600,urgency:'high'});if(ok)sent++;else bad.push(s.id)}catch(err){console.error('LoadFlow push error',err);}}
 if(bad.length)await admin.from('loading_push_subscriptions').delete().in('id',bad);
 return json({ok:true,sent});
});
