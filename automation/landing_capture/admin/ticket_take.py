from capture import *
port=os.environ["CAPTURE_CDP_PORT"]
def drag(*coords):
 subprocess.run(['node',str(Path(os.environ["PRODUCT_DEMO_SKILL"])/"scripts/gesture-cdp.mjs"),port,ab('get','url'),*map(str,coords)],check=True)
start('ticket-drag-'+os.environ.get('CAPTURE_LOCALE','cs'));cue('before');hold(1.2)
cue('title-drag');drag(590,540,590,505);hold(1.2)
cue('name-drag');drag(435,650,435,620);hold(.8)
cue('qr-drag');drag(1002,551,1032,520);hold(1.2)
ab('mouse','move',1100,800);ab('mouse','down');ab('mouse','up');cue('result');end();print(stop()['directory'])
ab('screenshot',str(OUT/'ticket-drag-final.png'))
