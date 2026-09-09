"""Resolve bundled resources independently of the working directory and PATH."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def model_path(name):
    base = Path(sys._MEIPASS) / 'models' if getattr(sys, 'frozen', False) else ROOT / '.build/live-models'
    path = base / name
    if not path.is_file():
        raise FileNotFoundError(f'Required bundled model is missing: {name}')
    return path


def vendor_path():
    return Path(sys._MEIPASS) if getattr(sys, 'frozen', False) else Path(__file__).parent / 'vendor'


def review_command():
    if getattr(sys, 'frozen', False):
        return [str(Path(sys.executable).parent.parent / 'tempo-review/tempo-review')]
    return [str(ROOT / '.build/live-review-venv/bin/python'), str(ROOT / 'audio_runtime/review.py')]
