/** Native Wallet appearance: a compatible subset of the saved ticket design. */
export function walletPublicImage(value:unknown):string|undefined {
 if(typeof value!=='string')return;
 try {
  const url=new URL(value);
  if(url.protocol!=='https:'||url.username||url.password||url.port||url.hash||url.search)return;
  const prefix=url.hostname==='img.festapp.net'?/^\/(images|assets)\//:url.hostname==='a.img.festapp.net'?/^\/images\//:null;
  if(!prefix?.test(url.pathname))return;
  // Google receives only public Worker URLs, never private URLs or signed query strings.
  url.searchParams.set('f','png');return url.href;
 }catch{return;}
}
export function googleWalletAppearance(feature:any,occasionData:any={},platform:'google'|'apple'='google') {
 const type=feature?.ticket_type==='named'?'named':'wide';
 const template=feature?.layout?.templates?.[type];
 const overrides=feature?.wallet_appearance??{};
 const parseColor=(color:unknown)=>typeof color==='string'&&/^#?[a-fA-F0-9]{6}$/.test(color)?'#'+color.replace(/^#/,'').toLowerCase():undefined;
 const backgroundColor=Object.hasOwn(overrides,'background_color')
  ?parseColor(overrides.background_color)
  :platform==='apple'
  ?(template?.canvasOpacity===0||template?.canvasColor==='transparent'
    ?undefined
    :parseColor(template?.canvasGradient?.[0])??parseColor(template?.canvasColor))??parseColor(feature?.lightColor)
  :parseColor(template?.canvasColor??template?.canvasGradient?.[0]??feature?.lightColor);
 const artwork=Object.hasOwn(overrides,'hero_image')?overrides.hero_image:feature?.background;
 const heroImage=walletPublicImage(artwork);
 return {backgroundColor,logo:walletPublicImage(Object.hasOwn(overrides,'logo')?overrides.logo:occasionData?.logo),
  heroImage:platform==='apple'&&heroImage?heroImage+'&w=300':heroImage};
}
