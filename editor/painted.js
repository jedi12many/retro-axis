// =====================================================================
//  Painted world + custom palette (C64 + REU / C64 Ultimate flavors)
//
//  The REU tier shows a pre-rendered world, so its art is not limited by
//  what the engine can draw fast. A painted world is made in three passes:
//    1. compose the scene in full colour: tiles keep their own colours
//       everywhere, with no colour clash while composing;
//    2. bake lighting: shadows from walls, trees and raised ground, in map
//       space (light from the upper left of the screen, i.e. from map -x),
//       so the result depends only on the world, not on the camera;
//    3. convert to legal C64 multicolour cells: every 4x8 cell picks the
//       best 3 colours (+ the shared $d021 background) from the palette,
//       with optional ordered dithering.
//  The palette is the standard VIC-II one, or (C64 Ultimate) a custom set
//  of 16 RGB colours per map, loaded through the Ultimate Command Interface.
//  Uses globals from the main editor script at call time
//  (PAL, MW, VP, CENTER_COL, CENTER_ROW, project, canTouchViewport).
// =====================================================================
const PALETTE_PRESETS={
  'Standard VIC-II':null,
  'Earthy':['#141018','#f2ead8','#a8452e','#7fb8b0','#7a4f86','#3f7a34','#2c4a78','#e2c35a','#b8743a','#5a3a22','#e0a27c','#3a3a40','#7c776c','#8fbf4c','#6f9ad0','#b8b0a0'],
  'Dungeon':['#0c0b10','#e6e1d3','#8e2f2a','#5e8f93','#5b3f6e','#3e5e3a','#24305a','#c9a64a','#8a5a32','#3d2b20','#b9786a','#2b2b33','#5a5866','#6f8f5a','#4f6a9a','#8f8a98'],
  'Desert':['#1a120c','#fff3d6','#b5532c','#86c2b6','#93607c','#7f8f3c','#3a5f8f','#f0cf6a','#d98c46','#7a4e2c','#f0b48c','#4a3e36','#9c8a72','#b8c46a','#8fb0d8','#d8c8a8'],
  'Night':['#05060c','#cfd8f0','#7a2a3a','#4f8fa8','#5a3f8a','#2a5a4a','#1c2a5a','#b8a85a','#7a5a3a','#2c2430','#9a7a8a','#1e2230','#46506a','#4f7a6a','#3f5a9a','#7a849a'],
};
const PAINT_DEFAULTS={on:false,shadows:true,strength:0.45,ambient:true,dither:true};

const hexRGB=h=>[parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];
function mapPalette(m,ultimate){return(ultimate&&m.ult&&m.ult.pal)?m.ult.pal:PAL;}

// elevation of a map cell in levels: ground height + how far its object rises
function cellElevation(m,tiles,i){
  const h=m.hgt[i]&3,o=m.obj[i],t=o?tiles[o]:null;
  return h+(t?Math.max(0,t.h-2):0);
}
// 0..1 shadow on each map cell's floor: an occluder d cells towards the light
// (map -x) that rises at least d levels above this floor shades it (45-degree sun)
function shadowMap(m,tiles){
  const s=new Float32Array(MW*MW),E=new Int8Array(MW*MW);
  for(let i=0;i<MW*MW;i++)E[i]=cellElevation(m,tiles,i);
  for(let y=0;y<MW;y++)for(let x=0;x<MW;x++){
    const i=y*MW+x,h=m.hgt[i]&3;let v=0;
    for(let d=1;d<=4&&x-d>=0;d++){const r=E[y*MW+x-d]-h;if(r>=d){v=1;break;}if(r>=d-1&&r>0)v=Math.max(v,0.5);}
    s[i]=v;
  }
  return s;
}

// pass 1+2: full-colour composition of the viewport, with lighting.
// rgb: Float32Array of 160x200 fat pixels x 3; set: which pixels were drawn
function paintedCompose(m,tiles,cx,cy,pal,opts){
  const W=160,H=200,rgb=new Float32Array(W*H*3),set=new Uint8Array(W*H),floor=new Int16Array(W*H).fill(-1);
  const prgb=pal.map(hexRGB),bg=prgb[m.bg];
  for(let p=0;p<W*H;p++){rgb[p*3]=bg[0];rgb[p*3+1]=bg[1];rgb[p*3+2]=bg[2];}
  const x0=VP.c0*4,x1=(VP.c1+1)*4,y0=VP.r0*8,y1=(VP.r1+1)*8;
  const draw=(t,bcol,grow,owner)=>{
    if(!t)return;const top=(grow+2-t.h)*8,left=bcol*4;
    for(let y=0;y<t.h*8;y++){const Y=top+y;if(Y<y0||Y>=y1)continue;
      for(let x=0;x<16;x++){const v=t.px[y*16+x];if(v<0)continue;const X=left+x;if(X<x0||X>=x1)continue;
        const cc=t.cells[(y>>3)*4+(x>>2)],c=prgb[[m.bg,cc.c1,cc.c2,cc.c3][v]],p=Y*W+X;
        rgb[p*3]=c[0];rgb[p*3+1]=c[1];rgb[p*3+2]=c[2];set[p]=1;floor[p]=owner;}}
  };
  for(let y=0;y<MW;y++)for(let x=0;x<MW;x++){
    const i=y*MW+x,h=m.hgt[i]&3,{col,row}=project(x,y,cx,cy);
    if(!canTouchViewport(col,row))continue;
    if(m.terr[i]){for(let l=0;l<h;l++)draw(tiles[m.slab],col,row-l,-1);draw(tiles[m.terr[i]],col,row-h,i);}
    if(m.obj[i])draw(tiles[m.obj[i]],col,row-h,-1);
  }
  if(opts.shadows){
    const sh=shadowMap(m,tiles),k=opts.strength;
    // ambient occlusion: floors right next to something taller get a little darker
    for(let p=0;p<W*H;p++){const i=floor[p];if(i<0)continue;
      let f=1-k*sh[i];
      if(opts.ambient&&sh[i]===0){const x=i%MW,y=(i/MW)|0,h=m.hgt[i]&3;
        if((x>0&&cellElevation(m,tiles,i-1)>h)||(y>0&&cellElevation(m,tiles,i-MW)>h))f=0.85;}
      rgb[p*3]*=f;rgb[p*3+1]*=f;rgb[p*3+2]*=f;}
  }
  return{rgb,set,prgb,bgIndex:m.bg};
}

