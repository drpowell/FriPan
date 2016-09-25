
class TreeBuilder
    # Dist - should be a square distance matrix,
    # 'method' - one of 'max', 'min', 'avg'.  Default is 'max'
    #   This determines how to calculate the distance between an internal node and other nodes.
    #     max - the maximum of all pairwise distance between the nodes' members
    #     min - the minimum of all pairwise distance between the nodes' members
    #     abg - the average of all pairwise distance between the nodes' members
    constructor: (dist, method) ->
        method = {max: d3.max, min: d3.min, avg: d3.min}[method || 'max']
        to_join = d3.keys(dist)
        tree = []

        # Lookup a node by name, add initial nodes (leaves)
        @by_name = {}
        to_join.forEach((n) => @by_name[n] = {name: n })


        # Copy the distance table.  We'll write to it for distance between 2 internal nodes
        @dist = {}
        to_join.map((k1) => to_join.map((k2) => (@dist[k1]||={})[k2] = dist[k1][k2]))

        while to_join.length>1
            min = @_pick_min(to_join)
            n = {name: "_node_#{tree.length}", children: [min.n1, min.n2], dist: min.val}
            tree.push(n)
            @by_name[n.name] = n

            # Remove the joined nodes, and add the new one
            to_join.splice(to_join.indexOf(min.n1), 1)
            to_join.splice(to_join.indexOf(min.n2), 1)
            to_join.push(n.name)

        # Convert tree to having children[] as node links rather than just names
        @flattened = []
        @tree = @_mk_subtree(tree[-1..][0], @flattened)

    _mk_subtree: (node, flattened) ->
        children = if node.children?
                      node.children.map((c) => @_mk_subtree(@by_name[c], flattened))
                    else
                      []
        n = {name: node.name, children: children, dist: node.dist || 0, leaf: children.length==0}
        flattened.push n
        n

    _pick_min: (nodes) ->
        min = null
        for i in [0...nodes.length]
            for j in [0...i]
                n1 = nodes[i]
                n2 = nodes[j]
                d = @_get_dist(n1,n2)
                if !min? || d<min.val
                    min = {val: d, n1: n1, n2: n2}
        min

    _get_dist: (n1,n2) ->
        return @dist[n1][n2] if @dist[n1]? && @dist[n1][n2]?
        if @by_name[n1].children?
            [n1,n2] = [n2,n1]
        if @by_name[n2].children?
            children = @by_name[n2].children
            dists = children.map((c) => @_get_dist(n1,c))
            d = d3.max(dists)
        else
            console.log "Can't find distance between #{n1} and #{n2}"
            die
        (@dist[n1] ||= {})[n2] = d
        (@dist[n2] ||= {})[n1] = d
        d

