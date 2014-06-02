

init = () ->
    d3.tsv("mtcars.tab", (data) ->
    #d3.tsv("USA-arrests.tab", (data) ->
        # Make a distance array
        keys = d3.keys(data[0])
        dist = {}
        d3.zip(keys, data).forEach(([k, row]) ->
            for k2, d of row
                (dist[k]||={})[k2] = +d
        )

        tree = new TreeBuilder(dist)
        new Dendrogram({elem: '#dendrogram'}).draw(tree, ()->"")
    )

$(document).ready(() -> init() )



#     require(graphics)
#
#     hc <- hclust(dist(USArrests), "ave")
#     plot(hc)