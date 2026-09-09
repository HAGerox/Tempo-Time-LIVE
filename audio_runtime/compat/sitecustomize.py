# Build-time compatibility for PyInstaller's madmom discovery subprocess.
import collections
import collections.abc
collections.MutableSequence = collections.abc.MutableSequence
import numpy as np
np.float = float
np.int = int
np.complex = complex
