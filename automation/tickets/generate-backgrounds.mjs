// Deterministic, dependency-free print gradients. Silk is an authored image.
import { deflateSync } from 'node:zlib';
import { writeFileSync } from 'node:fs';
import {ticketThemeColor,ticketThemePalettes} from '../../supabase/functions/_shared/ticketThemePalette.js';
const destination = new URL('../../supabase/functions/_shared/ticket-assets/backgrounds/', import.meta.url);
function chunk(type, data) {
  const payload = Buffer.concat([Buffer.from(type), data]);
  let crc = 0xffffffff;
  for (const byte of payload) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  const size = Buffer.alloc(4), sum = Buffer.alloc(4);
  size.writeUInt32BE(data.length); sum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([size, payload, sum]);
}
const palettes = {
  aurora: [[246, 247, 252], [201, 225, 231], [220, 207, 238]],
  midnight: [[15, 24, 43], [28, 62, 80], [53, 37, 75]],
  coral: [[255, 245, 232], [249, 208, 182], [236, 184, 191]],
};
for (const [name, colors] of Object.entries(palettes)) {
  const width = 1600, height = 800, pixels = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const u = x / width, v = y / height;
    const a = Math.exp(-((u - 1.05) ** 2 + (v - .1) ** 2) / .25) * .85;
    const b = Math.exp(-((u - .75) ** 2 + (v - 1.1) ** 2) / .38) * .75;
    for (let c = 0; c < 3; c++) pixels[y * (width * 3 + 1) + 1 + x * 3 + c] = Math.round(colors[0][c] * (1 - a - b) + colors[1][c] * a + colors[2][c] * b);
  }
  const header = Buffer.alloc(13); header.writeUInt32BE(width); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 2;
  writeFileSync(new URL(`${name}-v1.png`, destination), Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(pixels, {level: 9})), chunk('IEND', Buffer.alloc(0))]));
}

