import { decodeQRCodes } from './scanner_codes.js';
export const receptionPayload = value => typeof value === 'string' && value.trim().length <= 160 && /^festapp-login:v1:[1-9][0-9]*:[A-Za-z0-9_-]{40,80}$/.test(value.trim()) ? value.trim() : null;
export class ScannerInput {
    constructor(onCode, {onCodes=null,continuous=false}={}) { this.continuous=continuous;this.onCode = onCode;this.onCodes=onCodes;this.suppressedCodes=new Set(); this.paused = false; this.suppressed = null; this.facing = 'environment'; this.generation=0; }
    async start(video) {
        this.stop(); const generation=this.generation; this.paused = false; this.video = video;
        if (!navigator.mediaDevices?.getUserMedia) throw new Error('camera_unavailable');
        try {
            const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: this.facing } }, audio: false });
            if(generation!==this.generation){stream.getTracks().forEach(t=>t.stop());return;}
            this.stream=stream;
            video.srcObject = this.stream; video.muted = true; video.playsInline = true; await video.play();
            const { default: jsQR } = await import('jsqr');
            if (!this.stream) return;
            this.decode = jsQR; this.canvas = document.createElement('canvas'); this.context = this.canvas.getContext('2d', { willReadFrequently: true });
            this.timer = setInterval(() => this.frame(), 180);
        } catch (e) { this.stop(); throw new Error(e.name === 'NotAllowedError' ? 'camera_denied' : 'camera_unavailable'); }
    }
    frame() {
        if (this.paused || !this.video?.videoWidth) return;
        const w = Math.min(960, this.video.videoWidth), h = Math.round(this.video.videoHeight * w / this.video.videoWidth);
        this.canvas.width = w; this.canvas.height = h; this.context.drawImage(this.video, 0, 0, w, h);
        const pixels = this.context.getImageData(0, 0, w, h);
        const codes=decodeQRCodes(pixels.data,w,h,this.decode);
        const visible=new Set(codes.map(c=>c.value));
        for(const value of this.suppressedCodes)if(!visible.has(value))this.suppressedCodes.delete(value);
        const fresh=codes.filter(c=>!this.suppressedCodes.has(c.value)).map(c=>c.value);
        if(!fresh.length)return;
        if(this.onCodes && fresh.length>1){
            this.paused=!this.continuous;fresh.forEach(value=>this.suppressedCodes.add(value));this.onCodes(fresh);
        }else this.accept(fresh[0]);
    }
    accept(value) { if (this.paused || !value?.trim() || (this.continuous && this.suppressedCodes.has(value.trim()))) return; this.paused = !this.continuous; this.suppressed = value.trim();this.suppressedCodes.add(value.trim());this.onCode(value.trim()); }
    allowSame() { this.suppressed = null;this.suppressedCodes.clear(); }
    pause({ keepStream=false }={}) { this.paused = true;if(!keepStream)this.stop(); }
    async switchCamera() { const paused=this.paused;this.facing = this.facing === 'environment' ? 'user' : 'environment'; await this.start(this.video);this.paused=paused; }
    async torch() {
        const track = this.stream?.getVideoTracks()[0];
        if (track?.getCapabilities?.().torch) { this.torchOn = !this.torchOn; await track.applyConstraints({ advanced: [{ torch: this.torchOn }] }); }
    }
    stop() { this.generation++; clearInterval(this.timer); this.stream?.getTracks().forEach(t => t.stop()); this.stream = null; }
    dispose() { this.stop(); this.onCode = () => {}; }
}
