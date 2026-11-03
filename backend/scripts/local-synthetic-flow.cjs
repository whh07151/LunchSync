// Local API + real local Supabase/Auth/SMTP. No remote DB or real payment.
const assert = require('node:assert/strict');
const {readFileSync,writeFileSync} = require('node:fs');
const {join} = require('node:path');
const {randomUUID} = require('node:crypto');
const {createClient} = require('@supabase/supabase-js');
const state=join(__dirname,'../../.local');
const settings=JSON.parse(readFileSync(join(state,'supabase-status.json'),'utf8'));
assert.ok(['127.0.0.1','localhost'].includes(new URL(settings.API_URL).hostname));
assert.equal(new URL(settings.API_URL).port,'54321');
const db=createClient(settings.API_URL,settings.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const api='http://127.0.0.1:3000/api';
let checks=0;
async function request(method,path,body,token,expected=200) {
  const r=await fetch(api+path,{method,headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  const result=await r.json();
  if(r.status!==expected)throw new Error(`${method} ${path} status=${r.status} expected=${expected}; code=${result.code||''}; message=${JSON.stringify(result.message||'')}`);
  checks++;return result.data??result;
}
async function verify(account){
  const signup=await request('POST','/auth/signup/email',account,undefined,201);
  await request('GET','/users/me',undefined,signup.accessToken,401);
  await request('POST','/auth/email/send-otp',{email:account.email},signup.accessToken,201);
  let code;
  for(let i=0;i<30&&!code;i++){
    const inbox=await (await fetch('http://127.0.0.1:54324/api/v1/messages')).json();
    const item=inbox.messages.find(m=>m.To?.some(to=>to.Address===account.email));
    if(item){const mail=await (await fetch('http://127.0.0.1:54324/api/v1/message/'+item.ID)).json();code=(mail.Text||mail.HTML||'').match(/\b\d{6}\b/)?.[0];}
    if(!code)await new Promise(resolve=>setTimeout(resolve,250));
  }
  assert.ok(code,'Local inbox did not contain numeric OTP');
  const verified=await request('POST','/auth/email/verify-otp',{email:account.email,code},signup.accessToken,201);
  const login=await request('POST','/auth/login/email',{email:account.email,password:account.password},undefined,201);
  assert.ok(login.accessToken);assert.ok(verified.accessToken);
  return {...account,id:login.user.id,token:login.accessToken};
}
async function main(){
  await request('GET','/ready');
  const run=randomUUID().slice(0,8);const password='SyntheticLocal-'+randomUUID();
  const a=await verify({email:`local-a-${run}@synthetic.invalid`,password,name:'가상 고객 A',role:'CUSTOMER'});
  const b=await verify({email:`local-b-${run}@synthetic.invalid`,password,name:'가상 고객 B',role:'CUSTOMER'});
  const c=await verify({email:`local-c-${run}@synthetic.invalid`,password,name:'가상 외부 고객 C',role:'CUSTOMER'});
  writeFileSync(join(state,'demo-accounts.json'),JSON.stringify({accounts:[a,b,c].map(({token,...account})=>account)},null,2));
  console.log('PASS real local email signup → restricted JWT → local SMTP OTP → verification → normal login');
  for(const account of [a,b])await request('PATCH','/users/me',{org:'가상 연구실',radius:'500m',budget:10000,speed:'NORMAL'},account.token);
  const restaurantId='c9270000-0000-4000-8000-000000000001';
  const menuId='c9270000-0000-4000-8000-000000000002';
  for(const [table,rows] of [['restaurants',[{id:restaurantId,name:'로컬 가상 한식당',lat:37.5665,lng:126.978,category:'한식',price_range:9000,rating:4.5,address:'합성 데이터 전용 장소'}]],['menu_items',[{id:menuId,restaurant_id:restaurantId,name:'가상 비빔밥',price:9000,category:'한식',is_available:true,ingredients:['쌀','채소'],allergens:[],source:'MANUAL'}]]]){
    const {error}=await db.from(table).upsert(rows);if(error)throw new Error('Local fixture insert failed: '+table+' '+error.code);
  }
  const session=await request('POST','/sessions',{name:'합성 점심 '+run,radius:1000,budget:10000,returnMinutes:60,lat:37.5665,lng:126.978},a.token,201);
  const sessionId=session.id??session.sessionId;assert.ok(sessionId);
  const invitation=await request('POST','/invitations',{sessionId},a.token,201);
  const code=invitation.inviteCode;assert.ok(code);
  await request('POST',`/invitations/${code}/accept`,{},b.token,201);
  await request('PATCH',`/sessions/${sessionId}/status`,{status:'VOTING'},b.token,403);
  await request('PATCH',`/sessions/${sessionId}/status`,{status:'VOTING'},a.token);
  for(const account of [a,b])await request('POST',`/sessions/${sessionId}/votes`,{restaurantId},account.token,201);
  await request('POST',`/sessions/${sessionId}/decide`,{},b.token,403);
  const winner=await request('POST',`/sessions/${sessionId}/decide`,{},a.token,201);assert.equal(winner.winnerId,restaurantId);
  await request('GET',`/restaurants/${restaurantId}/menus`,undefined,a.token);
  const order=await request('POST','/orders',{sessionId,items:[{menuItemId:menuId,quantity:1}],paymentMethod:'SIMULATE'},a.token,201);
  assert.equal(order.status,'PAID');assert.equal(Number(order.totalPrice),9000);
  const orderId=order.id??order.orderId;assert.ok(orderId);
  // Session members share order status; unrelated users have no access.
  await request('GET',`/orders/${orderId}`,undefined,b.token);
  await request('GET',`/orders/${orderId}`,undefined,c.token,403);
  const persisted=await request('GET',`/orders/${orderId}`,undefined,a.token);assert.equal(persisted.status,'PAID');
  const {data:rows,error}=await db.from('orders').select('id,status,total_price,user_id').eq('id',orderId).single();assert.equal(error,null);assert.equal(rows.user_id,a.id);assert.equal(rows.status,'PAID');
  console.log('PASS actual session → invitation/member → vote/winner → persisted simulated order; cross-user/host guards');
  writeFileSync(join(state,'demo-accounts.json'),JSON.stringify({accounts:[a,b,c].map(({token,...account})=>account),restaurantId,menuId,sessionId,orderId},null,2));
  console.log(`PASS ${checks} actual HTTP checks; credentials kept in ignored .local/demo-accounts.json; real charges=0`);
}
main().catch(error=>{console.error('LOCAL_FLOW_FAILED',error.message);process.exitCode=1;});
