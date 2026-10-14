def unnest [list lv=0] {
    mut cur = []
    mut rt = []
    for i in $list {
        if ($i | describe -d).type == 'list' {
            $rt = [...$rt, {it: $cur, lv: $lv}, ...(unnest $i ($lv + 1))]
            $cur = []
        } else {
            $cur = [...$cur, $i]
        }
    }
    if ($cur | is-not-empty) {
        $rt = [...$rt, {it: $cur, lv: $lv}]
    }
    return $rt
}

export def spread [list lv=0] {
    $list
    | each {|x|
        if ($x | describe -d).type == 'list' {
            spread $x ($lv + 1)
        } else {
            $x
        }
    } | flatten
}

export def --wrapped dry [...x --prefix='    ' --strip] {
    let w = term size | get columns
    mut lines = []
    for a in (unnest (if $strip { $x.0 } else { $x })) {
        mut nl = '' | fill -c $prefix -w $a.lv
        for t in $a.it {
            let line = if ($nl | str replace -a ' ' '' | is-empty) { $"($nl)($t)" } else { $"($nl) ($t)" }
            if ($line | str length) > $w {
                $lines ++= [$nl]
                $nl = $"('' | fill -c $prefix -w $a.lv)($t)"
            } else {
                $nl = $line
            }
        }
        $lines ++= [$nl]
    }
    $lines | str join $" \\(char newline)"
}

# perform or print
export def --wrapped pp [
    ...x
    --print
    --as-str
] {
    if $print {
        let r = dry $x --strip
        if $as_str {
            $r
        } else {
            print -e $"(ansi light_gray)($r)(ansi reset)(char newline)"
        }
    } else {
        ^$x.0 ...(spread ($x | slice 1..))
    }
}
