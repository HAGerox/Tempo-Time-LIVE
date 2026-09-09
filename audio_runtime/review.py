"""Persistent background model process; JSON/PCM input, no device ownership."""
import os
for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','VECLIB_MAXIMUM_THREADS','TF_NUM_INTRAOP_THREADS','TF_NUM_INTEROP_THREADS'):
    os.environ[key]='1'
os.environ['TF_CPP_MIN_LOG_LEVEL']='2'
import sys,json,base64,threading,time
from pathlib import Path
import numpy as np

# The native service may terminate the coordinator immediately on shutdown.
# Do not leave model runtimes orphaned when that happens.
parent=os.getppid()
def watch_parent():
    while True:
        time.sleep(.5)
        if os.getppid()!=parent:os._exit(0)
threading.Thread(target=watch_parent,daemon=True).start()

from runtime_paths import model_path
import torch
from beat_this.inference import Audio2Frames
from beat_this.model.postprocessor import Postprocessor
torch.set_num_threads(1)
model=Audio2Frames(str(model_path('beat-this-final0.ckpt')))
post=Postprocessor(type='minimal')
model(np.zeros(8*22050,dtype='float32'),22050)
print(json.dumps({'ready':True}),flush=True)
for line in sys.stdin:
    try:
        r=json.loads(line);x=np.frombuffer(base64.b64decode(r['pcm'],validate=True),dtype='<f4')
        rate=float(r['rate'])
        if not np.isfinite(rate) or not 8000<=rate<=192000 or len(x)>rate*8+1 or not np.isfinite(x).all():raise ValueError('Invalid history window')
        logits,down=model(x.copy(),rate);beats,_=post(logits,down)
        p=torch.sigmoid(logits).numpy();duration=len(x)/rate
        beats=[float(t) for t in beats if .12<=t<=duration-.12]
        result={'beats':beats,'strengths':[float(p[min(len(p)-1,round(t*50))]) for t in beats]}
        print(json.dumps(result,allow_nan=False),flush=True)
    except Exception as error:
        print(json.dumps({'error':str(error)}),flush=True)
        sys.exit(1)
