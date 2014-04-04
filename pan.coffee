
# A worker that will only compute new values if the web worker is not busy
# and the parameters have changed
class LatestWorker
    constructor: (@worker, @get_current_data) ->
        @dispatch = d3.dispatch("updated")
        @_computing = 0
        @_last_data = null
        @worker.addEventListener('message', (ev) => @done(ev.data))

    on: (t,func) ->
        @dispatch.on(t, func)

    update: () ->
        if !@_computing
            cur_data = @get_current_data()
            if cur_data != @_last_data
                @_computing = 1
                @_last_data = cur_data
                console.log "Sending worker:", cur_data
                @worker.postMessage(data: cur_data)

    done: (res) ->
        console.log "Received results"
        @_computing = 0
        @dispatch.updated(res)

# MDSHandler takes "update" events and sends them to the 'LatestWorker'
# It dispatches "redraw" events when the the computation is done
class MDSHandler
    constructor: (@matrix) ->
        @dispatch = d3.dispatch("redraw")
        @_current_range = null
        worker = new Worker('mds-worker.js')
        worker.postMessage(init: @matrix.as_hash())
        @latest_worker = new LatestWorker(worker, () => @_current_range)
        @latest_worker.on('updated', (comp) => @redraw(comp))

    on: (t,func) ->
        @dispatch.on(t, func)

    update: (range) ->
        ngenes = @matrix.genes().length
        range = [0, ngenes-1] if !range?
        range = [Math.floor(range[0]), Math.min(Math.ceil(range[1]), ngenes-1)]
        @_current_range = range
        #console.log "drawing",range
        @latest_worker.update()

    redraw: (comp) ->
        @dispatch.redraw(comp)

        # Callback to reorder rows
        window.clearTimeout(@background_runner)
        @background_runner = window.setTimeout(() =>
            ids = @matrix.strains().map((s) -> s.id)
            ids.sort((a,b) -> comp[0][a] - comp[0][b])
            @matrix.set_order(ids)
        ,1000)

        # cmdscale is slow, do it in a callback
        # window.clearTimeout(@background_runner)
        # @background_runner = window.setTimeout(() =>
        #     $('#mds-thinking').show()
        #     $('#mds').css('opacity','0.3')
        #     window.setTimeout(() =>
        #         mds = MDS.cmdscale(MDS.distance(@matrix, range))
        #         @scatter.draw([mds.xs,mds.ys], @matrix.strains(), [0,1])
        #         $('#mds-thinking').hide()
        #         $('#mds').css('opacity','1.0')

        #         ids = @matrix.strains().map((s) -> s.id)
        #         ids.sort((a,b) -> mds.xs[a] - mds.xs[b])
        #         @matrix.set_order(ids)
        #         @redraw()
        #     ,0)
        # ,1000)



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
            @mds.update(null)
        else if diff > 1  # only sane scaling please
            sc = (@width / diff)
            #console.log "brushed", brush.extent(), diff, "scale=", sc, "width", width
            @set_scale(ex[0], sc)
            @mds.update(ex)

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
        $('g.gene-sep').toggle(sc>4)  # Hide the gene separator lines when zoomed out

    reset_scale: () ->
        @set_scale(0,@width/(@bw*@matrix.genes().length))

    detail_off: () ->
        @tooltip.style("display", "none")
        @unhighlight()

    detail: () ->
        [x,y] = d3.mouse(@focus.node())
        # convert from screen coordinates to matrix coordinates
        row = Math.floor(y/@bh)
        col = Math.floor(x/@bw)
        strain_id = @matrix.strain_pos_to_id(row)
        return if !strain_id?

        strain = @matrix.strains()[strain_id]
        @unhighlight()
        @highlight(strain)
        gene = @matrix.genes()[col]
        p = @matrix.presence(strain_id,col)
        gene_name_pri = @matrix.gene_name(col)
        gene_name_strain = @matrix.strain_gene_name(strain_id,col)
        desc_pri = @matrix.get_desc_non_hypot(col)
        desc = @matrix.get_desc(gene_name_strain)
        @tooltip.style("display", "block") # un-hide it (display: none <=> block)
               .style("left", (d3.event.pageX) + "px")
               .style("top", (d3.event.pageY) + "px")
               .select("#tooltip-text")
                   .html("<b>Strain:</b> #{strain.name}<br/><b>Gene:</b> #{gene_name_pri}</br><b>Gene from strain:</b> #{gene_name_strain}<br/><b>Present:</b> #{p}<br/><b>Desc (pri):</b> #{desc_pri}<br/><b>Desc:</b> #{desc}")

    create_elems: () ->
        tot_width = $(@elem).width()
        tot_height = @bh * @matrix.strains().length + 200
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
            .attr("id", "draw-region")
           .append('rect')
            .attr('width', @width)
            .attr('height',@height)
            .attr('x', 0)
            .attr('y', 0)

        # set up SVG for gene content pane

        main = @svg.append("g")
                     .attr("clip-path", "url(#draw-region)")
                     .attr("transform", "translate(#{margin.left},#{margin.top})")
        @focus = main.append("g")
                     .attr("transform","translate(0,0)scale(1,1)")
                     .attr("class", "scale")
                     .on("mousemove", () => @detail())
                     .on("mouseout", () => @detail_off())

        # set up SVG for brush selection
        @context = @svg.append("g")
            .attr( "transform", "translate(#{margin2.left},#{margin2.top})" );

        # Create - @mini a <g> to hold the small plot
        # FIXME.  Factor out this scaling.  width should be like "set scale full".  Heightt should depend on number of strains
        @mini = @context.append("g")
                        .attr("class", "minimap")
                        .attr("transform","translate(0,0)
                                           scale(#{@width/(@bw*@matrix.genes().length)},
                                           #{@height2/(@bh*@matrix.strains().length)})")

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
                   .on('click', (s) => @matrix.set_first(s.id))
        # Each row has a <rect> for 'on'
        ngs.append('rect')
                   .attr('class','on')
                   .attr('width', @bw*@matrix.genes().length)
                   .attr('height',@bh-1)
        # Then a bunch of <rect> for collapsed 'off'
        ngs.selectAll('rect.off')
            .data((s) => @collapse_off(s.id))
            .enter().append('rect')
                    .attr('class','off')
                    .attr('height',@bh-1)
                    .attr('x', (p) -> p.x)
                    .attr('width', (p) => @bw*p.len)

        row.transition()
           .attr('transform', (s) => "translate(0,#{s.pos * @bh})")

    # Draw the strain labels
    draw_labels: (elem) ->
        lbls = elem.selectAll('text.label')
                   .data(@matrix.strains(), (s) -> s.id)
        lbls.enter()
            .append('text')
             .attr('class',(s) -> "label strain-#{s.id}")
             .attr('text-anchor','end')
             .text((s) -> s.name)
             .on('click', (s) => @matrix.set_first(s.id))
             .on("mouseover", (s) => @highlight(s))
             .on("mouseout", (s) => @unhighlight())
        lbls.transition()
            .attr('y', (s) => (s.pos+1)*@bh-1)   # i+1 as TEXT is from baseline not top
        # TODO: set font size to be same as row height?

    draw_gaps: (elem) ->
        elem.selectAll('g.gene-sep').remove()
        g = elem.append('g')
                .attr('class','gene-sep')

        col = g.selectAll('line.gene-sep')
                  .data(@matrix.genes(), ((g) -> g.id))
        col.exit().remove()
        col.enter()
            .append('line')
            .attr('class','gene-sep')
            .attr('x1',(g,i) => i)
            .attr('x2',(g,i) => i)
            .attr('y1',0)
            .attr('y2',@bh * @matrix.strains().length)
            .style('stroke','white')
            .style('stroke-width','0.1')

    redraw: () ->
        @draw_boxes(@mini)

        @draw_boxes(@focus)
        @draw_labels(@labels)
        @draw_gaps(@focus)

    draw_chart: () ->
        @x2.domain([0, @matrix.genes().length])

        #xAxis2.tickFormat((d) -> genes[d])
        @context.select(".x.axis").call(@xAxis2)

        @redraw()

        # commence completely zoomed out
        @reset_scale()

    # Highlight the strain in the MDS plot, and in the table
    highlight: (strain) ->
        d3.selectAll(".strain-#{strain.id}").classed({'highlight':true})
        @scatter2.highlight("strain-#{strain.id}")

    unhighlight: () ->
        d3.selectAll(".highlight").classed({'highlight':false})
        @scatter2.unhighlight()

    mds_brushed: (strains) ->
        d3.selectAll(".brushed").classed({'brushed':false})
        if strains
            strains.map((strain) ->
                d3.selectAll(".strain-#{strain.id}").classed({'brushed':true})
            )

    constructor: (@elem, @matrix) ->
        # block width and height, one block per gene per species
        @bw = 1
        @bh = 10

        @vscale = 1.0
        @create_elems()
        @draw_chart()

        @matrix.on('order_changed', () => @redraw())

        @scatter2 = new ScatterPlot(
                     elem: '#mds2'
                     click: (s) => @matrix.set_first(s.id)
                     mouseover: (s) => @highlight(s)
                     mouseout: (s) => @unhighlight()
                     brush: (s) => @mds_brushed(s)
                    )

        @mds = new MDSHandler(@matrix)
        @mds.on('redraw', (comp) =>
            @scatter2.draw(comp, @matrix.strains(), [0,1])
        )
        @mds.update(null)

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


# Load gene descriptions from a file 'gene-desc.txt'
load_desc = (matrix) ->
    d3.text("gene-desc.txt", (data) ->
        lines = data.split("\n")

        lines.forEach( (l) ->
            return if l.match(/^\s*$/)
            match = />(.*?) (.*)/.exec(l)
            if match
                matrix.set_desc(match[1], match[2])
            else
                console.log "BAD LINE: #{l}"
        )
    )

init = () ->

    $('.by').mouseover(() -> $('.gravatar').show())
    $('.by').mouseout(() -> $('.gravatar').hide())

#    d3.csv("pan.csv", (data) ->
    d3.tsv("pan.proteinortho", (data) ->
        matrix = parse_proteinortho(data)

        console.log "Features : ",matrix.genes()
        console.log "Strains : ",matrix.strains()
        load_desc(matrix)

        d3.select("#topinfo")
            .html("Loaded #{matrix.strains().length} strains and #{matrix.genes().length} ortholog clusters")


        pan = new Pan('#chart', matrix)

        $( window ).resize(() -> pan.resize())
    )

$(document).ready(() -> init() )
