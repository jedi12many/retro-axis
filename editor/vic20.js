// =====================================================================
//  VIC-20 target (preview)
//  Converts the C64 tileset to VIC-20 multicolour characters and renders a
//  map the way a character-mode VIC-20 engine would:
//    - 22x23 PAL screen of 8x8 characters, one custom 256-character set
//    - multicolour cells: 00 screen colour, 01 border colour,
//      10 per-cell character colour (0-7, colour RAM), 11 auxiliary colour
//    - no hardware sprites: hero and monsters are composited into characters
//  Every distinct 8x8 pattern on screen needs its own character, so the
//  preview counts them against the character budget.
//  Uses globals from the main editor script at call time (PAL, SPRITES, MW).
// =====================================================================
const VIC_PAL=['#000000','#ffffff','#b61f21','#4df0ff','#b43fff','#44e237','#1a34ff','#dcd71b','#ca5400','#e9b072','#e79293','#9af7fd','#e09fff','#8fe493','#8290ff','#e5de85'];
const VIC_NAME=['black','white','red','cyan','purple','green','blue','yellow','orange','light orange','pink','light cyan','light purple','light green','light blue','light yellow'];
// charBudget: the engine double-buffers by giving each frame its own half of the
// character set (codes 0-111 / 112-223; 224-255 are kept for text)
const VIC={cols:22,rows:23,vp:{c0:0,c1:21,r0:0,r1:17},centerCol:9,centerRow:7,charBudget:112};
const VTILES_ADDR=0x7000,VTILES_MAX=0x1000,VSPR_ADDR=0x3800;

const rgb=h=>[parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];
const colDist=(a,b)=>{const p=rgb(a),q=rgb(b),r=(p[0]+q[0])/2;  // "redmean" perceptual distance
  return (2+r/256)*(p[0]-q[0])**2+4*(p[1]-q[1])**2+(2+(255-r)/256)*(p[2]-q[2])**2;};
let VIC_D=null; // VIC_D[c64][vic]
function vicDist(){if(!VIC_D)VIC_D=PAL.map(a=>VIC_PAL.map(b=>colDist(a,b)));return VIC_D;}

