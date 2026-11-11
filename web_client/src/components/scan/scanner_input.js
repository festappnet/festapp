import { decodeQRCodes } from './scanner_codes.js';
export const receptionPayload = value => typeof value === 'string' && value.trim().length <= 160 && /^festapp-login:v1:[1-9][0-9]*:[A-Za-z0-9_-]{40,80}$/.test(value.trim()) ? value.trim() : null;
export class ScannerInput {
    constructor(onCode, {accepts=()=>true,continuous=false,onError=()=>{}}={}) { this.onError=onError;this.continuous=continuous;this.onCode = onCode;this.accepts=accepts;this.suppressedCodes=new Set(); this.paused = false; this.suppressed = null; this.facing = 'environment'; this.generation=0; }
    async start(video) {
        this.stop(); const generation=this.generation; this.paused = false; this.video = video;
        if (!navigator.mediaDevices?.getUserMedia) throw new Error('camera_unavailable');
        try {
            const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: this.facing }, width:{ideal:1920}, height:{ideal:1080}, frameRate:{ideal:30,max:30} }, audio: false });
            if(generation!==this.generation){stream.getTracks().forEach(t=>t.stop());return;}
            this.stream=stream;
            const track=stream.getVideoTracks?.()[0];
            try {
                if(track?.getCapabilities?.().focusMode?.includes('continuous'))await track.applyConstraints({advanced:[{focusMode:'continuous'}]});
            } catch { /* Optional lens controls must not block camera access. */ }
            if(generation!==this.generation)return;
            video.srcObject = this.stream; video.muted = true; video.playsInline = true; await video.play();
            if (generation!==this.generation || !this.stream) return;
            this.decode=decodeQRCodes;
            this.canvas = document.createElement('canvas'); this.context = this.canvas.getContext('2d', { willReadFrequently: true });
            if (typeof Worker === 'function') {
                try {
                    const worker = new Worker(new URL('./scanner_decoder_worker.js', import.meta.url), { type: 'module' });
                    this.decoderWorker = worker;
                    worker.onmessage = ({ data }) => {
                        if (generation!==this.generation || this.decoderWorker!==worker) return;
                        this.decodingFrame=false;
                        if(data.error){worker.terminate();this.decoderWorker=null;return;}
                        if(!this.paused)this.dispatchCodes(data.codes);
                    };
                    worker.onerror = event => {
                        event.preventDefault?.();
                        if (generation!==this.generation || this.decoderWorker!==worker) return;
                        worker.terminate();this.decoderWorker=null;this.decodingFrame=false;
                    };
                } catch { /* The already-loaded local decoder remains available. */ }
            }
            if (generation!==this.generation || !this.stream) return;
            this.timer = setInterval(() => this.frame(), 100);
        } catch (e) { if(generation!==this.generation)return;this.stop(); throw new Error(e.name === 'NotAllowedError' ? 'camera_denied' : 'camera_unavailable'); }
    }
    frame() {
        if (this.paused || this.decodingFrame || !this.video?.videoWidth || (!this.decoderWorker && !this.decode)) return;
        const w = Math.min(1920, this.video.videoWidth), h = Math.round(this.video.videoHeight * w / this.video.videoWidth);
        this.canvas.width = w; this.canvas.height = h; this.context.drawImage(this.video, 0, 0, w, h);
        const pixels = this.context.getImageData(0, 0, w, h);
        if (this.decoderWorker) {
            this.decodingFrame=true;
            this.decoderWorker.postMessage({pixels:pixels.data,width:w,height:h},[pixels.data.buffer]);
        } else {
            const generation=this.generation;
            this.decodingFrame=true;
            return Promise.resolve(this.decode(pixels.data,w,h)).then(codes=>{
                if(generation!==this.generation)return;
                this.decodingFrame=false;if(!this.paused)this.dispatchCodes(codes);
            }).catch(()=>{if(generation===this.generation){this.stop();this.onError('camera_unavailable');}});
        }
    }
    dispatchCodes(codes) {
        if (this.paused) return;
        const visible=new Set(codes.map(c=>c.value));
        for(const value of this.suppressedCodes)if(!visible.has(value))this.suppressedCodes.delete(value);
        const fresh=codes.find(c=>!this.suppressedCodes.has(c.value) && this.accepts(c.value));
        if(fresh)this.accept(fresh.value);
    }
    accept(value) { if (this.paused || !value?.trim() || !this.accepts(value.trim()) || this.suppressedCodes.has(value.trim())) return; this.paused = !this.continuous; this.suppress(value);this.onCode(value.trim()); }
    suppress(value) { if(typeof value==='string' && value.trim()){this.suppressed=value.trim();this.suppressedCodes.add(value.trim());} }
    allowSame() { this.suppressed = null;this.suppressedCodes.clear(); }
    pause({ keepStream=false }={}) { this.paused = true;if(!keepStream)this.stop(); }
    async switchCamera() { const paused=this.paused;this.facing = this.facing === 'environment' ? 'user' : 'environment'; await this.start(this.video);this.paused=paused; }
    async torch() {
        const track = this.stream?.getVideoTracks()[0];
        if (track?.getCapabilities?.().torch) { this.torchOn = !this.torchOn; await track.applyConstraints({ advanced: [{ torch: this.torchOn }] }); }
    }
    stop() { this.generation++; clearInterval(this.timer); this.decoderWorker?.terminate();this.decoderWorker=null;this.decodingFrame=false;this.decode=null; this.stream?.getTracks().forEach(t => t.stop()); this.stream = null; }
    dispose() { this.stop(); this.onCode = () => {}; }
}
