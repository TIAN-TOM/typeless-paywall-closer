const fs=require('fs'),path=require('path');
const ASAR='/Applications/Typeless.app/Contents/Resources/app.asar';
const OUT=path.resolve('typeless_dist');
const fd=fs.openSync(ASAR,'r');const h=Buffer.alloc(16);fs.readSync(fd,h,0,16,0);
const N=h.readUInt32LE(4),L=h.readUInt32LE(12);const j=Buffer.alloc(L);fs.readSync(fd,j,0,L,16);
const hdr=JSON.parse(j.toString());const base=8+N;let n=0;
(function walk(node,prefix){for(const [name,v] of Object.entries(node.files||{})){const p=prefix+'/'+name;
  if(v.files){walk(v,p);continue}
  if(!p.startsWith('/dist/')||v.unpacked||v.offset===undefined)continue;
  if(/\.(png|jpg|jpeg|gif|woff2?|ttf|mp3|wav|ico|svg)$/i.test(p))continue;
  const dst=path.join(OUT,p);fs.mkdirSync(path.dirname(dst),{recursive:true});
  const b=Buffer.alloc(v.size);fs.readSync(fd,b,0,v.size,base+Number(v.offset));fs.writeFileSync(dst,b);n++;}})(hdr,'');
console.log('extracted',n,'files to',OUT);
