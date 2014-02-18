
strains = []
genes = []
descs = []
values = []

# block width and heightl, one block per gene per species
bw = 1
bh = 10
bcolouron = "green"
bcolouroff = "lightgray"

margin = margin2 = width = height = height2 = x = x2 = y = y2 = null
svg = focus = context = labels = xAxis = xAxis2 = yAxis = brush = tooltip = null

brushed = () ->
    #x.domain(if brush.empty() then x2.domain() else brush.extent())
    # focus.select("path").attr("d", area)
    #focus.select(".x.axis").call(xAxis)
    ex = brush.extent()
    diff = ex[1] - ex[0]
    if diff==0
        # Reset to full zoom
        set_scale(0, width/(bw*genes.length))
    else if diff > 1  # only sane scaling please
        sc = (width / diff)
        #console.log "brushed", brush.extent(), diff, "scale=", sc, "width", width
        set_scale(ex[0], sc)


# should the x-translate NOT be scaled?
set_scale = (pos,sc) ->
  svg.selectAll(".scale").attr("transform","translate(#{-pos*sc},0) scale(#{sc},1)")


detail = () ->
    [x,y] = d3.mouse(focus.node())
    # convert from screen coordinates to matrix coordinates
    row = Math.round(y/bh)
    col = Math.round(x/bw)  # dave didn't have /bw here -- because it was set to 1 ?
    strain = strains[row]
    gene = genes[col]
    desc = descs[col]
    p = values[row][col]
#    $('#info').text("Strain:#{strain}  Gene:#{gene}  present:#{p}")
    tooltip.style("display", "block") # un-hide it (display: none <=> block)
           .style("left", (d3.event.pageX) + "px")
           .style("top", (d3.event.pageY) + "px")
           .select("#tooltip-text")
               .html("Strain:#{strain}<br/>Gene:#{gene}</br>Product:#{desc}<br/>present:#{p}")


create_elems = () ->
    tot_width = 1200
    tot_height = 800
    margin = {top: 150, right: 10, bottom: 10, left: 140}
    margin2 = {top: 10, right: margin.right, bottom: 700, left: margin.left}
    width = tot_width - margin.left - margin.right
    height = tot_height - margin.top - margin.bottom
    height2 = tot_height - margin2.top - margin2.bottom

    x = d3.scale.linear().range([0, width])
    x2 = d3.scale.linear().range([0, width])
    y = d3.scale.linear().range([height, 0])
    y2 = d3.scale.linear().range([height2, 0])

    #x2.domain([0,2846])
    xAxis2 = d3.svg.axis().scale(x2).orient("bottom")

    brush = d3.svg.brush()
        .x(x2)
        .on("brush", brushed);

    # should tot_width here be width?
    svg = d3.select("#chart").append("svg")
        .attr("width", tot_width)
        .attr("height", tot_height)

    # Add a clip rectangle to keep the area inside
    svg.append("svg:defs")
       .append("svg:clipPath")
        .attr("id", "circle1")  # what is circle1?
       .append('rect')
        .attr('width', width)
        .attr('height',height)
        .attr('x', 0)
        .attr('y', 0)

    # svg.append("defs").append("clipPath")
    #     .attr("id", "clip")
    #   .append("rect")
    #     .attr("width", width)
    #     .attr("height", height);


    # set up SVG for gene content pane

    focus = svg.append("g")
                 .attr("clip-path", "url(#circle1)")
                 .attr("transform", "translate(#{margin.left},#{margin.top})")
               .append("g")
                 .attr("transform","translate(0,0)scale(0.3,1)")   # what is 0.3 here?
                 .attr("class", "scale")
                 .on("mousemove", () -> detail())
                 .on("mouseout", () -> tooltip.style("display", "none"))

    # set up SVG for brush selection

    context = svg.append("g")
        .attr( "transform", "translate(#{margin2.left},#{margin2.top})" );

    context.append("g")
        .attr("class", "x axis")
        .attr("transform", "translate(0,#{height2})")
        .call(xAxis2)

    context.append("g")
        .attr("class", "x brush")
        .call(brush)
      .selectAll("rect")
        .attr("y", -6)
        .attr("height", height2 + 7)

    # set up label area
    
    labels = svg.append("g")
         .attr("transform", "translate(0,#{margin.top})")
         .attr("width", margin.left)
         .attr("height", height)

    # set tooltip global variable
    tooltip = d3.select("#tooltip")
    window.tooltip = tooltip


init = () ->
    create_elems()

    $('.by').mouseover(() -> $('.gravatar').show())
    $('.by').mouseout(() -> $('.gravatar').hide())

    i=0
    d3.csv("pan.csv", (data) ->
        strains = []
        values = []
        for row in data
            i += 1
            if i==1
                genes = d3.keys(row)
                descs = d3.values(row)
                continue
            val_row = []
            values.push(val_row)
            j=0
            for k,v of row
                if k==''
                    strains.push(v)
                    continue
                j+=1
                p = parseInt(v)
                val_row.push(p)

        tot=0
        console.log "Features : ",genes
        console.log "Strains : ",strains

        d3.select("#topinfo")
            .html("Loaded #{strains.length} strains and #{genes.length} ortholog clusters")

        x.domain([0, genes.length])
        x2.domain([0, genes.length])

        #xAxis2.tickFormat((d) -> genes[d])
        context.select(".x.axis").call(xAxis2)

        for i in [0 ... strains.length]

	    # draw big rectangle first, then blank out missing genes
            focus.append('rect')
                .attr('width', bw*genes.length)
                .attr('height',bh-1)
                .attr('x', 0)
                .attr('y', i*bh)
                .attr('fill', bcolouron)

            # draw strain labels
            labels.append('text')
                .text(strains[i])
                .attr('x', 0)
                .attr('y', (i+1)*bh-1)   # i+1 as TEXT is from baseline not top
            # TODO: set font size to be same as row height?
            # TODO: right-align the text?

            # paint where the gene is ABSENT      
            last_j = null
            for j in [0 ... genes.length]
                p = values[i][j]
                if p==1
                    if last_j
                        tot+=1
                        focus.append('rect')
                           .attr('width',  (j-last_j)*bw)
                           .attr('height', bh-1)
                           .attr('x',last_j*bw)
                           .attr('y',i*bh)
                           .attr('fill', bcolouroff)
                           #.attr('opacity', 1-p)
                        last_j = null
                    continue
                if !last_j
                    last_j=j

            if last_j
                tot+=1
                focus.append('rect')
                   .attr('width',  (j-last_j)*bw)
                   .attr('height', bh-1)
                   .attr('x',last_j*bw)
                   .attr('y',i*bh)
                   .attr('fill', bcolouroff)
                   #.attr('opacity', 1-p)
        console.log tot

        # commence completely zoomed out
        set_scale(0, width/(bw*genes.length))
    )


$(document).ready(() -> init() )
