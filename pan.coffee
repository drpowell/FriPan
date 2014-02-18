
strains = []
genes = []
descs = []
values = []

bw = 1
bh = 5


margin = margin2 = width = height = height2 = x = x2 = y = y2 = null
svg = focus = context = xAxis = xAxis2 = yAxis = brush = tooltip = null

brushed = () ->
    #x.domain(if brush.empty() then x2.domain() else brush.extent())
    # focus.select("path").attr("d", area)
    #focus.select(".x.axis").call(xAxis)
    ex = brush.extent()
    diff = ex[1] - ex[0]
    sc = (width / diff)
    console.log "brushed", brush.extent(), diff, sc
    set_scale(ex[0], sc)


set_scale = (pos,sc) ->
  svg.selectAll(".scale").attr("transform","translate(#{-pos*sc},0)scale(#{sc},1)")

detail = () ->
    [x,y] = d3.mouse(focus.node())
    strain = strains[Math.round(y/bh)]
    gene = genes[Math.round(x)]
    desc = descs[Math.round(x)]
    p = values[Math.round(y/bh)][Math.round(x)]
    $('#info').text("Strain:#{strain}  Gene:#{gene}  present:#{p}")
    tooltip.style("display", "block") # un-hide it (was display: none)
           .style("left", (d3.event.pageX) + "px")
           .style("top", (d3.event.pageY) + "px")
           .select("#tooltip-text")
               .html("Strain:#{strain}<br/>Gene:#{gene}</br>Product:#{desc}<br/>present:#{p}")

create_elems = () ->
    tot_width = 1200
    tot_height = 600
    margin = {top: 150, right: 10, bottom: 10, left: 40}
    margin2 = {top: 10, right: 10, bottom: 500, left: 40}
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

    svg = d3.select("#chart").append("svg")
        .attr("width", tot_width)
        .attr("height", tot_height)

    # Add a clip rectangle to keep the area inside
    svg.append("svg:defs")
       .append("svg:clipPath")
        .attr("id", "circle1")
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

    focus = svg.append("g")
                 .attr("clip-path", "url(#circle1)")
                 .attr("transform", "translate(" + margin.left + "," + margin.top + ")")
               .append("g")
                 .attr("transform","translate(0,0)scale(0.3,1)")
                 .attr("class", "scale")
                 .on("mousemove", () -> detail())
                 .on("mouseout", () -> tooltip.style("display", "none"))


    context = svg.append("g")
        .attr("transform", "translate(" + margin2.left + "," + margin2.top + ")");

    context.append("g")
        .attr("class", "x axis")
        .attr("transform", "translate(0," + height2 + ")")
        .call(xAxis2)

    context.append("g")
        .attr("class", "x brush")
        .call(brush)
      .selectAll("rect")
        .attr("y", -6)
        .attr("height", height2 + 7)

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

        x.domain([0, genes.length])
        x2.domain([0, genes.length])

        #xAxis2.tickFormat((d) -> genes[d])
        context.select(".x.axis").call(xAxis2)


        focus.append('rect')
            .attr('width', bw*genes.length)
            .attr('height',bh*strains.length)
            .attr('x', 0)
            .attr('y', 0)
            .attr('fill', 'blue')

        for i in [0 ... strains.length]
            last_j = null
            for j in [0 ... genes.length]
                p = values[i][j]
                if p==1
                    if last_j
                        tot+=1
                        focus.append('rect')
                           .attr('width',  (j-last_j)*bw)
                           .attr('height', bh)
                           .attr('x',last_j*bw)
                           .attr('y',i*bh)
                           .attr('fill', 'white')
                           #.attr('opacity', 1-p)
                        last_j = null
                    continue
                if !last_j
                    last_j=j

            if last_j
                tot+=1
                focus.append('rect')
                   .attr('width',  (j-last_j)*bw)
                   .attr('height', bh)
                   .attr('x',last_j*bw)
                   .attr('y',i*bh)
                   .attr('fill', 'white')
                   #.attr('opacity', 1-p)
        console.log tot
    )


$(document).ready(() -> init() )