// pass 3: legal C64 multicolour cells. Returns cells of {cols:[bg,a,b,c], px:[32 slot values]}.
// Besides the 4 cell colours, a pixel may use a 50/50 dither of two of them
// (how C64 artists shade): a shadowed green becomes green dithered with black,
// not the nearest single colour (a grey or brown). The cell's colour choice
// accounts for that; to keep it fast, each cell only considers its 7 most
// useful colours (plus the background).
const MIX_PENALTY=1.15;   // a dithered mix must be clearly better than a solid colour
function paintedQuantize(comp,dither){
  const {rgb,prgb,bgIndex}=comp,cells=new Map();
  const dist=(R,G,B,q)=>{const rm=(R+q[0])/2;return(2+rm/256)*(R-q[0])**2+4*(G-q[1])**2+(2+(255-rm)/256)*(B-q[2])**2;};
  // every 50/50 pair of palette colours (i<=j; i==j is the solid colour)
  const pairs=[],pairIdx=[];for(let i=0;i<16;i++){pairIdx.push([]);}
  for(let i=0;i<16;i++)for(let j=i;j<16;j++){const a=prgb[i],b=prgb[j];pairIdx[i][j]=pairIdx[j][i]=pairs.length;
    pairs.push({i,j,rgb:[(a[0]+b[0])/2,(a[1]+b[1])/2,(a[2]+b[2])/2],pen:i===j?1:MIX_PENALTY});}
  const NP=pairs.length,D=new Float32Array(32*NP);
  for(let r=VP.r0;r<=VP.r1;r++)for(let col=VP.c0;col<=VP.c1;col++){
    for(let k=0;k<32;k++){const X=col*4+(k&3),Y=r*8+(k>>2),p=(Y*160+X)*3,R=rgb[p],G=rgb[p+1],B=rgb[p+2];
      for(let q=0;q<NP;q++)D[k*NP+q]=dist(R,G,B,pairs[q].rgb)*pairs[q].pen;}
    // rank colours by how often they take part in a pixel's best match
    const score=new Float32Array(16);
    for(let k=0;k<32;k++){let bq=0,bd=1e30;for(let q=0;q<NP;q++){const d=D[k*NP+q];if(d<bd){bd=d;bq=q;}}
      score[pairs[bq].i]+=1;score[pairs[bq].j]+=1;}
    const cand=[...Array(16).keys()].filter(c=>c!==bgIndex).sort((a,b)=>score[b]-score[a]).slice(0,7);
    let best=null,be=1e30;
    for(let a=0;a<cand.length;a++)for(let b=a+1;b<cand.length;b++)for(let c=b+1;c<cand.length;c++){
      const cs=[bgIndex,cand[a],cand[b],cand[c]],qs=[];
      for(let u=0;u<4;u++)for(let v=u;v<4;v++)qs.push(pairIdx[cs[u]][cs[v]]);
      let e=0;
      for(let k=0;k<32;k++){const o=k*NP;let mn=1e30;for(const q of qs){const d=D[o+q];if(d<mn)mn=d;}e+=mn;if(e>=be)break;}
      if(e<be){be=e;best=cs;}}
    const cols=best,px=new Array(32);
    for(let k=0;k<32;k++){const o=k*NP;let bu=0,bv=0,bd=1e30;
      for(let u=0;u<4;u++)for(let v=u;v<4;v++){if(!dither&&u!==v)continue;const d=D[o+pairIdx[cols[u]][cols[v]]];if(d<bd){bd=d;bu=u;bv=v;}}
      // a mix becomes a checkerboard of its two colours (fat pixel x + line)
      px[k]=(bu===bv||(((k&3)+(k>>2))&1)===0)?bu:bv;}
    cells.set(r*40+col,{cols,px,err:be});
  }
  return cells;
}

// the painted frame as RGBA (320x200 display pixels, 2 per fat pixel)
function paintedImage(m,tiles,cx,cy,pal,opts,img){
  const comp=paintedCompose(m,tiles,cx,cy,pal,opts),cells=paintedQuantize(comp,opts.dither),d=img.data,bg=comp.prgb[m.bg];
  for(let p=0;p<320*200;p++){d[p*4]=bg[0];d[p*4+1]=bg[1];d[p*4+2]=bg[2];d[p*4+3]=255;}
  let err=0;
  for(const [o,c] of cells){const r=(o/40)|0,col=o%40;err+=c.err;
    for(let k=0;k<32;k++){const q=comp.prgb[c.cols[c.px[k]]],X=col*8+(k&3)*2,Y=r*8+(k>>2);
      for(let z=0;z<2;z++){const p=(Y*320+X+z)*4;d[p]=q[0];d[p+1]=q[1];d[p+2]=q[2];}}}
  return{cells:cells.size,err:err/cells.size};
}
