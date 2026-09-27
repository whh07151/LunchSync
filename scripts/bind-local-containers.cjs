// Docker Desktop fallback when bridge host_binding_ipv4 is ignored.
// Only this script's isolated Supabase project. Keeps named volumes and a stopped rollback container.
const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
const host=execFileSync('docker.exe',['context','inspect','--format','{{.Endpoints.docker.Host}}'],{encoding:'utf8'}).trim();
assert.equal(host,'npipe:////./pipe/dockerDesktopLinuxEngine','Only the local Docker Desktop Linux engine is supported');
const socketPath='\\\\.\\pipe\\dockerDesktopLinuxEngine';
function api(method,endpoint,body){return new Promise((resolve,reject)=>{
  const payload=body===undefined?null:JSON.stringify(body);
  const req=http.request({socketPath,path:'/v1.47'+endpoint,method,headers:payload?{'content-type':'application/json','content-length':Buffer.byteLength(payload)}:{}},res=>{
    let result='';res.on('data',c=>result+=c);res.on('end',()=>{
      if(res.statusCode>=400)return reject(new Error(`Local Docker action failed (${res.statusCode})`));
      resolve(result?JSON.parse(result):null);
    });
  });req.on('error',()=>reject(new Error('Local Docker pipe unavailable')));req.end(payload);
});}
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const state=path.resolve(__dirname,'../.local');
const settings=JSON.parse(fs.readFileSync(path.join(state,'supabase-status.json'),'utf8'));
assert.equal(new URL(settings.API_URL).hostname,'127.0.0.1');
async function countOrders(){
  const r=await fetch(settings.API_URL+'/rest/v1/orders?select=id&limit=1',{headers:{apikey:settings.SERVICE_ROLE_KEY,authorization:'Bearer '+settings.SERVICE_ROLE_KEY,Prefer:'count=exact'},signal:AbortSignal.timeout(10000)});
  assert.ok([200,206].includes(r.status),'Local database readiness/count failed');
  const n=Number((r.headers.get('content-range')||'').split('/')[1]);assert.ok(Number.isFinite(n));return n;
}
async function main(){
  const before=await countOrders();
  const backups=[];
  const names=['supabase_db_lunchsync-local','supabase_kong_lunchsync-local','supabase_inbucket_lunchsync-local','supabase_studio_lunchsync-local'];
  for(const name of names){
    const old=await api('GET',`/containers/${name}/json`);
    assert.equal(old.Config.Labels['com.supabase.cli.project'],'lunchsync-local');
    const mappings=Object.values(old.NetworkSettings.Ports).flat().filter(Boolean);
    if(mappings.every(m=>m.HostIp==='127.0.0.1'))continue;
    const bindings=structuredClone(old.HostConfig.PortBindings);
    for(const value of Object.values(bindings))for(const mapping of value)mapping.HostIp='127.0.0.1';
    const network=old.HostConfig.NetworkMode;
    assert.equal(network,'lunchsync-loopback');
    const aliases=(old.NetworkSettings.Networks[network]?.Aliases||[]).filter(a=>a!==old.Id && a!==old.Id.slice(0,12));
    await api('POST',`/containers/${old.Id}/stop?t=60`);
    await api('POST',`/networks/${network}/disconnect`,{Container:old.Id,Force:false});
    await api('POST',`/containers/${old.Id}/rename?name=${name}_loopback_backup`);
    let created;
    try {
      created=await api('POST',`/containers/create?name=${name}`,{...old.Config,Image:old.Image,HostConfig:{...old.HostConfig,PortBindings:bindings},NetworkingConfig:{EndpointsConfig:{[network]:{Aliases:[...new Set([name,...aliases])]}}}});
      await api('POST',`/containers/${created.Id}/start`);
      let healthy=false;
      for(let i=0;i<60;i++){
        const current=await api('GET',`/containers/${created.Id}/json`);
        if(current.State.Running && (!current.State.Health || current.State.Health.Status==='healthy')){healthy=true;break;}
        await sleep(1000);
      }
      assert.ok(healthy,'Recreated local container failed health check');
      backups.push(old.Id);
      console.log(`PASS loopback binding: ${name}`);
    } catch(error) {
      if(created){await api('POST',`/containers/${created.Id}/stop?t=10`).catch(()=>{});await api('DELETE',`/containers/${created.Id}?v=false`).catch(()=>{});}
      await api('POST',`/containers/${old.Id}/rename?name=${name}`);
      await api('POST',`/networks/${network}/connect`,{Container:old.Id,EndpointConfig:{Aliases:[name,...aliases]}});
      await api('POST',`/containers/${old.Id}/start`);
      throw error;
    }
  }
  let after;
  for(let i=0;i<30;i++){try{after=await countOrders();break;}catch{await sleep(1000);}}
  assert.equal(after,before,'Local synthetic records must survive container recreation');
  for(const id of backups)await api('DELETE',`/containers/${id}?v=false`);
  for(const name of names){
    const c=await api('GET',`/containers/${name}/json`);
    assert.ok(Object.values(c.NetworkSettings.Ports).flat().filter(Boolean).every(m=>m.HostIp==='127.0.0.1'));
  }
  console.log(`PASS local data retained (${after} orders); published ports restricted to 127.0.0.1`);
}
main().catch(error=>{console.error('LOCAL_BIND_FAILED',error.message);process.exitCode=1;});
