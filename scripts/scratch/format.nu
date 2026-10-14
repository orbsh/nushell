use common.nu *

export def scratch-format [
    --md
    --md-list
    --body-lines: int=2
    --indent: int=2
] {
    $in | to tree | fmt tree --indent $indent --body-lines $body_lines --md=$md --md-list=$md_list | get txt
}

export def tag-format [
    tags
    --md
    --md-list
    --body-lines: int=2
    --indent: int=2
    --accumulator: record
] {
    $in
    | to tree
    | tagsplit $tags
    | tag tree
    | fmt tag-tree --indent $indent --body-lines $body_lines --md=$md --md-list=$md_list --accumulator $accumulator
    | get txt
}

def 'list starts-with' [b] {
    let a = $in
    if ($a | length) < ($b | length) { return false }
    for i in ($b | enumerate) {
        if $i.item != ($a | get $i.index) {
            return false
        }
    }
    true
}

def 'tagsplit' [tags] {
    let o = $in
    let x = $o | default [] | reverse | each {|i|
        let t = $i.tags
        let s = if ($tags | is-empty) {
            [
                [$i.tags.0?]
                ($i.tags | slice 1..)
            ]
        } else {
            let l = $tags.0 | length
            let multi_tags = ($tags | length) > 1
            mut m = []
            mut n = []
            for x in $i.tags {
                if ($tags | any {|y| $x | list starts-with $y }) {
                    if $multi_tags {
                        $m ++= [$x]
                    } else {
                        $m ++= [($x | slice $l..)]
                    }
                } else {
                    $n ++= [$x]
                }
            }
            [$m $n]
        }
        let main = $s.0
        let node = $i | update tags {|x| $s.1 }
        $main | each {|m| {tags: $m, node: $node} }
    }
    $x | flatten
}

def 'fmt tag-tree' [
    level:int=0
    --indent(-i):int=2
    --padding(-p):int=0
    --body-lines: int=2
    --md
    --md-list
    --accumulator: record
] {
    let o = $in
    mut out = []
    mut acc = []
    mut done = []
    # Siblings' leaf come before branch
    if ':' in $o {
        let j = $o | get ':' | fmt tree ($level) --indent $indent --body-lines $body_lines --md=$md --md-list=$md_list --accumulator $accumulator
        $out ++= [$j.txt]
        $acc ++= [$j.acc]
        $done ++= [$j.done]
    }
    for i in ($o | transpose k v | where {|x| $x.k != ':' }) {
        let instr = '' | fill -c ' ' -w ($padding + $level * $indent)
        # TODO:
        let x = $i.v | fmt tag-tree ($level + 1) --indent $indent --body-lines $body_lines --md=$md --md-list=$md_list --accumulator $accumulator
        $out ++= [({k: $i.k, v: $x.acc, d: $x.done} | fmt tag $instr --md=$md --md-list=$md_list)]
        $out ++= [$x.txt]
        $acc ++= [$x.acc]
        $done ++= [$x.done]
    }
    let acc = if ($accumulator | is-empty) {
        {}
    } else {
        $acc | reduce -f {} {|i,a| $a | map-acc $accumulator $i }
    }
    {
        txt: ($out | flatten | str join (char newline))
        acc: $acc
        done: ($done | all { $in })
    }
}

def 'fmt tag' [
    indent
    --md
    --md-list
] {
    let o = $in
    let color = $env.SCRATCH_THEME.color
    let done = $env.SCRATCH_THEME.symbol.box | get ($md | into int) | get ($o.d | into int)
    if $md_list {
        [$"($indent)($env.SCRATCH_THEME.symbol.md_list)" $o.k]
    } else if $md {
        [$"($indent)($env.SCRATCH_THEME.symbol.md_list)" $done $o.k]
    } else {
        let vs = $o.v | items {|k, v|
            let c = if $v < 0 { $color.value.negative } else { $color.value.positive }
            $"(ansi grey)($k):(ansi $c)($v)(ansi reset)"
        }
        | str join ' '
        [$"($indent)($done)" $"(ansi $color.branch)($o.k)(ansi reset)" $vs]
    }
    | str join ' '
}


def 'tag tree' [] {
    let a = $in
    mut r = {}
    for i in $a {
        $r = tag-tree $i $r
    }
    $r
}

def tag-tree [x r={}] {
    let t = $x.tags.0? | default ''
    let o = $r | get -o $t | default {}
    if ($x.tags | length) > 0 {
        $r | upsert $x.tags.0 (
            tag-tree ($x | update tags ($x.tags | slice 1..)) $o
        )
    } else {
        let n = if ':' in $r {
            $r | update ':' {|m| $m | get ':' | append $x.node}
        } else {
            $r | insert ':' [$x.node]
        }
        if $t == '' {
            $r | merge $n
        } else {
            $r | upsert $t $n
        }
    }
}

