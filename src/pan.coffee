work = require('webworkify');
Util = require('./util.coffee')
GeneMatrix = require('./gene-matrix.coffee')
Tree = require('./tree.coffee')
Plot = require('./mds-plot.coffee')
PanChart = require('./pan-chart.coffee')
Newick = require('./newick.coffee')
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


    redraw: () ->
        @panChart.redraw()
        @re_colour()

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

    pan_brushed: (ex) ->
        @mds.update(ex)
        @dendrogram.update(ex)

    constructor: (@matrix, @strains) ->
        @panChart = new PanChart.PanChart(
                            elem: '#chart'
                            matrix: @matrix
                            strains: @strains
                            highlight: (s) => @highlight(s)
                            unhighlight: () => @unhighlight()
                            brushed: (ex) => @pan_brushed(ex)
                            )

        @matrix.on('order_changed', () =>
            sel = $('select#gene-order option:selected').val()
            # Order of the strains has changed.
            # If we are ordering genes by the first strain, reorder genes too
            # otherwise just redraw
            if (sel == '1st')
                @reorder_genes(sel)
            else
                @panChart.redraw()
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
            @panChart.set_vscale(val)
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
            dat = $("option:selected",e.target).data()
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
        @panChart.draw_chart()
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
        @panChart.clear_boxes()
        @panChart.redraw()

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
        if @sort_order=='_mds-dyn'
            @mds.enable_sort(true)
        else if @sort_order=='_mds'
            @mds.enable_sort('once')
        else if @sort_order=='_tree'
            @mds.enable_sort(false)
            tree = $('select#strain-sort option:selected').data()
            @panChart.show_tree(tree)
        else
            @mds.enable_sort(false)
            fld = @sort_order
            strains = @strains.as_array()

            if fld=='_fixed'
                strains.sort((a,b) -> a.id - b.id)
            else
                strains.sort((a,b) -> a[fld].localeCompare(b[fld], [], {numeric: true}))

            ids = strains.map((s) -> s.id)
            @matrix.set_strain_order(ids)

    # Resize.  Just redraw everything!
    # TODO : Would be nice to maintain current brush on resize
    resize: () ->
        @panChart.resize()

    _init_search: () ->
        $( "#search" ).autocomplete(
          source: (req,resp) =>
            lst = @matrix.search_gene(req.term,20)
            resp(lst)
        focus: (event, ui) =>
            @panChart.show_gene_pointer(ui.item.value)
            $("#search").val(ui.item.label)
            false
        select: (event, ui) =>
            @panChart.show_gene_pointer(ui.item.value)
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
# Load a Roary output file
parse_roary = (csv) ->
    info_cols = ["Gene","Non-unique Gene name","Annotation","No. isolates","No. sequences",
                 "Avg sequences per isolate","Genome Fragment","Order within Fragment","Accessory Fragment",
                 "Accessory Order with Fragment","QC","Min group size nuc","Max group size nuc","Avg group size nuc"
                ]
    strains = []
    values = []
    genes = []
    i=0
    for row in csv
        i += 1
        if i==1
            strains = d3.keys(row)
                        .filter((s) -> info_cols.indexOf(s)<0)  # skip 3 junk columns
                        .map((s) -> {name: s})
        gene = {name:"cluster#{i}", desc:""}
        info_cols.forEach((i) -> gene[i] = row[i])
        genes.push(gene)
        values.push( strains.map( (s) -> if row[s.name]=='' then null else row[s.name]) )

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

load_tree = () ->
    d3.text("#{get_stem()}.tree", (data) ->
        return if !data?
        tree = new Newick.Newick(data)
        Util.log_info("Loaded tree :\n#{tree.top.to_string()}")

        # Add a separator to the "select" groups
        $('select#strain-sort').append("<option disabled>──────────</option>")

        # Add a selector for each column of strain info
        opt = $("<option value='_tree'>Tree</option>")
        $('select#strain-sort').append(opt)
        opt.data(tree)
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

load_rest = (matrix) ->
    strains = new StrainInfo(matrix.strains().map((s) -> {name:s.name, id:s.id}))
    #console.log "Features : ",matrix.genes()
    #console.log "Strains : ",matrix.strains()

    load_json(matrix)
    load_strains(strains)
    load_tree()

    d3.select("#topinfo")
      .html("<b>Strains</b>: #{matrix.strains().length}  <b>gene clusters</b>:#{matrix.genes().length}")

    pan = new Pan(matrix, strains)

    $( window ).resize(() -> pan.resize())

    setup_download(".svg_download")


init = () ->
    document.title = "FriPan : #{get_stem()}"
    $(".hdr").prepend(LogoSVG)
    $(".hdr .title").append("<span class='title'>: #{get_stem()}</span>")
    Util.setup_nav_bar()
    setup_about()
    load_index()

    url = "#{get_stem()}.proteinortho"
    d3.tsv(url, (data) ->
        if data?
            $('#chart').html('')
            matrix = parse_proteinortho(data)
            load_rest(matrix)
        else
            url = "#{get_stem()}.roary"
            Util.log_info "No proteinortho, trying : #{url}"
            d3.csv(url, (data) ->
                if data?
                    $('#chart').html('')
                    matrix = parse_roary(data)
                    load_rest(matrix)
                else
                    Util.log_error "No data file found"
                    $('#chart').text("Unable to load : #{url}")
            )
    )

$(document).ready(() -> Util.add_browser_warning() ; init() )
