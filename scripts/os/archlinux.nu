def parse_pkg_list [] {
    let d = $in | lines
    mut r = []
    mut cur = {}
    let char = {
        i : (ansi xterm_yellow)
        v : (ansi xterm_blue)
        c : (ansi xterm_grey)
        x : (ansi xterm_red)
        _ : (ansi reset)
        t : (char tab)

    }
    for i in 0..<($d | length) {
        if ($i mod 2) == 0 {
            $cur = ($d
                | get $i
                | parse -r '(?<t>[^ ]+)/(?<n>[^ ]+) (?<v>[^ ]+)( \[(?<c>.+?)\])?(?<x>.+)?'
                | first
                )
        } else {
            let t = $"($char.i)($cur.t)"
            let v = $"($char.v)($cur.v)"
            let c = $"($char.c)($cur.c? | default '')"
            let x = $cur.x?
                | default ''
                | str replace -ra  '\] \[' '/'
                | str replace -ra  '[\[ \]]' ''
            let x = if ($x | is-empty) { "" } else { $"($char.c)/($x)" }
            let d = $"(char newline)($char.c)($d | get $i)"
           $r ++= [{
                value: $cur.n
                description: $"($t)($x)($char.t)($v)($char.t)($c)($char._)"
           }]
        }
    }
    $r
}

use argx

def cmpl-aur [buffer: string] {
    let k = $buffer | argx parse
    ^yay -Ss ($k.args | last)
    | parse_pkg_list
}


def cmpl-list [buffer: string] {
    let k = $buffer | argx parse
    ^yay -Qs ($k.opt.list? | default '')
    | parse_pkg_list
}

def cmpl-remove [buffer: string] {
    let k = $buffer | argx parse
    ^yay -Qs ($k.opt.remove? | default '')
    | parse_pkg_list
}


export def --wrapped yay [
    --remove (-R): string@cmpl-remove
    --query (-q): string
    --list (-l): string@cmpl-list
    ...args: string@cmpl-aur
] {
    if ($query | is-not-empty) {
        ^yay -Qo $query
    } else if ($list | is-not-empty) {
        ^yay -Ql $list
    } else if ($remove | is-not-empty) {
        ^yay -cnsR $remove
    } else if ($args | is-empty) {
        ^yay -Syu
    } else {
        ^yay ...$args
    }
}
