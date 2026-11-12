import { formatDisplayNumber } from '../../utils/formatters.js';
import { scannerReturnPath, scannerInputHistoryState } from './scanner_navigation.js';
import { Component } from '../base/component.js';
import { ScannerApi } from '../../services/scanner_api.js';
import { ScannerStore, offlineGrantValid, isTerminal } from '../../services/scanner_store.js';
import { ScannerSync } from '../../services/scanner_sync.js';
import { ScannerController, ticketPayload } from './scanner_controller.js';
import { ScannerInput } from './scanner_input.js';
import { scanResult } from './scan_result.js';
import { tr, reasonText, escape as e } from './scan_strings.js';
import { AppConfig } from '../../app_config.js';
import { ThemeService } from '../../services/theme_service.js';
import './scan.css';
import { icon } from './scan_icons.js';
import { LocalizationService } from '../../services/localization_service.js';
import { ScannerFeedback } from './scanner_feedback.js';
import {scannerSearchPreview} from './scanner_presentation.js';
export class ScanPage extends Component {
    constructor(host, { client, store = new ScannerStore(), backend = null } = {}) {
        super(host); this.client = client; this.store = store;
        this.backend = backend || client.scannerBackendContext || { generation: client.supabaseUrl === AppConfig.backendActivationCanonicalSupabaseUrl ? 1 : 0, origin: client.supabaseUrl || AppConfig.supabaseUrl, organization: AppConfig.organization };
        this.sound=new ScannerFeedback();this.feedbackStates=new WeakMap();
        this.mode = 'camera'; this.rows = []; this.history = []; this.summaryAt = 0; this.online = navigator.onLine; this.disposed = false;
    }
    get canSearchTickets() { return Boolean(this.row?.session.capabilities.search_tickets); }
    get canSearchUsers() { return AppConfig.isAppSupported && Boolean(this.row?.session.capabilities.search_users); }
    async init(route) {
        this.onGesture=event=>{if(event.target.closest?.('[data-sound]'))return;this.sound.unlock().then(()=>this.updateSoundControl());};
        this.host.addEventListener('pointerdown',this.onGesture,true);this.host.addEventListener('keydown',this.onGesture,true);
        let returnStorage; try { returnStorage=window.sessionStorage; } catch {}
        this.returnNavigation = {location:{href:window.location.href},referrer:document.referrer,returnTo:route.returnTo,storage:returnStorage};
        this.returnPath = '/';
        this.route = route; document.querySelector('meta[name=referrer]')?.remove();
        const meta = document.createElement('meta'); meta.name = 'referrer'; meta.content = 'no-referrer'; document.head.append(meta);
        this.referrerMeta = meta;
        try {
            await this.store.open(); this.storageAvailable = true;
            this.rows = (await this.store.list('sessions')).filter(r => r.backend.generation === this.backend.generation && r.backend.origin === this.backend.origin && r.backend.organization === this.backend.organization);
        } catch { this.storageAvailable = false; this.store = null; }
        this.api = new ScannerApi(this.client);
        this.input = new ScannerInput(code => this.loadCodes([code]),{accepts:ticketPayload,onError:reason=>{this.cameraUnavailable=true;this.error=reason;this.render();}});
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
        if(route.page==='scan'){const view=this.inputHistory();if(view.history.state?.scannerInput==='manual')this.setInputMode('manual',{fromHistory:true});}
    }
    async open(params) {
        if (this.opening) return;
        this.opening = true; this.error = null; this.render();
        try {
            const session = await this.api.open(params);
            if(this.client.scannerBackendContext)this.backend=this.client.scannerBackendContext;
            this.row = this.store ? await this.store.saveSession(session, this.backend) : { session, partition: null };
            this.entryDraft = null;
            // Sanitize the entry before controls can create a search history entry.
            window.history.replaceState(null, '', this.route.page==='scan'?'/scan':'/scan/'+this.route.page);
            await this.select(this.row);
        } catch (err) { this.error = err.message; }
        finally {
            this.opening = false; this.render();
            if (this.error && !this.row) this.host.querySelector(this.error==='invalid_scan_code'?'[name=code]':'#scan-entry-error')?.focus();
        }
    }
    async select(row) {
        this.returnPath = scannerReturnPath({...this.returnNavigation,session:row.session,backend:this.backend});
        clearTimeout(this.searchTimer);this.searchTimer=null;this.searchPending=false;
        this.searchGeneration=(this.searchGeneration||0)+1;this.searchResults=[];this.searchQuery='';this.searchError=null;this.searchScope='tickets';this.presentedTicketKey=null;this.searchOpen=this.mode==='manual';
        this.disposeControllers();this.sync?.stop(); this.summaryAt=0; this.row = row; this.api.session = row.session;
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
    controllers() { return this.controller?[this.controller]:[]; }
    disposeControllers() { for(const c of this.controllers())c.dispose(); }
    createController() {
        return new ScannerController({ api: this.api, store: this.store, row:this.row, sync: this.sync, online:()=>navigator.onLine&&!this.transportOffline, onChange: c => {
            if(c.operation){const index=this.history.findIndex(r=>r.key===c.operation.key);if(index<0)this.history.push(c.operation);else this.history[index]=c.operation;}
            if (c.ticket?.source==='offline') this.transportOffline=true; if (!c.store) this.storageAvailable=false; this.render();
            if(c.state!=='ready'){this.input?.suppress?.(c.ticket?.symbol);this.input?.pause({keepStream:true});}
            this.feedback(c);
            if (c===this.controller && c.state === 'result') this.host.querySelector('[data-result-title]')?.focus({preventScroll:true});
        } });
    }
    async loadCodes(codes) {
        if(!this.controller || this.controller.state!=='ready' || this.disposed || this.authBlocked || this.row?.locked)return;
        const symbol=codes.map(ticketPayload).find(Boolean);
        if(!symbol)return;
        clearTimeout(this.advanceTimer);this.advanceTimer=null;
        this.reviewHistory();
        this.input?.pause({keepStream:true});
        this.controller.scanSymbol=symbol;
        await this.controller.loadCode(symbol);
    }
    inputHistory() {
        const view=this.host.ownerDocument.defaultView;
        if(!this.onInputHistory){
            this.inputHistoryPath=view.location.pathname;
            this.historyLevel=view.history.state?.scannerLevel;
            this.onInputHistory=event=>this.handleInputHistory(event);
            view.addEventListener('popstate',this.onInputHistory);
        }
        return view;
    }
    prepareInputHistory() {
        const view=this.inputHistory();
        if(!scannerInputHistoryState(view.history.state)){
            // Reserve the two levels during the camera/search gesture. Creating
            // entries on automatic detections after Back makes browser UI skip
            // the whole scanner (history.back() does not expose that behavior).
            view.history.replaceState({scannerInput:'camera',scannerLevel:'camera'},'',view.location.href);
            view.history.pushState({scannerInput:'camera',scannerLevel:'workspace'},'',view.location.href);
            this.historyLevel='workspace';
        }
        return view;
    }
    moveInputHistory(target) {
        const view=this.prepareInputHistory();
        if(target)this.historyTarget=target;
        if(this.historyTravel || !this.historyTarget)return;
        const {level,state={scannerInput:'camera'}}=this.historyTarget;
        if(view.history.state?.scannerLevel===level){
            view.history.replaceState({...state,scannerLevel:level},'',view.location.href);
        }else{
            this.historyTravel=level;
            view.history.go(level==='camera'?-1:1);
        }
    }
    handleInputHistory(event) {
        const view=this.host.ownerDocument.defaultView,state=event.state,mode=state?.scannerInput;
        if(this.disposed || view.location.pathname!==this.inputHistoryPath || !['camera','manual'].includes(mode))return false;
        this.handledInputHistory ??= new WeakSet();
        if(this.handledInputHistory.has(event))return true;
        this.handledInputHistory.add(event);
        event.stopImmediatePropagation();
        const previous=this.historyLevel,level=state.scannerLevel || (state.scannerReview || mode==='manual'?'workspace':'camera');
        this.historyLevel=level;
        if(this.historyTravel===level){
            this.historyTravel=null;this.moveInputHistory();return true;
        }
        this.historyTarget=null;
        if(level==='camera'){
            if(this.controllers().some(c=>['persisting','looking_up','awaiting_server'].includes(c.state))){
                this.moveInputHistory({level:'workspace',state:{scannerInput:this.mode,scannerReview:!this.searchOpen}});
            }else if(this.controller && (this.mode==='manual' || this.controller.state!=='ready')){
                this.returnToCamera({fromHistory:true});
            }else if(previous==='workspace'){
                // The reserved workspace was still showing the full camera.
                // One Back from that camera must leave, without an empty stop.
                view.history.back();
            }
        }else if(mode!==this.mode){
            this.setInputMode(mode,{fromHistory:true});
        }
        return true;
    }
    setInputMode(mode,{fromHistory=false}={}) {
        if(this.controllers().some(c=>['persisting','looking_up','awaiting_server'].includes(c.state)))return false;
        if(mode==='camera' && !fromHistory)return this.returnToCamera();
        if(mode==='manual' && !fromHistory)this.moveInputHistory({level:'workspace',state:{scannerInput:'manual'}});
        clearTimeout(this.advanceTimer);this.advanceTimer=null;this.advanceKey=null;
        if(mode==='camera'){clearTimeout(this.searchTimer);this.searchTimer=null;this.searchPending=false;this.searchGeneration=(this.searchGeneration||0)+1;}
        this.mode=mode;this.searchOpen=mode==='manual';
        if(mode==='manual')this.input.stop();
        this.render();
        if(mode==='camera'){this.startCamera();this.updateAutoAdvance();}
        else this.host.querySelector('[name=query]')?.focus();
        return true;
    }
    reviewHistory() {
        this.moveInputHistory({level:'workspace',state:{scannerInput:this.mode,scannerReview:true}});
    }
    returnToCamera(options={}) { return this.nextScan('camera',{...options,keepSuppression:true}); }
    loadSelectedTicket(reference) {
        this.reviewHistory();this.searchOpen=false;
        return this.controller.loadTicket(reference);
    }

    nextScan(mode=this.cameraWasStarted&&!this.cameraUnavailable?'camera':this.mode,{auto=false,fromHistory=false,keepSuppression=false}={}) {
        if(!this.controller || this.controllers().some(c=>['persisting','looking_up','awaiting_server'].includes(c.state)))return false;
        if(!fromHistory && mode==='camera')this.moveInputHistory({level:'camera'});
        clearTimeout(this.advanceTimer);this.advanceTimer=null;
        if(mode==='manual')this.input.stop();
        clearTimeout(this.searchTimer);this.searchTimer=null;this.searchPending=false;this.searchGeneration=(this.searchGeneration||0)+1;
        if(auto && mode==='manual'){this.searchQuery='';this.searchResults=[];const field=this.host.querySelector('[name=query]');if(field)field.value='';}
        this.mode=mode;this.searchOpen=mode==='manual';this.renderedController=null;
        this.controller.scanSymbol=null;this.controller.unpaidConfirmed=false;this.controller.next();
        if(!auto && !keepSuppression)this.input.allowSame?.();
        this.input.paused=false;this.render();
        if(this.mode==='camera'){if(this.input.stream)this.updateCameraState();else if(!auto||this.cameraWasStarted)this.startCamera();}else this.host.querySelector('[name=query]')?.focus();
        return true;
    }
    resultHtml(c) {
        return scanResult(c,this.storageAvailable && !this.authBlocked && !this.row.locked);
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
            await import('./scanner_codes.js'); // The engine and its WASM asset belong to the offline PWA shell.
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
        const backToCamera=session && (this.route.page!=='scan' || this.mode==='manual' || this.controller && this.controller.state!=='ready');
        const backPath=backToCamera?'/scan':this.returnPath || '/';
        return `<main class="scan-shell ${session ? '' : 'scan-entry-shell'}"><header class="scan-header"><a class="scan-home" href="${e(backPath)}" aria-label="${tr(this.returnPath && this.returnPath!=='/'?'back':'home')}">${icon('back')}</a><h1>${e(session?.title || tr('scan'))}</h1>${session ? `<details class="scan-menu"><summary>${icon('settings')}<span>${tr('options')}</span></summary><div class="scan-menu-panel"><p class="scan-menu-title">${tr('scanner_tools')}</p>${session ? `<nav aria-label="${tr('scan')}">${this.route.page!=='scan'?`<a href="/scan">${icon('camera')}${tr('back_to_camera')}</a>`:''}<a href="/scan/history" ${this.route.page==='history'?'aria-current="page"':''}>${icon('history')}${tr('history')}</a>${session?.capabilities.settings?`<a href="/scan/settings">${icon('settings')}${tr('display_settings')}</a>`:''}${needsSync?`<a href="/scan/offline">${icon('offline')}${tr('sync_status')}</a>`:''}</nav>` : ''}<button data-theme>${icon('theme')}${tr('theme')}</button>${session ? `<button data-sound>${icon('sound')}${tr(this.sound?.ready?'sound_on':'sound_enable')}</button>` : ''}${canPrepare?`<details class="scan-advanced"><summary>${tr('more_options')}</summary>${canPrepare?`<a href="/scan/offline">${tr('prepare_offline_short')}</a>`:''}</details>`:''}</div></details>` : `<button data-theme aria-label="${tr('theme')}" title="${tr('theme')}">${icon('theme')}</button>`}</header>
        <div class="scan-status" role="status"><span class="scan-connection ${navigator.onLine && !this.transportOffline ? 'is-online' : 'is-offline'}"><span class="scan-dot"></span>${tr(navigator.onLine && !this.transportOffline ? 'online' : 'offline')}</span>${sum ? `<span class="scan-count">${tr('used')}: <strong>${formatDisplayNumber(sum.used_current, LocalizationService.currentLocale)} <span>/ ${formatDisplayNumber(sum.eligible_total, LocalizationService.currentLocale)}</span></strong><span class="scan-percent">${percent} %</span></span>` : ''}${pending ? `<span class="scan-pending-count">${tr('pending_count')}: ${pending}</span>` : ''}${conflicts ? `<span class="scan-conflict-count">${tr('conflicts')}: ${conflicts}</span>` : ''}${sum ? `<div class="scan-progress" role="progressbar" aria-label="${tr('used')}" aria-valuemin="0" aria-valuemax="${total||1}" aria-valuenow="${Math.min(used,total)}" aria-valuetext="${used} / ${total} (${percent} %)"><span style="width:${percent}%"></span></div>` : ''}</div>
        ${session && (!navigator.onLine || this.transportOffline) ? `<p class="scan-offline-notice"><a href="/scan/offline">${tr(this.snapshot?'offline_saved_short':'offline_unprepared_short')}</a></p>` : ''}
        ${!this.storageAvailable ? `<p class="scan-warning" role="alert">${tr('storage_failed')}</p>` : ''}
        ${this.authBlocked ? `<p class="scan-warning">${tr('blocked_auth')}</p>` : ''}
        ${this.message ? `<p role="status">${e(this.message)}</p>` : ''}
        ${this.error && this.row ? `<p class="scan-warning" role="alert">${e(reasonText(this.error))}</p>` : ''}
        ${content}</main>`;
    }
    render() {
        if (this.disposed || this.settingsPage) return;
        // Keep the permission request and pending video.play attached. Recovery can
        // refresh counters while the browser is still opening the camera.
        if(this.cameraStarting && this.mode==='camera' && this.route.page==='scan' && this.renderedSession===this.row?.session){this.updateCameraState();return;}
        if(this.cameraStarting){this.cameraStarting=null;this.input.stop();}
        const c = this.controller;
        const reviewing=Boolean(!this.searchOpen && c && c.state!=='ready');
        const navigationBusy=this.controllers().some(controller=>['persisting','looking_up','awaiting_server'].includes(controller.state));
        if (!this.canSearchUsers && this.searchScope==='users') { this.searchScope='tickets';this.searchResults=[]; }
        if(!this.canSearchTickets && this.canSearchUsers)this.searchScope='users';
        const drafts = !this.row || this.renderedSession===this.row.session && this.mode==='manual' ? [...this.host.querySelectorAll('[data-open] input,[data-search] input')].map(input=>({name:input.name,value:input.value,focused:input===document.activeElement,start:input.selectionStart,end:input.selectionEnd})) : [];
        if (!this.row && drafts.length) this.entryDraft = Object.fromEntries(drafts.map(({name,value})=>[name,value]));
        const liveVideo = this.mode==='camera' && this.route.page==='scan' && this.input?.stream ? this.input.video : null;
        if (!liveVideo) this.input?.stop();
        let content;
        if (!this.row) content = this.entryHtml();
        else if (this.route.page === 'history') content = `<section class="scan-settings"><h2>${tr('this_device')}</h2>${this.row.session.capabilities.event_history?`<button data-event-history>${tr('event_history')}</button>`:''}${this.historyHtml()}${this.eventHistory?`<h3>${tr('event_history')}</h3><ul class="scan-list">${this.eventHistory.map(r=>`<li>${e(reasonText(r.receipt.reason))} #${r.receipt.ticket_id} · ${e(new Date(r.receipt.committed_at).toLocaleString(LocalizationService.currentLocale))}</li>`).join('')}</ul><button data-event-more>${tr('search_more')}</button>`:''}</section>`;
        else if (this.route.page === 'offline') content = `<section class="scan-settings"><h2>${tr('offline')}</h2><p>${tr('valid_until')}: ${e(new Date(this.row.session.offline_until).toLocaleString(LocalizationService.currentLocale))}</p>
        ${this.snapshot ? `<p>${tr('prepared')}: ${this.snapshot.ticket_count} ${tr('tickets')} · ${e(new Date(this.snapshot.server_time).toLocaleString(LocalizationService.currentLocale))}</p>` : ''}
        <button data-prepare ${this.preparing || !this.store || !navigator.onLine ? 'disabled' : ''}>${tr('prepare')}</button><button data-retry>${tr('retry')}</button><p>${tr('logout_note')}</p><button data-lock>${tr('logout')}</button>
        <p>${tr('sync_latency')}: ${Math.round(this.lastSyncLatency||0)} ms · ${tr('oldest_pending')}: ${e(this.history.filter(r=>!isTerminal(r.state)).map(r=>r.payload.captured_at).sort()[0] || '-')}</p><h3>${tr('pending_count')} / ${tr('conflicts')}</h3>${this.historyHtml(true)}</section>`;
        else content = `<div class="scan-layout ${this.mode==='manual' && !reviewing?'manual-ready':''} ${this.mode==='camera'?'camera-mode':''} ${this.mode==='camera' && c?.state==='ready'?'camera-ready':''} ${reviewing ? 'has-result' : ''}"><section class="scan-input">
        ${this.mode==='camera' ? `<div class="scan-camera" data-active="false"><video aria-label="${tr('camera')}"></video><div class="scan-camera-idle">${icon('camera')}<strong>${tr('camera_ready')}</strong><p>${tr('camera_privacy')}</p><button class="scan-primary" data-camera>${icon('camera')}${tr('camera_start')}</button></div><div class="scan-viewfinder" aria-hidden="true"><i></i><i></i><i></i><i></i></div><span class="scan-camera-live"><span class="scan-dot"></span>${tr('camera_live')}</span></div><p class="scan-camera-hint">${tr('camera_aim')}</p><div class="scan-camera-footer"><button class="scan-manual-link" data-mode="manual">${tr('manual_entry')}</button><details class="scan-camera-options"><summary>${tr('camera_controls')}</summary><div class="scan-camera-popover"><div class="scan-camera-tools"><button data-switch>${icon('switch')}${tr('camera_switch')}</button><button data-camera-stop>${icon('stop')}${tr('camera_stop')}</button><button data-torch hidden>${tr('torch')}</button></div><p>${tr('camera_help_text')}</p></div></details></div>` : `<form data-search novalidate aria-busy="${Boolean(this.searchPending)}">${this.canSearchTickets && this.canSearchUsers ? `<label>${tr('search_scope')}<select data-search-scope><option value="tickets">${tr('tickets')}</option><option value="users" ${this.searchScope==='users'?'selected':''}>${tr('users')}</option></select></label>`:''}<label>${tr(this.searchScope==='users' && this.canSearchUsers?'user_search':this.canSearchTickets?'search_input':'symbol')}<input name="query" type="search" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="search" maxlength="200" aria-invalid="${Boolean(this.searchError)}" ${this.searchError?'aria-describedby="scan-search-error"':''}></label><p class="scan-field-error" id="scan-search-error" role="alert" ${this.searchError?'':'hidden'}>${e(this.searchError?reasonText(this.searchError):'')}</p></form><p class="scan-search-context">${tr('search_current_event')}: ${e(this.row.session.title)}</p><ul class="scan-list scan-search-results">${(this.searchResults||[]).map((t,index)=>`<li><button data-search-ticket="${index}">${scannerSearchPreview(t)}</button></li>`).join('')}</ul>${this.searchResults?.length===30 ? `<button data-search-more>${tr('search_more')}</button>` : ''}${c?.state==='ready'?`<button class="scan-manual-link" data-mode="camera">${icon('camera')}${tr('back_to_camera')}</button>`:''}`}</section>
        ${this.mode==='manual' && reviewing?`<div class="scan-review-navigation"><button data-mode="camera">${icon('camera')}${tr('back_to_camera')}</button><button data-next-mode="manual" ${navigationBusy?'disabled':''}>${icon('manual')}${tr('search')}</button></div>`:''}<section class="scan-detail" aria-live="polite" aria-busy="${['looking_up','persisting','awaiting_server'].includes(c?.state)}">${!this.searchOpen && c ? this.resultHtml(c) : ''}</section></div>`;
        // Recovery updates the shell counters without recreating the review surface.
        // Keep native disclosure state, focused controls and the actual scrolling node.
        const template=document.createElement('template');
        template.innerHTML=this.shell(content);
        const shell=template.content.firstElementChild;
        const focused=document.activeElement;
        const previousLayout=this.host.querySelector('.scan-layout');
        const nextLayout=shell.querySelector('.scan-layout');
        const sameReview=this.renderedController===c && this.renderedMode===this.mode;
        const previousDetail=previousLayout?.querySelector('.scan-detail');
        const detailScroll=sameReview?previousDetail?.scrollTop:0;
        const openDetails=sameReview?[...(previousDetail?.querySelectorAll('details')||[])].map(detail=>detail.open):[];
        let footer;
        if(nextLayout && previousLayout && sameReview && this.renderedContent===content){
            nextLayout.replaceWith(previousLayout);
            footer=this.host.querySelector('.scan-review-footer');
        }else if(nextLayout){
            const actions=[...nextLayout.querySelectorAll('.scan-actions')].filter(el=>el.children.length);
            if(actions.length){
                footer=document.createElement('footer');footer.className='scan-review-footer';
                const inner=document.createElement('div');inner.className='scan-review-actions';
                inner.append(...actions);footer.append(inner);
            }
            const detail=nextLayout.querySelector('.scan-detail');
            detail?.querySelectorAll('details').forEach((el,index)=>{el.open=Boolean(openDetails[index]);});
        }
        if(footer){
            shell.append(footer);shell.classList.add('has-review-footer');
            const reserved=this.host.querySelector('.scan-shell')?.style.getPropertyValue('--scan-bottom-reserve');
            if(reserved)shell.style.setProperty('--scan-bottom-reserve',reserved);
        }
        this.footerObserver?.disconnect();
        this.host.replaceChildren(shell);
        if(focused && this.host.contains(focused))focused.focus({preventScroll:true});
        const detail=this.host.querySelector('.scan-detail');
        this.renderedContent=content;this.renderedController=c;this.renderedMode=this.mode;this.renderedSession=this.row?.session;
        if(footer){
            const reserve=()=>shell.style.setProperty('--scan-bottom-reserve',`${Math.ceil(footer.getBoundingClientRect().height)}px`);
            reserve();
            if(globalThis.ResizeObserver){this.footerObserver=new ResizeObserver(reserve);this.footerObserver.observe(footer);}
        }
        if(detail && sameReview)detail.scrollTop=detailScroll||0;
        if (liveVideo) { this.host.querySelector('video')?.replaceWith(liveVideo);liveVideo.play().catch(()=>{});this.updateCameraState(); }
        this.bind();
        this.updateCameraState();
        const ticketKey=!this.searchOpen && c?.state==='result' && c.ticket?`${this.row?.partition}:${c.serial}:${c.ticket.ticket_id ?? c.ticket.symbol}`:null;
        if(ticketKey && ticketKey!==this.presentedTicketKey){
            this.presentedTicketKey=ticketKey;
            const view=this.host.ownerDocument.defaultView;
            if(!view.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches)this.host.querySelector('.scan-detail')?.animate?.([
                {opacity:0,transform:'translateY(16px)'},{opacity:1,transform:'translateY(0)'}
            ],{duration:550,easing:'cubic-bezier(.16,1,.3,1)'});
        }
        for(const draft of drafts){
            const input=[...this.host.querySelectorAll('input[name]')].find(input=>input.name===draft.name);
            if(!input)continue;input.value=draft.value;
            if(draft.focused){input.focus({preventScroll:true});input.setSelectionRange(draft.start,draft.end);}
        }
    }
    entryHtml() {
        const invalidCode = this.error === 'invalid_scan_code';
        const error = this.error ? `<div class="scan-entry-error" id="scan-entry-error" role="alert" tabindex="-1">${icon('alert')}<div><strong>${e(reasonText(this.error))}</strong>${invalidCode ? `<p>${tr('entry_code_retry')}</p>` : ''}</div></div>` : '';
        return `<section class="scan-entry" aria-labelledby="scan-entry-title">
            <h2 id="scan-entry-title">${tr('open')}</h2><p class="scan-entry-intro">${tr('entry_intro')}</p>
            <form data-open aria-busy="${Boolean(this.opening)}">
                <div class="scan-entry-field"><label for="scan-entry-code">${tr('scan_code')}</label>
                <input id="scan-entry-code" name="code" autocomplete="off" autocapitalize="none" spellcheck="false" required maxlength="100" value="${e(this.entryDraft?.code || '')}" aria-invalid="${invalidCode}" aria-describedby="scan-code-hint${invalidCode?' scan-entry-error':''}" ${this.opening?'readonly':''}>
                ${invalidCode ? error : ''}<p class="scan-entry-hint" id="scan-code-hint">${tr('entry_code_hint')}</p></div>
                <div class="scan-entry-field"><label for="scan-entry-device">${tr('device')}</label>
                <input id="scan-entry-device" name="device" autocomplete="off" required maxlength="80" value="${e(this.entryDraft?.device ?? tr('this_device'))}" aria-describedby="scan-device-hint" ${this.opening?'readonly':''}>
                <p class="scan-entry-hint" id="scan-device-hint">${tr('entry_device_hint')}</p></div>
                ${!invalidCode ? error : ''}
                ${!navigator.onLine ? `<p class="scan-entry-network" role="status">${tr('entry_offline')}</p>` : ''}
                <button class="scan-primary" ${this.opening || !navigator.onLine?'disabled':''}>${this.opening?tr('entry_opening'):tr('open')}${icon(this.opening?'clock':'arrow')}</button>
            </form>
        </section>${this.rows.length ? `<section class="scan-saved" aria-labelledby="scan-saved-title"><h2 id="scan-saved-title">${tr('saved_sessions')}</h2><p class="scan-entry-hint">${tr('entry_saved_hint')}</p><div class="scan-saved-list">${this.rows.map((r,i)=>`<button data-session="${i}" ${this.opening?'disabled':''}><span><strong>${e(r.session.title)}</strong><span class="scan-saved-device">${e(r.session.device_name)}</span>${r.locked ? `<span class="scan-saved-locked">${tr('blocked_auth')}</span>` : ''}</span>${icon('arrow')}</button>`).join('')}</div></section>` : ''}`;
    }
    historyHtml(onlyOpen = false) {
        const rows = this.history.filter(r => !onlyOpen || !isTerminal(r.state) || r.state==='conflict').sort((a,b)=>b.payload.captured_at.localeCompare(a.payload.captured_at));
        return `<ul class="scan-list">${rows.length ? rows.map(r=>`<li><strong>${tr(r.state)==r.state ? reasonText(r.receipt?.reason) : tr(r.state)}</strong> #${r.payload.ticket_id}<p>${tr(r.payload.snapshot_id ? 'source_offline' : 'source_online')}</p><p>${tr('captured_at')}: ${e(new Date(r.payload.captured_at).toLocaleString(LocalizationService.currentLocale))}</p>${r.receipt ? `<p>${tr('committed_at')}: ${e(new Date(r.receipt.committed_at).toLocaleString(LocalizationService.currentLocale))}</p>` : ''}
        ${r.state==='conflict' && this.row.session.capabilities.settings && !r.resolved ? `<form data-resolve="${r.key}"><label>${tr('resolution_reason')}<input name="reason" required minlength="3" maxlength="1000"></label><button>${tr('resolve')}</button></form>` : ''}</li>`).join('') : `<li>${tr('no_history')}</li>`}</ul>`;
    }
    bind() {
        const one = (s,f) => { const el=this.host.querySelector(s); if(el) el.onclick=f; };
        one('.scan-home',event=>{if(this.route.page==='scan' && (this.mode==='manual' || this.controller && this.controller.state!=='ready')){event.preventDefault();this.returnToCamera();}});
        const eventHistory=async before=>{try{this.eventHistory=(await this.api.call('get_scanner_event_history',{p_occasion:this.row.session.occasion_id,...(before?{p_before:before}:{})},false)).data;this.render();}catch(err){this.error=err.message;this.render();}};
        one('[data-event-history]',()=>eventHistory());one('[data-event-more]',()=>eventHistory(this.eventHistory.at(-1)?.receipt.committed_at));
        one('[data-theme]',()=>ThemeService.toggle());
        one('[data-sound]',async()=>{if(this.sound.ready){this.sound.enabled=false;}else{this.sound.enabled=true;await this.sound.unlock();this.sound.play('good');}this.updateSoundControl();});
        const open=this.host.querySelector('[data-open]'); if(open) open.onsubmit=ev=>{ev.preventDefault();this.open({p_scan_code:open.elements.code.value,p_device_name:open.elements.device.value});};
        this.host.querySelectorAll('[data-session]').forEach(b=>b.onclick=()=>{const row=this.rows[Number(b.dataset.session)]; this.authBlocked=Boolean(row.locked);this.select(row);});
        this.host.querySelectorAll('[data-mode]').forEach(b=>{b.disabled=this.controllers().some(c=>['persisting','looking_up','awaiting_server'].includes(c.state));b.onclick=()=>b.dataset.mode==='camera'?this.returnToCamera():this.setInputMode(b.dataset.mode);});
        const search=this.host.querySelector('[data-search]');
        if(search){
            search.setAttribute('aria-busy',String(Boolean(this.searchPending)));
            const scope=this.host.querySelector('[data-search-scope]');
            const schedule=(immediate=false)=>{
                this.searchQuery=search.elements.query.value;
                this.searchScope=scope?.value || (this.row.session.capabilities.search_tickets?'tickets':'users');
                this.scheduleSearch({immediate});
            };
            search.onsubmit=event=>{event.preventDefault();schedule(true);};
            search.elements.query.oninput=event=>{if(!event.isComposing)schedule();};
            search.elements.query.oncompositionend=()=>schedule();
            search.elements.query.onkeydown=event=>{if(event.key==='Enter' && !event.isComposing){event.preventDefault();schedule(true);}};
            if(scope)scope.onchange=()=>schedule();
        }
        one('[data-search-more]',()=>this.search((this.searchResults.at(-1).user_id || this.searchResults.at(-1).ticket_id)));
        this.host.querySelectorAll('[data-search-ticket]').forEach(b=>{
            b.disabled=this.controllers().some(c=>['persisting','looking_up','awaiting_server'].includes(c.state));
            b.onclick=async()=>{
                await this.loadSelectedTicket(this.searchResults[Number(b.dataset.searchTicket)]);
                // Selecting a row is navigation; background recovery must never do this.
                if(!this.disposed && this.controller.state==='result')this.host.querySelector('.scan-layout')?.scrollIntoView?.({block:'start'});
            };
        });
        one('[data-confirm]',()=>this.controller.confirm(Boolean(this.host.querySelector('[data-unpaid]')?.checked)));
        const reset=this.host.querySelector('[data-reset]'); if(reset) reset.onsubmit=async ev=>{ev.preventDefault();try {await this.api.call('reset_scanner_password',{p_ticket:this.controller.ticket.ticket_id,p_password:reset.elements.password.value});reset.reset();this.error=null;this.message=tr('password_reset_done');this.render();}catch(err){reset.reset();this.error=err.message;this.render();}};
        const unpaid=this.host.querySelector('[data-unpaid]'); if(unpaid){unpaid.checked=Boolean(this.controller.unpaidConfirmed);this.host.querySelector('[data-confirm]').disabled=!unpaid.checked;unpaid.onchange=()=>{this.controller.unpaidConfirmed=unpaid.checked;this.host.querySelector('[data-confirm]').disabled=!unpaid.checked;};}
        one('[data-next]',()=>this.nextScan());
        one('[data-next-mode]',()=>this.setInputMode('manual'));
        one('[data-camera]',()=>this.startCamera());
        one('[data-camera-stop]',()=>{this.cameraStarting=null;this.input.stop();this.render();});
        one('[data-switch]',async()=>{try{await this.input.switchCamera();this.updateCameraState();}catch(err){this.error=err.message;this.render();}});
        one('[data-torch]',()=>this.input.torch());
        one('[data-prepare]',()=>this.prepare());one('[data-retry]',()=>this.recover());
        one('[data-lock]',async()=>{try {await this.api.call('revoke_scanner_session');} catch {} await this.store.lockSession(this.row.partition);this.sync.stop();this.row=null;this.disposeControllers();this.rows=await this.store.list('sessions');this.render();});
        this.host.querySelectorAll('[data-resolve]').forEach(form=>form.onsubmit=async ev=>{ev.preventDefault();try {await this.api.call('resolve_scanner_conflict',{p_operation:form.dataset.resolve,p_reason:form.elements.reason.value},false);const row=this.history.find(r=>r.key===form.dataset.resolve);await this.store.put('outbox',{...row,resolved:true});this.history=await this.store.list('outbox',this.row.partition);this.render();} catch(err){this.error=err.message;this.render();}});
    }
    feedback(c) {
        const key=c.state+':'+(c.error||c.operation?.receipt?.reason||'');
        if(this.feedbackStates.get(c)===key)return;
        this.feedbackStates.set(c,key);
        {
            if(c.state==='accepted')this.sound.play('accepted');
            else if(c.state==='result')this.sound.play(c.ticket?.admission_allowed&&!c.ticket.requires_unpaid_confirmation?'good':'error');
            else if(['error','conflict','rejected','blocked_auth','blocked_schema'].includes(c.state))this.sound.play('error');
        }
        this.updateAutoAdvance();
    }
    updateAutoAdvance() {
        const controllers=this.controllers();
        if(this.searchOpen || !controllers.length || !controllers.every(c=>c.state==='accepted'&&c.operation?.receipt?.outcome==='accepted'))return;
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
        if(camera){camera.dataset.active=String(Boolean(this.input.stream));camera.dataset.paused=String(Boolean(this.input.paused));const hint=this.host.querySelector('.scan-camera-hint');if(hint)hint.textContent=tr(this.input.paused?'camera_review':'camera_aim');}
        const start=this.host.querySelector('[data-camera]');if(start){start.disabled=Boolean(this.cameraStarting);start.setAttribute('aria-busy',String(Boolean(this.cameraStarting)));}
        const torch=this.host.querySelector('[data-torch]');
        if(torch)torch.hidden=!this.input.stream?.getVideoTracks()[0]?.getCapabilities?.().torch;
        for(const selector of ['[data-switch]','[data-camera-stop]']) {
            const button=this.host.querySelector(selector);if(button)button.disabled=!this.input.stream || (selector==='[data-switch]' && Boolean(this.cameraStarting));
        }
    }
    startCamera() {
        if(this.cameraStarting)return this.cameraStarting.promise;
        const video=this.host.querySelector('video');if(!video)return;
        this.prepareInputHistory();
        const attempt={};this.cameraStarting=attempt;this.error=null;
        attempt.promise=(async()=>{
            try {
                if(!this.input.stream)await this.input.start(video);
                if(this.cameraStarting!==attempt || this.disposed)return;
                this.cameraWasStarted=Boolean(this.input.stream);this.cameraUnavailable=false;
                this.input.paused=this.controller?.state!=='ready';
            } catch(err) {
                if(this.cameraStarting!==attempt || this.disposed)return;
                this.cameraUnavailable=true;this.error=err.message;this.sound.play('error');
            } finally {
                if(this.cameraStarting===attempt){this.cameraStarting=null;if(!this.disposed)this.render();}
            }
        })();
        this.updateCameraState();return attempt.promise;
    }
    scheduleSearch({immediate=false}={}) {
        clearTimeout(this.searchTimer);this.searchTimer=null;
        // Invalidate an older request as soon as typing changes, before debounce.
        this.searchGeneration=(this.searchGeneration||0)+1;
        this.searchError=null;
        const query=String(this.searchQuery||'').trim();
        if(query.length<2 && !immediate){
            this.searchPending=false;this.searchResults=[];this.render();return;
        }
        if(!this.canSearchTickets && !this.canSearchUsers){
            this.searchPending=false;this.searchResults=[];
            if(immediate)return this.loadSelectedTicket({symbol:query});
            return;
        }
        if(immediate)return this.search(0,{openExact:true});
        this.searchPending=true;
        const form=this.host.querySelector('[data-search]');
        form?.setAttribute('aria-busy','true');
        const input=form?.elements.query;
        if(input){input.setAttribute('aria-invalid','false');input.removeAttribute('aria-describedby');}
        const error=this.host.querySelector('#scan-search-error');if(error)error.hidden=true;
        this.searchTimer=setTimeout(()=>{this.searchTimer=null;this.search(0);},350);
    }
    async search(after,{openExact=false}={}) {
        clearTimeout(this.searchTimer);this.searchTimer=null;

        if(this.disposed)return;
        if (!AppConfig.isAppSupported && this.searchScope==='users') this.searchScope='tickets';
        const generation=this.searchGeneration=(this.searchGeneration||0)+1;
        const row=this.row,session=row?.session,query=String(this.searchQuery||'').trim(),scope=this.searchScope;
        const current=()=>!this.disposed && this.row===row && this.row?.session===session && this.searchGeneration===generation;
        this.searchError=null;this.error=null;this.searchQuery=query;this.searchPending=true;
        try {
            if(query.length<2 || query.length>100)throw new Error('invalid_query');
            let results;
            if (!navigator.onLine) {
                if (scope==='users' || !offlineGrantValid(row)) throw new Error('offline_grant_expired');
                const normalized=query.toLocaleLowerCase();
                results=(await this.store.list('tickets',row.partition)).map(r=>r.ticket).filter(t=>t.ticket_id>after && `${t.holder_name || ''} ${t.purchaser_name || ''} ${t.purchaser_email || ''} ${t.batch_title || ''} ${t.symbol || ''}`.toLocaleLowerCase().includes(normalized)).slice(0,30);
            } else if (scope==='users') {
                results=(await this.api.call('search_scanner_users',{p_query:query,...(after?{p_after:after}:{})})).data;
            } else results=await this.api.search(query,after);
            if(!current())return;
            this.searchPending=false;this.searchResults=results;this.render();
            const exact=openExact && results.find(t=>t.symbol?.toLocaleLowerCase()===query.toLocaleLowerCase());
            if(exact)await this.loadSelectedTicket(exact);
            else if(openExact && scope==='users' && !results.length)await this.loadSelectedTicket({symbol:query});
        } catch(err) {
            if(!current())return;
            this.searchPending=false;this.searchError=err.message;this.searchResults=[];this.render();this.host.querySelector('[data-search] [name=query]')?.focus({preventScroll:true});
        }
    }
    async showSettings() {
        const { ScannerSettingsPage }=await import('./scanner_settings_page.js');
        this.settingsPage=new ScannerSettingsPage(this.host,{api:this.api,session:this.row.session,returnPath:this.returnPath,onBack:()=>location.assign('/scan')}); await this.settingsPage.init();
    }
    clear() {
        this.disposed=true;this.footerObserver?.disconnect();this.entryDraft=null;clearTimeout(this.advanceTimer);clearTimeout(this.searchTimer);this.sound.dispose();this.host.removeEventListener('pointerdown',this.onGesture,true);this.host.removeEventListener('keydown',this.onGesture,true);clearInterval(this.interval);this.input?.dispose();this.disposeControllers();this.sync?.stop();this.settingsPage?.clear();
        this.host.ownerDocument.defaultView.removeEventListener('popstate',this.onInputHistory);window.removeEventListener('online',this.onNetwork);window.removeEventListener('offline',this.onNetwork);window.removeEventListener('beforeunload',this.onUnload);document.removeEventListener('visibilitychange',this.onVisible);this.referrerMeta?.remove();delete window.festappScannerCanReload;this.store?.close();super.clear();
    }
}
