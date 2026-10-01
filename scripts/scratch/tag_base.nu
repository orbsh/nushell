use libs/db.nu *

def cmpl-tags [...prefix] {
    sqlx $"with (tag-tree) select * from tags"
    | get name
    | where { $in | is-not-empty }
    | each {|x| $prefix | each {|y| $"($y)($x)" } }
    | flatten
}

def id-tag [] {
    let id = $in
    sqlx $"with (tag-tree) select * from tags
        join scratch_tag on tags.id = scratch_tag.tag_id
        where scratch_tag.scratch_id = ($id)
    " | get name | each { $":($in)" }
}

export def cmpl-tag-1 [] {
    cmpl-tags ':'
}

export def cmpl-tag-2 [] {
    cmpl-tags '+' '^'
}

export def cmpl-tag-3 [] {
    cmpl-tags ':' '+' '^'
}

export def cmpl-tag-id [] {
    sqlx $"with (tag-tree) select * from tags"
    | each {|x|
        { value: $x.id, description: $x.name }
    }
    | {
        options: { match_description: true, sort: false }
        completions: $in
    }
}

export def cmpl-id-tag [buffer: string] {
    if NU_ARGX_EXISTS not-in $env {
        cmpl-tags ':'
    } else {
        $buffer | argx parse | get -o pos.id | id-tag
    }
}

export def tags-group [] {
    let x = $in
    mut $r = { not: [], and: [], or: [], other: [] }
    for i in $x {
        let h = $i | str substring ..<1
        if $h in ['^' '+' ':'] {
            let v = $i | str substring 1.. | split row ':'
            match $h {
                '^' => {$r.not ++= [$v]}
                '+' => {$r.and ++= [$v]}
                ':' => {$r.or ++= [$v]}
            }
        } else {
            $r.other ++= [$i]
        }
    }
    $r
}

export def group-to-tags [] {
    let o = $in
    $o.other
    | append ($o.not | each { $"^($in | str join ':')" })
    | append ($o.and | each { $"+($in | str join ':')" })
    | append ($o.or | each { $":($in | str join ':')" })
}

export def tag-tree [name?: string='tags' --where: string='parent_id in (-1)'] {
    let t = $"_(random chars -l 3)"
    let n = $"_($t)"
    $"recursive ($t) as \(
        select id, parent_id, hidden, name from tag where ($where)
        union all
        select ($n).id, ($n).parent_id, ($n).hidden, ($t).name || ':' || ($n).name as name from tag as ($n)
        join ($t) on ($t).id = ($n).parent_id
    \), ($name) as \(
        select id, hidden, name from ($t)
    \)"
}

export def scratch-tag-paths-id [...tag_path: list<string>] {
    let a = $tag_path | enumerate
    let ts = $a
    | each {|x| $x.item | each { $"\(($x.index), (Q $in)\)" } }
    | flatten
    | str join ', '

    let q = sqlx $"with recursive input\(gr, name\) as \(
        values ($ts)
    \), v as \(
        select  row_number\(\) over \(partition by gr\) as lv, gr, name from input
    \), g as \(
        select 1 as lv, v.gr, parent_id, id, tag.name from tag
        join v on lv = v.lv
        where v.lv = 1 and tag.name = v.name
        union all
        select g.lv + 1 as lv, g.gr, t.parent_id, t.id, t.name from tag as t
        join v on \(g.lv + 1\) = v.lv and g.gr = v.gr
        join g on g.id = t.parent_id
        where t.name = v.name
    \) select * from g order by gr;"

    mut r = []
    for i in $a {
        let d = $q | where gr == $i.index | reject gr
        let p = ($i.item | length) == ($d | length)
        $r ++= [{path: $i.item, data: $d, present: $p}]
    }
    $r
}

export def scratch-tags-children [...ids] {
    let tags_id = $ids | str join ', '
    let tags_id = $"with recursive g as \(
        select id, parent_id from tag where id in \(($tags_id)\)
        union all
        select t.id, t.parent_id from tag as t join g on g.id = t.parent_id
    \) select id from g
    "
    sqlx $tags_id | get id
}

# add tag
export def scratch-ensure-tags [tags] {
    mut ids = []
    let tags = scratch-tag-paths-id ...$tags
    for tag in $tags {
        let ts = $tag.path
        let r = $tag.data

        mut idx = 0
        mut pid = -1
        mut name = null
        for i in $ts {
            let x = $r | where parent_id == $pid and name == $i
            if ($x | is-empty) {
                $name = $i
                break
            } else {
                $pid = $x.0.id
            }
            $idx += 1
        }

        if ($name != null) {
            for t in ($ts | slice $idx..) {
                $pid = sqlx $"insert into tag \(parent_id, name\) values
                \(($pid), (Q $t)\)
                on conflict \(parent_id, name\) do update set parent_id = EXCLUDED.parent_id
                returning id, name;"
                | get 0.id
                print $"(ansi grey)Tag has been created: (ansi yellow)($t)(ansi reset)"
            }
        }
        $ids ++= [$pid]
    }

    return $ids
}
