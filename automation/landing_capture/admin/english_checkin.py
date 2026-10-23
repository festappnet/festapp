"""Online admission using the actual code printed in the generated English PDF."""
from capture import *
def record():
    install_pointer();start('check-in-en');cue('ticket-code-lookup-and-online-confirmation')
    try:
        fill('input[name=symbol]','X12X7G6I4E')
        ab('find','role','button','click','--name','Look up','--exact');hold(1.4)
        # Fresh rendered button only appears after the server validates the ticket.
        ab('find','role','button','click','--name','Confirm admission','--exact');hold(1.4)
        end()
    finally:result=stop()
    print(json.dumps({'take':result['directory']}))
if __name__=='__main__':record()
