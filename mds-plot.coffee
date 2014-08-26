
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
            .attr("x", 8+@width)
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
        @opts.tot_height ||= 160
        margin = {top: 20, right: 5, bottom: 30, left: 45}
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
                   .ticks(5)
                   .tickFormat(d3.format("%"))

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
             .attr("x", @width/2 - 14)
             .attr("y", -10)
             .style("text-anchor", "middle")
             .text("Variance percentage by MDS dimension")

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
             .text("Variance percentage")

        @svg.selectAll(".bar")
            .data(data)
            .enter().append("rect")
              .attr("class", "bar")
              .attr("x", (d) => @x(d.lbl))
              .attr("width", @x.rangeBand())
              .attr("y", (d) => @y(d.val))
              .attr("height", (d) => @height - @y(d.val))
              .on('click', (d) => if @opts.click? then @opts.click(d))

@ScatterPlot = ScatterPlot
@BarGraph = BarGraph
