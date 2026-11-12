const ID = 'x'

export def 'scope project' [] {
    scope modules | where name == $ID | get -o 0
}

def 'cmpl-cmd' [] {
    let p = scope project
    [...$p.commands.name ...$p.aliases.name]
}

def 'cmd exists' [] {
    let o = $in
    scope commands | where name == $o | is-not-empty
}

# overlay use -r ($ID).nu as ($ID) -p
export def --wrapped 'project watch' [...cmd:string@cmpl-cmd] {
    run-and-watch -c -g $'($ID).nu' {
        [
            'use project'
            $'project direnv ($ID)'
            $'overlay use -r ($ID).nu as ($ID) -p'
            $'($ID) ($cmd |str join " ")'
        ]
        | str join (char newline)
        | nu -c $in
    }
}

export def 'run-and-watch' [
    --clear(-c)
    --path(-p):string='.'
    --glob(-g):string='*'
    action
] {
    do $action '' '' ''
    watch $path -g $glob -q
    | where operation in ['Write']
    | each {
        if $clear { ansi cls }
        do $action $in
        if not $clear { print $"(char newline)(ansi grey)------(ansi reset)(char newline)" }
    }
}

export def --env direnv [
    mod?:string=$ID
    --env-file(-e):string='.env'
] {
    let _ = if ($env_file | path exists) {
        open $env_file
    }
    | default {}

    [yaml, toml, nuon]
    | reduce -f {} {|i,a|
        let f = $'($mod).($i)'
        if ($f | path exists) { $a | merge (open $f) } else { $a }
    }
    | merge $_
    | load-env
}

export def find-project [dir] {
    for d in (
        $dir
        | path expand
        | path split
        | slice 1..
        | reduce -f ['/'] {|i, a| $a | append ([($a | last) $i] | path join) }
        | each { [$in $'($ID).nu'] | path join }
        | reverse
    ) {
        if ($d | path exists) { return $d }
    }
    ''
}

export def project-rename-id [old] {
    for i in (fd $"($old).nu" | lines) {
        let x = $i | path parse
        if $x.extension == 'nu' {
            let n0 = $x | update stem $ID
            let n = $n0 | path join
            print $"($i) -> ($n)"
            mv $i $n
            for e in [yaml, yml, toml] {
                let o0 = $x | update extension $e
                let o = $o0 | path join
                if ($o | path exists) {
                    mv $o ($o0 | update stem $ID | path join)
                }
            }
        }
    }
}
