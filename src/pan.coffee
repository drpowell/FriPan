work = require('webworkify');
Util = require('./util.coffee')
GeneMatrix = require('./gene-matrix.coffee')
Tree = require('./tree.coffee')
Plot = require('./mds-plot.coffee')
LogoSVG = require('./FriPan-logo.svg.js')

# A worker that will only compute new values if the web worker is not busy
# and the parameters have changed
class LatestWorker
    constructor: (@worker, @get_current_data) ->
        @dispatch = d3.dispatch("started","updated")
        @_computing = 0
        @_last_data = null
        @worker.addEventListener('message', (ev) => @done(ev.data))

    on: (t,func) ->
        @dispatch.on(t, func)

    update: () ->
        if !@_computing
            cur_data = @get_current_data()
            if !@deep_cmp(cur_data, @_last_data)
                @_computing = 1
                @_last_data = cur_data
                @dispatch.started()
                @worker.postMessage(msg: cur_data)

    # A slow deep compare (but easy to write!)
    deep_cmp: (a,b) ->
        JSON.stringify(a) == JSON.stringify(b)

    done: (res) ->
        @_computing = 0
        @dispatch.updated(res)
        # Now check if the data changed in between, may need to recompute!
        @update()

class ThinkingElement
    constructor: (@main_elem, @think_elem) ->
        # pass
    start: () ->
        @background_runner = window.setTimeout(() =>
            $(@think_elem).show()
            $(@main_elem).css('opacity','0.3')
        , 500)

    done: () ->
        window.clearTimeout(@background_runner)
        $(@think_elem).hide()
        $(@main_elem).css('opacity','1.0')

# MDSHandler takes "update" events and sends them to the 'LatestWorker'
# It dispatches "redraw" events when the the computation is done
class MDSHandler
    constructor: (@matrix, @think_elem) ->
        @dispatch = d3.dispatch("redraw")
        @_current_range = null
        worker = work(require('./mds-worker.coffee'))
        worker.postMessage(init: @matrix.as_hash())
        @latest_worker = new LatestWorker(worker, () => {mds: @_current_range})
        @latest_worker.on('updated', (comp) => @redraw(comp))

        @latest_worker.on('started.think', () => @think_elem.start())
        @latest_worker.on('updated.think', () => @think_elem.done())

    on: (t,func) ->
        @dispatch.on(t, func)

    enable_sort: (enable) ->
        @sort_enabled = enable
        @reorder()

    update: (range) ->
        ngenes = @matrix.genes().length
        range = [0, ngenes-1] if !range?
        range = [Math.floor(range[0]), Math.min(Math.ceil(range[1]), ngenes-1)]
        @_current_range = range
        @latest_worker.update()

    redraw: (comp) ->
        @last_comp = comp
        @dispatch.redraw(comp)
        @reorder()

    redispatch: () ->
        @dispatch.redraw(@last_comp)

    reorder: () ->
        if @last_comp? && @sort_enabled
            comp = @last_comp
            if @sort_enabled=='once'
                @sort_enabled = false
            # Callback to reorder rows.  Do it occasionally, otherwise very disconcerting
            window.clearTimeout(@background_runner)
            @background_runner = window.setTimeout(() =>
                ids = @matrix.strains().map((s) -> s.id)
                pts = numeric.transpose(comp.points)
                ids.sort((a,b) -> pts[0][a] - pts[0][b])
                @matrix.set_strain_order(ids)
            ,1000)

