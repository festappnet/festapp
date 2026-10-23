"""Camera consumes a fixture stream rendered from the actual purchased PDF QR.

This is the real scanner decoder, lookup and online admission path. No decoder,
network response or application state is replaced. The owned headless Chrome
must be launched with its documented PDF-derived fake video device.
"""
from capture import *
def record():
    install_pointer();start('check-in-qr-en');cue('camera-qr-and-online-admission')
    try:
        ab('find','role','button','click','--name','Start camera','--exact');hold(2)
        ab('find','role','button','click','--name','Confirm admission','--exact');hold(1.2)
        end()
    finally:result=stop()
    print(json.dumps({'take':result['directory']}))
if __name__=='__main__':record()
