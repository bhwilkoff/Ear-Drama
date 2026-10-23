/**
 * The microphone tap (WEB-DESIGN §4.10): copies the input's first channel to
 * the page in blocks of 1,024 frames and outputs silence, so the microphone
 * is never heard in the performer's headphones and never reaches a speaker.
 */
class EdCapture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.block = new Float32Array(1024);
    this.filled = 0;
  }

  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (ch) {
      let i = 0;
      while (i < ch.length) {
        const n = Math.min(ch.length - i, this.block.length - this.filled);
        this.block.set(ch.subarray(i, i + n), this.filled);
        this.filled += n;
        i += n;
        if (this.filled === this.block.length) {
          this.port.postMessage(this.block, [this.block.buffer]);
          this.block = new Float32Array(1024);
          this.filled = 0;
        }
      }
    }
    return true;
  }
}

registerProcessor('ed-capture', EdCapture);