class DendrogramWrapper
    constructor: (@widget, @matrix, @think_elem) ->
        @_current_range = null
        worker = work(require('./mds-worker.coffee'))
        worker.postMessage(init: @matrix.as_hash())
        @latest_worker = new LatestWorker(worker, () => {dist: @_current_range})
        @latest_worker.on('updated', (d) => @_calc_done(d))
        @latest_worker.on('started.think', () => @think_elem.start())
        @latest_worker.on('updated.think', () => @think_elem.done())

        @typ = 'radial'
        @colours = []

    set_type: (@typ) ->
        # pass

    set_colours: (@colours) ->
        # pass

    update: (range) ->
        ngenes = @matrix.genes().length
        range = [0, ngenes-1] if !range?
        range = [Math.floor(range[0]), Math.min(Math.ceil(range[1]), ngenes-1)]
        @_current_range = range
        @latest_worker.update()

    _calc_done: (dist_arr) ->
        @tree = new Tree.TreeBuilder(dist_arr)
        @redraw()

    redraw: () ->
        return if !@tree?
        strain_info = @matrix.strains().map((s,i) =>
                          text:s.name
                          colour: @colours[i] || 'black'
                          clazz: "strain-#{s.id}"
                          strain: s
                        )

        @widget.draw(@typ, @tree, strain_info)
        #console.log "Dendrogram: distance=#{t2-t1}ms tree=#{t3-t2}ms draw=#{t4-t3}ms"


