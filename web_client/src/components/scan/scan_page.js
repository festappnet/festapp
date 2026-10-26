import { scannerReturnPath } from './scanner_navigation.js';
import { Component } from '../base/component.js';
import { ScannerApi } from '../../services/scanner_api.js';
import { ScannerStore, offlineGrantValid, isTerminal } from '../../services/scanner_store.js';
import { ScannerSync } from '../../services/scanner_sync.js';
import { ScannerController } from './scanner_controller.js';
import { ScannerInput } from './scanner_input.js';
import { scanResult } from './scan_result.js';
import { tr, reasonText, escape as e } from './scan_strings.js';
import { AppConfig } from '../../app_config.js';
import { ThemeService } from '../../services/theme_service.js';
import './scan.css';
import { icon } from './scan_icons.js';
import { LocalizationService } from '../../services/localization_service.js';
import { ScannerFeedback } from './scanner_feedback.js';
import {scannerProductTitle,scannerProductCaption,scannerNotes} from './scanner_presentation.js';
import { groupScannerTickets } from './scanner_groups.js';
export class ScanPage extends Component {
    constructor(host, { client, store = new ScannerStore(), backend = null } = {}) {
        super(host); this.client = client; this.store = store;
        this.backend = backend || client.scannerBackendContext || { generation: client.supabaseUrl === AppConfig.backendActivationCanonicalSupabaseUrl ? 1 : 0, origin: client.supabaseUrl || AppConfig.supabaseUrl, organization: AppConfig.organization };
        this.sound=new ScannerFeedback();this.feedbackStates=new WeakMap();
        this.mode = 'camera'; this.rows = []; this.history = []; this.summaryAt = 0; this.online = navigator.onLine; this.disposed = false;
    }
    async init(route) {
        this.onGesture=event=>{if(event.target.closest?.('[data-sound]'))return;this.sound.unlock().then(()=>this.updateSoundControl());};
        this.host.addEventListener('pointerdown',this.onGesture,true);this.host.addEventListener('keydown',this.onGesture,true);
        let returnStorage; try { returnStorage=window.sessionStorage; } catch {}
        this.returnPath = scannerReturnPath({location:window.location,referrer:document.referrer,returnTo:route.returnTo,storage:returnStorage});
        this.route = route; document.querySelector('meta[name=referrer]')?.remove();
        const meta = document.createElement('meta'); meta.name = 'referrer'; meta.content = 'no-referrer'; document.head.append(meta);
        this.referrerMeta = meta;
        try {
            await this.store.open(); this.storageAvailable = true;
            this.rows = (await this.store.list('sessions')).filter(r => r.backend.generation === this.backend.generation && r.backend.origin === this.backend.origin && r.backend.organization === this.backend.organization);
        } catch { this.storageAvailable = false; this.store = null; }
        this.api = new ScannerApi(this.client);
        this.input = new ScannerInput(code => this.loadCodes([code]),{continuous:true,onCodes:codes=>this.loadCodes(codes)});
        this.onNetwork = async () => { this.online = navigator.onLine; this.render(); if (this.online) await this.recover(); };
        this.onVisible = () => { if (document.visibilityState === 'visible') this.recover(); };
        window.festappScannerCanReload=()=>!['persisting','awaiting_server'].includes(this.controller?.state);
        this.onUnload = event => { if (this.controller?.state==='persisting' || this.history.some(r => !isTerminal(r.state))) { event.preventDefault(); event.returnValue = ''; } };
        window.addEventListener('online', this.onNetwork); window.addEventListener('offline', this.onNetwork);
        document.addEventListener('visibilitychange', this.onVisible); window.addEventListener('beforeunload', this.onUnload);
        this.interval = setInterval(() => { if (document.visibilityState === 'visible' && this.row && navigator.onLine) this.recover(); }, 15000);
        this.render();
        if (route.code) await this.open({ p_scan_code: route.code, p_device_name: tr('device') });
        else if (route.occasion) await this.open({ p_occasion: Number(route.occasion), p_device_name: tr('device') });
        else {
            const active = await this.store?.get('preferences', `active:${JSON.stringify(this.backend)}`);
            const row = active && this.rows.find(r => r.key === active.partition && !r.locked);
            if (row) await this.select(row);
        }
    }
    async open(params) {
        try {
            this.error = null; const session = await this.api.open(params);
            if(this.client.scannerBackendContext)this.backend=this.client.scannerBackendContext;
            this.row = this.store ? await this.store.saveSession(session, this.backend) : { session, partition: null };
            await this.select(this.row);
            // Secrets never survive the exchange in the URL/history.
            window.history.replaceState(null, '', this.route.page==='scan'?'/scan':'/scan/'+this.route.page);
        } catch (err) { this.error = err.message; this.render(); }
    }
    async select(row) {
        this.disposeControllers();this.batch=null;this.groupDetailController=null; this.sync?.stop(); this.summaryAt=0; this.row = row; this.api.session = row.session;
        if (this.store) {
            await this.store.put('preferences', { key: `active:${JSON.stringify(this.backend)}`, partition: row.partition });
            this.snapshot = await this.store.snapshot(row.partition);
            this.history = await this.store.list('outbox', row.partition);
            this.summary = (await this.store.get('preferences', `${row.partition}:summary`))?.data;
        }
        this.sync = this.store ? new ScannerSync({ store: this.store, api: this.api, partition: row.partition, onChange: async ({auth,latency}) => {
            if(Number.isFinite(latency))this.lastSyncLatency=latency;
            if (auth) {this.authBlocked = true;row.locked=true;await this.store.lockSession(row.partition);}
            this.history = await this.store.list('outbox', row.partition);
            for(const c of this.controllers())await c.refreshOperation(); this.render();
        } }) : null;
        this.controller = this.createController();
        this.render(); await this.recover();
        if (this.store && row.session.capabilities.offline) navigator.serviceWorker?.ready?.then(()=>{if(!this.disposed&&this.row===row&&!this.snapshot){this.lastSnapshotAttempt=0;this.recover();}}).catch(()=>{});
        if (this.route.page === 'settings') await this.showSettings();
    }
    controllers() { return this.batch?.map(item=>item.controller) || (this.controller?[this.controller]:[]); }
    disposeControllers() { for(const c of this.controllers())c.dispose(); }
    createController() {
        return new ScannerController({ api: this.api, store: this.store, row:this.row, sync: this.sync, online:()=>navigator.onLine&&!this.transportOffline, onChange: c => {
            if(c.operation){const index=this.history.findIndex(r=>r.key===c.operation.key);if(index<0)this.history.push(c.operation);else this.history[index]=c.operation;}
            if (c.ticket?.source==='offline') this.transportOffline=true; if (!c.store) this.storageAvailable=false; this.render();
            this.feedback(c);
            if (c===this.controller && c.state === 'result') this.host.querySelector('[data-result-title]')?.focus({preventScroll:true});
        } });
    }
    async loadCodes(codes) {
        if(!this.controller || this.disposed || this.authBlocked || this.row?.locked)return;
        const existing=this.batch || (this.controller.state!=='ready'?[{symbol:this.controller.scanSymbol || this.controller.ticket?.symbol,controller:this.controller}]:[]);
        const known=new Set(existing.map(item=>item.symbol));
        const unique=[...new Set(codes.map(code=>code.trim()).filter(Boolean))].filter(symbol=>!known.has(symbol)).slice(0,12);
        if(!unique.length)return;
        clearTimeout(this.advanceTimer);this.advanceTimer=null;
        const additions=unique.map((symbol,index)=>({symbol,controller:!existing.length&&index===0?this.controller:this.createController()}));
        for(const item of additions)item.controller.scanSymbol=item.symbol;
        const group=[...existing,...additions];
        this.batch=group.length>1?group:null;
        this.render();
        await Promise.all(additions.map(item=>item.controller.loadCode(item.symbol)));
    }

