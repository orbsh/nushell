export def cmpl-docker-ns [] {
    if $env.CNTRCTL == 'nerdctl' {
        ^$env.CNTRCTL namespace list
        | from ssv -a
        | each {|x| { value: $x.NAME }}
    } else {
        []
    }
}


export def --env container-change-namespace [ns:string@cmpl-docker-ns] {
    $env.CNTRNS = $ns
}

export def --wrapped container [...args] {
    let o = $in
    mut ns = []
    if $env.CNTRCTL in [nerdctl] {
        if ($env.CNTRNS? | is-not-empty) {
            $ns = [--namespace $env.CNTRNS]
        }
    }
    if ($o | is-empty) {
        ^$env.CNTRCTL ...$ns ...$args
    } else {
        $o | ^$env.CNTRCTL ...$ns ...$args
    }
}

export def expand-exists [p] {
    # order matters: absolute paths must expand even with ':' in name;
    # ':' marks container/ssh path — skip expansion before exists-check so a
    # local namesake can't hijack it
    if ($p | str starts-with '~') or ($p | str starts-with '/') {
        $p | path expand
    } else if ($p | str contains ':') {
        $p
    } else if ($p | path exists) {
        $p | path expand
    } else {
        $p
    }
}