class Pan
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
            @mds.update(null)
            @dendrogram.update(null)
        else if diff > 1  # only sane scaling please
            sc = (@width / diff)
            #console.log "brushed", brush.extent(), diff, "scale=", sc, "width", width
            @set_scale(ex[0], sc)
            @mds.update(ex)
            @dendrogram.update(ex)

        # Draw or hide the gene gaps depending on the scale
        if diff<=300
            @draw_gaps(ex)
        else
            @hide_gaps()

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
        @set_scale(0,@width/(@bw*@matrix.genes().length))

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
                 <tr><th>Gene (pri):<td> #{gene_name_pri}
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


    dendrogram_mouseover: ([leaves,d,nodes]) ->
        @tooltip = d3.select("#tooltip")
        if leaves?
            @mds_brushed(leaves.map((n) -> n.strain))
            if nodes.length>0
                d3.selectAll(nodes.join(',')).classed({'brushed':true})

            str = if leaves.length==1
                    "<b>Name:</b>#{leaves[0].strain.name}"
                  else
                    "<b>Selected:</b>#{leaves.length}"

            @tooltip.style("display", "block") # un-hide it (display: none <=> block)
               .style("left", (d3.event.pageX) + "px")
               .style("top", (d3.event.pageY) + "px")
               .select("#tooltip-text")
                   .html("#{str}<br/><b>Dist:</b>#{d.dist}")
        else
            @mds_brushed([])
            @tooltip.style("display","none")

    create_elems: () ->
        tot_width = $(@elem).width()
        tot_height = @bh * @matrix.strains().length + 200
        margin = {top: 150, right: 10, bottom: 10, left: 140}
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

        # set tooltip object
        @tooltip = d3.select("#tooltip")

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
        window.xx = info
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
    _show_gene_pointer: (gene) ->
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

    redraw: () ->
        @draw_boxes(@mini)

        @draw_boxes(@focus)
        @draw_labels(@labels)
        @re_colour()

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
        @scatter.highlight("strain-#{strain.id}")

    unhighlight: () ->
        d3.selectAll(".highlight").classed({'highlight':false})
        @scatter.unhighlight()

    mds_brushed: (strains) ->
        d3.selectAll(".brushed").classed({'brushed':false})
        if strains
            strains.map((strain) ->
                d3.selectAll(".strain-#{strain.id}").classed({'brushed':true})
            )

    constructor: (@elem, @matrix, @strains) ->
        # block width and height, one block per gene per species
        @bw = 1
        @bh = 10

        @vscale = 1.0
        @create_elems()

        @matrix.on('order_changed', () =>
            sel = $('select#gene-order option:selected').val()
            # Order of the strains has changed.
            # If we are ordering genes by the first strain, reorder genes too
            # otherwise just redraw
            if (sel == '1st')
                @reorder_genes(sel)
            else
                @redraw()
        )

        @mdsDimension = 1
        @mdsBarGraph = new Plot.BarGraph(
                         elem: '#mds-bargraph'
                         click: (d) =>
                            @mdsDimension=+d.lbl
                            @mds.redispatch()
                        )
        @scatter = new Plot.ScatterPlot(
                     elem: '#mds'
                     width: 500
                     height: 399
                     left: 50
                     click: (s) => @matrix.set_first(s.id)
                     mouseover: (s) => @highlight(s)
                     mouseout: (s) => @unhighlight()
                     brush: (s) => @mds_brushed(s)
                    )

        @mds = new MDSHandler(@matrix, new ThinkingElement('#mds', '#mds-thinking'))
        @mds.on('redraw', (comp) =>
            points = numeric.transpose(comp.points)
            @scatter.draw(points, @matrix.strains(), [@mdsDimension-1, @mdsDimension])

            # Convert eigenvalues to percentages
            eigen_total = d3.sum(comp.eigenvalues)
            @mdsBarGraph.draw(comp.eigenvalues[0..9].map((v,i) ->
                {lbl: "#{i+1}", val: v/eigen_total}
            ))
        )
        @mds.update(null)

        dendrogramWidget = new Tree.Dendrogram(
                        elem: '#dendrogram'
                        width: 600
                        height: 400
                        radius: 100
                        mouseover: (d) => @dendrogram_mouseover(d)
                        mouseout:  () => @dendrogram_mouseover([])
                        )

        @dendrogram = new DendrogramWrapper(dendrogramWidget, @matrix,
                                            new ThinkingElement('#dendrogram', '#dendrogram-thinking'))
        @dendrogram.set_type($('select#dendrogram-type option:selected').val())
        @dendrogram.update(null)

        @_init_search()
        $('input#vscale').on('keyup', (e) =>
            str = $(e.target).val()
            val = parseFloat(str)
            if val>0 && val<2
                @vscale = val
                @set_scale()
        )

        if (colorbrewer?)
            brewer_options = "<option disabled>──────────</option>"
            d3.keys(colorbrewer).forEach((c) ->
                brewer_options += "<option value='brewer-#{c}'>#{c}</option>"
            )
            $('select#strain-colour-scheme').append(brewer_options)

        $('select#strain-colour').on('change', (e) => @re_colour())
        $('select#strain-colour-scheme').on('change', (e) => @re_colour())

        $('select#strain-sort').on('change', (e) =>
            @sort_order = $(e.target).val()
            @reorder()
        )

        $('select#dendrogram-type').on('change', (e) =>
            v = $(e.target).val()
            @dendrogram.set_type(v)
            @dendrogram.redraw()
        )

        $('select#gene-order').on('change', (e) =>
            sel = $('option:selected',e.target).val()
            @reorder_genes(sel)
        )

        @sort_order = $('select#strain-sort option:selected').val()
        @draw_chart()
        @reorder()

    reorder_genes: (sel) ->
        if sel == 'none'
            order = []  # default order is from input file
        else if sel == '1st'
            order = @matrix.get_genes_for_strain_pos(0) # Take the first row
                           .filter((n) -> !!n)          # Remove null names
                           .map((n) -> n.split(',')[0]) # First name for paralogs
                           .sort()
        else
            order = $('option:selected',e.target).data('order')
        @matrix.set_gene_order(order)
        @clear_boxes()
        @redraw()

    make_colour_legend: (scale, fld) ->
        vals = scale.domain().sort((a,b) -> a.localeCompare(b, [], {numeric: true}))
        elem = d3.select('#colour-legend')
        elem.html('')
        return if vals.length==0

        elem.append('div')
            .attr('class','title')
            .text("Colour legend : #{fld}")
        elem.selectAll('div.elem')
            .data(vals)
            .enter()
            .append('div')
              .attr('class','elem')
              .style('color', (v) -> scale(v))
              .text((v) -> v)
            .append('div')
            .attr('class','box')
              .style('background-color', (v) -> scale(v))

    re_colour: () ->
        col_fld = $('select#strain-colour').val()
        col_scheme = $('select#strain-colour-scheme').val()
        @colour_by(col_fld, col_scheme)

    colour_by: (fld, scheme) ->
        strains = @strains.as_array()
        domain = if (fld != 'none')
                     d3.set(strains.map((s) -> s[fld])).values().sort()
                 else
                     []

        # Choose, and prime, the correct colour scale
        if scheme=='cat10'
            scale = d3.scale.category10()
            scale.domain(domain)
        else if scheme=='cat20a'
            scale = d3.scale.category20()
            scale.domain(domain)
        else if scheme=='cat20b'
            scale = d3.scale.category20b()
            scale.domain(domain)
        else if scheme=='cat20c'
            scale = d3.scale.category20c()
            scale.domain(domain)
        else if scheme=='raw'
            scale = d3.scale.ordinal()
            scale.domain(domain)
            scale.range(domain)
        else if scheme.indexOf('brewer-')==0
            scale = d3.scale.ordinal()
            scale.domain(domain)
            # Try and find the best number in the palette based on the size of the domain
            b = colorbrewer[scheme.slice(7)]
            sizes = d3.keys(b).sort().reverse()
            best = sizes[0]  # Default to the largest
            sizes.forEach((s) -> best=s if s>=domain.length)
            #console.log "domain size=#{domain.length}  sizes=#{sizes}.  Best=#{best}"
            scale.range(b[best])
            if domain.length>best
                Util.log_error("Not enough colours in #{scheme}, max=#{best}.  Need #{domain.length}")
        else
            Util.log_error("Bad colour scheme")

        strain_colour = []
        for s in strains
            col = if fld=='none' then '' else scale(s[fld])

            $(".strain-#{s.id} rect.on").css('fill', col)
            $(".label.strain-#{s.id}").css('fill', col)

            # mds
            $(".mds-scatter .labels.strain-#{s.id}").css('fill', col)
            $(".mds-scatter .dot.strain-#{s.id}").css('fill', col)

            # for the dendrogram
            strain_colour[s.id] = col

        @make_colour_legend(scale, fld)
        @dendrogram.set_colours(strain_colour)
        @dendrogram.redraw()

    reorder: () ->
        if @sort_order=='mds-dyn'
            @mds.enable_sort(true)
        else if @sort_order=='mds'
            @mds.enable_sort('once')
        else
            @mds.enable_sort(false)
            fld = @sort_order
            strains = @strains.as_array()

            if fld=='fixed'
                strains.sort((a,b) -> a.id - b.id)
            else
                strains.sort((a,b) -> a[fld].localeCompare(b[fld], [], {numeric: true}))

            ids = strains.map((s) -> s.id)
            @matrix.set_strain_order(ids)

    # Resize.  Just redraw everything!
    # TODO : Would be nice to maintain current brush on resize
    resize: () ->
        @svg.remove()
        @create_elems()
        @draw_chart()

    _init_search: () ->
        $( "#search" ).autocomplete(
          source: (req,resp) =>
            lst = @matrix.search_gene(req.term,20)
            resp(lst)
        focus: (event, ui) =>
            @_show_gene_pointer(ui.item.value)
            $("#search").val(ui.item.label)
            false
        select: (event, ui) =>
            @_show_gene_pointer(ui.item.value)
            false
        )

