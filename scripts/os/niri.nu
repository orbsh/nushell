export-env {
    $env.NIRI_SOCKET = glob /run/user/(id -u)/niri*sock | first
}


def cmpl-cmd [] {
    use parser/indent.nu parse-indent
    niri msg --json out+err>| lines | get 1 | from nuon
}

export def --wrapped nmsg [cmd: string@cmpl-cmd, ...args] {
    niri msg $cmd ...$args
}

def cmpl-actions [buffer: string] {
    use parser/indent.nu parse-indent
    use argx
    let c = $buffer | argx parse
    niri msg action out+err>| lines
    | parse-indent
    | get 'Actions:'
    | items {|k, v| {value: $k, description: ($v | columns | first)} }
}

export def --wrapped nact [...args: string@cmpl-actions] {
    niri msg action ...$args
}

export def nwin [
    --all(-a)
    --len(-l): int = 20
] {
    let r = niri msg -j windows | from json
    if $all {
        $r
    } else {
        $r
        | select id title app_id workspace_id pid
        | update title {|x|
            if ($x.title | str length) > 20 {
                $"($x.title | str substring ..$len)..."
            } else {
                $x.title
            }
        }
    }
}

def cmpl-win [] {
    nwin -a | each {|x| {value: $x.id, description: $x.title} }
}

export def nfocus [id: int@cmpl-win] {
    niri msg action focus-window --id $id
}
