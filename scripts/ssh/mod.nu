use argx

export def 'str max-length' [] {
    $in | reduce -f 0 {|x, a|
        if ($x|is-empty) { return $a }
        let l = ($x | str length)
        if $l > $a { $l } else { $a }
    }
}

def cmpl-env [] {
    open ([$env.HOME .ssh index.toml] | path join)
    | transpose k v
    | get v
    | each {|x|
        $x | transpose k v | get v | transpose k v | get k
    }
    | flatten
    | uniq
    | where {|x| $x != 'default' }
}

def cmpl-group [] {
    open ([$env.HOME .ssh index.toml] | path join)
    | columns
}

export def ssh-switch  [
    environ?: string@cmpl-env
    --group(-g): string@cmpl-group
    --no-compression
    --forward
    --no-hostkey-checking
    --password-authentication
] {
    {
        environ: $environ
        group: $group
    }
    | to json
    | save -f ([$env.HOME .ssh index.json] | path join)

    mut o = []
    if $password_authentication {
        $o ++= [
            "PasswordAuthentication yes"
            "PubkeyAuthentication no"
        ]
    }
    if not $no_compression {
        $o ++= ["Compression yes"]
    }
    if $forward {
        $o ++= ["ForwardAgent yes"]
    }
    if $no_hostkey_checking {
        $o ++= [
            "StrictHostKeyChecking no"
            "UserKnownHostsFile /dev/null"
        ]
    }
    let c = open ([$env.HOME .ssh index.toml] | path join)
    let gr = if ($group | is-empty) {
        $c
    } else {
        $c | select $group
    }
    for i in ($gr | transpose k v) {
        $o ++= [$"### ($i.k)"]
        for j in ($i.v | transpose k v) {
            $o ++= [$"Host ($j.k)"]
            let v = $j.v | get default
            let v = if ($environ | is-empty) {
                $v
            } else {
                $v | merge ($j.v | get -o $environ | default {})
            }
            for l in ($v | transpose k v) {
                if ($l.v | is-not-empty) {
                    $o ++= [$"    ($l.k) ($l.v)"]
                }
            }
        }
    }
    $o | save -f ([$env.HOME .ssh config] | path join)
}

export def cmpl-ssh [buffer?] {
    if ($buffer | is-not-empty) {
        do -i {
            let target = $buffer | argx parse | get opt
            let environ = $target | get -o environ
            let group = $target | get -o group
            if ($environ | is-not-empty) or ($group | is-not-empty) {
                ssh-switch $environ --group $group
            }
        }
    }

    let t = [$env.HOME .ssh index.toml] | path join
    if not ($t | path exists) {
        ssh-index-init
        ssh-switch
    }
    let e = open ([$env.HOME .ssh index.json] | path join)
    open $t
    | do {
        let x = $in
        if ($e.group? | is-empty) {
            $x
        } else {
            $x | select $e.group
        }
    }
    | transpose k v
    | get v
    | each {|x|
        $x | transpose k v | each {|y|
            if ($e.environ? | is-empty) {
                $y.v.default
            } else {
                $y.v.default | merge ($y.v | get -o $e.environ | default {})
            }
            | insert name $y.k
        }
    }
    | flatten
    | each {|x|
        {
            value: $x.name
            description: $"($x.User? | default 'root')@($x.HostName? | default localhost):($x.Port? | default 22)"
        }
    }
}

export def --wrapped main [
    host: string@cmpl-ssh               # host
    ...cmd                              # cmd
    --environ: string@cmpl-env
    --group: string@cmpl-group
    -v                                  # verbose
    -i: string                          # key
    -p: int                             # port
] {
    let o = $in
    mut args = []
    if $v { $args ++= [-v] }
    if ($i | is-not-empty) { $args ++= [-i $i] }
    if ($p | is-not-empty) { $args ++= [-p $p] }
    if ($o | is-empty) {
        ssh $host ...$args ...$cmd
    } else {
        $o | ssh $host ...$args ...$cmd
    }
}

export use parse.nu *
export use utils.nu *
