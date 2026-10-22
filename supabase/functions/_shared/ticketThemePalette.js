// Keep the artwork's tonal hierarchy while applying an event's two ink colors.
export const ticketThemePalettes = {
 clean:['4465A6','4465A6'], gala:['14284B','A87F28'], energy:['BB350C','8B182E'],
 nature:['216445','146475'], soft:['885268','B89A68'], contrast:['111111','111111'],
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

// Source colors identify graphic roles only. Actual inks always come from the
// action palette; source hue must never decide which action ink owns a panel.
/** @type {Record<string, {primary:string[],secondary:string[]}>} */
export const ticketArtworkRoles = {
 concert_stub: {primary:['9F3027','C56A55'],secondary:['EDE8DE','9C958B','C8BFB2']},
 festival_poster: {primary:['203B2F','273021'],secondary:['E4F359','E88C42','7E9035']},
 club_panorama: {primary:['19152B','5B3773','302344'],secondary:['B8A2ED','78628B','9279B0','947CB2']},
 theatre_program: {primary:['8C6470','6A2635'],secondary:['F5F0E6']},
 gallery_square: {primary:['B1362C'],secondary:['C4C4BF']},
 gala_invitation: {primary:['102F2B','1A463A'],secondary:['B9A57E']},
 boarding_pass: {primary:['164D49','84AAA0'],secondary:['DAE9E2','70968B','B8C9BF']},
 cinema_strip: {primary:['211F1A'],secondary:['F3CF70','8F7947']},
 sports_arena: {primary:['102C4A','47728E'],secondary:['E9A55D','9FADBA','C8D0D7']},
 festival_badge: {primary:['513976'],secondary:['F5F0FC','C4ACE3','EEE7FC','BEAED3']},
 workshop_card: {primary:['294D3B','8AA184'],secondary:['E2EBDD','A6B7A0','FCFBF5']},
};
export function ticketArtworkColor(hex,primary,secondary,roles) {
 const rgb=channels(hex); let ink=primary, nearest=Infinity;
 for(const [role,sources] of Object.entries(roles))for(const source of sources) {
  const target=channels(source), distance=rgb.reduce((sum,c,i)=>sum+(c-target[i])**2,0);
  if(distance<nearest){nearest=distance;ink=role==='primary'?primary:secondary;}
 }
 return ticketThemeColor(hex,ink,ink);
}
