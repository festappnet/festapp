"""Select real available seats in the English customer picker at 430x900."""
from capture import *
def click(x,y):
    ab('mouse','move',x,y);hold(.35);ab('mouse','down');ab('mouse','up');hold(.8)
def record():
    install_pointer();start('seat-select-en');cue('choose-two-seats-and-review')
    try:
        click(58,296);click(83,296);hold(1)
        click(215,862);hold(1.5);end()
    finally:result=stop()
    print(json.dumps({'take':result['directory']}))
if __name__=='__main__':record()
