const fs=require('fs'),vm=require('vm');
const src=fs.readFileSync(process.argv[2],'utf8');
const ctx={WebAssembly,Uint8Array,Uint32Array,Promise,console,module:{exports:{}},exports:{}};
vm.createContext(ctx); vm.runInContext(src+';this.__M=typeof MeshoptDecoder!=="undefined"?MeshoptDecoder:module.exports.MeshoptDecoder||module.exports;',ctx);
const M=ctx.__M;
const d=fs.readFileSync(process.argv[3]); const n=d.readUInt32LE(12); const j=JSON.parse(d.slice(20,20+n).toString());
const bin=d.slice(20+n+8);
M.ready.then(()=>{
  // names each decoded view by what it feeds: pos / nrm / uv / idx (others v<N>, e.g. joints and weights)
  const pr=j.meshes[0].primitives[0],A=j.accessors,names={};for(let k=0;k<64;k++)names[k]='v'+k;
  names[A[pr.attributes.POSITION].bufferView]='pos';names[A[pr.attributes.NORMAL].bufferView]='nrm';names[A[pr.attributes.TEXCOORD_0].bufferView]='uv';names[A[pr.indices].bufferView]='idx';
  j.bufferViews.forEach((bv,i)=>{
    const e=bv.extensions&&bv.extensions.EXT_meshopt_compression; if(!e) return;
    const out=new Uint8Array(e.count*e.byteStride);
    M.decodeGltfBuffer(out,e.count,e.byteStride,new Uint8Array(bin.buffer,bin.byteOffset+e.byteOffset,e.byteLength),e.mode,e.filter||'NONE');
    fs.writeFileSync(process.argv[4]+'/'+names[i]+'.bin',out); console.log(names[i],e.count,e.byteStride);
  });
  j.images.forEach((im,k)=>{const bv=j.bufferViews[im.bufferView]; fs.writeFileSync(process.argv[4]+'/tex'+k+(im.mimeType=='image/png'?'.png':'.jpg'),bin.slice(bv.byteOffset,bv.byteOffset+bv.byteLength));});
});
