import {measurementProtocol, measurementConsent, measurementManifest, sameMeasurementManifest, measurementDataLayerPayload} from '../components/forms/form_measurement_contract.js';
import {bindKlaroConsent} from '../components/forms/form_measurement_consent.js';
// Presence is the long-lived public opt-in; absent preserves existing embeds.
export const usesHostDataLayer = frame => frame.hasAttribute('data-festapp-datalayer');

export function createHostMeasurement({frames, currentRecord, disposeRecord, scan}) {
    let suspended = false;
    const stopHeartbeat = record => {
        clearInterval(record.heartbeat);
        record.heartbeat = null;
    };
    const readChoice = record => {
        try { return measurementConsent(record.choice?.read(record.manifest)); }
        catch { return measurementConsent(false); }
    };
    const sendConsent = (frame, record) => record.channel.send('measurement-consent', {measurement:{protocol:measurementProtocol, manifest:record.manifest, leaseId:record.lease?.id,
            ttl:record.lease ? 60000 : 0, consent:readChoice(record)}});
    const revoke = (frame, record) => {
        record.lease = null;
        record.pageContext = null;
        if (record.manifest && currentRecord(frame, record)) sendConsent(frame, record);
    };
    // Liveness belongs to the record, independently of the visitor's choice.
    const syncConsent = (frame, record) => {
        if (!currentRecord(frame, record)) { disposeRecord(frame, record); return; }
        if (suspended || !record.manifest) return;
        record.heartbeat ??= setInterval(() => syncConsent(frame, record), 20000);
        record.lease ??= {id:crypto.randomUUID()};
        record.lease.until = Date.now() + 60000;
        sendConsent(frame, record);
    };
    const scopeOf = manifest => manifest && JSON.stringify([manifest.organization, manifest.unit, manifest.processing_revision]);
    const scopedChoice = (record, read) => {
        let scope = scopeOf(record.manifest);
        return manifest => {
            if (!manifest) return false;
            scope ??= scopeOf(manifest);
            return scope === scopeOf(manifest) ? read() : false;
        };
    };
    // All public choice adapters install one binding. Retired callbacks are inert.
    const bindChoice = (frame, record, connect) => {
        if (!currentRecord(frame, record)) return null;
        record.choice?.dispose();
        const binding = {read:() => false};
        record.choice = binding;
        const notify = () => {
            if (record.choice === binding && currentRecord(frame, record)) syncConsent(frame, record);
        };
        let adapter, disposed = false;
        binding.dispose = () => {
            if (disposed) return;
            disposed = true;
            const owns = record.choice === binding;
            if (owns) record.choice = null;
            try { adapter?.dispose?.(); } catch { /* Retired source cannot retain a choice. */ }
            if (owns && currentRecord(frame, record)) syncConsent(frame, record);
        };
        try { adapter = connect(notify); binding.read = adapter.read; }
        catch { binding.read = () => false; }
        notify();
        return binding.dispose;
    };
    const api = Object.freeze({
        connectMeasurementConsent(frame, source) {
            const record = frames.get(frame);
            if (!record || typeof source?.read !== 'function' || typeof source?.subscribe !== 'function') return null;
            return bindChoice(frame, record, notify => {
                const dispose = source.subscribe(notify);
                return {dispose, read:manifest => {
                    if (!manifest) return false;
                    const choice = source.read({organization:manifest.organization, unit:manifest.unit,
                        processingRevision:manifest.processing_revision, requiredPurposes:manifest.required_purposes});
                    return choice?.processingRevision === manifest.processing_revision ? choice : false;
                }};
            });
        },
        connectKlaro(frame, manager) {
            const record = frames.get(frame);
            if (!record) return null;
            return bindChoice(frame, record, notify => {
                let choice = measurementConsent(false);
                const read = scopedChoice(record, () => choice);
                const dispose = bindKlaroConsent(manager, value => { choice = measurementConsent(value); notify(); });
                return {read, dispose};
            });
        },
        setMeasurementConsent(frame, value) {
            const record = frames.get(frame);
            if (!record || !currentRecord(frame, record)) return false;
            const choice = measurementConsent(value);
            bindChoice(frame, record, () => ({read:scopedChoice(record, () => choice)}));
            return true;
        }
    });
    document.addEventListener('visibilitychange', () => {
        if (!document.hidden && !suspended) frames.forEach((record, frame) => syncConsent(frame, record));
    });
    window.addEventListener('pagehide', () => {
        suspended = true;
        frames.forEach((record, frame) => { stopHeartbeat(record); revoke(frame, record); });
    });
    window.addEventListener('pageshow', () => {
        suspended = false;
        scan();
        frames.forEach((record, frame) => syncConsent(frame, record));
    });
    return {api, stopHeartbeat, revoke, syncConsent, receive(frame, record, data) {
            if(data.type==='measurement-context' && data.measurement?.protocol===measurementProtocol) {
                const m=data.measurement.manifest;
                if(!m || !sameMeasurementManifest(m,measurementManifest(m,m.form_link)))return true;
                if(!sameMeasurementManifest(m,record.manifest)){revoke(frame,record);record.manifest=m;}
                syncConsent(frame,record);return true;
            }
            if(data.type==='measurement-activate' || data.type==='analytics') {
                const m=data.measurement;
                if(m?.protocol!==measurementProtocol || !record.lease || Date.now()>=record.lease.until ||
                    m.leaseId!==record.lease.id || !sameMeasurementManifest(m.manifest,record.manifest) || !Number.isSafeInteger(m.generation))return true;
                if(data.type==='measurement-activate') {
                    if(record.lease.generation!==m.generation)record.pageContext=null;
                    record.lease.generation=m.generation;
                    record.channel.send('measurement-ack', {measurement:m});return true;
                }
                if(record.lease.generation!==m.generation)return true;
                if(usesHostDataLayer(frame)) {
                    const payload=measurementDataLayerPayload(data.payload,{embedded:true,pageContext:record.pageContext});if(!payload)return true;
                    if(!payload.event)record.pageContext=payload;
                    window.dataLayer=window.dataLayer||[];
                    if(payload.ecommerce || payload.event==='generate_lead')window.dataLayer.push({ecommerce:null,user_data:null});
                    window.dataLayer.push(payload);
                    // The website shares this retained model. Scope our marker to
                    // this push so later native website events cannot inherit it.
                    window.dataLayer.push({...(['purchase','generate_lead'].includes(payload.event)?{user_data:null}:{}),form_embedded:false});
                }
                return true;
            }
        return false;
    }};
}
