// record_lines: node run.cjs jobs.json raw_dir (serve a folder holding h.html and a link "app" -> Echo Vision app/ on 127.0.0.1:8766)
// usage: node run.cjs jobs.json outdir   jobs: [{id, sample(mp3 path), text, out(name)}]
const {chromium}=require('playwright');const fs=require('fs'),path=require('path');
(async()=>{const jobs=JSON.parse(fs.readFileSync(process.argv[2]));const out=process.argv[3];fs.mkdirSync(out,{recursive:true});
const b=await chromium.launch({args:['--autoplay-policy=no-user-gesture-required']});const p=await b.newPage();
p.on('console',m=>{if(!/status/.test(m.text()))console.log('page:',m.text().slice(0,200))});
await p.goto('http://127.0.0.1:8766/h.html');await p.waitForFunction('window.ready');
const cache={};
for(const j of jobs){const f=path.join(out,j.out+'.wav');if(fs.existsSync(f))continue;
 cache[j.sample]??=fs.readFileSync(j.sample).toString('base64');const t0=Date.now();
 try{const r=await p.evaluate(([t,i,s])=>window.gen(t,i,s),[j.text,j.id,cache[j.sample]]);
  const pcm=Buffer.from(r.b64,'base64');const h=Buffer.alloc(44);h.write('RIFF',0);h.writeUInt32LE(36+pcm.length,4);h.write('WAVEfmt ',8);h.writeUInt32LE(16,16);h.writeUInt16LE(1,20);h.writeUInt16LE(1,22);h.writeUInt32LE(r.rate,24);h.writeUInt32LE(r.rate*2,28);h.writeUInt16LE(2,32);h.writeUInt16LE(16,34);h.write('data',36);h.writeUInt32LE(pcm.length,40);
  fs.writeFileSync(f,Buffer.concat([h,pcm]));console.log('ok',j.out,((Date.now()-t0)/1000).toFixed(1)+'s',(pcm.length/2/r.rate).toFixed(1)+'s audio');
 }catch(e){console.log('fail',j.out,e.message)}}
await b.close()})();
