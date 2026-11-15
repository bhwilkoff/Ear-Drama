#!/usr/bin/env bash
# Make the play-phoneme build's environment (Decision 078) at catalog/.venv-phonemes.
#
#     bash catalog/tools/setup_phoneme_env.sh
#
# Python 3.12 (spaCy's wheels), the pinned packages in requirements-phonemes.txt, and g2p_en with
# --no-deps (only its network file is read). Refuses to finish if anything GPL (espeak, phonemizer)
# ended up installed. tools/refresh_play_library.sh runs the phoneme step with this environment's python.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VENV="$HERE/../.venv-phonemes"
if command -v uv >/dev/null 2>&1; then
  uv venv --python 3.12 "$VENV"
  uv pip install --python "$VENV/bin/python" -r "$HERE/requirements-phonemes.txt"
  uv pip install --python "$VENV/bin/python" --no-deps g2p_en==2.1.0
else
  python3.12 -m venv "$VENV"
  "$VENV/bin/pip" install -r "$HERE/requirements-phonemes.txt"
  "$VENV/bin/pip" install --no-deps g2p_en==2.1.0
fi
if "$VENV/bin/python" -c "import importlib.util as u, sys; sys.exit(0 if any(u.find_spec(m) for m in ('phonemizer', 'espeakng_loader')) else 1)"; then
  echo "refused: a GPL eSpeak package is installed in $VENV" >&2
  exit 1
fi
"$VENV/bin/python" -c "import misaki, spacy, en_core_web_sm; print('phoneme env ok: misaki', misaki.__version__ if hasattr(misaki, '__version__') else '0.9.4')"
