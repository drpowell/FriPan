
# Calculate a MDS (classic) from a distnace matrix
class MDS

    # Calculate a "distance" based on presence/absence of genes
    # Returns an array of array of distances
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
        our_log "Distance took : #{new Date - t1}ms"

        dist


    @pca: (mat, gene_range) ->
        t1= new Date
        matrix = []
        for s in [0...mat.strains().length]
            matrix.push(row = [])
            for g in [gene_range[0] .. gene_range[1]]
                row.push(mat.presence(s,g))

        # We expect 1 row per sample.  Each column is a different gene
        # Subtract column-wise mean (need zero-mean for PCA).
        X = numeric.transpose(numeric.transpose(matrix).map((r) -> mean = 1.0*numeric.sum(r)/r.length; numeric.sub(r,mean)))
        #console.log("matrix",matrix,"X",X)

        sigma = numeric.dot(X,numeric.transpose(X))
        svd = numeric.svd(sigma)
        r = numeric.dot(svd.V, numeric.diag(svd.S))   # No sqrt - means we are using manhattan distance(?)
        #r = numeric.dot(svd.V, numeric.sqrt(numeric.diag(svd.S)))
        our_log "SVD took : #{new Date - t1}ms"
        r


    @cmdscale: (dist) ->
        dist = numeric.pow(dist, 2)        # , done by cmdscale!
        # Function to mean center the rows
        centre = (mat) -> mat.map((r) -> m=numeric.sum(r)/r.length ; numeric.sub(r,m))

        # row and col center matrix
        c = centre(numeric.transpose(centre(dist)))
        c = numeric.neg( numeric.div(c,2) )              # Not sure why, done by cmdscale
        t1 = new Date
        eig = numeric.eig(c)
        our_log "eig took : #{new Date - t1}ms"
        order = [0...c.length]
        #order.sort((a,b) -> eig.lambda.x[b] - eig.lambda.x[a])  # FIXME - we're not selecting the largest eigenvalues!
        ev = order.map((i) -> eig.lambda.x[i])
        evec = order.map((i) -> eig.E.x[i])
        #console.log ev

        dim = (idx) ->
            numeric.mul(numeric.transpose(evec)[idx], Math.sqrt(ev[idx]))

        {xs: dim(0), ys: dim(1) }


# Very simple scatter plot
class ScatterPlot
    constructor: (@opts) ->
        @opts.elem     ?= 'svg'
        @opts.width    ?= 500
        @opts.height   ?= 400
        @opts.left     ?= 100
        @opts.right    ?= 100
        @opts.callback = {}
        ['click','mouseover','mousemove','mouseout','brush'].forEach((s) =>
            @opts.callback[s] = @opts[s])

        margin = {top: 20, right: @opts.right, bottom: 40, left: @opts.left}
        @width =  @opts.width - margin.left - margin.right
        @height = @opts.height - margin.top - margin.bottom

        @x = d3.scale.linear()
               .range([0, @width])

        @y = d3.scale.linear()
               .range([@height, 0])

        @color = d3.scale.category10()

        @xAxis = d3.svg.axis()
                   .scale(@x)
                   .orient("bottom")

        @yAxis = d3.svg.axis()
                   .scale(@y)
                   .orient("left");

        div = d3.select(@opts.elem).append("div")
                .style(
                    width: (@width + margin.left + margin.right)+"px"
                    height: (@height + margin.top + margin.bottom)+"px")
                .attr("class","mds-scatter")
        @svg = div.append("svg")
                 .attr("width", @width + margin.left + margin.right)
                 .attr("height", @height + margin.top + margin.bottom)
                 .attr("class","main")
                .append("g")
                 .attr("transform", "translate(" + margin.left + "," + margin.top + ")")

        # Create an SVG "overlay" layer.  Only drawn on for highlighting to show stuff on top
        @svg_overlay = div.append('svg')
                 .attr("width", @width + margin.left + margin.right)
                 .attr("height", @height + margin.top + margin.bottom)
                 .attr("class","overlay")
                .append("g")
                 .attr("transform", "translate(" + margin.left + "," + margin.top + ")")

        gBrush = @svg.append('g')
        @mybrush = d3.svg.brush()
                     .x(@x)
                     .y(@y)
                     .clamp([false,false])
                     .on("brush",  () => @_brushed())
        gBrush.call(@mybrush)

    _brushed: () ->
        sel = @_selected()
        @_event('brush', sel)

    _selected: () ->
        if @mybrush.empty()
            null
        else
            ex = @mybrush.extent()
            sel = @locs.filter((d) -> d.x>=ex[0][0] && d.x<=ex[1][0] && d.y>=ex[0][1] && d.y<=ex[1][1])
            sel.map((d) -> d.item)


    # draw(data,labels)
    #   data - array of rows.  First row is all x-coordinates (dimension 1)
    #                          Second row is all y-coordinates (dimension 2)
    #   labels - array of samples.  sample.name, and (sample.parent for colouring)
    draw: (data, labels, dims) ->
        [dim1,dim2] = dims
        @x.domain(d3.extent(data[dim1]))
        @y.domain(d3.extent(data[dim2]))

        # Easier to plot with array of
        locs = d3.transpose(data)

        @svg.selectAll(".axis").remove()
        @svg.append("g")
            .attr("class", "x axis")
            .attr("transform", "translate(0," + @height + ")")
            .call(@xAxis)
          .append("text")
            .attr("class", "label")
            .attr("x", 5+@width)
            .attr("y", 10)
            .style("text-anchor", "start")
            .text("Dim #{dim1+1}");

        @svg.append("g")
            .attr("class", "y axis")
            .call(@yAxis)
          .append("text")
            .attr("class", "label")
            .attr("transform", "rotate(-90)")
            .attr("y", 6)
            .attr("dy", ".71em")
            .style("text-anchor", "end")
            .text("Dim #{dim2+1}");

        dots = @svg.selectAll(".dot")
                   .data(locs)
        dots.exit().remove()

        # Create the dots and labels
        dot_g = dots.enter().append("g")
                    .attr('class', (d,i) -> "dot strain-#{i}")
        dot_g.append("rect")
             .attr("width",80)
             .attr("height",13)
             .attr('x',-3)
             .attr('y',-3-10)
             .attr('rx',5)
             .attr('ry',5)
        dot_g.append("circle")
             .attr('class', (d,i) -> "strain-#{i}")
             .attr("r", 3.5)
             .attr("cx",0)
             .attr("cy",0)
             .on("click", (_,i)     => @_event('click',labels[i]))
             .on("mouseover", (_,i) => @_event('mouseover',labels[i]))
             .on("mouseout", (_,i)  => @_event('mouseout',labels[i]))
             #.style("fill", (d,i) => @color(labels[i].parent))
        dot_g.append("text")
             .attr('class', (d,i) -> "labels strain-#{i}")
             .text((d,i) -> labels[i].name)
             .attr('x',3)
             .attr('y',-3)
             .on("click", (_,i)     => @_event('click',labels[i]))
             .on("mouseover", (_,i) => @_event('mouseover',labels[i]))
             .on("mouseout", (_,i)  => @_event('mouseout',labels[i]))
             #.style("fill", (d,i) => @color(labels[i]))

        # Position the dots
        dots.transition()
            .duration(10)
            .attr("transform", (d) => "translate(#{@x(d[dim1])},#{@y(d[dim2])})")

        # Record the dot positions (needed for the brush)
        @locs = locs.map((d,i) => {x: d[dim1], y: d[dim2], item: labels[i]})

    highlight: (cls) ->
        elem = @svg.select(".dot.#{cls}")
        @svg_overlay[0][0].appendChild(elem[0][0].cloneNode(true))

    unhighlight: () ->
        @svg_overlay.html('')



    _event: (typ, arg) ->
        if @opts.callback[typ]
            @opts.callback[typ](arg)


