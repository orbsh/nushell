def cmpl-ps [] {
    ps -l
    | each {|x|
        { value: $x.pid, description: $"($x.name)(char tab)($x.command)" }
    }
    | {
        options: { match_description: true, sort: false }
        completions: $in
    }
}

export def wait-pid [pid: string@cmpl-ps] {
    do -i { tail --pid $pid -f /dev/null }
}

export def wait-cmd [action -i: duration = 1sec  -t: string='waiting'] {
    mut time = 0
    loop {
        print -e $"(ansi dark_gray)($t) (ansi dark_gray_italic)($i * $time)(ansi reset)"
        let c = do --ignore-errors $action | complete | get exit_code
        if $c == 0 { break }
        sleep $i
        $time = $time + 1
    }
}

export module proc {
    export def ancestor [pid: int@cmpl-ps] {
        let px = ps
        let cur = $px | where pid == $pid | get 0
        mut s = [$cur]
        loop {
            let ppid = $s | last | get ppid
            let p = $px | where pid == $ppid
            if ($p | is-empty) { break }
            $s ++= $p
        }
        $s
    }

    def desc [ps pid] {
        let p = $ps | where ppid == $pid
        if ($p | is-empty) {
            return []
        } else {
            let pd = $p | each {|x| desc $ps $x.pid } | flatten
            return [...$p ...$pd]
        }
    }
    export def descendant [pid: int@cmpl-ps] {
        desc (ps) $pid
    }
}

export def psgroup [] {
    ps
    | group-by name
    | items {|k, v|
        {
            name: $k
            cpu: ($v.cpu | math sum)
            mem: ($v.mem | math sum)
            count: ($v.pid | length)
        }
    }
    | sort-by mem
}

def cmpl-pid [] {
    ps -l
    | each {|x|
        { value: $x.pid, description: $"($x.name)(char tab)($x.command)" }
    }
    | {
        options: { match_description: true, sort: false }
        completions: $in
    }
}

export extern kill [
    --force(-f)
    --quiet(-q)
    --signal(-s): int
    ...pid: int@cmpl-pid
]