# ------------------------------------------------------------
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
            strains = d3.keys(row)
                        .filter((s) -> ['# Species','Genes', 'Alg.-Conn.'].indexOf(s)<0)  # skip 3 junk columns
                        .map((s) -> {name: s})
        genes.push( {name:"cluster#{i}", desc:""} )
        values.push( strains.map( (s) -> if row[s.name]=='*' then null else row[s.name]) )

    new GeneMatrix( strains, genes, d3.transpose(values) )

# ------------------------------------------------------------
#
get_stem = () ->
    Util.get_url_params() || 'pan'

process_gene_order = (matrix, json) ->
    strains = d3.keys(json).sort()
    for strain in strains
        row = json[strain]
        add_gene_order(strain,row)
        for gene in row
            matrix.set_desc(gene.name, gene.desc + " length:#{gene.length}")

load_json = (matrix) ->
    d3.json("#{get_stem()}.json", (err, json) ->
        if (err)
            Util.log_warn("Missing '#{get_stem()}.json', trying deprecated .descriptions file")
            load_desc(matrix)
        else
            process_gene_order(matrix,json.gene_order) if json.gene_order?
    )

add_gene_order = (strain, genes) ->
    opt = "<option value=\"#{strain}\">#{strain}</option>"
    elem = $(opt).appendTo('select#gene-order')
    elem.data('order', genes.map((g) -> g.name))

