numeric = require('./lib/numeric-1.2.6.js')
Util = require('./util.coffee')

class MDS
    # The "data" are rows, the "dimensions" are columns
    # Matrix has 1 row per "strain", 1 column per "cluster".  Each entry is a boolean
    @pca: (matrix) ->
        # Subtract column-wise mean.
        X = numeric.transpose(
                numeric.transpose(matrix).map( (r) ->
                    mean = 1.0*numeric.sum(r)/r.length
                    numeric.sub(r,mean)
                ))

        svd = @_svd(X)

        # console.log numeric.dot(numeric.dot(svd.U, numeric.diag(svd.S)), numeric.transpose(svd.V))

        # Combine eigenvector and eigenvalues -> transformed X to principal components
        #pts = numeric.dot(svd.U, numeric.diag(svd.S))
        pts = numeric.dot(X, svd.V)

        # pts is the correct re-projection, but we want distance not to be euclidean,
        # but manhattan (easy to interpret as the number of "genes" different between strains)
        # Can't usually do that with SVD, *but* all our dimensions are 0 or 1, so can just
        # square the euclidean distance to get the manhattan.  Or, re-mult by the eigenvalues
        pts = numeric.dot(pts, numeric.diag(svd.S))

        # Not sure the correct thing to return for eigenvalues.  svd.S is the typical choice,
        # but since we are using squared euclidean distance, perhaps we should use svd.S^2?
        {points:pts, eigenvalues: svd.S}  # numeric.mul(svd.S,svd.S)}

    # Wrapper around numeric.svd() to handle when there are less rows than columns
    @_svd: (m) ->
      [nrow,ncol] = numeric.dim(m)
      if nrow >= ncol
          return numeric.svd(m)
      else
          # Compute svd of t(m).  And swap U&V when returning
          r = numeric.svd(numeric.transpose(m))
          [r.U,r.V] = [r.V,r.U]
          return r

    @pca_gene: (mat, gene_range) ->
        t1= new Date

        # Build array of 1 row per strain, 1 column per gene of interest
        matrix = []
        for s in [0...mat.strains().length]
            matrix.push(row = [])
            for g in [gene_range[0] .. gene_range[1]]
                row.push(mat.presence(s,g))
        r = @pca(matrix)
        console.log "SVD took : #{new Date - t1}ms"
        r

    test: () ->
        m = [1..5].map((r) -> [1..15].map((c) -> (r+c)%7 == 0))

        console.log numeric.dim(m)
        console.log MDS.pca(m)



class Distance
    # Calculate a "distance" based on presence/absence of genes
    # Returns an array of array of distances
    # (Used by tree building code)
    @distance: (mat, gene_range) ->
        t1 = new Date
        dist = []
        for s1 in [0...mat.strains().length]
            (dist[s1]||=[])[s1] = 0
            for s2 in [0...s1]
                d = 0
                for g in [gene_range[0] .. gene_range[1]]
                    d += Math.abs(mat.presence(s1,g) - mat.presence(s2,g))
                (dist[s1] ||= [])[s2] = d
                (dist[s2] ||= [])[s1] = d

        # Print as R code!
        #console.log "matrix(c("+dist.map((r) -> ""+r)+"), byrow=T, nrow=#{dist.length}"
        #mat.strains().forEach((s1,i) -> mat.strains().map((s2,j) -> console.log s1,s2,dist[i][j]))
        #console.log mat.strains(),dist[0]
        Util.our_log "Distance took : #{new Date - t1}ms"

        dist

module.exports.MDS = MDS
module.exports.Distance = Distance
