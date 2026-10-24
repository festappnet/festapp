// Locally synthesized feedback: no media downloads, network or speech provider.
export class ScannerFeedback {
    constructor({ AudioContext = globalThis.AudioContext || globalThis.webkitAudioContext } = {}) {
        this.AudioContext=AudioContext;this.enabled=true;this.context=null;
    }
    get ready() { return Boolean(this.enabled && this.context?.state==='running'); }
    async unlock() {
        if(!this.enabled || !this.AudioContext)return;
        try {this.context ||= new this.AudioContext();if(this.context.state!=='running')await this.context.resume();}
        catch { /* The visible sound control remains available for retry. */ }
    }
    play(kind) {
        if(!this.ready)return;
        const notes=kind==='error'?[[220,0,.17],[165,.19,.2]]:kind==='accepted'?[[880,0,.09],[1175,.12,.13]]:[[880,0,.11]];
        for(const [frequency,offset,duration] of notes){
            const oscillator=this.context.createOscillator(),gain=this.context.createGain(),start=this.context.currentTime+offset;
            oscillator.type=kind==='error'?'triangle':'sine';oscillator.frequency.value=frequency;
            gain.gain.setValueAtTime(0,start);gain.gain.linearRampToValueAtTime(.18,start+.008);gain.gain.exponentialRampToValueAtTime(.001,start+duration);
            oscillator.connect(gain);gain.connect(this.context.destination);oscillator.start(start);oscillator.stop(start+duration+.02);
            oscillator.onended=()=>{oscillator.disconnect();gain.disconnect();};
        }
    }
    dispose() {this.context?.close().catch(()=>{});}
}
