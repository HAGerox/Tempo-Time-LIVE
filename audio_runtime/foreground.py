"""Selected-channel PCM adapter for BeatNet+ non-percussive inference and particle filtering.
No microphone ownership, file loading, playback, or network access here.
"""
import os
os.environ.setdefault('MPLBACKEND', 'Agg')
import collections
import collections.abc
# madmom 0.16.1 compatibility with Python 3.11 / NumPy 1.26.
collections.MutableSequence = collections.abc.MutableSequence
import numpy as np
np.float = float
np.int = int
np.complex = complex
import base64
import json
from pathlib import Path
import sys
import torch
import soxr
from runtime_paths import model_path, vendor_path
sys.path.insert(0,str(vendor_path()))
from BeatNet.particle_filtering_cascade import particle_filter_cascade

torch.set_num_threads(1)
torch.set_num_interop_threads(1)

class SongDetector:
    def __init__(self, rate, variant="beatnet-plus"):
        self.variant = variant
        if variant != 'beatnet-plus':raise ValueError('Tempo Time LIVE uses BeatNet+')
        from BeatNetPlus.model import BeatNetPlusBranch
        from BeatNetPlus.log_spect import LOG_SPECT as PlusFeatures
        self.model = BeatNetPlusBranch(288, 150, 4, 'cpu')
        self.feature_type = PlusFeatures
        self.win_length = 1764
        self.frame_offset = self.win_length - 2 * 441
        self.model.load_state_dict(torch.load(model_path('beatnet-plus-af.pt'), map_location='cpu', weights_only=True))
        self.model.eval()
        self.reset(rate)

    @torch.inference_mode()
    def reset(self, rate):
        self.model.hidden.zero_()
        self.model.cell.zero_()
        self.features = self.feature_type(sample_rate=22050, win_length=self.win_length, hop_size=441, n_bands=[24], mode='stream')
        self.decoder = particle_filter_cascade(beats_per_bar=[], fps=50, plot=[], mode='online')
        self.resampler = soxr.ResampleStream(rate, 22050, 1, dtype='float32')
        self.pending = np.empty(0, dtype=np.float32)
        self.window = np.zeros(self.win_length + 2 * 441, dtype=np.float32)
        self.frames = 0
        self.quiet = 0

    def process(self, pcm):
        self.pending = np.concatenate((self.pending, self.resampler.resample_chunk(pcm)))
        beats = []
        strengths = []
        reset = False
        with torch.inference_mode():
            while len(self.pending) >= 441:
                hop, self.pending = self.pending[:441], self.pending[441:]
                self.window[:-441] = self.window[441:]
                self.window[-441:] = hop
                self.quiet = self.quiet + 1 if np.max(np.abs(hop)) < 0.001 else 0
                pred = np.zeros((1, 2))
                if self.frames >= 5 and self.quiet < 5:
                    feats = self.features.process_audio(self.window).T[-1].copy()
                    logits = self.model(torch.from_numpy(feats)[None, None])[0]
                    probs = torch.softmax(logits, dim=0)
                    pred = probs.numpy()[:2].T
                # Do not emit recurrent-model afterimages during silence.
                if self.quiet >= 5:
                    pred[:] = 0
                if self.quiet == 20:
                    # Forget the previous song, without reloading model weights or
                    # changing the absolute resampled audio timeline.
                    self.model.hidden.zero_()
                    self.model.cell.zero_()
                    self.decoder = particle_filter_cascade(beats_per_bar=[], fps=50, plot=[], mode='online')
                    self.decoder.counter = self.frames - 1
                    self.features = self.feature_type(sample_rate=22050, win_length=self.win_length, hop_size=441, n_bands=[24], mode='stream')
                    self.window.fill(0)
                    beats.clear()
                    strengths.clear()
                    reset = True
                previous = self.decoder.path[-1, 0]
                # Keep particle weights defined even during digital silence.
                path = self.decoder.process(np.maximum(pred, 1e-6))
                fresh = [float(t) for t in path[:, 0] if t > previous]
                beats.extend(fresh)
                strengths.extend([float(np.max(pred))] * len(fresh))
                # The upstream decoder only needs its most recent beat; bound history.
                self.decoder.path = self.decoder.path[-1:]
                self.frames += 1
        return {'beats': beats, 'strengths': strengths, 'silent': self.quiet >= 20, 'reset': reset}

def main(variant="beatnet-plus"):
    detector = None
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if 'rate' in request:
                if detector is None:
                    detector = SongDetector(float(request['rate']), variant)
                else:
                    detector.reset(float(request['rate']))
                response = {'ready': True, 'frameOffsetSeconds': detector.frame_offset / 22050}
            else:
                pcm = np.frombuffer(base64.b64decode(request['pcm'], validate=True), dtype='<f4')
                if detector is None or len(pcm) > 65536 or not np.isfinite(pcm).all():
                    raise ValueError('Invalid PCM block')
                response = detector.process(pcm)
            print(json.dumps(response), flush=True)
        except Exception as error:
            print(json.dumps({'error': str(error)}), flush=True)
            return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
