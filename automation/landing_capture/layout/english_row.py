"""Compatibility entrypoint; CS/EN now execute the same original row recipe."""
import os
os.environ['CAPTURE_LOCALE']='en'
from row_ready import record
if __name__=='__main__':record()
