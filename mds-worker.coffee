
importScripts('lib/numeric-1.2.6.js')
importScripts('mds-plot.js')
importScripts('gene-matrix.js')

@onmessage = (ev) ->
    if ev.data.init?
        console.log "WORKER: Initialized!"
        @matrix = GeneMatrix.from_hash(ev.data.init)
    else if ev.data.data?
        range = ev.data.data
        console.log "WORKER: #{range}"
        comp = MDS.pca(@matrix, range)
        comp = numeric.transpose(comp)
        postMessage(comp)
