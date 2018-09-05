class PanChart
    constructor: (@opts) ->
        @elem = @opts.elem
        @matrix = @opts.matrix
        @strains = @opts.strains

        # block width and height, one block per gene per species
        @bw = 1
        @bh = 10

        @vscale = 1.0
        @create_elems()

    highlight: (s) -> @opts.highlight(s)
    unhighlight: () -> @opts.unhighlight()

    brushed: (brush) ->
        #x.domain(if brush.empty() then x2.domain() else brush.extent())
        # focus.select("path").attr("d", area)
        #focus.select(".x.axis").call(xAxis)
        ex = brush.extent()
        diff = ex[1] - ex[0]
        # FIXME - diff here is by pos (gene_by_pos), but other tools are slicing by id - BUG
        if diff==0
            # Reset to full zoom
            @reset_scale()
            @opts.brushed(null)
        else if diff > 1  # only sane scaling please
            sc = (@width / diff)
            #console.log "brushed", brush.extent(), diff, "scale=", sc, "width", width
            @_set_scale(ex[0], sc)
            @opts.brushed(ex)

        # Draw or hide the gene gaps depending on the scale
        if diff<=300
            @draw_gaps(ex)
        else
            @hide_gaps()

    set_vscale: (val) ->
        if val>0 && val<2
            @vscale = val
            @_set_scale()

    # should the x-translate NOT be scaled?
    _set_scale: (pos,sc) ->
        if !pos?
            pos = @last_pos
            sc = @last_sc

        @last_pos = pos
        @last_sc = sc
        @svg.selectAll(".scale").attr("transform","translate(#{-pos*sc},0)
                                                   scale(#{sc},#{@vscale})")
        @svg.selectAll(".label-scale").attr("transform", "scale(1,#{@vscale})")

    reset_scale: () ->
        @_set_scale(0,@width/(@bw*@matrix.genes().length))

    detail_off: () ->
        @tooltip.style("display", "none")
        @unhighlight()

    _detail_position: (e) ->
        [x,y] = [d3.event.pageX, d3.event.pageY]

        r_edge = $(@elem).offset().left+$(@elem).width()
        b_edge = $(@elem).offset().top+$(@elem).height()
        w = e[0][0].offsetWidth
        h = e[0][0].offsetHeight

        x = x-w if x+w > r_edge
        y = y-h if y+h > b_edge
        e.style('left', x + "px").style('top', y + "px")

    detail: () ->
        [x,y] = d3.mouse(@focus.node())
        # convert from screen coordinates to matrix coordinates
        row = Math.floor(y/@bh)
        col = Math.floor(x/@bw)
        strain_id = @matrix.strain_pos_to_id(row)
        gene = @matrix.genes_by_pos()[col]
        return if !gene? || !strain_id?

        strain = @matrix.strains()[strain_id]
        @unhighlight()
        @highlight(strain)
        p = @matrix.presence(strain_id,gene.id)
        gene_name_pri = @matrix.gene_name(gene.id)
        gene_name_strain = @matrix.strain_gene_name(strain_id,gene.id)
        desc_pri = @matrix.get_desc_non_hypot(gene.id)
        desc = @matrix.get_desc(gene_name_strain)
        num_present = @matrix.count_presence(gene.id)
        txt = """<table>
                 <tr><th>Strain:<td>#{strain.name}
                 <tr><th>Gene (pri):<td> #{gene_name_pri} (#{gene.name})
                 <tr><th>Gene:<td> #{gene_name_strain}
                 <tr><th>Present:<td>#{p}
                 <tr><th>Desc (pri):<td>#{desc_pri}
                 <tr><th>Desc:<td>#{desc}
                 <tr><th>Strains with gene:<td>#{num_present} of #{@matrix.strains().length}
                 <tr><th>Pos:<td>#{gene.pos}
                 </table>
                """
        @tooltip.style("display", "block") # un-hide it (display: none <=> block)
                .select("#tooltip-text")
                  .html(txt)
        @_detail_position(@tooltip)

    create_elems: () ->
        tot_width = $(@elem).width()
        tot_height = @bh * @matrix.strains().length + 200
        @tree_width = if @tree_newick? then 240 else 100

        margin = {top: 150, right: 10, bottom: 10, left: @tree_width}
        margin2 = {top: 30, right: margin.right, bottom: tot_height - 100, left: margin.left}
        @width = tot_width - margin.left - margin.right
        @height = tot_height - margin.top - margin.bottom
        @height2 = tot_height - margin2.top - margin2.bottom

        @x2 = d3.scale.linear().range([0, @width])

        @xAxis2 = d3.svg.axis().scale(@x2).orient("bottom")

        brush = d3.svg.brush()
        brush.x(@x2)
             .on("brush", () => @brushed(brush))

        # should tot_width here be width?
        @svg = d3.select(@elem).append("svg")
            .attr("width", tot_width)
            .attr("height", tot_height)

        defs = @svg.append("svg:defs")
        # Add a clip rectangle to keep the area inside
        defs.append("svg:clipPath")
             .attr("id", "draw-region")
            .append('rect')
             .attr('width', @width)
             .attr('height',@height)
             .attr('x', 0)
             .attr('y', 0)
        defs.append("marker")
             .attr("id","arrowhead")
             .attr("viewBox","0 0 10 10")
             .attr("refX","1")
             .attr("refY","5")
             .attr("markerUnits","strokeWidth")
             .attr("orient","auto")
             .attr("markerWidth","4")
             .attr("markerHeight","3")
            .append("polyline")
             .attr("points","0,0 10,5 0,10 1,5")
             .attr("fill","red")

        # set up SVG for gene content pane
        main = @svg.append("g")
                     .attr("clip-path", "url(#draw-region)")
                     .attr("transform", "translate(#{margin.left},#{margin.top})")
                   .append("g")
                     .attr("transform","translate(0,0)scale(1,1)")
                     .attr("class", "scale")
                     .on("mousemove", () => @detail())
                     .on("mouseout", () => @detail_off())
        @focus = main.append("g")

        @gene_gaps = main.append("g")
                         .attr("class","gene-gap")

        # set up SVG for brush selection
        @context = @svg.append("g")
            .attr( "transform", "translate(#{margin2.left},#{margin2.top})" );

        # Create - @mini a <g> to hold the small plot
        # FIXME.  Factor out this scaling.  width should be like "set scale full".  Height should depend on number of strains
        @mini = @context.append("g")
                        .attr("class", "minimap")
                        .attr("transform","translate(0,0)
                                           scale(#{@width/(@bw*@matrix.genes().length)},
                                           #{@height2/(@bh*@matrix.strains().length)})")

        # Add the pointer arrow
        @mini.append("g")
               .attr("class","arrow")
               .attr("transform", "translate(0,0)")
               .attr("display","none")
             .append("g")
               .attr("transform", "scale(#{0.5*(@bw*@matrix.genes().length)/@width},
                                         #{0.5*(@bh*@matrix.strains().length)/@height2})")
             .append('line')
               .attr('class','pointer')
               .attr("marker-end", "url(#arrowhead)")
               .attr('x1', 0)
               .attr('x2', 0)
               .attr('y1',-50)
               .attr('y2',-25)
               .style('stroke','red')
               .style('stroke-width',10)

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

        # set up tree area
        @tree = @svg.append("g")
                     .attr("transform", "translate(0,#{margin.top})")
                    .append("g")
                     .attr('class','label-scale')
                     .attr("transform", "scale(1,#{@vscale})")

        # set tooltip object
        @tooltip = d3.select("#tooltip")

    draw_chart: () ->
        @x2.domain([0, @matrix.genes().length])

        #xAxis2.tickFormat((d) -> genes[d])
        @context.select(".x.axis").call(@xAxis2)

        @redraw()

        # commence completely zoomed out
        @reset_scale()

    redraw: () ->
        @draw_boxes(@mini)
        @draw_boxes(@focus)
        if @tree_newick?
            @draw_tree(@tree, @tree_newick)
        else
            @draw_labels(@labels)

    # Collapse the 'off' regions in a set of boxes with x and len
    collapse_off: (strain_id) ->
        res = []
        last_p=1
        @matrix.genes_by_pos().forEach((g) =>
            p = @matrix.presence(strain_id,g.id)
            if !p
                if last_p
                    res.push({x:g.pos, len: 0})
                res[res.length-1].len += 1
            last_p = p
        )
        res

    # Used when the genes change order.  Otherwise we don't want to re-render all the gene boxes
    clear_boxes: () ->
        @mini.selectAll('g.gene-row').remove()
        @focus.selectAll('g.gene-row').remove()
        @_hide_gene_pointer()

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

        row #.transition()
           .attr('transform', (s) => "translate(0,#{s.pos * @bh})")

    show_strain_info: (s) ->
        if !s?
            @tooltip.style("display", "none")
            return
        info = @strains.find_strain_by_name(s.name)
        str = ""
        for k,v of info
            if k not in ['id','name']
                str += "<tr><th>#{k}<td>#{info[k]}"
        txt = """<table>
                 <tr><th>Strain:<td>#{s.name}
                 #{str}
                 </table>
                """
        @tooltip.style("display", "block") # un-hide it (display: none <=> block)
                .select("#tooltip-text")
                  .html(txt)
        @_detail_position(@tooltip)


    ################################################################################
    # Tree

    set_tree: (tree) ->
        @tree_newick = tree
        @resize()
        @draw_tree(@tree, @tree_newick)

    _set_node_y_pos: (node) ->
        if node.leaf()
            strain = @matrix.strains().filter((s) -> s.name == node.name)
            if strain.length!=1
                Util.log_warn("Expected to find 1 strain, found : ",strain)
                node.y = 0
            else
                node.y = strain[0].pos
        else
            node.y = d3.mean(d3.extent(node.children.map((c) -> c.y)))

    draw_tree: (elem, tree_newick) ->
        if (!tree_newick?)
            elem.html('')
            return
        nodes = tree_newick.nodes
        nodes.forEach((n) => @_set_node_y_pos(n))
        #console.log "nodes",nodes

        max_depth = d3.max(nodes.map((n) -> n.depth))
        depth2x = d3.scale.linear().range([0, @tree_width-80]).domain([0, max_depth])
        x = (n) => depth2x(n.depth)
        y = (n) => (n.y+1)*@bh
        node2line = (n) =>
            res = []
            for c in n.children
                res.push({x:x(n), y:y(c)})
                res.push({x:x(c), y:y(c)})
                res.push({x:x(n), y:y(c)})
            res

        bh = @bh
        mk_line = d3.svg.line()
                    .x((d) -> d.x)
                    .y((d) -> d.y - bh/2)

        # Draw the dendrogram
        g = elem
        links = g.selectAll('path.link')
                 .data(nodes.filter((n) -> !n.leaf()))
        links.exit().remove()
        links.enter()
             .append('path')
              .attr('class', 'link')
              .attr("stroke", (d) -> "black") # d.colour)
              .attr('d', (d) -> mk_line(node2line(d)))
            #   .on('mouseover', (d) => @_mouseover(node_info, d))
            #   .on('mouseout', (d) => @_mouseout(node_info, d))

        lbls = g.selectAll('text.label')
                .data(nodes.filter((n) -> n.children.length==0), (n) -> n.name)
        lbls.exit().remove()
        lbls.enter()
            .append('text')
             .attr('class', (n) => s=@strains.find_strain_by_name(n.name); "label strain-#{s.id}")
             .attr('text-anchor','start')
             .text((n) -> n.name)
             .on("mouseover", (n) => s=@strains.find_strain_by_name(n.name); @highlight(s); @show_strain_info(s))
             .on("mouseout", () => @unhighlight(); @show_strain_info(null))
        lbls.transition()
             .attr('y', (n) -> y(n) - 2)
             .attr('x', (n) -> x(n))

    ################################################################################

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
             .on("mouseover", (s) => @highlight(s); @show_strain_info(s))
             .on("mouseout", (s) => @unhighlight(); @show_strain_info(null))
        lbls.transition()
            .attr('y', (s) => (s.pos+1)*@bh-1)   # i+1 as TEXT is from baseline not top
        # TODO: set font size to be same as row height?

    # Collapse the 'off' regions in a set of boxes with x and len
    collapse_off: (strain_id) ->
        res = []
        last_p=1
        @matrix.genes_by_pos().forEach((g) =>
            p = @matrix.presence(strain_id,g.id)
            if !p
                if last_p
                    res.push({x:g.pos, len: 0})
                res[res.length-1].len += 1
            last_p = p
        )
        res

    # Used when the genes change order.  Otherwise we don't want to re-render all the gene boxes
    clear_boxes: () ->
        @mini.selectAll('g.gene-row').remove()
        @focus.selectAll('g.gene-row').remove()
        @_hide_gene_pointer()

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

        row #.transition()
           .attr('transform', (s) => "translate(0,#{s.pos * @bh})")

    show_strain_info: (s) ->
        if !s?
            @tooltip.style("display", "none")
            return
        info = @strains.find_strain_by_name(s.name)
        str = ""
        for k,v of info
            if k not in ['id','name']
                str += "<tr><th>#{k}<td>#{info[k]}"
        txt = """<table>
                 <tr><th>Strain:<td>#{s.name}
                 #{str}
                 </table>
                """
        @tooltip.style("display", "block") # un-hide it (display: none <=> block)
                .select("#tooltip-text")
                  .html(txt)
        @_detail_position(@tooltip)

    hide_gaps: () ->
        @gene_gaps.selectAll('line.gene-gap').remove()

    draw_gaps: (ex) ->
        in_range = @matrix.genes_by_pos().filter((g) -> g.pos >= ex[0] && g.pos<=ex[1])
        col = @gene_gaps.selectAll('line.gene-gap')
                        .data(in_range, ((g) -> g.pos))
        col.exit().remove()
        col.enter()
            .append('line')
            .attr('class','gene-gap')
            .attr('x1',(g,i) => g.pos)
            .attr('x2',(g,i) => g.pos)
            .attr('y1',0)
            .attr('y2',@bh * @matrix.strains().length)
            .style('stroke','white')
            .style('stroke-width','0.1')


    _hide_gene_pointer: () ->
        arrow = @context.selectAll("g.arrow").attr('display','none')
        @focus.selectAll('line.pointer').remove()

    # Draw a pointing indicator to a specific gene on both minimap and main display
    show_gene_pointer: (gene) ->
        arrow = @context.selectAll("g.arrow")
                        .data([1])
        arrow.attr('transform', "translate(#{gene.pos}+0.5)")
             .attr('display', null)

        pointer = @focus.selectAll('line.pointer')
                        .data([1])
        pointer.enter()
            .append('line')
            .attr('class','pointer')
        pointer.attr('x1', gene.pos+0.5)
               .attr('x2', gene.pos+0.5)
               .attr('y1', 0)
               .attr('y2', @bh*@matrix.strains().length)
               .style('stroke','red')
               .style('stroke-width',1)
               .style('opacity', 0.8)
    resize: () ->
        @svg.remove()
        @create_elems()
        @draw_chart()

module.exports.PanChart = PanChart
