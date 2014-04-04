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
        @_desc = {}
        # @dispatch is used to send events when the order of rows changes
        @dispatch = d3.dispatch("order_changed") if d3?

    # Convert GeneMatrix to a hash (for transport to a web-worker)
    as_hash: () ->
        {strains: @_strains, genes: @_genes, values: @_values, desc: @_desc}

    # Create a GeneMatrix from a hash (created from above)
    @from_hash: (hsh) ->
        res = new GeneMatrix(hsh.strains, hsh.genes, hsh.values)
        res._desc = hsh.desc
        res

    on: (t,func) ->
        @dispatch.on(t, func)

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

    search_gene: (str, max) ->
        res = []
        for i in @_pos
            for j in [0 ... @_values[i].length]
                n =  @_values[i][j]
                if n? && n.indexOf(str)>=0
                    res.push({label:n, value:j})
                return res if res.length>=max
        return res

    # Find a name for the gene - searching by "pos" (ie. from the top)
    gene_name: (gene_id) ->
        for idx in @_pos
            n = @strain_gene_name(idx,gene_id)
            return n if n?
        "not found"

    # Set gene description for the given gene name
    set_desc: (gene_name, desc) ->
        @_desc[gene_name] = desc

    # Find the first description that is not "hypothetical protein"
    get_desc_non_hypot: (gene_id) ->
        fst = ""
        for idx in @_pos
            n = @strain_gene_name(idx,gene_id)
            continue if !n?
            desc = @get_desc(n)
            fst = desc if fst.length==0
            return desc if desc.length>0 && !desc.match('hypothetical')
        fst

    # Get description by gene name
    get_desc: (gene_name) ->
        names = (gene_name || '').split(',')
        res = ""
        names.forEach((n) =>
            res += " # " if res.length>0
            res += @_desc[n] if @_desc[n]
        )
        res

    # Set the given strain id to be first in the list
    set_first: (strain_id) ->
        idx = @_pos.indexOf(strain_id)
        @_pos.splice(idx, 1)         # Remove it from the list
        @_pos.splice(0,0, strain_id) # And put it on the front
        @_pos.forEach((s_id, idx) => @_strains[s_id].pos = idx) # Now re-pos the strains
        @dispatch.order_changed()

    # Set the complete order of strains
    set_order: (order) ->
        @_pos = order
        @_pos.forEach((s_id, idx) => @_strains[s_id].pos = idx) # Now re-pos the strains
        @dispatch.order_changed()


@GeneMatrix=GeneMatrix