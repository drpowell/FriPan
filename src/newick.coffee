class Node
    constructor: () ->
        @name = null
        @dist = null
        @children = []

    to_string: (n=0) ->
        Array(n+1).join(' ') + "#{@name} : #{@dist}\n" + @children.map((c) -> c.to_string(n+4)).join('')

class Newick
    constructor: (str) ->
        @top = @parse(str)

    # First group from wikipedia : https://en.wikipedia.org/wiki/Newick_format
    @tests = ["(,,(,));",                               # no nodes are named
              "(A,B,(C,D));",                           # leaf nodes are named
              "(A,B,(C,D)E)F;",                         # all nodes are named
              "(:0.1,:0.2,(:0.3,:0.4):0.5);",           # all but root node have a distance to parent
              "(:0.1,:0.2,(:0.3,:0.4):0.5):0.0;",       # all have a distance to parent
              "(A:0.1,B:0.2,(C:0.3,D:0.4):0.5);",       # distances and leaf names (popular)
              "(A:0.1,B:0.2,(C:0.3,D:0.4)E:0.5)F;",     # distances and all names
              "((B:0.2,(C:0.3,D:0.4)E:0.5)F:0.1)A;",    # a tree rooted on a leaf node (rare)
              "((NC_018406:0.023538712,NC_018407:0.012700077)0.958:0.024988382,(NC_018409:0.053375797,(NC_018408:0.024979596,NC_018412:0.016510774)0.970:0.017864827)0.999:0.034328993,((NC_018411:0.044126378,NC_018413:0.028649479)1.000:0.072452306,((NC_017503:0.078032814,(NC_023030:0.200477713,(NC_004829:0.003594537,NC_017502:0.007866479)1.000:0.807564327)0.198:0.003156151)1.000:0.667290829,NC_018410:0.019218006)0.918:0.022957290)0.810:0.013982213);"
          ]
    parse: (str) ->
        toks = str.split(/([():,;])/).filter((s) -> s.length>0)
        cur = new Node
        top = cur
        stack = []
        while(toks.length>0)
            tok = toks.shift()
            if tok=="("
                stack.push(cur)
                n = new Node
                cur.children.push(n)
                cur = n
            else if tok==")"
                cur = stack.pop()
            else if tok==":"
                tok = toks.shift()
                cur.dist = tok
            else if tok==";"
                # End!  ignoring
            else if tok==","
                cur = new Node
                stack[stack.length-1].children.push(cur)
            else
                cur.name = tok
        cur

tests = () ->
    Newick.tests.forEach((t) ->
        console.log("Test string : ", t)
        tree = new Newick(t)
        console.log(tree.top.to_string())
    )

module.exports.Newick = Newick