// per tile cell: the C64 colour of each pixel value and how often it is used
function cellHist(t,c64bg){
  const out=[];
  for(let r=0;r<t.h;r++)for(let c=0;c<4;c++){
    const cc=t.cells[r*4+c],cols=[c64bg,cc.c1,cc.c2,cc.c3],n=[0,0,0,0];
    for(let y=0;y<8;y++)for(let i=0;i<4;i++){const v=t.px[(r*8+y)*16+c*4+i];if(v>=0)n[v]++;}
    out.push({cols,n});
  }
  return out;
}
// best character colour (0-7) for one cell and the slot each pixel value maps to
function fitCell(h,g){
  const D=vicDist();let best=null;
  for(let fg=0;fg<8;fg++){
    const slots=[g.bg,g.border,fg,g.aux];let err=0;const map=[0,0,0,0];
    for(let k=0;k<4;k++){if(!h.n[k])continue;let bs=0,bd=1e18;
      for(let s=0;s<4;s++){const d=D[h.cols[k]][slots[s]];if(d<bd){bd=d;bs=s;}}
      map[k]=bs;err+=bd*h.n[k];}
    if(!best||err<best.err)best={fg,map,err};
  }
  return best;
}
// VIC-20 version of a tile: px = VIC slot per pixel (-1 transparent, 0 screen,
// 1 border, 2 cell colour, 3 auxiliary), cells = [{fg 0-7, own}].
// t.vic holds a hand-edited version; otherwise it is converted from the C64 tile
// with this map's shared colours.
function vicAutoTile(t,g,c64bg){
  const hist=cellHist(t,c64bg),px=new Array(16*8*t.h).fill(-1),cells=[];
  for(let r=0;r<t.h;r++)for(let c=0;c<4;c++){
    const f=fitCell(hist[r*4+c],g);cells.push({fg:f.fg,own:t.cells[r*4+c].own||'auto'});
    for(let y=0;y<8;y++)for(let i=0;i<4;i++){const k=(r*8+y)*16+c*4+i,v=t.px[k];px[k]=v<0?-1:f.map[v];}
  }
  return{px,cells};
}
const vicTileData=(t,g,c64bg)=>t.vic||vicAutoTile(t,g,c64bg);
function vicEditable(t,g,c64bg){if(!t.vic)t.vic=vicAutoTile(t,g,c64bg);return t.vic;}
// keep a hand-edited version in step when the tile height changes (bottom aligned)
function vicResize(t,d){
  if(!t.vic)return;const v=t.vic;
  if(d>0){v.px=new Array(d*128).fill(-1).concat(v.px);v.cells=Array.from({length:4*d},()=>({...v.cells[0]})).concat(v.cells);}
  else if(d<0){v.px=v.px.slice(-d*128);v.cells=v.cells.slice(-d*4);}
}
// tile -> character cells (same cell types as the C64 version)
function vicEncodeTile(t,g,c64bg){
  const d=vicTileData(t,g,c64bg),cells=[];
  for(let r=0;r<t.h;r++)for(let c=0;c<4;c++){
    const bmp=[],mask=[];let trans=0;
    for(let y=0;y<8;y++){let b=0,m=0;
      for(let i=0;i<4;i++){const v=d.px[(r*8+y)*16+c*4+i];
        if(v<0){trans++;m|=3<<(6-2*i);}else b|=v<<(6-2*i);}
      bmp.push(b);mask.push(m);}
    const cc=d.cells[r*4+c];let type;
    if(trans===32)type=0;else if(trans===0)type=1;
    else type=cc.own==='own'?2:cc.own==='keep'?3:((32-trans)>=16?2:3);
    cells.push({type,fg:cc.fg,bmp,mask});
  }
  return{h:t.h,cells};
}
// how often each tile id is drawn on this map (slab counted once per level)
function tileUse(m,n){
  const use=new Array(n).fill(0);
  for(let i=0;i<MW*MW;i++){if(m.terr[i]){use[m.terr[i]]++;use[m.slab]+=m.hgt[i]&3;}if(m.obj[i])use[m.obj[i]]++;}
  return use;
}
// pick screen, border and auxiliary colours that fit this map's tiles best
function vicAutoColours(tiles,m){
  const D=vicDist(),use=tileUse(m,tiles.length),cells=[];
  tiles.forEach((t,i)=>{if(!t||!use[i])return;cellHist(t,m.bg).forEach(h=>{if(h.n.some(x=>x))cells.push({h,w:use[i]});});});
  let best=null;
  for(let bg=0;bg<16;bg++)for(let border=0;border<8;border++)for(let aux=0;aux<16;aux++){
    let err=0;
    for(const {h,w} of cells){let cb=1e18;
      for(let fg=0;fg<8;fg++){const sl=[bg,border,fg,aux];let e=0;
        for(let k=0;k<4;k++){if(!h.n[k])continue;const row=D[h.cols[k]];
          e+=h.n[k]*Math.min(row[sl[0]],row[sl[1]],row[sl[2]],row[sl[3]]);}
        if(e<cb)cb=e;}
      err+=cb*w;
      if(best&&err>=best.err)break;}
    if(!best||err<best.err)best={err,bg,border,aux};
  }
  return{bg:best.bg,border:best.border,aux:best.aux};
}
function vicNearest(c64col,max=8){const D=vicDist();let b=0;for(let v=1;v<max;v++)if(D[c64col][v]<D[c64col][b])b=v;return b;}

