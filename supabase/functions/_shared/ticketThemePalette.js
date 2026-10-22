// Keep the artwork's tonal hierarchy while applying an event's two ink colors.
export const ticketThemePalettes = {
 clean:['4465A6','4465A6'], gala:['14284B','A87F28'], energy:['BB350C','8B182E'],
 nature:['216445','146475'], soft:['885268','885268'], contrast:['111111','111111'],
};
export const themedTicketArtwork = ['concert-stub','festival-poster','club-panorama','theatre-program','gallery-square','gala-invitation','boarding-pass','cinema-strip','sports-arena','festival-badge','workshop-card'];
const channels=hex=>[0,2,4].map(i=>parseInt(hex.slice(i,i+2),16));
const luminance=rgb=>rgb.map(v=>{const c=v/255;return c<=.04045?c/12.92:((c+.055)/1.055)**2.4;}).reduce((s,c,i)=>s+c*[.2126,.7152,.0722][i],0);
export function ticketThemeColor(hex,primary,secondary) {
 const source=channels(hex), desired=luminance(source);
 // Keep pure black and white registration/paper colors neutral.
 if(Math.max(...source)-Math.min(...source)<8 && (desired>.94||desired<.002))return hex.toUpperCase();
 const warm=source[0]>source[1]*1.03 && source[0]>source[2]*1.12;
 const target=channels(warm?secondary:primary), end=luminance(target)<desired?255:0;
 let low=0,high=1;
 for(let i=0;i<24;i++){
  const blend=(low+high)/2, rgb=target.map(c=>c+(end-c)*blend);
  if((luminance(rgb)<desired)===(end===255))low=blend;else high=blend;
 }
 return target.map(c=>Math.round(c+(end-c)*(low+high)/2).toString(16).padStart(2,'0')).join('').toUpperCase();
}
