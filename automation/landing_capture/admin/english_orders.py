"""Review real sales, edit an internal note, filter and export paid tickets."""
from capture import *
from continuous_form import port,last_fill

def wheel_x(delta):
    script="""const [port,url,delta]=process.argv.slice(1);const t=(await(await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t=>t.url===url);const w=new WebSocket(t.webSocketDebuggerUrl);await new Promise(r=>w.onopen=r);w.send(JSON.stringify({id:1,method:'Input.dispatchMouseEvent',params:{type:'mouseWheel',x:700,y:400,deltaX:Number(delta),deltaY:0}}));await new Promise(r=>setTimeout(r,650));w.close();"""
    subprocess.run(['node','--input-type=module','-e',script,port(),ab('get','url'),str(delta)],check=True)
def record():
    install_pointer();start('orders-overview-en');cue('note-filter-sales-and-export')
    try:
        fill('input:not([aria-label])','Ready for doors');hold(.8)
        ui('Save changes');hold(1)
        wheel_x(-1800);hold(.5)
        ab('mouse','move',550,257);ab('mouse','down');ab('mouse','up');hold(.5)
        # The focused grid filter is a real editable input.
        js('document.activeElement.setAttribute("data-order-filter","true")')
        fill('[data-order-filter=true]','alex');hold(1.2)
        ui('Report','tab');hold(2)
        ui('Tickets','tab');hold(1.4);ui('Download Table');hold(1)
        end()
    finally:result=stop()
    print(json.dumps({'take':result['directory']}))
if __name__=='__main__':record()
