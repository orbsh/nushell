def cmpl-job [] {
    nomad job status | from ssv -a | get ID
}

def list-alloc [job] {
    mut f = false
    mut r = []
    for x in (nomad job status $job | lines) {
        if $f {
            $r ++= [$x]
        } else {
            if $x == 'Allocations' {
                $f = true
            }
        }
    }
    $r | str join (char newline) | from ssv -a
}

def cmpl-alloc [buffer: string] {
    use argx
    let ctx = $buffer | argx parse
    list-alloc $ctx.pos.job
    | each {|x|
        {
            value: $x.ID
            description: ($x | reject ID | values | str join (char tab))
        }
    }
    | { completions: $in, options: { sort: false } }
}

def cmpl-task [buffer: string] {
    use argx
    let ctx = $buffer | argx parse
    nomad alloc logs $ctx.pos.alloc err>| lines
    | str trim
    | where {$in | str starts-with '*' }
    | each { $in | str substring 2.. }
}

export def nomad-status [
    job?: string@cmpl-job
    alloc?: string@cmpl-alloc
    task?: string@cmpl-task
] {
    if ($job | is-empty) {
        nomad job status | from ssv -a
    } else if ($alloc | is-empty) {
        nomad job status $job
    } else if ($task | is-empty) {
        nomad alloc logs -f $alloc
    } else {
        nomad alloc logs -f $alloc $task
    }
}

export def nomad-ls [
    job?: string@cmpl-job
    alloc?: string@cmpl-alloc
    path?: path = '.'
] {
    nomad alloc fs $alloc $path
}

def cmpl-nomad-file [] {
  do -i {ls **/*.nomad} | append (do -i {ls **/*.hcl}) | get name
}

export def nomad-run [
    file:path@cmpl-nomad-file
    --var(-v): record = {}
    --dry-run(-d)
] {
    $var
    | transpose k v
    | reduce -f {} {|i,a|
        $a | insert $"NOMAD_VAR_($i.k)" $i.v
    }
    | load-env
    if $dry_run {
        nomad job plan $file
    } else {
        nomad job run $file
    }
}

export def nomad-terminate [
    job: string@cmpl-job
] {
    nomad job stop -purge $job
}