class Dendrogram
    constructor: (@opts) ->
        @opts.width ||= 500
        @opts.height ||= 500
        @opts.label_width ||= 180
        @opts.h_pad ||= 20
        @opts.w_pad ||= 10
        @opts.axis_height = 10
        @opts.label_pad ||= 5
        @opts.radius ||= 150
        @opts.callback = {}
        ['mouseover','mouseout'].forEach((s) =>
            @opts.callback[s] = @opts[s])

        zoom = d3.behavior.zoom()
                 .scaleExtent([0.2,10])
                 .on("zoom", () => @_zoomed())

        @svg = d3.select(@opts.elem).append("svg")
            .attr("class", "dendrogram")
            .attr("width", "100%")
            .attr("height", "100%")
            .attr("viewBox", "0 0 #{@opts.width} #{@opts.height} ")
            .call(zoom)

        # Create a full size rect to capture zoom events not otherwise on an element
        @svg.append("rect")
            .attr("width", @opts.width)
            .attr("height", @opts.height)
            .style("fill", "none")
            .style("pointer-events", "all")

        # Container <g> that will be scaled and translated
        @g = @svg.append("g")

    _zoomed: () ->
        @g.attr("transform", "translate(#{d3.event.translate})scale(#{d3.event.scale})")

    _calc_pos: (node, leaf_pos) ->
        if node.leaf
            node.y = leaf_pos
            return leaf_pos+1
        else
            [c1,c2] = node.children
            if (c1.dist > c2.dist)    # Order sub trees by smallest distance first
                [c2,c1] = [c1,c2]
            leaf_pos = @_calc_pos(c1, leaf_pos)
            leaf_pos = @_calc_pos(c2, leaf_pos)
            node.y = 0.5*(c1.y + c2.y)
            return leaf_pos

    _prep_tree: (builder) ->
        root = builder.tree
        all = builder.flattened
        nodes = all.filter((n) -> !n.leaf)
        leaves = all.filter((n) -> n.leaf)

        @_calc_pos(root,0)

        [root, nodes, leaves]

    _attach_colours: (node, node_info) ->
        if node.leaf
            node.colour = if node_info[node.name]?
                              node_info[node.name].colour
                          else
                              'black'
        else
            node.children.forEach((n) => @_attach_colours(n, node_info))
            col1 = node.children[0].colour
            col2 = node.children[1].colour
            node.colour = if col1==col2 then col1 else 'black'

    clear: () ->
        # @g.html('') # seems not to work on Safari?!?
        @g.selectAll('*').remove()

    # typ - 'horz' or 'radial'
    # builder - A TreeBuilder object
    # node_info - A hash with keys as for distance matrix passed to TreeBuilder
    #             value is an object like:  {text: "leaf label", colour: "leaf colour"}
    #             This object will also be passed back on 'mouseover' events
    draw: (typ, builder, node_info={}) ->
        typ ||= 'horz'
        if typ=='horz'
            @draw_horz(builder, node_info)
        else if typ=='radial'
            @draw_radial(builder, node_info)
        else
            log_error("Unknown dendrogram type",typ)

    draw_horz: (builder, node_info) ->
        @clear()
        [root, nodes, leaves] = @_prep_tree(builder)
        @_attach_colours(root, node_info)

        x=d3.scale.linear()
                  .range([ @opts.width-@opts.label_width-@opts.w_pad, 0])
                  .domain([0, root.dist])

        y=d3.scale.linear()
                  .range([0, d3.max([leaves.length*10, @opts.height-@opts.h_pad-@opts.axis_height])])
                  .domain([0, leaves.length])
        g = @g.append("g")
                .attr("transform","translate(#{@opts.w_pad},#{@opts.h_pad+@opts.axis_height})")

        node2line = (n) -> [{x:n.children[0].dist, y:n.children[0].y},
                            {x:n.dist, y:n.children[0].y},
                            {x:n.dist, y:n.children[1].y},
                            {x:n.children[1].dist, y:n.children[1].y}]

        mk_line = d3.svg.line()
                  .x((d) -> x(d.x))
                  .y((d) -> y(d.y))
                  #.interpolate("basis")

        # Draw the dendrogram
        g.selectAll('path.link')
            .data(nodes)
            .enter()
            .append('path')
              .attr('class', (d) -> 'link '+d.name)
              .attr("stroke", (d) -> d.colour)
              .attr('d', (d) -> mk_line(node2line(d)))
              .on('mouseover', (d) => @_mouseover(node_info, d))
              .on('mouseout', (d) => @_mouseout(node_info, d))

        get = (d,fld,def) ->
            if node_info[d.name]?
                node_info[d.name][fld]
            else
                def

        text = (d) -> get(d, 'text', d.name)
        clazz = (d)-> get(d, 'clazz', '')


        # Text for leaves
        g.selectAll('text.leaf')
            .data(leaves)
            .enter()
              .append("text")
              .attr("class",(d) -> "leaf "+clazz(d))
              .attr("text-anchor", "start")
              .attr("dominant-baseline", "central")
              .attr("x", (d) => @opts.label_pad + x(d.dist))
              .attr("y", (d) -> y(d.y))
              .attr("fill", (d) -> d.colour)
              .text((d) -> text(d))
              .on('mouseover', (d) => @_mouseover(node_info, d))
              .on('mouseout', (d) => @_mouseout(node_info, d))

        # Draw the axis
        axis = d3.svg.axis()
                   .scale(x)
                   .orient("top")
                   .ticks(4)
        @g.selectAll(".axis").remove()
        @g.append("g")
            .attr("class", "axis")
            .attr("transform", "translate(#{@opts.w_pad},#{@opts.h_pad})")
            .call(axis)

    draw_radial: (builder, node_info) ->
        @clear()
        [root, nodes, leaves] = @_prep_tree(builder)
        @_attach_colours(root, node_info)

        x=d3.scale.linear()
                  .range([ @opts.radius, 0 ])
                  .domain([0, root.dist])

        # Convert leaf position to angle
        y = d3.scale.linear().range([0, 359]).domain([0, leaves.length])

        # Same conversion, but -90 degrees.  We draw text horizontal, so 0 degrees is East
        # Whilst the rest of SVG has 0 degrees as North
        yTxt = d3.scale.linear().range([-90, 359-90]).domain([0, leaves.length])

        # Same as y(), but it radians.  For some reason D3 uses radians...
        yRad = (v) -> y(v) * Math.PI/180

        g = @g.append("g")
                .attr("transform","translate(#{@opts.width/2},#{@opts.height/2}) rotate(-90)")

        mk_line = (n) ->
            # f() generates the arc part
            f = d3.svg.arc()
              .innerRadius((d) -> x(d.dist))
              .outerRadius((d) -> x(d.dist))
              .startAngle((d) -> yRad(d.children[0].y))
              .endAngle((d) -> yRad(d.children[1].y))
            # f2() generates one radial line for the given child
            f2 = (n,i) -> d3.svg.line.radial()(
                              [[x(n.children[i].dist), yRad(n.children[i].y)],
                               [x(n.dist), yRad(n.children[i].y)]])
            f(n)+f2(n,0)+f2(n,1)

        # Draw the dendrogram
        g.selectAll('path.link')
            .data(nodes)
            .enter()
            .append('path')
              .attr('class', (d) -> 'link '+d.name)
              .attr("stroke", (d) -> d.colour)
              .attr('d', (d) -> mk_line(d))
              .on('mouseover', (d) => @_mouseover(node_info, d))
              .on('mouseout', (d) => @_mouseout(node_info, d))

        # Simple function, will the given angle rotate text to lookup upright?
        isTxtUp = (r) -> r>=0 && r<180

        get = (d,fld,def) ->
            if node_info[d.name]?
                node_info[d.name][fld]
            else
                def

        text = (d) -> get(d, 'text', d.name)
        clazz = (d)-> get(d, 'clazz', '')

        # Text for leaves
        # Be careful to position the text upright on both sides of the circle
        g.selectAll('text.leaf')
            .data(leaves)
            .enter()
             .append("g")
              .attr("transform",(d) => r=yTxt(d.y) ; "rotate(#{if isTxtUp(r) then r else 180+r} 0 0)")
             .append("text")
              .attr("class",(d) -> "leaf "+clazz(d))
              .attr("text-anchor", (d) -> r=yTxt(d.y); if isTxtUp(r) then "start" else "end")
              .attr("dominant-baseline", "central")
              .attr("x", (d) => (@opts.label_pad + x(d.dist)) * if isTxtUp(yTxt(d.y)) then 1 else -1)
              .attr("fill", (d) -> d.colour)
              .text((d) -> text(d))
              .on('mouseover', (d) => @_mouseover(node_info, d))
              .on('mouseout', (d) => @_mouseout(node_info, d))

    # Call the mouseover defined in @opts
    #   Will pass:  leaves - an array of node_info[] objects for the moused-over leaves
    #               d - the actual node (includes the 'dist')
    #               nodes - an array of CSS selectors for the moused-over nodes
    _mouseover: (node_info, d) ->
        trav = (n,leaves,nodes) ->
            if n.leaf
                leaves.push(node_info[n.name])
            else
                nodes.push("path.link.#{n.name}")
            n.children.forEach((c) -> trav(c, leaves, nodes))

        leaves = []
        nodes = []
        trav(d, leaves, nodes)
        @_event('mouseover', leaves, d, nodes)

    _mouseout: (node_info, d) ->
        @_event('mouseout', node_info[d.name], d)

    _event: (typ, args...) ->
        if @opts.callback[typ]
            @opts.callback[typ](args)



module.exports.Dendrogram = Dendrogram
module.exports.TreeBuilder = TreeBuilder
