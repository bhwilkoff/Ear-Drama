"""R4-9b: the design's detection table, reproduced with the built tool (tools/originality/) in place of fingerprint.py.

    python3 reproduce.py <cache dir> <transcripts.json.gz> <originality index dir> <out.json>
    python3 report.py <out.json>

measure.py is run as it was (same seed, same planted copies, same unrelated scripts); only the `fingerprint`
module it imports is the tool's Index. Features only, never a word of a text.
"""
import os
import runpy
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "..", "tools"))
from originality import index as I  # noqa: E402
from originality import normalize as N  # noqa: E402


class Index(I.Index):
    def __init__(self, d):
        super().__init__(d)
        self.names = [n for p in self.parts for n in p[3]]
        stats = {}
        for src, e in self.man["sources"].items():
            stats.update({f"{src}_docs": e["docs"], f"{src}_words": e["words"], f"{src}_prints": e["prints"]})
        self.meta = {"k": self.k, "w": self.w, "norm": 0, "stats": stats, "seconds": self.man.get("seconds", 0)}


shim = types.ModuleType("fingerprint")
shim.Index, shim.read, shim.gut_body, shim.strip_labels = Index, I.read, N.gut_body, N.strip_labels
sys.modules["fingerprint"] = shim
sys.argv = [os.path.join(HERE, "measure.py")] + sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")