// ---- renderer --------------------------------------------------------------
function vicNewFB(){const n=VIC.cols*VIC.rows;return{bmp:new Uint8Array(n*8),fg:new Uint8Array(n),src:new Int8Array(n*32).fill(-1)};}
const vicProject=(x,y,cx,cy)=>{const dx=x-cx,dy=y-cy;return{col:VIC.centerCol+2*(dx-dy),row:VIC.centerRow+dx+dy};};
const vicCanTouch=(col,row)=>col>=VIC.vp.c0-3&&col<=VIC.vp.c1&&row>=VIC.vp.r0-1&&row<=VIC.vp.r1+9;
function vicDrawTile(fb,enc,bcol,grow){
  if(!enc)return;
  let row=grow+2-enc.h;
  for(let r=0;r<enc.h;r++,row++)for(let c=0;c<4;c++){
    const cell=enc.cells[r*4+c],col=bcol+c,vp=VIC.vp;
    if(!cell.type||row<vp.r0||row>vp.r1||col<vp.c0||col>vp.c1)continue;
    const o=row*VIC.cols+col,b=o*8;
    if(cell.type!==3)fb.fg[o]=cell.fg;
    for(let i=0;i<8;i++){
      const keep=cell.type===1?0:cell.mask[i];
      fb.bmp[b+i]=(fb.bmp[b+i]&keep)|cell.bmp[i];
      // remember which colour each 10-pixel was drawn with (for clash detection)
      for(let p=0;p<4;p++){const sh=6-2*p;if((keep>>sh&3)===3)continue;
        fb.src[o*32+i*4+p]=(cell.bmp[i]>>sh&3)===2?cell.fg:-1;}
    }
  }
}
function vicDrawSprite(fb,sid,fg,mx,y){ // mx in multicolour pixels, y in pixel rows
  const rows=(SPRITES[sid]||SPRITES[0])[1],slot={o:0,x:2,s:1};
  rows.forEach((line,sy)=>{line=line.padEnd(12,'.').slice(0,12);
    for(let i=0;i<12;i++){const ch=line[i];if(ch==='.')continue;
      const X=mx+i,Y=y+sy,col=X>>2,row=Y>>3,vp=VIC.vp;
      if(X<0||Y<0||col<vp.c0||col>vp.c1||row<vp.r0||row>vp.r1)continue;
      const o=row*VIC.cols+col,b=o*8+(Y&7),sh=6-2*(X&3),v=slot[ch];
      fb.bmp[b]=(fb.bmp[b]&~(3<<sh))|(v<<sh);
      fb.src[o*32+(Y&7)*4+(X&3)]=v===2?fg:-1;
      if(v===2)fb.fg[o]=fg;}});
}
function vicRender(m,tiles,cx,cy){
  const g=m.vic,enc=tiles.map(t=>t?vicEncodeTile(t,g,m.bg):null),fb=vicNewFB();
  for(let y=0;y<MW;y++)for(let x=0;x<MW;x++){
    const i=y*MW+x,h=m.hgt[i]&3,{col,row}=vicProject(x,y,cx,cy);
    if(!vicCanTouch(col,row))continue;
    if(m.terr[i]){for(let l=0;l<h;l++)vicDrawTile(fb,enc[m.slab],col,row-l);vicDrawTile(fb,enc[m.terr[i]],col,row-h);}
    if(m.obj[i])vicDrawTile(fb,enc[m.obj[i]],col,row-h);
  }
  // soft sprites, back to front, hero last
  const H=(x,y)=>m.hgt[y*MW+x]&3,spr=[];
  for(const e of m.ents){if(!e.type||e.type===4)continue;const p=vicProject(e.x,e.y,cx,cy);
    spr.push({d:e.x+e.y,sid:e.sprite,fg:vicNearest(e.color),col:p.col,row:p.row-H(e.x,e.y)});}
  spr.sort((a,b)=>a.d-b.d);
  spr.push({sid:0,fg:vicNearest(m.hero),col:VIC.centerCol,row:VIC.centerRow-H(cx,cy)});
  for(const s of spr)vicDrawSprite(fb,s.sid,s.fg,s.col*4+2,s.row*8-9);
  // characters needed and colour clash
  const uniq=new Set(),vp=VIC.vp;let clash=0;const clashCells=[];
  for(let r=vp.r0;r<=vp.r1;r++)for(let c=vp.c0;c<=vp.c1;c++){
    const o=r*VIC.cols+c;uniq.add(Array.from(fb.bmp.subarray(o*8,o*8+8)).join(','));
    let bad=false;
    for(let k=0;k<32;k++){const y=k>>2,p=k&3;if(((fb.bmp[o*8+y]>>(6-2*p))&3)===2&&fb.src[o*32+k]>=0&&fb.src[o*32+k]!==fb.fg[o]){bad=true;break;}}
    if(bad){clash++;clashCells.push(o);}
  }
  return{fb,chars:uniq.size,clash,clashCells,sprites:spr.length};
}
// ---- export -----------------------------------------------------------------
// vtiles.prg -> $7000. Same layout as the C64 TILES file (count, pointer table,
// records of h, flags, cell pointers) but VIC-20 cells:
//   type (1 opaque, 2 masked + colour, 3 masked keep colour), colour RAM byte
//   (cell colour | 8 = multicolour), 8 bitmap bytes, 8 mask bytes unless opaque
function vicExportTiles(tiles,g,c64bg){
  const n=tiles.length-1,out=[VTILES_ADDR&255,VTILES_ADDR>>8,n],ptrs=[0,0],recs=[];
  let addr=VTILES_ADDR+1+2*(n+1);
  for(let i=1;i<=n;i++){
    const e=vicEncodeTile(tiles[i],g,c64bg),tbl=2+e.cells.length*2,r=[e.h,tiles[i].flags],data=[];
    e.cells.forEach(c=>{
      if(!c.type){r.push(0,0);return;}
      const a=addr+tbl+data.length;r.push(a&255,a>>8);
      data.push(c.type,c.fg|8,...c.bmp);if(c.type!==1)data.push(...c.mask);});
    r.push(...data);ptrs.push(addr&255,addr>>8);addr+=r.length;recs.push(r);}
  out.push(...ptrs);recs.forEach(r=>out.push(...r));
  return new Uint8Array(out);
}
// vsprites.prg -> $3800. Figures pre-shifted to where the engine draws them:
// a sprite at tile column col / row row covers a 4x4 block of cells starting at
// (col, row-2), with the figure 2 multicolour pixels in and 7 lines down.
//   $3800 + s*256 + cell*16 : 8 bitmap bytes, 8 mask bytes  (cell = cy*4+cx)
//   $3c00 + s*16 + cell     : 1 if the cell has body pixels (takes the colour)
//   $3c40                   : C64 colour -> nearest VIC-20 cell colour (16 bytes)
function vicExportSprites(){
  const b=new Uint8Array(2+0x450);b[0]=VSPR_ADDR&255;b[1]=VSPR_ADDR>>8;
  const slot={o:0,x:2,s:1};
  SPRITES.slice(0,4).forEach(([,rows],s)=>{
    const bmp=new Uint8Array(16*8),mask=new Uint8Array(16*8).fill(255),hasx=new Uint8Array(16);
    rows.forEach((line,sy)=>{line=line.padEnd(12,'.').slice(0,12);
      for(let i=0;i<12;i++){const ch=line[i];if(ch==='.')continue;
        const X=2+i,Y=7+sy,cell=(Y>>3)*4+(X>>2),k=cell*8+(Y&7),sh=6-2*(X&3);
        bmp[k]|=slot[ch]<<sh;mask[k]&=~(3<<sh);if(ch==='x')hasx[cell]=1;}});
    for(let c=0;c<16;c++){const o=2+s*256+c*16;b.set(bmp.subarray(c*8,c*8+8),o);b.set(mask.subarray(c*8,c*8+8),o+8);b[2+0x400+s*16+c]=hasx[c];}
  });
  for(let c=0;c<16;c++)b[2+0x440+c]=vicNearest(c);
  return b;
}
function vicToImage(fb,g,img){
  const d=img.data,W=VIC.cols*8;
  for(let row=0;row<VIC.rows;row++)for(let col=0;col<VIC.cols;col++){
    const o=row*VIC.cols+col,inVp=row>=VIC.vp.r0&&row<=VIC.vp.r1,slots=[g.bg,g.border,fb.fg[o],g.aux];
    for(let y=0;y<8;y++){const b=fb.bmp[o*8+y];
      for(let p=0;p<4;p++){const c=rgb(VIC_PAL[inVp?slots[(b>>(6-2*p))&3]:g.bg]);
        for(let k=0;k<2;k++){const i=((row*8+y)*W+col*8+p*2+k)*4;d[i]=c[0];d[i+1]=c[1];d[i+2]=c[2];d[i+3]=255;}}}}
}
