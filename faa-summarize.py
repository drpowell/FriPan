#!/usr/bin/env python

# This script reads a bunch of fasta files (*.faa) and produces a json file of the gene names and lengths
# Usage:  faa-summarize.py *.faa > pan.json

import sys,re, json

if len(sys.argv)==1:
    sys.stderr.write("Usage: %s <fasta files>\n"%sys.argv[0])
    sys.exit(1)

result = {}
sys.stderr.write("Reading files : "+" ".join(sys.argv[1:])+"\n") 
for fname in sys.argv[1:]:
    strain = []
    with open(fname) as f:
        gene = None
        for l in f:
            m = re.match('^>(\S+)\s+(.*)', l)
            if m:
                if gene is not None:
                    strain.append(gene)
                gene = {'name': m.group(1), 'desc': m.group(2), 'length': 0}
            else:
                # Part of the sequence, increment the length
                if gene is not None:
                    gene['length'] += len(l.rstrip('*\n'))
        if gene is not None:
            strain.append(gene)

    result[fname] = strain

print json.dumps({'gene_order':result})
