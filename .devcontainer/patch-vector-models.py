#!/usr/bin/env python3
"""Patch /exist/etc/conf.xml vector-models registry (workload experiments)."""
from pathlib import Path
import re
import sys

p = Path('/exist/etc/conf.xml')
text = p.read_text()
bak = Path('/exist/etc/conf.xml.bak-workload')
if not bak.exists():
    bak.write_text(text)
    print('backed up conf.xml')

new = '''   <vector-models>
      <model id="all-MiniLM-L6-v2"
             path="onnx-models/all-MiniLM-L6-v2"
             dimension="384"/>
      <model id="all-MiniLM-L12-v2"
             path="onnx-models/all-MiniLM-L12-v2"
             dimension="384"/>
      <model id="paraphrase-multilingual-MiniLM-L12-v2"
             path="onnx-models/paraphrase-multilingual-MiniLM-L12-v2"
             dimension="384"/>
      <model id="all-mpnet-base-v2"
             path="onnx-models/all-mpnet-base-v2"
             dimension="768"/>
   </vector-models>'''

pat = re.compile(r'<vector-models>[\s\S]*?</vector-models>(?=\s*</exist>)')
matches = list(pat.finditer(text))
print('blocks_before_</exist>:', len(matches))
if not matches:
    sys.exit('no vector-models block found before </exist>')
last = matches[-1]
text2 = text[:last.start()] + new + text[last.end():]
p.write_text(text2)
print('patched')
# verify
print('--- tail ---')
print(Path('/exist/etc/conf.xml').read_text()[last.start():last.start() + len(new) + 20])
