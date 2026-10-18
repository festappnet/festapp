import { Component } from '../base/component.js';
import { ScannerInput, receptionPayload } from './scanner_input.js';
import { ScannerStore } from '../../services/scanner_store.js';
import { tr, reasonText, escape as e } from './scan_strings.js';
import { AppConfig } from '../../app_config.js';
import './scan.css';
export class ScannerDomainPage extends Component {
    constructor(host,{client}) {super(host);this.client=client;this.participants=[];}
    async init(route) {
        this.route=route;this.input=new ScannerInput(code=>this.load(code));
        if(route.page==='program') {
            try {const {data,error}=await this.client.rpc('get_event_participants_for_edit',{p_event:Number(route.eventId)});if(error||data?.code!==200)throw new Error('program_forbidden');this.participants=data.data;}
            catch(err){this.error=err.message;}
        } else await this.checkReceptionBoundary();
        this.render();
    }
    async checkReceptionBoundary() {
        const {data}=await this.client.auth.getSession();
        let scanner=false;const store=new ScannerStore();
        try {await store.open();scanner=(await store.list('sessions')).some(r=>!r.locked&&Date.parse(r.session.expires_at)>Date.now());}
        catch {scanner=true;} finally {store.close();}
        this.blocked=Boolean(data?.session)||scanner;return this.blocked;
    }
    async load(code) {
        this.input.pause();this.error=null;
        if(this.route.page==='program') {
            if(!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(code)){this.error='wrong_mode';this.render();return;}
            this.result=this.participants.find(p=>p.id.toLowerCase()===code.toLowerCase())||false;this.render();return;
        }
        const payload=receptionPayload(code);if(!payload){this.error='wrong_mode';this.render();return;}
        await this.login({payload});
    }
    async login(body) {
        if(this.busy || !navigator.onLine)return;this.busy=true;
        try {
            // Recheck immediately before exchange. Never replace a worker's existing account.
            if(await this.checkReceptionBoundary()){this.render();return;}
            const {data,error}=await this.client.functions.invoke('exchange-login-qr',{body});
            if(error||!data?.refresh_token||!data.access_token)throw new Error('reception_failed');
            // Validate target organization before persisting tokens in the shared auth namespace.
            const identity=await this.client.auth.getUser(data.access_token);
            if(identity.error || !identity.data.user?.id)throw new Error('reception_failed');
            const profile=await fetch(`${this.client.supabaseUrl}/rest/v1/user_info?select=id&id=eq.${encodeURIComponent(identity.data.user.id)}&organization=eq.${encodeURIComponent(AppConfig.organization)}`,{headers:{apikey:this.client.supabaseKey,Authorization:`Bearer ${data.access_token}`},cache:'no-store'});
            const identities=profile.ok?await profile.json():[];
            if(!identities.length)throw new Error('reception_failed');
            if(await this.checkReceptionBoundary()){this.render();return;}
            const auth=await this.client.auth.setSession({access_token:data.access_token,refresh_token:data.refresh_token});
            if(auth.error||!auth.data.session)throw new Error('reception_failed');this.done=true;
        }catch(err){this.error=err.message;}finally{this.busy=false;this.render();}
    }
    render() {
        this.input?.stop();const program=this.route.page==='program';
        const rows=this.participants.filter(p=>`${p.name} ${p.surname}`.toLowerCase().includes((this.query||'').toLowerCase()));
        this.host.innerHTML=`<main class="scan-shell"><section class="scan-settings"><a href="/scan">${tr('scan')}</a><h1>${tr(program?'program':'reception')}</h1>
        ${this.error?`<p class="scan-warning" role="alert">${e(reasonText(this.error))}</p>`:''}
        ${this.blocked?`<p class="scan-warning">${tr('worker_active')}</p>`:this.done?`<p>${tr('login_done')}</p><a href="/transfer">${tr('continue_app')}</a>`:`
        ${program?`<p>${tr('program_count')}: ${this.participants.length}</p><label>${tr('search')}<input data-search value="${e(this.query||'')}"></label>`:''}
        ${this.result!==undefined?`<h2 tabindex="-1" data-result>${tr(this.result?'program_signed':'program_not_signed')}</h2>${this.result?`<p>${e(this.result.name)} ${e(this.result.surname)}</p><ul>${this.participants.filter(p=>p.companion_parent===this.result.id).map(p=>`<li>${e(p.name)} ${e(p.surname)} · ${tr('program_signed')}</li>`).join('')}</ul>`:''}<button data-next>${tr('next')}</button>`:`<video aria-label="${tr('camera')}"></video><button data-camera>${tr('camera_start')}</button><form data-code><label>${tr(program?'symbol':'scan_code')}<input name="code" autocomplete="off" maxlength="200" required></label><button>${tr('lookup')}</button></form>`}
        ${!program?`<form data-manual><label>${tr('occasion')}<input name="occasion" type="number" min="1" required></label><label>${tr('manual_login')}<input name="code" autocomplete="off" maxlength="80" required></label><button ${this.busy?'disabled':''}>${tr('login')}</button></form>`:`<ul class="scan-list">${rows.slice(0,30).map(p=>`<li>${e(p.name)} ${e(p.surname)}</li>`).join('')}</ul>`}`}</section></main>`;
        const camera=this.host.querySelector('[data-camera]');if(camera)camera.onclick=()=>this.input.start(this.host.querySelector('video')).catch(err=>{this.error=err.message;this.render();});
        const code=this.host.querySelector('[data-code]');if(code)code.onsubmit=ev=>{ev.preventDefault();this.load(code.elements.code.value);};
        const manual=this.host.querySelector('[data-manual]');if(manual)manual.onsubmit=ev=>{ev.preventDefault();this.login({occasion:Number(manual.elements.occasion.value),manualCode:manual.elements.code.value.trim()});};
        const search=this.host.querySelector('[data-search]');if(search)search.onchange=()=>{this.query=search.value;this.render();};
        const next=this.host.querySelector('[data-next]');if(next)next.onclick=()=>{this.result=undefined;this.input.paused=false;this.render();};
        this.host.querySelector('[data-result]')?.focus();
    }
    clear(){this.input.dispose();super.clear();}
}