# Load gene labels from XXXX.descriptions file that ProteinOrtho5 produces
load_desc = (matrix) ->
    d3.text("#{get_stem()}.descriptions", (data) ->
        return if !data?
        lines = data.split("\n")

        lines.forEach( (l) ->
            return if l.match(/^\s*$/)
            match = /^(.*?)\t(.*)$/.exec(l)
            if match
                matrix.set_desc(match[1], match[2])
            else
                Util.log_error "BAD LINE: #{l}"
        )
    )

load_strains = (strainInfo) ->
    d3.tsv("#{get_stem()}.strains", (data) ->
        return if !data?
        strainInfo.set_info(data)

        # Add a separator to the "select" groups
        if strainInfo.columns.length > 0
            opt= "<option disabled>──────────</option>"
            $('select#strain-sort').append(opt)
            $('select#strain-colour').append(opt)

        # Add a selector for each column of strain info
        for c in strainInfo.columns
            opt = "<option value=\"#{c}\">#{c}</option>"
            $('select#strain-sort').append(opt)
            $('select#strain-colour').append(opt)
    )

class StrainInfo
    constructor: (@strains) ->
        # Pass

    as_array: () ->
        @strains[..]

    find_strain_by_name: (name) ->
        @strains.filter((s) -> s.name == name)[0]

    set_info: (@matrix) ->
        @columns = d3.keys(@matrix[0])
        if 'ID' != @columns.shift()
            Util.log_error("No ID column in #{get_stem()}.strains")
            @columns = []
            return

        # Fill in an "unknown" for all
        for s in @strains
            for c in @columns
                s[c] = '_not-set_'

        Util.log_info "Read info on #{@matrix.length}.  Columns=#{@columns}"
        for row in @matrix
            s = @find_strain_by_name(row['ID'])
            if !s?
                Util.log_error "Unable to find strain for #{row['ID']}"
            else
                for c in @columns
                    s[c] = row[c]
load_index = () ->
    d3.text('pan.index', (err, data) ->
        $("a.index-link").click(() -> $('.index-list').toggle())
        if (err)
            Util.log_info("No pan.index.  Skipping index list...")
            d3.select(".index-list ul").html("Create a pan.index file")
        else
            d3.select(".index-list ul")
              .selectAll("li")
              .data(data.split("\n").filter((str) -> str.length > 0))
              .enter()
                .append("li")
                .html((str) -> "<A HREF='?#{str}'>#{str}</A>")
    )

setup_download = (sel) ->
    d3.selectAll(".svg-download")
          .on("mousedown", (e) -> Util.download_svg(d3.event.target))

setup_about = () ->
    $("a.about-link").click(() ->
        $( "#dialog-message" ).dialog(
            modal: true
            width: 500
            buttons:
                Ok: () -> $( this ).dialog( "close" )
        )
    )
    $( "#dialog-message" ).prepend(LogoSVG)


init = () ->
    document.title = "FriPan : #{get_stem()}"
    $(".hdr").prepend(LogoSVG)
    $(".hdr .title").append("<span class='title'>: #{get_stem()}</span>")
    Util.setup_nav_bar()
    setup_about()
    load_index()

    url = "#{get_stem()}.proteinortho"
    d3.tsv(url, (data) ->
        if !data?
            $('#chart').text("Unable to load : #{url}")
            return
        $('#chart').html('')
        matrix = parse_proteinortho(data)

        strains = new StrainInfo(matrix.strains().map((s) -> {name:s.name, id:s.id}))
        #console.log "Features : ",matrix.genes()
        #console.log "Strains : ",matrix.strains()

        load_json(matrix)
        load_strains(strains)

        d3.select("#topinfo")
          .html("<b>Strains</b>: #{matrix.strains().length}  <b>gene clusters</b>:#{matrix.genes().length}")

        pan = new Pan('#chart', matrix, strains)

        $( window ).resize(() -> pan.resize())

        setup_download(".svg_download")
    )

$(document).ready(() -> Util.add_browser_warning() ; init() )
