class GeneMatrix
    # _strains - array of strain objects.  Should have 'name'
    # _genes - array of gene objects.  Each element is a "cluster".  This array is the "pan-genome"
    # _values - 2d array, 1 row per strain. 1 col per gene.  value should be null
    #          for not-present.  Otherwise may use a per-gene name.  Should be in the same order as "_genes"
    #
    # _desc - hash of gene descriptions.  Keyed on gene name
    constructor: (@_strains, @_genes, @_values) ->
        # Give both genes and strains ids.
        @_strains.forEach((s,i) -> s.id = s.pos = i)
        @_genes.forEach((g,i) -> g.id = g.pos = i )
        @_desc = {}
        # @dispatch is used to send events when the order of rows changes
        @dispatch = d3.dispatch("order_changed") if d3?
        @_build_gene_name_idx()

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

    # Build a gene name to gene.id mapping
    _build_gene_name_idx: () ->
        gene_name_map = {}
        @_values.forEach((row) ->
            row.forEach((g, idx) ->
                if g?
                    names = g.split(',')
                    names.forEach((n) ->
                        gene_name_map[n] = idx
                    )
            )
        )
        @_gene_name_id = gene_name_map

    # Return array of strains ordered by id
    strains: () ->
        @_strains

    # Return strain_id for the given strain_pos
    strain_pos_to_id: (pos) ->
        @_strain_pos[pos]

    genes: () ->
        @_genes

    genes_by_pos: () ->
        if !@_genes_by_pos?
            @_genes_by_pos = @_genes.slice()
            @_genes_by_pos.sort((g1,g2) -> g1.pos - g2.pos)
        @_genes_by_pos

    # Set the order of genes.  Takes an array of gene names
    set_gene_order: (gene_names) ->
        console.log "Ordering genes.  Genes specified:#{gene_names.length}"
        # First reset all positions, then set the known ones, and fill in the rest
        @_genes.forEach((g) -> g.pos=-1)
        new_pos=0
        gene_names.forEach((n) =>
            id = @_gene_name_id[n]
            if !id?
                console.log "Unable to find gene '#{n}'"
            else
                # Set the gene position if it hasn't already been set
                gene = @_genes[id]
                if gene.pos<0
                    gene.pos = new_pos
                    new_pos += 1
        )
        @_genes.forEach((g) ->
            if g.pos<0
                g.pos = new_pos
                new_pos += 1
        )
        @_genes_by_pos=null

    # is the given gene present in the given strain
    presence: (strain_id, gene_id) ->
        @_values[strain_id][gene_id]?

    # Count number of genes in the cluster
    count_presence: (gene_id) ->
        tot=0
        @_values.forEach( (row) ->
            tot+=1 if row[gene_id]?
        )
        tot

    strain_gene_name: (strain_id, gene_id) ->
        @_values[strain_id][gene_id]

    search_gene: (str, max) ->
        res = []
        for i in @_strain_pos
            for j in [0 ... @_values[i].length]
                n =  @_values[i][j]
                if n? && n.indexOf(str)>=0
                    res.push({label:n, value:@_genes[j]})
                return res if res.length>=max
        return res

    # Find a name for the gene - searching by "pos" (ie. from the top)
    gene_name: (gene_id) ->
        for idx in @_strain_pos
            n = @strain_gene_name(idx,gene_id)
            return n if n?
        "not found"

    # Set gene description for the given gene name
    set_desc: (gene_name, desc) ->
        @_desc[gene_name] = desc

    # Find the first description that is not "hypothetical protein"
    get_desc_non_hypot: (gene_id) ->
        fst = ""
        for idx in @_strain_pos
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
        idx = @_strain_pos.indexOf(strain_id)
        @_strain_pos.splice(idx, 1)         # Remove it from the list
        @_strain_pos.splice(0,0, strain_id) # And put it on the front
        @_strain_pos.forEach((s_id, idx) => @_strains[s_id].pos = idx) # Now re-pos the strains
        @dispatch.order_changed()

    # Set the complete order of strains
    set_strain_order: (order) ->
        @_strain_pos = order
        @_strain_pos.forEach((s_id, idx) => @_strains[s_id].pos = idx) # Now re-pos the strains
        @dispatch.order_changed()


@GeneMatrix=GeneMatrix