    async confirmBatch() {
        if(this.batchConfirming || !this.batch || !this.storageAvailable || this.authBlocked || this.row.locked)return;
        this.batchConfirming=true;this.render();
        try{
            for(const {controller:c} of [...this.batch]){
                if(this.disposed || this.authBlocked || this.row.locked)break;
                if(c.state==='result' && c.ticket?.admission_allowed && !c.ticket.requires_unpaid_confirmation)await c.confirm();
            }
        }finally{this.batchConfirming=false;this.render();if(this.batch?.some(i=>i.controller.state==='accepted'))this.sound.play('accepted');this.updateAutoAdvance();}
    }
    nextScan(mode=['accepted','pending','sending'].includes(this.controller?.state)&&!this.cameraUnavailable?'camera':this.mode,{auto=false}={}) {
        if(this.batchConfirming || this.controllers().some(c=>['persisting','looking_up','awaiting_server'].includes(c.state)))return;
        clearTimeout(this.advanceTimer);this.advanceTimer=null;
        if(mode==='manual')this.input.stop();
        this.mode=mode;
        if(this.batch){this.disposeControllers();this.batch=null;this.groupDetailController=null;this.controller=this.createController();}
        else {this.controller.scanSymbol=null;this.controller.unpaidConfirmed=false;this.controller.next();}
        this.input.paused=false;this.render();
        if(this.mode==='camera'){if(this.input.stream)this.updateCameraState();else if(!auto||this.cameraWasStarted)this.startCamera();}else this.host.querySelector('[name=symbol]')?.focus();
    }
    resultHtml(c,inGroup=false) {
        return scanResult({...c,inGroup},this.storageAvailable && !this.authBlocked && !this.row.locked && !this.batchConfirming);
    }
    batchHtml() {
        if(!this.batch)return '';
        const eligible=this.batch.filter(({controller:c})=>c.state==='result' && c.ticket?.admission_allowed && !c.ticket.requires_unpaid_confirmation).length;
        const busy=this.batchConfirming || this.batch.some(({controller:c})=>['ready','looking_up','persisting','awaiting_server'].includes(c.state));
        const card=({symbol,controller:c,index:i,sharedOrder=false})=>{
            const used=(c.state==='result'&&c.ticket?.state==='used')||(['conflict','rejected'].includes(c.state)&&c.operation?.receipt?.reason==='already_used');
            const good=c.state==='accepted',pending=['pending','sending','persisting','awaiting_server'].includes(c.state),unpaid=c.state==='result'&&c.ticket?.requires_unpaid_confirmation,valid=c.state==='result'&&c.ticket?.admission_allowed&&!unpaid;
            const label=good?tr('accepted'):pending?tr(c.state):c.error?reasonText(c.error):c.state==='ready'||c.state==='looking_up'?tr('looking_up'):c.state==='result'?tr(c.ticket?.state==='used'?'already_used':c.ticket?.requires_unpaid_confirmation?'unpaid':valid?'valid':'not_allowed'):c.operation?.receipt?reasonText(c.operation.receipt.reason):tr(c.state);
            const expanded=this.groupDetailController===c;
            const named=c.ticket?.holder_name && c.ticket.holder_name!==symbol;
            const purchaser=c.ticket?.purchaser_name;
            const seatHeading=c.ticket?.spot?`${tr('spot')} ${c.ticket.spot}`:null;
            const heading=named?c.ticket.holder_name:c.error?tr('unknown_ticket'):!sharedOrder&&purchaser?purchaser:seatHeading|| (c.ticket?tr('ticket_label'):symbol);
            const products=(c.ticket?.products||[]).filter(product=>!(c.ticket.spot && product.type==='spot' && scannerProductTitle(product).trim().toLocaleLowerCase()===product.type_title?.trim().toLocaleLowerCase()));
            const extras=`${!sharedOrder&&purchaser&&purchaser!==heading?`<span class="scan-group-purchaser">${tr('purchaser')}: ${e(purchaser)}</span>`:''}${c.ticket?.spot&&heading!==seatHeading?`<span class="scan-group-seat">${tr('spot')} ${e(c.ticket.spot)}</span>`:''}${products.length?`<span class="scan-group-products">${products.sort((a,b)=>Number(b.type==='food')-Number(a.type==='food')).map(product=>`<span class="${product.type==='food'?'scan-product-food':''}">${e(scannerProductCaption(product))}</span>`).join('')}</span>`:''}`;
            return `<div class="scan-group-item"><button id="scan-group-ticket-${i}" data-group-ticket="${i}" aria-expanded="${expanded}" aria-controls="scan-group-detail-${i}" class="${good?'complete':pending?'pending':unpaid?'unpaid':used?'already-used':valid?'allowed':'blocked'}"><span class="scan-group-number">${i+1}</span><span class="scan-group-body"><span class="scan-group-title"><strong>${e(heading)}</strong><span class="scan-ticket-status" aria-label="${e(label)}">${icon(good||valid?'ticket_check':pending?'clock':used?'ticket':'alert')}${e(valid?tr('valid_short'):label)}</span></span>${extras}${scannerNotes(c.ticket,{order:!this.batch.some(item=>item!==this.batch[i]&&item.controller.ticket?.order_id!=null&&item.controller.ticket.order_id===c.ticket?.order_id)})}${!c.ticket?`<small>${e(symbol)}</small>`:''}</span></button><section id="scan-group-detail-${i}" class="scan-group-detail" aria-labelledby="scan-group-ticket-${i}" ${expanded?'':'hidden'}>${expanded?this.resultHtml(c,true):''}</section></div>`;

        };
        const groups=groupScannerTickets(this.batch).map(group=>group.sharedOrder?`<section class="scan-order-group"><header class="scan-order-header"><h3>${group.items[0].controller.ticket?.purchaser_name?e(group.items[0].controller.ticket.purchaser_name):tr('shared_order')}</h3>${group.table?`<p>${/^\d+$/.test(group.table)?tr('table')+' ':''}${e(group.table)}</p>`:''}</header>${scannerNotes(group.items[0].controller.ticket,{individual:false})}${group.items.map(item=>card({...item,sharedOrder:true})).join('')}</section>`:group.items.map(card).join('')).join('');
        return `<section class="scan-group" aria-label="${tr('ticket_group')}"><h2>${tr('ticket_group')} (${this.batch.length})</h2><div class="scan-group-list">${groups}</div>${eligible?`<button class="scan-primary" data-group-confirm ${this.batchConfirming||!this.storageAvailable||this.authBlocked||this.row.locked?'disabled':''}>${icon('check')}${tr('confirm_valid')} (${eligible})</button>`:''}<button data-group-next ${busy?'disabled':''}>${tr('next_group')}${icon('arrow')}</button></section>`;
    }
    async recover() {
        if (!this.row || !navigator.onLine || this.disposed) return;
        try {
            await this.sync?.run();
            if (Date.now() - this.summaryAt >= 15000) { this.summaryAt=Date.now(); this.summary = await this.api.summary(); this.transportOffline=false; this.summaryAt = Date.now(); if (this.store) await this.store.put('preferences', { key: `${this.row.partition}:summary`, data: this.summary }); }
            // A prepared device keeps refreshing even when the event later grows.
            // Initial automatic preparation needs a known count of the complete snapshot.
            const ticketCount=this.summary?.snapshot_ticket_count;
            const autoPrepare=this.snapshot || (Number.isSafeInteger(ticketCount) && ticketCount>=0 && ticketCount<=1000);
            if (autoPrepare && this.store && this.row.session.capabilities.offline && this.row.session.settings?.offline?.enabled && (!this.snapshot || Date.now()-Date.parse(this.snapshot.server_time)>60000) && !this.refreshingSnapshot && !this.authBlocked && Date.now()-(this.lastSnapshotAttempt||0)>=60000) {
                this.refreshingSnapshot = true;this.lastSnapshotAttempt=Date.now();
                this.backgroundPreparation=this.prepare({automatic:true}).catch(()=>{}).finally(()=>{this.refreshingSnapshot=false;});
            }
        } catch (err) { if ([401,403].includes(err.code)) {this.authBlocked = true;this.row.locked=true;await this.store?.lockSession(this.row.partition);} }
        if (!this.summary && this.store) this.summary = (await this.store.get('preferences', `${this.row.partition}:summary`))?.data;
        this.render();
    }
    async prepare({automatic=false}={}) {
        if (!this.store || !this.row || this.preparing) return;
        const preparingRow=this.row;
        this.preparing = true; if(!automatic)this.error = null; this.render();
        try {
            await import('jsqr'); // Cache the local decoder chunk together with the existing PWA shell.
            const registration = await navigator.serviceWorker?.getRegistration();
            if (!registration?.active) throw new Error('offline_shell_unavailable');
            const health=await new Promise((resolve,reject)=>{
                const channel=new MessageChannel();const timer=setTimeout(()=>reject(new Error('offline_shell_unavailable')),2000);
                channel.port1.onmessage=ev=>{clearTimeout(timer);channel.port1.close();resolve(ev.data);};
                registration.active.postMessage({type:'FESTAPP_SCANNER_SHELL_STATUS'},[channel.port2]);
            });
            if(!health.ready || health.version!==AppConfig.version)throw new Error('offline_shell_unavailable');
            if(!automatic)await navigator.storage?.persist?.();
            const snapshot=await this.api.prepare(this.store,preparingRow.partition);if(this.row===preparingRow)this.snapshot=snapshot;
        } catch (err) { if(!automatic)this.error = err.message;this.offlinePreparationError=err.message; }
        this.preparing = false; this.render();
    }
    shell(content) {
        const session = this.row?.session, sum = this.summary;
        const pending = this.history.filter(r => !isTerminal(r.state)).length;
        const conflicts = this.history.filter(r => r.state === 'conflict' && !r.resolved).length;
        const total=Math.max(0,Number(sum?.eligible_total)||0), used=Math.max(0,Number(sum?.used_current)||0);
        const percent=total ? Math.min(100,Math.round(used/total*100)) : 0;
        const needsSync=pending>0 || conflicts>0 || !navigator.onLine || this.transportOffline;
        const canPrepare=session?.settings?.offline?.enabled;
        return `<main class="scan-shell"><header class="scan-header"><a class="scan-home" href="${e(this.returnPath || '/')}" aria-label="${tr(this.returnPath && this.returnPath!=='/'?'back':'home')}">${icon('back')}</a><h1>${e(session?.title || tr('scan'))}</h1><details class="scan-menu"><summary>${tr('options')}</summary><div class="scan-menu-panel"><p class="scan-menu-title">${tr('scanner_tools')}</p><nav aria-label="${tr('scan')}">${this.route.page!=='scan'?`<a href="/scan">${icon('camera')}${tr('back_to_camera')}</a>`:''}<a href="/scan/history" ${this.route.page==='history'?'aria-current="page"':''}>${icon('history')}${tr('history')}</a>${session?.capabilities.settings?`<a href="/scan/settings">${icon('settings')}${tr('display_settings')}</a>`:''}${needsSync?`<a href="/scan/offline">${icon('offline')}${tr('sync_status')}</a>`:''}</nav><button data-theme>${icon('theme')}${tr('theme')}</button><button data-sound>${icon('sound')}${tr(this.sound?.ready?'sound_on':'sound_enable')}</button>${canPrepare?`<details class="scan-advanced"><summary>${tr('more_options')}</summary>${canPrepare?`<a href="/scan/offline">${tr('prepare_offline_short')}</a>`:''}</details>`:''}</div></details></header>
        <div class="scan-status" role="status"><span class="scan-connection ${navigator.onLine && !this.transportOffline ? 'is-online' : 'is-offline'}"><span class="scan-dot"></span>${tr(navigator.onLine && !this.transportOffline ? 'online' : 'offline')}</span>${sum ? `<span class="scan-count">${tr('used')}: <strong>${sum.used_current.toLocaleString()} <span>/ ${sum.eligible_total.toLocaleString()}</span></strong><span class="scan-percent">${percent} %</span></span>` : ''}${pending ? `<span class="scan-pending-count">${tr('pending_count')}: ${pending}</span>` : ''}${conflicts ? `<span>${tr('conflicts')}: ${conflicts}</span>` : ''}${sum ? `<div class="scan-progress" role="progressbar" aria-label="${tr('used')}" aria-valuemin="0" aria-valuemax="${total||1}" aria-valuenow="${Math.min(used,total)}" aria-valuetext="${used} / ${total} (${percent} %)"><span style="width:${percent}%"></span></div>` : ''}</div>
        ${!navigator.onLine || this.transportOffline ? `<p class="scan-offline-notice"><a href="/scan/offline">${tr(this.snapshot?'offline_saved_short':'offline_unprepared_short')}</a></p>` : ''}
        ${!this.storageAvailable ? `<p class="scan-warning" role="alert">${tr('storage_failed')}</p>` : ''}
        ${this.authBlocked ? `<p class="scan-warning">${tr('blocked_auth')}</p>` : ''}
        ${this.message ? `<p role="status">${e(this.message)}</p>` : ''}
        ${this.error ? `<p class="scan-warning" role="alert">${e(reasonText(this.error))}</p>` : ''}
        ${content}</main>`;
    }
    render() {
        if (this.disposed || this.settingsPage) return;
        const c = this.controller;
        const drafts = c?.state==='ready' && this.mode==='manual' ? [...this.host.querySelectorAll('[data-code] input:not(:disabled),[data-search] input')].map(input=>({name:input.name,value:input.value,focused:input===document.activeElement,start:input.selectionStart,end:input.selectionEnd})) : [];
        const liveVideo = this.mode==='camera' && this.route.page==='scan' && this.input?.stream ? this.input.video : null;
        if (!liveVideo) this.input?.stop();
        let content;
        if (!this.row) content = `<section class="scan-settings"><h2>${tr('open')}</h2><form data-open><label>${tr('scan_code')}<input name="code" autocomplete="off" required maxlength="100"></label><label>${tr('device')}<input name="device" required maxlength="80" value="${tr('device')}"></label><button class="scan-primary">${tr('open')}</button></form>
        <h3>${tr('saved_sessions')}</h3>${this.rows.map((r,i)=>`<button data-session="${i}">${e(r.session.title)} · ${e(r.session.device_name)}${r.locked ? ' ('+tr('blocked_auth')+')' : ''}</button>`).join('')}</section>`;
        else if (this.route.page === 'history') content = `<section class="scan-settings"><h2>${tr('this_device')}</h2>${this.row.session.capabilities.event_history?`<button data-event-history>${tr('event_history')}</button>`:''}${this.historyHtml()}${this.eventHistory?`<h3>${tr('event_history')}</h3><ul class="scan-list">${this.eventHistory.map(r=>`<li>${e(reasonText(r.receipt.reason))} #${r.receipt.ticket_id} · ${e(new Date(r.receipt.committed_at).toLocaleString(LocalizationService.currentLocale))}</li>`).join('')}</ul><button data-event-more>${tr('search_more')}</button>`:''}</section>`;
        else if (this.route.page === 'offline') content = `<section class="scan-settings"><h2>${tr('offline')}</h2><p>${tr('valid_until')}: ${e(new Date(this.row.session.offline_until).toLocaleString(LocalizationService.currentLocale))}</p>
        ${this.snapshot ? `<p>${tr('prepared')}: ${this.snapshot.ticket_count} ${tr('tickets')} · ${e(new Date(this.snapshot.server_time).toLocaleString(LocalizationService.currentLocale))}</p>` : ''}
        <button data-prepare ${this.preparing || !this.store || !navigator.onLine ? 'disabled' : ''}>${tr('prepare')}</button><button data-retry>${tr('retry')}</button><p>${tr('logout_note')}</p><button data-lock>${tr('logout')}</button>
        <p>${tr('sync_latency')}: ${Math.round(this.lastSyncLatency||0)} ms · ${tr('oldest_pending')}: ${e(this.history.filter(r=>!isTerminal(r.state)).map(r=>r.payload.captured_at).sort()[0] || '-')}</p><h3>${tr('pending_count')} / ${tr('conflicts')}</h3>${this.historyHtml(true)}</section>`;
        else content = `<div class="scan-layout ${this.mode==='manual' && c?.state==='ready'?'manual-ready':''} ${this.mode==='camera'?'camera-mode':''} ${this.batch?'is-group':''} ${this.mode==='camera' && !this.batch && c?.state==='ready'?'camera-ready':''} ${this.batch || c && c.state !== 'ready' ? 'has-result' : ''}"><section class="scan-input">
        ${this.mode==='camera' ? `<div class="scan-camera" data-active="false"><video aria-label="${tr('camera')}"></video><div class="scan-camera-idle">${icon('camera')}<strong>${tr('camera_ready')}</strong><p>${tr('camera_privacy')}</p><button class="scan-primary" data-camera>${icon('camera')}${tr('camera_start')}</button></div><div class="scan-viewfinder" aria-hidden="true"><i></i><i></i><i></i><i></i></div><p class="scan-camera-hint">${tr('camera_aim')}</p><span class="scan-camera-live"><span class="scan-dot"></span>${tr('camera_live')}</span></div><div class="scan-camera-footer"><button class="scan-manual-link" data-mode="manual">${tr('manual_entry')}</button><details class="scan-camera-options"><summary>${tr('camera_controls')}</summary><div class="scan-camera-popover"><div class="scan-camera-tools"><button data-switch>${icon('switch')}${tr('camera_switch')}</button><button data-camera-stop>${icon('stop')}${tr('camera_stop')}</button><button data-torch hidden>${tr('torch')}</button></div><p>${tr('camera_help_text')}</p><button data-same>${tr('same_code')}</button></div></details></div>` : `<form data-code><label>${tr('symbol')}<input name="symbol" autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="200" ${c?.state!=='ready' ? 'disabled' : ''}></label><button ${c?.state!=='ready' ? 'disabled' : ''}>${icon('scan')}${tr('lookup')}</button></form><button class="scan-manual-link" data-mode="camera">${icon('camera')}${tr('back_to_camera')}</button>${!this.cameraUnavailable?`<p class="scan-manual-note">${tr('manual_once')}</p>`:''}`}
        ${this.mode==='manual' && (this.row.session.capabilities.search_tickets || this.row.session.capabilities.search_users) ? `<form data-search novalidate>${this.row.session.capabilities.search_tickets && this.row.session.capabilities.search_users ? `<label>${tr('search_scope')}<select data-search-scope><option value="tickets">${tr('tickets')}</option><option value="users" ${this.searchScope==='users'?'selected':''}>${tr('users')}</option></select></label>`:''}<label>${tr('search')}<input name="query" minlength="2" maxlength="100" aria-invalid="${Boolean(this.searchError)}" ${this.searchError?'aria-describedby="scan-search-error"':''}></label><p class="scan-field-error" id="scan-search-error" role="alert" ${this.searchError?'':'hidden'}>${e(this.searchError?reasonText(this.searchError):'')}</p><button>${tr('search')}</button></form><ul class="scan-list">${(this.searchResults||[]).map(t=>`<li><button data-ticket="${e(t.symbol)}">${e(t.holder_name)} · ${e(t.symbol)}</button></li>`).join('')}</ul>${this.searchResults?.length===30 ? `<button data-search-more>${tr('search_more')}</button>` : ''}` : ''}</section>
        <section class="scan-detail" aria-live="polite" aria-busy="${['looking_up','persisting','awaiting_server'].includes(c?.state)}">${this.batchHtml()}${c && !this.batch ? this.resultHtml(c) : ''}</section></div>`;
        this.host.innerHTML = this.shell(content);
        if (liveVideo) { this.host.querySelector('video')?.replaceWith(liveVideo);liveVideo.play().catch(()=>{});this.updateCameraState(); }
        this.bind();
        this.updateCameraState();
        for(const draft of drafts){
            const input=[...this.host.querySelectorAll('input[name]')].find(input=>input.name===draft.name);
            if(!input)continue;input.value=draft.value;
            if(draft.focused){input.focus({preventScroll:true});input.setSelectionRange(draft.start,draft.end);}
        }
    }
    historyHtml(onlyOpen = false) {
        const rows = this.history.filter(r => !onlyOpen || !isTerminal(r.state) || r.state==='conflict').sort((a,b)=>b.payload.captured_at.localeCompare(a.payload.captured_at));
        return `<ul class="scan-list">${rows.length ? rows.map(r=>`<li><strong>${tr(r.state)==r.state ? reasonText(r.receipt?.reason) : tr(r.state)}</strong> #${r.payload.ticket_id}<p>${tr(r.payload.snapshot_id ? 'source_offline' : 'source_online')}</p><p>${tr('captured_at')}: ${e(new Date(r.payload.captured_at).toLocaleString(LocalizationService.currentLocale))}</p>${r.receipt ? `<p>${tr('committed_at')}: ${e(new Date(r.receipt.committed_at).toLocaleString(LocalizationService.currentLocale))}</p>` : ''}
        ${r.state==='conflict' && this.row.session.capabilities.settings && !r.resolved ? `<form data-resolve="${r.key}"><label>${tr('resolution_reason')}<input name="reason" required minlength="3" maxlength="1000"></label><button>${tr('resolve')}</button></form>` : ''}</li>`).join('') : `<li>${tr('no_history')}</li>`}</ul>`;
    }
    bind() {
        const one = (s,f) => { const el=this.host.querySelector(s); if(el) el.onclick=f; };
        const eventHistory=async before=>{try{this.eventHistory=(await this.api.call('get_scanner_event_history',{p_occasion:this.row.session.occasion_id,...(before?{p_before:before}:{})},false)).data;this.render();}catch(err){this.error=err.message;this.render();}};
        one('[data-event-history]',()=>eventHistory());one('[data-event-more]',()=>eventHistory(this.eventHistory.at(-1)?.receipt.committed_at));
        one('[data-theme]',()=>ThemeService.toggle());
        one('[data-sound]',async()=>{if(this.sound.ready){this.sound.enabled=false;}else{this.sound.enabled=true;await this.sound.unlock();this.sound.play('good');}this.updateSoundControl();});
        const open=this.host.querySelector('[data-open]'); if(open) open.onsubmit=ev=>{ev.preventDefault();this.open({p_scan_code:open.elements.code.value,p_device_name:open.elements.device.value});};
        this.host.querySelectorAll('[data-session]').forEach(b=>b.onclick=()=>{const row=this.rows[Number(b.dataset.session)]; this.authBlocked=Boolean(row.locked);this.select(row);});
        this.host.querySelectorAll('[data-mode]').forEach(b=>{b.disabled=Boolean(this.batchConfirming)||this.controllers().some(c=>['persisting','looking_up','awaiting_server'].includes(c.state));b.onclick=()=>this.nextScan(b.dataset.mode);});
        const code=this.host.querySelector('[data-code]'); if(code) code.onsubmit=ev=>{ev.preventDefault();this.controller.loadCode(code.elements.symbol.value);};
        const search=this.host.querySelector('[data-search]'); if(search) search.onsubmit=ev=>{ev.preventDefault();this.searchQuery=search.elements.query.value;this.searchScope=this.host.querySelector('[data-search-scope]')?.value || (this.row.session.capabilities.search_tickets?'tickets':'users');this.search(0);};
        if(search)search.elements.query.oninput=()=>{if(search.elements.query.value.trim().length>=2){this.searchError=null;search.elements.query.setAttribute('aria-invalid','false');search.elements.query.removeAttribute('aria-describedby');this.host.querySelector('#scan-search-error').hidden=true;}};
        one('[data-search-more]',()=>this.search((this.searchResults.at(-1).user_id || this.searchResults.at(-1).ticket_id)));
        this.host.querySelectorAll('[data-ticket]').forEach(b=>b.onclick=()=>this.controller.loadCode(b.dataset.ticket));
        one('[data-confirm]',()=>this.controller.confirm(Boolean(this.host.querySelector('[data-unpaid]')?.checked)));
        const reset=this.host.querySelector('[data-reset]'); if(reset) reset.onsubmit=async ev=>{ev.preventDefault();try {await this.api.call('reset_scanner_password',{p_ticket:this.controller.ticket.ticket_id,p_password:reset.elements.password.value});reset.reset();this.error=null;this.message=tr('password_reset_done');this.render();}catch(err){reset.reset();this.error=err.message;this.render();}};
        const unpaid=this.host.querySelector('[data-unpaid]'); if(unpaid){unpaid.checked=Boolean(this.controller.unpaidConfirmed);this.host.querySelector('[data-confirm]').disabled=!unpaid.checked;unpaid.onchange=()=>{this.controller.unpaidConfirmed=unpaid.checked;this.host.querySelector('[data-confirm]').disabled=!unpaid.checked;};}
        one('[data-next]',()=>this.nextScan());
        one('[data-group-next]',()=>this.nextScan());one('[data-group-confirm]',()=>this.confirmBatch());
        this.host.querySelectorAll('[data-group-ticket]').forEach(button=>button.onclick=()=>{const selected=this.batch[Number(button.dataset.groupTicket)].controller;this.groupDetailController=this.groupDetailController===selected?null:selected;this.controller=selected;this.render();this.host.querySelector(`[data-group-ticket="${button.dataset.groupTicket}"]`)?.focus({preventScroll:true});});
        one('[data-camera]',()=>this.startCamera());
        one('[data-camera-stop]',()=>{this.input.stop();this.updateCameraState();});
        one('[data-switch]',async()=>{try{await this.input.switchCamera();this.updateCameraState();}catch(err){this.error=err.message;this.render();}});
        one('[data-torch]',()=>this.input.torch()); one('[data-same]',()=>this.input.allowSame());
        one('[data-prepare]',()=>this.prepare());one('[data-retry]',()=>this.recover());
        one('[data-lock]',async()=>{try {await this.api.call('revoke_scanner_session');} catch {} await this.store.lockSession(this.row.partition);this.sync.stop();this.row=null;this.disposeControllers();this.batch=null;this.groupDetailController=null;this.rows=await this.store.list('sessions');this.render();});
        this.host.querySelectorAll('[data-resolve]').forEach(form=>form.onsubmit=async ev=>{ev.preventDefault();try {await this.api.call('resolve_scanner_conflict',{p_operation:form.dataset.resolve,p_reason:form.elements.reason.value},false);const row=this.history.find(r=>r.key===form.dataset.resolve);await this.store.put('outbox',{...row,resolved:true});this.history=await this.store.list('outbox',this.row.partition);this.render();} catch(err){this.error=err.message;this.render();}});
    }
    feedback(c) {
        const key=c.state+':'+(c.error||c.operation?.receipt?.reason||'');
        if(this.feedbackStates.get(c)===key)return;
        this.feedbackStates.set(c,key);
        if(!this.batchLoading&&!this.batchConfirming){
            if(c.state==='accepted')this.sound.play('accepted');
            else if(c.state==='result')this.sound.play(c.ticket?.admission_allowed&&!c.ticket.requires_unpaid_confirmation?'good':'error');
            else if(['error','conflict','rejected','blocked_auth','blocked_schema'].includes(c.state))this.sound.play('error');
        }
        this.updateAutoAdvance();
    }
    updateAutoAdvance() {
        const controllers=this.controllers();
        if(this.batchConfirming || !controllers.length || !controllers.every(c=>c.state==='accepted'&&c.operation?.receipt?.outcome==='accepted'))return;
        const key=controllers.map(c=>c.operation.payload.operation_id).join(':');if(this.advanceKey===key)return;
        this.advanceKey=key;clearTimeout(this.advanceTimer);
        this.advanceTimer=setTimeout(()=>{this.advanceTimer=null;if(!this.disposed&&this.route.page==='scan'&&this.controllers().every(c=>c.state==='accepted'))this.nextScan(undefined,{auto:true});},1200);
    }
    updateSoundControl() {
        const button=this.host.querySelector('[data-sound]');if(!button)return;
        button.innerHTML=icon('sound')+tr(this.sound.ready?'sound_on':this.sound.enabled?'sound_enable':'sound_off');
        button.setAttribute('aria-pressed',String(this.sound.ready));
    }
    updateCameraState() {
        const camera=this.host.querySelector('.scan-camera');
        if(camera){camera.dataset.active=String(Boolean(this.input.stream));camera.dataset.paused=String(Boolean(this.input.paused));const hint=camera.querySelector('.scan-camera-hint');if(hint)hint.textContent=tr(this.input.paused?'camera_review':'camera_aim');}
        const torch=this.host.querySelector('[data-torch]');
        if(torch)torch.hidden=!this.input.stream?.getVideoTracks()[0]?.getCapabilities?.().torch;
        for(const selector of ['[data-switch]','[data-camera-stop]']) {
            const button=this.host.querySelector(selector);if(button)button.disabled=!this.input.stream;
        }
    }
    async startCamera() {
        const video=this.host.querySelector('video');if(!video)return;
        try { this.error=null;if(!this.input.stream)await this.input.start(video);this.cameraWasStarted=Boolean(this.input.stream);this.cameraUnavailable=false;this.input.paused=false;this.updateCameraState(); }
        catch(err) { this.cameraUnavailable=true;this.error=err.message;this.sound.play('error');this.render(); }
    }
    async search(after) {
        this.searchError=null;this.error=null;this.searchQuery=String(this.searchQuery||'').trim();
        try {
            if(this.searchQuery.length<2 || this.searchQuery.length>100)throw new Error('invalid_query');
            if (!navigator.onLine) {
                if (this.searchScope==='users' || !offlineGrantValid(this.row)) throw new Error('offline_grant_expired');
                const query=this.searchQuery.toLocaleLowerCase();
                this.searchResults=(await this.store.list('tickets',this.row.partition)).map(r=>r.ticket).filter(t=>t.ticket_id>after && `${t.holder_name} ${t.symbol}`.toLocaleLowerCase().includes(query)).slice(0,30);
            } else if (this.searchScope==='users') {
                this.searchResults=(await this.api.call('search_scanner_users',{p_query:this.searchQuery,...(after?{p_after:after}:{})})).data;
            } else this.searchResults=await this.api.search(this.searchQuery,after);
            this.render();
        } catch(err) {this.searchError=err.message;this.searchResults=[];this.render();this.host.querySelector('[data-search] [name=query]')?.focus({preventScroll:true});}
    }
    async showSettings() {
        const { ScannerSettingsPage }=await import('./scanner_settings_page.js');
        this.settingsPage=new ScannerSettingsPage(this.host,{api:this.api,session:this.row.session,returnPath:this.returnPath,onBack:()=>location.assign('/scan')}); await this.settingsPage.init();
    }
    clear() {
        this.disposed=true;clearTimeout(this.advanceTimer);this.sound.dispose();this.host.removeEventListener('pointerdown',this.onGesture,true);this.host.removeEventListener('keydown',this.onGesture,true);clearInterval(this.interval);this.input?.dispose();this.disposeControllers();this.sync?.stop();this.settingsPage?.clear();
        window.removeEventListener('online',this.onNetwork);window.removeEventListener('offline',this.onNetwork);window.removeEventListener('beforeunload',this.onUnload);document.removeEventListener('visibilitychange',this.onVisible);this.referrerMeta?.remove();delete window.festappScannerCanReload;this.store?.close();super.clear();
    }
}
