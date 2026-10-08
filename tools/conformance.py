"""The conformance oracle (design section 15): Python fastcdc 1.7.0 with
zudedup's gear table substituted chunks every input, and xxhsum -H2 hashes
every input and chunk. Called by tools/conformance.R, which compares.

    python conformance.py WORKDIR

WORKDIR holds gear.txt, params.tsv (min, avg, max per line) and inputs/*.
Writes WORKDIR/python-chunks.tsv: input, min, avg, max, offset, length.
"""
import os
import sys

import fastcdc
from fastcdc import fastcdc_py

assert fastcdc.__version__ == "1.7.0", fastcdc.__version__

work = sys.argv[1]
fastcdc_py.GEAR = [int(line, 16) for line in open(os.path.join(work, "gear.txt")).read().split()]
assert len(fastcdc_py.GEAR) == 256

params = [tuple(int(v) for v in line.split("\t"))
          for line in open(os.path.join(work, "params.tsv")).read().splitlines()]
inputs = sorted(os.listdir(os.path.join(work, "inputs")))

with open(os.path.join(work, "python-chunks.tsv"), "w") as out:
    out.write("input\tmin\tavg\tmax\toffset\tlength\n")
    for name in inputs:
        data = open(os.path.join(work, "inputs", name), "rb").read()
        for mi, av, ma in params:
            for c in fastcdc_py.fastcdc_py(data, mi, av, ma):
                out.write(f"{name}\t{mi}\t{av}\t{ma}\t{c.offset}\t{c.length}\n")