// Code-native graphic furniture, with no event text baked into the artwork.
const graphicSources=new Map();
function graphic(name, w, h, base, paint, version='v3', palette=null) {
  if(!palette)graphicSources.set(name,{w,h,base,paint});
  const colorCache=new Map();
  const scale=8, width=Math.round(w*scale),height=Math.round(h*scale);
  const pixels=Buffer.alloc((width*3+1)*height);
  const rgb=hex=>{if(!colorCache.has(hex)){const value=palette?ticketThemeColor(hex,...palette):hex;colorCache.set(hex,[0,2,4].map(i=>parseInt(value.slice(i,i+2),16)));}return colorCache.get(hex);};
  const put=(x,y,color)=>{if(x<0||y<0||x>=width||y>=height)return;const offset=y*(width*3+1)+1+x*3;for(let c=0;c<3;c++)pixels[offset+c]=color[c];};
  const rect=(x,y,rw,rh,hex)=>{const c=rgb(hex);for(let py=Math.max(0,Math.round(y*scale));py<Math.min(height,Math.round((y+rh)*scale));py++)for(let px=Math.max(0,Math.round(x*scale));px<Math.min(width,Math.round((x+rw)*scale));px++)put(px,py,c);};
  const line=(x,y,length,hex,vertical=false,dashed=false)=>{for(let d=0;d<length;d+=.125)if(!dashed||Math.floor(d/1.5)%2===0)rect(x+(vertical?0:d),y+(vertical?d:0),vertical?.15:.125,vertical?.125:.15,hex);};
  const ring=(cx,cy,r,hex)=>{const c=rgb(hex);for(let y=Math.max(0,Math.floor((cy-r)*scale));y<Math.min(height,(cy+r)*scale);y++)for(let x=Math.max(0,Math.floor((cx-r)*scale));x<Math.min(width,(cx+r)*scale);x++){const distance=Math.hypot(x/scale-cx,y/scale-cy);if(Math.abs(distance-r)<.35)put(x,y,c);}};
  const disc=(cx,cy,r,hex)=>{const c=rgb(hex);for(let y=Math.max(0,Math.floor((cy-r)*scale));y<Math.min(height,(cy+r)*scale);y++)for(let x=Math.max(0,Math.floor((cx-r)*scale));x<Math.min(width,(cx+r)*scale);x++)if(Math.hypot(x/scale-cx,y/scale-cy)<=r)put(x,y,c);};
  const glow=(cx,cy,r,hex)=>{const c=rgb(hex);for(let y=0;y<height;y++)for(let x=0;x<width;x++){const a=Math.exp(-((x/scale-cx)**2+(y/scale-cy)**2)/(r*r))*.7;const offset=y*(width*3+1)+1+x*3;for(let k=0;k<3;k++)pixels[offset+k]=Math.round(pixels[offset+k]*(1-a)+c[k]*a);}};
  rect(0,0,w,h,base);paint({rect,line,ring,disc,glow});
  const header=Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8]=8;header[9]=2;
  writeFileSync(new URL(`${name}-${version}.png`,destination),Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(pixels,{level:9})),chunk('IEND',Buffer.alloc(0))]));
}
graphic('concert-stub',180,65,'FFFBF3',({rect,line})=>{
 rect(129,0,51,65,'EDE8DE');rect(0,0,129,2,'9F3027');rect(0,0,17,65,'9F3027');
 for(const x of [5,8.5,12])line(x,6,53,'C56A55',true);
 line(129,3,59,'9C958B',true,true);line(23,51,101,'C8BFB2');
});
graphic('festival-poster',90,140,'E4F359',({rect,line,ring})=>{
 rect(0,103,90,37,'203B2F');rect(0,100,30,3,'E88C42');
 line(8,74,74,'273021');ring(95,29,28,'7E9035');ring(95,29,23,'7E9035');
});
graphic('club-panorama',210,70,'19152B',({rect,line,glow})=>{
 glow(67,-10,80,'5B3773');rect(0,0,210,2,'B8A2ED');rect(168,2,42,68,'302344');
 line(119,10,50,'78628B',true);line(168,8,54,'9279B0',true,true);
 for(let x=12;x<105;x+=4)rect(x,66,.5,.5,'947CB2');
});
graphic('theatre-program',105,148,'F5F0E6',({line,rect})=>{
 for(const inset of [4,6]){line(inset,inset,105-2*inset,'8C6470');line(inset,148-inset,105-2*inset,'8C6470');line(inset,inset,148-2*inset,'8C6470',true);line(105-inset,inset,148-2*inset,'8C6470',true);}
 line(26,25,23,'8C6470');line(56,25,23,'8C6470');rect(51.5,24,2,2,'6A2635');
 line(26,73,53,'8C6470');line(39,107,27,'8C6470');
});
graphic('gallery-square',100,100,'FFFFFF',({rect,line})=>{
 rect(8,0,20,2,'B1362C');rect(96,0,4,45,'B1362C');line(8,51,84,'B1362C');line(39,60,35,'C4C4BF',true);
});
graphic('gala-invitation',70,160,'102F2B',({line,ring,rect,glow})=>{
 glow(35,85,90,'1A463A');
 for(const inset of [4,6]){line(inset,inset,70-2*inset,'B9A57E');line(inset,160-inset,70-2*inset,'B9A57E');line(inset,inset,160-2*inset,'B9A57E',true);line(70-inset,inset,160-2*inset,'B9A57E',true);}
 line(22,27,26,'B9A57E');ring(35,27,2,'B9A57E');rect(33.5,25.5,3,3,'B9A57E');
 line(22,105,26,'B9A57E');
});
graphic('boarding-pass',200,90,'FFFEF9',({rect,line})=>{
 rect(0,0,200,30,'164D49');rect(145,30,55,60,'DAE9E2');line(145,34,52,'70968B',true,true);
 line(145,6,18,'84AAA0',true);line(10,51,125,'B8C9BF');line(10,71,125,'B8C9BF');line(78,35,13,'B8C9BF',true);
});
graphic('cinema-strip',160,60,'211F1A',({rect,line})=>{
 rect(0,0,41,60,'F3CF70');line(41,5,50,'8F7947',true,true);
 for(let x=46;x<158;x+=7){rect(x,1.4,3,1.6,'F3CF70');rect(x,57,3,1.6,'F3CF70');}
});
graphic('sports-arena',190,80,'102C4A',({rect,line})=>{
 rect(0,56,190,24,'F2F5F7');rect(0,53,136,3,'E9A55D');rect(136,0,1,53,'47728E');
 line(75,61,10,'9FADBA',true);line(10,74,125,'C8D0D7');
});
graphic('festival-badge',80,120,'F5F0FC',({rect,line,disc})=>{
 rect(0,0,80,32,'513976');rect(0,32,80,2,'C4ACE3');
 disc(33,4.5,1,'EEE7FC');disc(47,4.5,1,'EEE7FC');rect(33,3.5,14,2,'EEE7FC');
 line(12,73,56,'BEAED3');rect(0,116,80,4,'513976');
});
graphic('workshop-card',148,105,'FCFBF5',({rect,line})=>{
 rect(99,0,49,105,'E2EBDD');rect(10,29,14,2,'294D3B');line(10,73,83,'A6B7A0');
 line(103,34,36,'8AA184');line(103,98,36,'8AA184');
});


// Reuse each original composition, rules and blocks; only its ink palette varies.
for(const [style,palette] of Object.entries(ticketThemePalettes)) {
 for(const [name,source] of graphicSources) {
  graphic(`theme-${style}-${name}`,source.w,source.h,source.base,source.paint,style==='soft'?'v2':'v1',palette);
 }
}
