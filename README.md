# FriPan

Interactive visualization of bacterial pan-genomes

## Introduction

<img align="right" width="20%" src="fripan.png">
FriPan is a web-based tool for exploring the pan-genome of multiple
bacterial genomes.  FriPan does not perform the ortholog clustering itself,
but it can import data from ProteinOrtho5 output files.  Each isolate/strain
is a row, and there is a columnar position for each gene cluster.  You can
zoom/scroll through the pan-proteome, and hover over sections to see a
description of the gene.

## Installation

Ensure you have `npm` installed:
```
brew install npm          # MacOS
sudo apt-get install npm  # Debian/Ubuntu
sudo yum install npm      # Redhat/Centos
```

Install the code and build:
```
git clone https://github.com/drpowell/FriPan
cd FriPan
npm install
make compile
```

Run the demo code locally using our Python-based server in `server.sh`:
```
./server.sh
firefox http://localhost:8030/pan.html
```

Or make it publicly accessible using your `public_html` if your server is 
already running Apache:

```
# will put in $HOME/public_html/fripan by default, type 'make help' to see options
make install
firefox http://localhost/~user/fripan/pan.html
```
    
## Input files

An example set of input files with the stem `test` is provided:

1. `test.proteinortho`
2. `test.descriptions`
3. `test.strains`

### XXX.proteinortho

This is the gene presence/absence matrix in TSV format.
Each row is a gene ortholog cluster, and each column in a strain.  
Each cell in the matrix is gene ID, or `*` if none.
Paralogs are CSV within the cell. The first 3 columns are unused,
but you must use **the exact** names as below.

```
# Species   Genes   Alg.-Conn.   USA300    TW20      JKD6159
3           3       1            USA_001   TW20_001  JKD_001  
3           4       1            USA_002   TW20_002  JKD_002,JKD_004
2           2       1            USA_003   *         JKD_003 
1           1       1            USA_004   *         *
```

### XXX.descriptions

This maps gene IDs from the strain columns, in 2-column TSV format.

```
USA_001	      DNA replication protein
USA_002       hypothetical protein
USA_003       gyrase A
USA_004       alcohol dehydrogenase (EC:1.1.1.1)
TW20_001      DNA replication protein
TW20_002      unknown protein
JKD_001       DNA replication protein, dnaA
JKD_002       hypothetical protein
JKD_003       gyrase
JKD_004       hypothetical protein
```

### XXX.strains

This a multi-column TSV format. The first `ID` column links it with
the strains in the other two files. The remainign columns can be used
for colouring and ordering within the application.

```
ID        ST     Phenotype     Country    Colour
USA300    239    resistant     US         blue
TW20        2    suspectible   UK         green
JKD6159   239    resistant     AU         red
```

## Viewing multiple pan genomes

The included example input files all start with the stem/prefix `test`.
You can add as many pan-genomes to the fripan folder as you like,
just give each of them a different stem, say `mypop`. Then you just
append `?mypop` to the URL, so it looks like 
`http://example.com/~user/fripan/pan.html?mypop`.

## Development

While developing code, it is useful to enable coffee in "watch" mode and with source maps.  Run the following:
```
make debug
```

## Issues

Report feedback, suggestions and bugs on the [Issues page](https://github.com/drpowell/FriPan/issues)

## Source

* Github: https://github.com/drpowell/FriPan
* Website: http://drpowell.github.io/FriPan/

## Authors

* [David Powell](https://twitter.com/d_r_powell)
* [Torsten Seemann](https://twitter.com/torstenseemann)

