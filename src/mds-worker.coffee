
# importScripts('util.js')
# importScripts('lib/numeric-1.2.6.js')
# importScripts('mds.js')
# importScripts('gene-matrix.js')

Util = require('./util.coffee')
MDS = require('./mds.coffee')
GeneMatrix = require('./gene-matrix.coffee')

process = (ev) ->
    #console.log ev.data
    if ev.data.init?
        #console.log "WORKER: Initialized!"
        @matrix = GeneMatrix.from_hash(ev.data.init)
    else if ev.data.msg?
        msg = ev.data.msg
        if msg.mds?
            range = msg.mds
            #our_log "WORKER: #{range}"
            comp = MDS.MDS.pca_gene(@matrix, range)
            postMessage(comp)
        else if msg.dist?
            range = msg.dist
            #our_log "WORKER: #{range}"
            dist_arr = MDS.Distance.distance(@matrix, range)
            postMessage(dist_arr)
        else
            Util.our_log "WORKER:  Unknown method:",msg
    else
        Util.our_log "WORKER:  Unknown message:",ev.data

module.exports =  (self) ->
    self.addEventListener('message',(ev) -> process(ev))
