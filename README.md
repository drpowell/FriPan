# FriPan

### Introduction
FriPan is a web-based tool for exploring the pan-genome of multiple bacterial genomes. FriPan does not perform the ortholog clustering itself, but it can import data from ProteinOrtho5, OrthoMCL or a native CSV format. Each isolate/strain is a row, and there is a columnar position for each gene cluster. You can zoom/scroll through the pan-proteome, and hover over sections to see a description of the gene. 

### Installation
Ensure you have CoffeeScript >= 1.4 installed:

    npm install -g coffee-script


Then, run a test server and coffeescript compiler:

    ./server.sh &
    coffee -w -c .
    
Or just put it in your public_html folder if you are running Apache already.

### Input file
An example CSV input file is provided called "pan.csv"

### Authors
* David Powell
* Torsten Seemann

### Source
* Github: https://github.com/Victorian-Bioinformatics-Consortium/FriPan
* Website: http://www.vicbioinformatics.com/software.fripan.shtml