class BarGraph
    constructor: (@opts) ->
        @opts.tot_width  ||= 200
        @opts.tot_height ||= 150
        margin = {top: 20, right: 10, bottom: 30, left: 40}
        @width = @opts.tot_width - margin.left - margin.right
        @height = @opts.tot_height - margin.top - margin.bottom

        @x = d3.scale.ordinal()
               .rangeRoundBands([0, @width], .1)

        @y = d3.scale.linear()
               .range([@height, 0])

        @xAxis = d3.svg.axis()
                   .scale(@x)
                   .orient("bottom")
                   .tickSize(8,1)

        @yAxis = d3.svg.axis()
                   .scale(@y)
                   .orient("left")
                   .tickSize(8,1)

        @svg = d3.select(@opts.elem).append("svg")
                 .attr('class','bar-chart')
                 .attr("width", @width + margin.left + margin.right)
                 .attr("height", @height + margin.top + margin.bottom)
                .append("g")
                 .attr("transform", "translate(" + margin.left + "," + margin.top + ")")
    draw: (data) ->
        @svg.selectAll("*").remove()
        @x.domain(data.map((d) -> d.lbl ))
        @y.domain([0, d3.max(data, (d) -> d.val)])

        @svg.append("text")
             .attr('class', 'title')
             .attr("x", @width/2)
             .attr("y", -10)
             .style("text-anchor", "middle")
             .text("Magnitude of each MDS dimension")

        @svg.append("g")
             .attr("class", "x axis")
             .attr("transform", "translate(0," + @height + ")")
             .call(@xAxis)
            .append("text")
             .attr('class', 'label')
             .attr("x", @width/2)
             .attr("y", 30)
             .style("text-anchor", "middle")
             .text("Dimension")

        @svg.append("g")
             .attr("class", "y axis")
             .call(@yAxis)
           .append("text")
             .attr('class', 'label')
             .attr("transform", "rotate(-90)")
             .attr("x", -10)
             .attr("y", -33)
             .style("text-anchor", "end")
             .text("Magnitude")

        @svg.selectAll(".bar")
            .data(data)
            .enter().append("rect")
              .attr("class", "bar")
              .attr("x", (d) => @x(d.lbl))
              .attr("width", @x.rangeBand())
              .attr("y", (d) => @y(d.val))
              .attr("height", (d) => @height - @y(d.val))
              .on('click', (d) => if @opts.click? then @opts.click(d))

@MDS = MDS
@ScatterPlot = ScatterPlot
@BarGraph = BarGraph