export def 'to tree' [] {
    let i = $in
    # dynamically determines the root node
    let all_ids = $i | get id | uniq
    let root_ids = $i | get parent_id | uniq | where { $in not-in $all_ids }
    let root = $i | where parent_id in $root_ids
    if ($root | is-empty) { return }
    to-tree $root ($i | group-by parent_id)
}

def to-tree [root o] {
    $root | each {|i|
        let k = $i.id | into string
        let t = if $k in $o {
            to-tree ($o | get $k) $o
        } else {
            []
        }
        $i | insert children $t
    }
}

def map-acc [acc:record merge?:record] {
    let o = $in
    $acc
    | items {|k, v|
        let v = if ($v | describe) == 'closure' { [$v $v] } else { $v }
        let v = if ($merge | describe) == 'nothing' {
            $o | do $v.0 $o
        } else {
            let o = [$o $merge] | each { $in | get -o $k | default 0 }
            $o | do $v.1 $o
        }
        {k: $k, v: $v}
    }
    | reduce -f {} {|i, a|
        $a | insert $i.k $i.v
    }
}

def 'fmt tree' [
    level:int=0
    --indent(-i):int=2
    --padding(-p):int=0
    --body-lines: int=2
    --md
    --md-list
    --accumulator: record
] {
    mut out = []
    mut col = []
    mut acc = {}
    mut done = []
    for i in $in {
        $col ++= [$i]
        $done ++= [$i.done]
        let prefix = '' | fill -c ' ' -w ($padding + $level * $indent)
        let l = $i
        | reject children
        | fmt leaves $prefix --body-lines $body_lines --md=$md --md-list=$md_list --show-value=($accumulator | is-not-empty)
        for j in $l {
            $out ++= [$j]
        }
        if ($i.children | is-not-empty) {
            let x = $i.children | fmt tree ($level + 1) --indent $indent --body-lines $body_lines --md=$md --md-list=$md_list --accumulator $accumulator
            $out ++= [$x.txt]
            $acc = $x.acc
        }
    }
    let acc = if ($accumulator | is-empty) {
        {}
    } else {
        $col | map-acc $accumulator | map-acc $accumulator $acc
    }
    {
        txt: ($out | flatten | str join (char newline))
        acc: $acc
        done: ($done | all { $in > 0 })
    }
}

def 'fmt leaves' [
    indent
    --md
    --md-list
    --body-lines: int=2
    --show-value
] {
    let o = $in
    let color = $env.SCRATCH_THEME.color
    let formatter = $env.SCRATCH_THEME.formatter

    let done = $env.SCRATCH_THEME.symbol.box | get ($md | into int) | get $o.done
    let title = if $md_list {
        [$"($indent)($env.SCRATCH_THEME.symbol.md_list)" $o.title $"#($o.id)"]
    } else if $md {
        [$"($indent)($env.SCRATCH_THEME.symbol.md_list)" $done $o.title $"#($o.id)"]
    } else {
        [$"($indent)($done)" $"(ansi $color.title)($o.title)" $"(ansi $color.id)#($o.id)"]
    }
    let verbose = not $md and not $md_list

    let value = if $verbose and $show_value {
        let c = if $o.value < 0 { $color.value.negative } else { $color.value.positive }
        $"(ansi $c)($o.value)(ansi reset)"
    }

    let tags = if $verbose and ($o.tags? | is-not-empty) {
        let ct = ansi $color.tag
        $o.tags | each {|x| $"($ct)($x | str join ':')" }
        # :TODO:
        #| group-by cat
        #| items {|k,v| $"(ansi $color.cat)($k):(ansi $color.tag)($v.tag | str join '/')"}
    } else {
        []
    }

    let dd = if $o.done == 0 { [deadline] } else { [] }
    let meta = [important urgent challenge ...$dd created updated]
    | each {|x|
        let y = $o | get -o $x
        let z = match ($y | describe) {
            int => $y
            string => {$y | str length}
            _ => -1
        }
        if $verbose and $z > 0 {
            $"(ansi ($color | get $x))(do ($formatter | get $x) $y $o)"
        }
    }


    mut body_len = 0
    let body = if $verbose and ($o.body? | is-not-empty) {
        let l = $o.body | lines
        $body_len = $l | length
        $l
        | slice ..<$body_lines
        | each {$"($indent)  (ansi $color.body)($in)(ansi reset)"}
    } else { [] }

    let body_info = if $body_len > 0 { $"(ansi grey)($o.kind):($body_len)" }

    let header = [...$title $value ...$tags ...$meta $body_info]
    | where { $in | is-not-empty }
    | str join ' '
    |  if $verbose { $"($in)(ansi reset)" } else { $in }

    [$header ...$body]
}
