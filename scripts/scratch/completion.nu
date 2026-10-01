use common.nu *
use libs/db.nu *

export def cmpl-scratch-id [] {
    sqlx "select id as value,
        case parent_id when -1 then title else '    ' || title end as description
        from scratch order by updated desc;"
    | { completions: $in, options: { sort: false } }
}

export def list-untagged-root [type, ctx] {
    let ts = term size
    let rw = $ts.columns
    let ch = $ts.rows - 5
    let cond = if ($ctx | is-not-empty) {
        mut r = []
        if ($ctx.kind? | is-not-empty) { $r ++= [$"s.kind = (Q $ctx.kind)"] }
        if ($ctx.preset? | is-not-empty) { $r ++= [$"p.preset = (Q $ctx.preset)"] }
        $r
    }
    let pr = match $type {
        id => ['s.id as value', "ltrim(s.title || ' ')"]
        title => ['s.title as value', "s.id || ' '"]
    }
    let cond = if $type == 'title' { $cond | append $"length\(s.title\) > 0" } else { $cond }
    let cond = if ($cond | is-empty) { "" } else { $"and ($cond | str join ' and ')" }
    let q = $"select ($pr.0),
        substr\(
            updated || '│' ||
            printf\('%-10s', s.kind\) || '│' ||
            printf\('%-10s', p.preset\) || '│' ||
            ($pr.1) || '⯒' || ltrim\(s.body\),
            0 , ($rw)
        \) as description
    from scratch as s
    left outer join scratch_tag as t on s.id = t.scratch_id
    left outer join scratch_preset as p on s.id = p.scratch_id
    where t.tag_id is null and s.parent_id = -1 and s.deleted = '' ($cond)
    order by updated desc limit ($ch);"
    sqlx $q
    | update description {|x|
        $x.description | str substring 0..$rw | str replace '⯒' (ansi grey)
    }
    | { completions: $in, options: { sort: false } }
}

export def cmpl-untagged-root-scratch [buffer: string] {
    let cond = if NU_ARGX_EXISTS in $env {
        $buffer | argx parse | get opt
    }
    list-untagged-root id $cond
}

export def cmpl-untagged-root-title [buffer: string] {
    let cond = if NU_ARGX_EXISTS in $env {
        $buffer | argx parse | get opt
    }
    list-untagged-root title $cond
}

export def cmpl-sort [] {
    [created, updated, deadline, done, important, urgent]
    | each {[$"!(in)" $in]}
    | flatten
}


export def cmpl-relevant-id [] {
    sqlx 'select id, name from person;'
    | each {|x|
        { value: $x.id, description: $x.name }
    }
    | {
        options: { match_description: true, sort: false }
        completions: $in
    }
}


export def cmpl-todo-md [] {
    ls **/TODO.md | get name
}

export def cmpl-accumulator [] {
    $env.SCRATCH_ACCUMULATOR | columns
}
