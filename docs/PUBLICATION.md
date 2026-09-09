# Publication review

The public repository begins with a reviewed source snapshot. Experimental
branch history, recordings, benchmark datasets/results, caches, development
installers, session checkpoints and private audit logs are excluded.

Manual review covers application/runtime source, adapters, build scripts,
workflows and permissions, dependency/model provenance, documentation, icons,
screenshots and initial commit metadata. The app has no upload/telemetry path;
only build preparation downloads model weights, with pinned SHA-256 checks.
Public metadata uses the GitHub noreply identity. Required upstream author and
copyright attributions are retained.

Automated checks include `scripts/audit-publication.py`, Gitleaks over the
publication snapshot and Git history, npm audit, cargo audit and pip-audit over
both Python environment lockfiles. The bundle check also rejects embedded local
home paths and unused madmom pretrained models. Private scan reports stay in
ignored local build directories.

For the initial release, npm and the review runtime report no known
vulnerabilities. The foreground runtime uses an updated PyTorch. Its setuptools
80.9 compatibility pin has advisory PYSEC-2026-3447 concerning Unicode exclusion
patterns when building source distributions. This app does not build source
distributions or run user-provided packaging manifests. RustSec reports upstream
maintenance warnings for proc-macro-error/UNIC and a glib iterator warning in the
cross-platform lockfile; glib is not in the macOS runtime dependency graph.
These findings are documented rather than described as a completely clean audit.

The app's original code is MIT. BeatNet/BeatNet+ attribution and CC BY 4.0 terms
are included; BeatNet+ redistribution relies on the app author's confirmation
from its maintainer. Beat This! code/model MIT and madmom source BSD notices are
included. Unused madmom model data and its separate model licence are excluded.
Other dependency notices are generated from pinned installed packages, with
upstream copies only where a required licence is absent from package archives.
