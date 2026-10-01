use argx

def cmpl-scp [buffer: string] {
    let ctx = $buffer | argx parse
    let p = $ctx.args | slice (-1)..-1 | default ''
    let ssh = cmpl-ssh
    let n = $p | split row ':'
    if ($n | length) > 1 and ($n | get 0) in ($ssh | get value) {
        ^ssh ($n | get 0) $"sh -c 'ls -dp ($n | get -o 1)*'"
        | lines
        | each {|x| $"($n | get 0):($x)"}
    } else {
        let files = (do -i {
            ls -a ($"($p)*" | into glob)
            | each {|x| if $x.type == dir { $"($x.name)/"} else { $x.name }}
        })
        let ssh = $ssh | each { $in | update value {|x| $"($x.value):"} }
        $files | append $ssh
    }
}

def expand-exists [p] {
    if ($p | path exists) {
        $p | path expand
    } else {
        $p
    }
}

export def --wrapped scp [
    lhs: string@cmpl-scp
    rhs: string@cmpl-scp
    ...opts
] {
    ^scp -r ...$opts (expand-exists $lhs) (expand-exists $rhs)
}
