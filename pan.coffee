
# block width and heightl, one block per gene per species
bw = 1
bh = 10

class Pan
    brushed: (brush) ->
        #x.domain(if brush.empty() then x2.domain() else brush.extent())
        # focus.select("path").attr("d", area)
        #focus.select(".x.axis").call(xAxis)
        ex = brush.extent()
        diff = ex[1] - ex[0]
        if diff==0
            # Reset to full zoom
            @reset_scale()
        else if diff > 1  # only sane scaling please
            sc = (@width / diff)
            #console.log "brushed", brush.extent(), diff, "scale=", sc, "width", width
            @set_scale(ex[0], sc)


    # should the x-translate NOT be scaled?
    set_scale: (pos,sc) ->
        if !pos?
            pos = @last_pos
            sc = @last_sc

        @last_pos = pos
        @last_sc = sc
        @svg.selectAll(".scale").attr("transform","translate(#{-pos*sc},0)
                                                   scale(#{sc},#{@vscale})")
        @svg.selectAll(".label-scale").attr("transform", "scale(1,#{@vscale})")

    reset_scale: () ->
        @set_scale(0,@width/(bw*@matrix.genes().length))

    detail: () ->
        [x,y] = d3.mouse(@focus.node())
        # convert from screen coordinates to matrix coordinates
        row = Math.round(y/bh)
        col = Math.round(x/bw)
        strain_id = @matrix.strain_pos_to_id(row)
        return if !strain_id?

        strain = @matrix.strains()[strain_id]
        gene = @matrix.genes()[col]
        p = @matrix.presence(strain_id,col)
        gene_name_pri = @matrix.gene_name(col)
        gene_name_strain = @matrix.strain_gene_name(strain_id,col)
    #    $('#info').text("Strain:#{strain}  Gene:#{gene.name}  present:#{p}")
        @tooltip.style("display", "block") # un-hide it (display: none <=> block)
               .style("left", (d3.event.pageX) + "px")
               .style("top", (d3.event.pageY) + "px")
               .select("#tooltip-text")
                   .html("<b>Strain:</b> #{strain.name}<br/><b>Gene:</b> #{gene_name_pri}</br><b>Gene from strain:</b> #{gene_name_strain}<br/><b>Present:</b> #{p}")

    create_elems: () ->
        tot_width = $(@elem).width()
        tot_height = bh * @matrix.strains().length + 200
        margin = {top: 150, right: 10, bottom: 10, left: 140}
        margin2 = {top: 50, right: margin.right, bottom: tot_height - 100, left: margin.left}
        @width = tot_width - margin.left - margin.right
        @height = tot_height - margin.top - margin.bottom
        @height2 = tot_height - margin2.top - margin2.bottom

        @x2 = d3.scale.linear().range([0, @width])

        #x2.domain([0,2846])
        @xAxis2 = d3.svg.axis().scale(@x2).orient("bottom")

        brush = d3.svg.brush()
        brush.x(@x2)
             .on("brush", () => @brushed(brush))

        # should tot_width here be width?
        @svg = d3.select(@elem).append("svg")
            .attr("width", tot_width)
            .attr("height", tot_height)

        # Add a clip rectangle to keep the area inside
        @svg.append("svg:defs")
           .append("svg:clipPath")
            .attr("id", "circle1")  # what is circle1?
           .append('rect')
            .attr('width', @width)
            .attr('height',@height)
            .attr('x', 0)
            .attr('y', 0)

        # set up SVG for gene content pane

        @focus = @svg.append("g")
                     .attr("clip-path", "url(#circle1)")
                     .attr("transform", "translate(#{margin.left},#{margin.top})")
                   .append("g")
                     .attr("transform","translate(0,0)scale(1,1)")
                     .attr("class", "scale")
                     .on("mousemove", () => @detail())
                     .on("mouseout", () => @tooltip.style("display", "none"))


        # set up SVG for brush selection
        @context = @svg.append("g")
            .attr( "transform", "translate(#{margin2.left},#{margin2.top})" );

        # Create - @mini a <g> to hold the small plot
        # FIXME.  Factor out this scaling.  width should be like "set scale full".  Heightt should depend on number of strains
        @mini = @context.append("g")
                        .attr("class", "minimap")
                        .attr("transform","translate(0,0)
                                           scale(#{@width/(bw*@matrix.genes().length)},
                                           #{@height2/(bh*@matrix.strains().length)})")

        @context.append("g")
            .attr("class", "x axis")
            .attr("transform", "translate(0,#{@height2})")
            .call(@xAxis2)

        @context.append("g")
            .attr("class", "x brush")
            .call(brush)
          .selectAll("rect")
            .attr("y", -6)
            .attr("height", @height2 + 7)

        # set up label area
        @labels = @svg.append("g")
                       .attr("transform", "translate(#{margin.left-10},#{margin.top})")
                      .append("g")
                       .attr('class','label-scale')
                       .attr("transform", "scale(1,#{@vscale})")

        # set tooltip object
        @tooltip = d3.select("#tooltip")

    # Collapse the 'off' regions in a set of boxes with x and len
    collapse_off: (strain_id) ->
        res = []
        last_p=1
        @matrix.genes().forEach((g) =>
            p = @matrix.presence(strain_id,g.id)
            if !p
                if last_p
                    res.push({x:g.id, len: 0})
                res[res.length-1].len += 1
            last_p = p
        )
        res

    # Draw the per-gene 'on/off' boxes
    draw_boxes: (elem) ->
        row = elem.selectAll('g.gene-row')
                  .data(@matrix.strains(), (s) -> s.id)
        row.exit().remove()
        # Create a <g> to hold each row
        ngs = row.enter()
                  .append('g')
                   .attr('class',(s) -> "gene-row strain-#{s.id}")
                   .on('click', (s) => @matrix.set_first(s.id) ; @redraw())
        # Each row has a <rect> for 'on'
        ngs.append('rect')
                   .attr('class','on')
                   .attr('width', bw*@matrix.genes().length)
                   .attr('height',bh-1)
        # Then a bunch of <rect> for collapsed 'off'
        ngs.selectAll('rect.off')
            .data((s) => @collapse_off(s.id))
            .enter().append('rect')
                    .attr('class','off')
                    .attr('height',bh-1)
                    .attr('x', (p) -> p.x)
                    .attr('width', (p) -> bw*p.len)

        row.transition()
           .attr('transform', (s) -> "translate(0,#{s.pos * bh})")

    # Draw the strain labels
    draw_labels: (elem) ->
        lbls = elem.selectAll('text.label')
                   .data(@matrix.strains(), (s) -> s.id)
        lbls.enter()
            .append('text')
             .attr('class','label')
             .attr('text-anchor','end')
             .text((s) -> s.name)
             .on('click', (s) => @matrix.set_first(s.id) ; @redraw())
             .on("mouseover", (s) -> d3.selectAll(".strain-#{s.id}").classed({'highlight':true}))
             .on("mouseout", (s) -> d3.selectAll(".strain-#{s.id}").classed({'highlight':false}))
        lbls.transition()
            .attr('y', (s) -> (s.pos+1)*bh-1)   # i+1 as TEXT is from baseline not top
        # TODO: set font size to be same as row height?

    redraw: () ->
        @draw_boxes(@mini)

        @draw_boxes(@focus)
        @draw_labels(@labels)

    draw_chart: () ->
        @x2.domain([0, @matrix.genes().length])

        #xAxis2.tickFormat((d) -> genes[d])
        @context.select(".x.axis").call(@xAxis2)

        @redraw()

        # commence completely zoomed out
        @reset_scale()

    constructor: (@elem, @matrix) ->
        @vscale = 1.0
        @create_elems()
        @draw_chart()

        $('#vscale input').on('keyup', (e) =>
            str = $(e.target).val()
            val = parseFloat(str)
            if val>0 && val<2
                @vscale = val
                @set_scale()
        )

    # Resize.  Just redraw everything!
    # TODO : Would be nice to maintain current brush on resize
    resize: () ->
        @svg.remove()
        @create_elems()
        @draw_chart()

class GeneMatrix
    # strains - array of strain objects.  Should have 'name'
    # genes - array of gene objects.  Should have 'name'
    # values - 2d array, 1 row per strain. 1 col per gene.  value should be null
    #          for not-present.  Otherwise may use a per-gene name
    constructor: (@_strains, @_genes, @_values) ->
        # Give both genes and strains ids.
        @_strains.forEach((s,i) -> s.id = s.pos = i)
        @_genes.forEach((g,i) -> g.id = i)
        @_build_by_pos()

    # Sort the strains by position order into a local array @_pos
    # @_pos indexed by position, returns strain_id
    _build_by_pos: () ->
        @_pos = @_strains.map((s) -> s.pos)
        @_pos.sort((a,b) -> a-b)

    # Return array of strains ordered by id
    strains: () ->
        @_strains

    # Return strain_id for the given strain_pos
    strain_pos_to_id: (pos) -> @_pos[pos]

    genes: () ->
        @_genes

    presence: (strain_id, gene_id) ->
        @_values[strain_id][gene_id]?

    strain_gene_name: (strain_id, gene_id) ->
        @_values[strain_id][gene_id]

    # Find a name for the gene - searching by "pos" (ie. from the top)
    gene_name: (gene_id) ->
        for idx in @_pos
            n = @strain_gene_name(idx,gene_id)
            return n if n?
        "not found"

    # Set the given strain id to be first in the list
    set_first: (strain_id) ->
        idx = @_pos.indexOf(strain_id)
        @_pos.splice(idx, 1)         # Remove it from the list
        @_pos.splice(0,0, strain_id) # And put it on the front
        @_pos.forEach((s_id, idx) => @_strains[s_id].pos = idx) # Now re-pos the strains

# Load a Torsty home-brew .CSV ortholog file
# This needs to be deprecated, not sure how I generated it!

parse_csv = (csv) ->
    strains = []
    values = []
    genes = []
    i=0
    for row in csv
        i += 1
        if i==1
            genes = d3.keys(row).map((g) -> {name:g, desc: row[g]})
            continue
        val_row = []
        values.push(val_row)
        j=0
        for k,v of row
            if k==''
                strains.push({name:v})
                continue
            j+=1
            p = parseInt(v)
            val_row.push(if p==0 then null else true)
    new GeneMatrix(strains,genes,values)


# Load a ProteinOrtho5 output file
# Please use -singles option to ensure singleton clusters are included!
# http://www.bioinf.uni-leipzig.de/Software/proteinortho/

parse_proteinortho = (tsv) ->
    strains = []
    values = []
    genes = []
    i=0
    for row in tsv
        i += 1
        if i==1
            strains = d3.keys(row)[3..] # skip first 3 junk columns
                        .map((s) -> {name: s})
            console.log "STRAINS: #{strains}"
        genes.push( {name:"cluster#{i}", desc:""} )
        values.push( strains.map( (s) -> if row[s.name]=='*' then null else row[s.name]) )

    new GeneMatrix( strains, genes, d3.transpose(values) )


# Load an OrthoMCL 1.4 output file  (2.0 not supported)
# (does not output singleton clusters)
# http://orthomcl.org/common/downloads/software/v2.0/

parse_orthomcl = (tsv) ->
    # FIXME


# main()

init = () ->

    $('.by').mouseover(() -> $('.gravatar').show())
    $('.by').mouseout(() -> $('.gravatar').hide())

#    d3.csv("pan.csv", (data) ->
    d3.tsv("pan.proteinortho", (data) ->
        matrix = parse_proteinortho(data)

        console.log "Features : ",matrix.genes()
        console.log "Strains : ",matrix.strains()

        d3.select("#topinfo")
            .html("Loaded #{matrix.strains().length} strains and #{matrix.genes().length} ortholog clusters")


        pan = new Pan('#chart', matrix)

        $( window ).resize(() -> pan.resize())
    )

$(document).ready(() -> init() )
