import jsQR from 'jsqr';
import { decodeQRCodes } from './scanner_codes.js';

// Decode one transferred frame at a time, outside the interactive UI thread.
self.onmessage = ({ data: { pixels, width, height } }) => {
    self.postMessage({ codes: decodeQRCodes(pixels, width, height, jsQR) });
};
