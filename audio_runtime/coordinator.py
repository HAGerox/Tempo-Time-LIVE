"""Live BeatNet+ foreground and eight-second Beat This! final0 review."""
import os
for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','VECLIB_MAXIMUM_THREADS'):
    os.environ[key]='1'
import sys,json,base64,subprocess,select,time,concurrent.futures,collections,threading
from pathlib import Path
import numpy as np
from runtime_paths import review_command
import foreground as worker
from tracking import fit

HISTORY_SECONDS = 8

class ModelProcess:
    def __init__(self):
        self.process=subprocess.Popen(review_command(),
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=sys.stderr,bufsize=0)
        self.pending=b''
        if self.read(90).get('ready') is not True:raise RuntimeError('Background model failed to initialize')
        os.set_blocking(self.process.stdin.fileno(),False)
    def read(self,timeout):
        deadline=time.monotonic()+timeout
        while b'\n' not in self.pending:
            remaining=deadline-time.monotonic()
            if remaining<=0 or not select.select([self.process.stdout],[],[],remaining)[0]:raise TimeoutError('Background model timed out')
            data=os.read(self.process.stdout.fileno(),65536)
            if not data:raise RuntimeError('Background model disconnected')
            self.pending+=data
            if len(self.pending)>1024*1024:raise RuntimeError('Background reply exceeded limit')
        line,self.pending=self.pending.split(b'\n',1)
        result=json.loads(line)
        if 'error' in result:raise RuntimeError(result['error'])
        return result
    def infer(self,pcm,rate,generation,end):
        data=json.dumps({'pcm':base64.b64encode(pcm.astype('<f4',copy=False).tobytes()).decode(),'rate':rate}).encode()+b'\n'
        # Dedicated background thread: pipe writes and inference never block PCM replies.
        view=memoryview(data)
        deadline=time.monotonic()+10
        while len(view):
            remaining=deadline-time.monotonic()
            if remaining<=0 or not select.select([],[self.process.stdin],[],remaining)[1]:raise TimeoutError('Background model input timed out')
            try:count=os.write(self.process.stdin.fileno(),view)
            except BlockingIOError:continue
            view=view[count:]
        return generation,end,self.read(max(.01,deadline-time.monotonic()))
    def stop(self):
        if self.process.poll() is None:self.process.kill()
        self.process.wait()

class LiveDetector:
    def __init__(self):
        self.models=[]
        try:
            self.models.append(ModelProcess())
        except Exception:
            for m in self.models:m.stop()
            raise
        self.pool=concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.futures=[None];self.detector=None;self.generation=0
    def reset(self,rate):
        if not np.isfinite(rate) or not 8000<=rate<=192000:raise ValueError('Invalid sample rate')
        if self.detector:self.detector.reset(rate)
        else:self.detector=worker.SongDetector(rate,'beatnet-plus')
        self.rate=rate;self.frames=0;self.generation+=1
        self.buffer=np.zeros(round(rate*HISTORY_SECONDS),dtype='float32');self.used=0;self.write=0
        self.next_jobs=[float(HISTORY_SECONDS)]
        self.latest=None;self.last_period=None;self.stable=0
        return {'ready':True,'frameOffsetSeconds':.04,'backgroundReview':True}
    def review(self,end,result):
        b=[t+end-HISTORY_SECONDS for t in result['beats']];w=result['strengths']
        # Same unhinted candidate order as the benchmark's flexible selector.
        candidates=[]
        for score,bb,ww in [(.1,b,w),(0,b[::2],w[::2]),(0,b[1::2],w[1::2])]:
            candidate=fit(bb,ww,True)
            if candidate:candidates.append((score,candidate))
        chosen=max(candidates,key=lambda v:v[0])[1] if candidates else None
        p=chosen['period'] if chosen else None
        self.stable=self.stable+1 if p and self.last_period and abs(np.log2(p/self.last_period))<.06 else (1 if p else 0)
        self.last_period=p
        self.latest=dict(chosen,id=end) if chosen and self.stable>=2 and chosen['quality']>=.55 else None
    def process(self,pcm):
        result=self.detector.process(pcm);self.frames+=len(pcm);end=self.frames/self.rate
        size=len(self.buffer);n=len(pcm)
        if n>=size:self.buffer[:]=pcm[-size:];self.write=0;self.used=size
        else:
            first=min(n,size-self.write);self.buffer[self.write:self.write+first]=pcm[:first]
            self.buffer[:n-first]=pcm[first:];self.write=(self.write+n)%size;self.used=min(size,self.used+n)
        if result['silent'] or result['reset']:
            self.generation+=1;self.used=0;self.latest=None;self.stable=0;self.last_period=None
            self.next_jobs=[end+HISTORY_SECONDS]
        # Consume completed reviews; reject results from an old stream generation.
        for i in (0,):
            future=self.futures[i]
            if future and future.done():
                self.futures[i]=None
                gen,at,value=future.result()
                if gen==self.generation:
                    self.review(at,value)
        if self.used==size:
            history=None
            for i,interval in [(0,1.)]:
                if self.futures[i] is None and end>=self.next_jobs[i]:
                    if history is None:history=np.concatenate((self.buffer[self.write:],self.buffer[:self.write]))
                    self.futures[i]=self.pool.submit(self.models[i].infer,history,self.rate,self.generation,end)
                    self.next_jobs[i]=end+interval
        review=self.latest
        if review and end-review['beat']>review['period']*3+.08:review=None
        result['review']=review
        return result
    def stop(self):
        for m in self.models:m.stop()
        self.pool.shutdown(wait=True,cancel_futures=True)

def main():
    detector=None
    try:
        for line in sys.stdin:
            r=json.loads(line)
            if 'rate' in r:
                if detector is None:detector=LiveDetector()
                response=detector.reset(float(r['rate']))
            else:
                if detector is None:raise ValueError('No stream initialized')
                pcm=np.frombuffer(base64.b64decode(r['pcm'],validate=True),dtype='<f4')
                if len(pcm)>65536 or not np.isfinite(pcm).all():raise ValueError('Invalid PCM')
                response=detector.process(pcm)
            print(json.dumps(response,allow_nan=False),flush=True)
    except Exception as error:
        print(json.dumps({'error':str(error)}),flush=True)
        return 1
    finally:
        if detector:detector.stop()
    return 0

if __name__=='__main__':sys.exit(main())
