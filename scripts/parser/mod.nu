def spy [l=9] {
    if true {
        $in | str substring ..$l
    }
}


export def any-char [t: string] {
    {|pos|
        let o = $in
        let i = $o | parse -r '^(?<s>.+)'
        if ($i | is-not-empty) {
            {
                len: ($i.0.s | str length)
                pos: $pos
                val: ($i.0.s)
            }
        } else {
            {
                len: -1
                pos: $pos
            }
        } | merge {
            typ: mid
            tag: $t
        }
    }
}

export def word [t: string] {
    {|pos|
        let o = $in
        let i = $o | parse -r '^(?<s>[^\s]+)'
        if ($i | is-empty) {
            {
                len: -1
                pos: $pos
            }
        } else {
            {
                len: ($i.0.s | str length)
                pos: $pos
                val: $i.0.s
            }
        } | merge {
            typ: word
            tag: $t
            ctx: ($o | spy)
        }
    }
}

export def lit [t: string, e] {
    {|pos|
        let o = $in
        let l = $e | str length
        let a = $o | str substring 0..<$l
        if $a == $e {
            {
                len: $l
                pos: $pos
                val: $e
            }
        } else {
            {
                len: -1
                pos: $pos
                err: $e
            }
        } | merge {
            typ: lit
            tag: $t
            ctx: ($o | spy)
        }
    }
}

export def cap0 [t: string, e] {
    {|pos|
        let o = $in
        let r = $o | parse -r $"^($e).*"
        if ($r | is-empty) {
            {
                len: -1
                pos: $pos
                err: $e
            }
        } else {
            let r = $r.0.capture0
            {
                len: ($r | str length)
                pos: $pos
                val: $r
            }
        } | merge {
            typ: cap
            tag: $t
            ctx: ($o | spy)
        }
    }

}

export def end-of-line [t: string] {
    {|pos|
        let o = $in
        let i = $o | str index-of (char newline)
        if $i < 0 {
            {
                len: -1
                pos: $pos
            }
        } else {
            {
                len: ($i + 1) # include "\n"
                pos: $pos
                val: (if $i == 0 { '' } else { $o | str substring 0..<($i) })
            }
        } | merge {
            typ: eol
            tag: $t
            ctx: ($o | spy)
        }
    }
}

export def new-line [t=''] {
    {|pos|
        let o = $in
        let i = $o | str substring ..<1
        if $i == (char newline) {
            {
                len: 1
                pos: $pos
                val: ''
            }
        } else {
            {
                len: -1
                pos: $pos
            }
        } | merge {
            typ: nl
            tag: $t
            ctx: ($o | spy)
        }
    }
}


export def space [t='', --with-line(-l)] {
    let re = if $with_line { '^(?<s>[ \s\n]+)' } else { '^(?<s>[ \s]+)' }
    {|pos|
        let o = $in
        let i = $o | parse -r $re
        if ($i | is-empty) {
            {
                len: -1
                pos: $pos
            }
        } else {
            let v = $i.0.s
            if (not $with_line) and ($v | str index-of (char newline)) >= 0 {
                {
                    len: -1
                    pos: $pos
                }
            } else {
                {
                    len: ($v | str length)
                    pos: $pos
                    val: ''
                }
            }
        } | merge {
            typ: space
            tag: $t
            ctx: ($o | spy)
        }
    }
}

export def recursive [t: string, n] {
    {|pos|
        let o = $in
        let cls = scope variables | where name == $n | get 0.value
        $o | do $cls $pos
    }
}

export def one-of [t: string, s] {
    {|pos|
        let o = $in
        mut err = {}
        for i in $s {
            let x = $o | do $i $pos
            if $x.len < 0 {
                $err = $x
                continue
            } else {
                return ($x | merge {typ: $":($x.typ)", tag: $t})
            }
        }
        {
            typ: select
            tag: $t
            len: -1
            pos: $pos
            ctx: ($o | spy)
            err: $err
        }
    }

}

def _more [t: string, s, --zero(-z), --one(-o)] {
    {|pos|
        let o = $in
        mut p = 0
        mut r = []
        mut err = {}
        while true {
            if $one and ($r | length) > 0 {
                break
            }
            let y = $o | str substring $p..
            let x = $y | do $s $p
            if $x.len < 0 {
                $err = $x
                break
            } else {
                $p += $x.len
            }
            $r ++= [$x]
        }
        if (not $zero) and ($r | is-empty)  {
            {
                len: -1
                pos: $pos
                err: $err
            }
        } else {
            {
                len: ($p + ($r | last).len)
                pos: $pos
                val: $r
            }
        } | merge {
            typ: repeat
            tag: $t
            ctx: ($o | str substring $p.. | spy)
        }
    }
}

export def one-or-more [t: string, s] {
    $in | _more $t $s
}

export def zero-or-more [t: string, s] {
    $in | _more $t $s --zero
}

export def zero-or-one  [t: string, s] {
    $in | _more $t $s --one
}

export def one-by-one [t: string, s] {
    {|pos=0|
        let o = $in
        mut p = 0
        mut r = []
        for i in $s {
            let y = $o | str substring $p..
            let x = $y | do $i $p
            if $x.len < 0 {
                return {
                    typ: seq
                    tag: $t
                    len: -1
                    pos: $pos
                    ctx: ($o | spy)
                    result: $r
                    err: $x
                }
            } else {
                $p += $x.len
            }
            $r ++= [$x]
        }
        {
            typ: seq
            tag: $t
            len: $p
            pos: $pos
            val: $r
            ctx: ($o | spy)
        }
    }
}
