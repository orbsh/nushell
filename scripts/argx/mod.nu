export def get-ast [] {
    let d = ast $in -j -m | get block | from json
    let cur = $d
        | get -o pipelines | last
        | get elements | last
    if ($cur | is-not-empty) {
        $cur.expr.expr.Call?
    } else {
        null
    }
}

def expr-to-value [expr] {
    if ($expr | describe -d).type == record {
        $expr
        | items {|k, v|
            match $k {
                List => {
                    $v | each { expr-to-value $in.Item.expr }
                }
                FullCellPath => {
                    $v.head.expr.Record | reduce -f {} {|i,a|
                        let p = $i.Pair | get expr
                        $a | insert (expr-to-value $p.0) (expr-to-value $p.1)
                    }
                }
                Closure => {
                    # TODO:
                    null
                }
                Filepath => { $v.0 }
                String | Int | Bool => { $v }
                _ => { $"($k):($v)" }
            }
        }
        | first
    } else {
        null
    }
}

def get-args [] {
    let o = $in
    let a = $o.arguments
    let s = $o.head.start
    mut r = {
        args: []
        opt: {}
    }
    for i in $a {
        if ('Named' in $i) {
            let named_items = $i.Named
            let name = $named_items | where {|j| ($j | is-not-empty) and ($j.item? | is-not-empty)} | get 0.item
            let expr_filtered = $named_items | where {|j| ($j | is-not-empty) and ($j.expr? | is-not-empty)}
            let expr = if ($expr_filtered | is-not-empty) { $expr_filtered.0.expr } else { {Bool: true} }
            $r.opt = $r.opt | upsert $name (expr-to-value $expr)
        }
        if ('Positional' in $i) {
            $r.args ++= [(expr-to-value $i.Positional.expr)]
        }
    }

    $r
}

export def parse [] {
    let cmd = $in

    let ast = $cmd | get-ast
    if ($ast | is-empty) { return }
    let x = $ast | get-args

    let def = scope commands
    | where decl_id == $ast.decl_id | first
    let sign = $def
    | get -o signatures?.any?
    | insert name {|y|
        if ($y.parameter_name | is-empty) {
            $y.short_flag
        } else {
            $y.parameter_name
        }
    }

    let defaults = $sign
    | reduce -f {} {|i,a|
        if ($i.parameter_default | is-not-empty) {
            $a | insert $i.name $i.parameter_default
        } else {
            $a
        }
    }

    let sign = $sign | group-by parameter_type

    let opt = $sign.named? | default []
    | get -o name
    | reduce -f $x.opt {|i, a|
        if ($i in $defaults) and ($i not-in $a) {
            $a | insert $i ($defaults | get $i)
        } else {
            $a
        }
    }

    mut pos = $sign.positional? | default []
    | get name
    | enumerate
    | reduce -f {} {|it, acc|
        let v = $x.args | get -o $it.index
        let v = if ($v | is-empty) { $defaults | get -o $it.item } else { $v }
        $acc | insert $it.item $v
    }

    if ($sign.rest? | is-not-empty) {
        # HACK: If the name of the rest parameter is `rest`, then the name is empty.
        let name = $sign.rest.0.name | default 'rest'
        $pos = $pos | insert $name ($x.args | slice ($sign.positional? | length)..)
    }

    $x
    | insert tag $def.name
    | insert pos $pos
    | update opt $opt
}

export-env {
    $env.NU_ARGX_EXISTS = true
}

export def test [$s -p] {
    print $"(ansi yellow)($s)(ansi reset)"
    let r = $s | parse | to yaml
    print $"(ansi grey)($r)(ansi reset)"
}
