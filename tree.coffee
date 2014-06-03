
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
            n = {name: "Node:#{tree.length}", children: [min.n1, min.n2], dist: min.val}
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
        @svg = d3.select(@opts.elem).append("svg")
            .attr("class", "dendrogram")
            .attr("width", @opts.width)
            .attr("height", @opts.height)
           #.append("g")
           #.attr("transform","rotate(90 #{@opts.width/2} #{@opts.height/2})")

    _calc_pos: (node, leaf_pos) ->
        if node.leaf
            node.y = leaf_pos
            return leaf_pos+1
        else
            [c1,c2] = node.children
            if (c1.dist > c2.dist)
                [c2,c1] = [c1,c2]
            leaf_pos = @_calc_pos(c1, leaf_pos)
            leaf_pos = @_calc_pos(c2, leaf_pos)
            node.y = 0.5*(c1.y + c2.y)
            return leaf_pos

    show_tip: (node) ->
        @tooltip = d3.select("#tooltip")
        if node?
            @tooltip.style("display", "block") # un-hide it (display: none <=> block)
               .style("left", (d3.event.pageX) + "px")
               .style("top", (d3.event.pageY) + "px")
               .select("#tooltip-text")
                   .html("<b>Name:</b>#{node.name}<br/><b>Dist:</b>#{node.dist}")
        else
            @tooltip.style("display","none")


    draw: (builder, lbl_to_id) ->
        @svg.html('')
        root = builder.tree
        all = builder.flattened
        nodes = all.filter((n) -> !n.leaf)
        leaves = all.filter((n) -> n.leaf)

        num_leaf = @_calc_pos(root,0)

        x=d3.scale.linear()
                  .range([ @opts.width-@opts.label_width-@opts.w_pad, 0])
                  .domain([0, root.dist])

        y=d3.scale.linear()
                  .range([0, @opts.height-@opts.h_pad-@opts.axis_height])
                  .domain([0, num_leaf])
        g = @svg.append("g")
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
              .attr('class','link')
              .attr('d', (d) -> mk_line(node2line(d)))
              .on('mouseover', (d) => @show_tip(d))
              .on('mouseout', () => @show_tip(null))

        # Text for leaves
        g.selectAll('text.leaf')
            .data(leaves)
            .enter()
              .append("text")
              .attr("class",(d) -> "leaf strain-#{lbl_to_id(d.name)}")
              .attr("text-anchor", "start")
              .attr("dominant-baseline", "central")
              .attr("x", (d) => @opts.label_pad + x(d.dist))
              .attr("y", (d,i) -> y(d.y))
              .text((d) -> d.name)
              .on('mouseover', (d) => @show_tip(d))
              .on('mouseout', () => @show_tip(null))

        # Draw the axis
        axis = d3.svg.axis()
                   .scale(x)
                   .orient("top")
                   .ticks(4)
        @svg.selectAll(".axis").remove()
        @svg.append("g")
            .attr("class", "axis")
            .attr("transform", "translate(#{@opts.w_pad},#{@opts.h_pad})")
            .call(axis)

    draw2: (builder, lbl_to_id) ->
        @svg.html('')
        root = builder.tree
        all = builder.flattened
        nodes = all.filter((n) -> !n.leaf)
        leaves = all.filter((n) -> n.leaf)

        num_leaf = @_calc_pos(root,0)

        radius = 150

        x=d3.scale.linear()
                  .range([ radius, 0 ])
                  .domain([0, root.dist])

        y=d3.scale.linear()
                  .range([0, 359])
                  .domain([0, num_leaf])
        g = @svg.append("g")
                .attr("transform","translate(#{radius + 100},#{radius + 100}) rotate(-90)")

        node2line = (n) -> [{x:n.children[0].dist, y:n.children[0].y},
                            {x:n.dist, y:n.children[0].y},
                            {x:n.dist, y:n.children[1].y},
                            {x:n.children[1].dist, y:n.children[1].y}]
        #mk_line = d3.svg.line.radial()
        #          .radius((d) -> x(d.x))
        #          .angle((d) -> y(d.y) * Math.PI/180)
        #          #.interpolate("basis")

        mk_line = (n) ->
            f = d3.svg.arc()
              .innerRadius((d) -> x(d.dist))
              .outerRadius((d) -> x(d.dist))
              .startAngle((d) -> y(d.children[0].y) * (Math.PI/180)) #converting from degs to radians
              .endAngle((d) -> y(d.children[1].y) * (Math.PI/180)) #converting from degs to radians
            f2 = d3.svg.line.radial()
            f(n)+
              f2([[x(n.children[0].dist), y(n.children[0].y)* (Math.PI/180)], [x(n.dist), y(n.children[0].y)* (Math.PI/180)]]) +
              f2([[x(n.children[1].dist), y(n.children[1].y)* (Math.PI/180)], [x(n.dist), y(n.children[1].y)* (Math.PI/180)]])

        # Draw the dendrogram
        g.selectAll('path.link')
            .data(nodes)
            .enter()
            .append('path')
              .attr('class','link')
              .attr('d', (d) -> mk_line(d)) # node2line(d)))
              .on('mouseover', (d) => @show_tip(d))
              .on('mouseout', () => @show_tip(null))

        # Text for leaves
        g.selectAll('text.leaf')
            .data(leaves)
            .enter()
             .append("g")
              .attr("transform",(d) => r=y(d.y) ; if r<180 then "rotate(#{r} 0 0)" else "rotate(#{-r} 0 0)")
             .append("text")
              .attr("class",(d) -> "leaf strain-#{lbl_to_id(d.name)}")
              .attr("text-anchor", (d) -> r=y(d.y); if r < 180 then "start" else "end")
              .attr("dominant-baseline", "central")
              .attr("x", (d) => r=y(d.y); if r < 180 then @opts.label_pad + x(d.dist) else -x(d.dist) )
              .text((d) -> d.name)
              .on('mouseover', (d) => @show_tip(d))
              .on('mouseout', () => @show_tip(null))


window.Dendrogram = Dendrogram

window.TreeBuilder = TreeBuilder
