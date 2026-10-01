use base.nu *

export def cmpl-image-vols [] {
    $env.CNTRLAYER | keys
}

export def cmpl-docker-network [] {
    containers-network-list | get NAME
}

export def cmpl-docker-network-driver [] {
    [bridge host none overlay ipvlan macvlan]
}

export def cmpl-docker-ps [] {
    container ps
    | from ssv -a
    | each {|x| {description: $x.NAMES value: $x.'CONTAINER ID'}}
}

export def cmpl-docker-containers [] {
    container ps -a
    | from ssv -a
    | each {|i|
        let st = if ($i.STATUS | str starts-with 'Up') { ' ' } else { '!' }
        { id: $i.'CONTAINER ID', name: $i.NAMES, status: $st }
    }
    | group-by name
    | transpose k v
    | each {|i|
        let s = ($i.v | length) == 1
        $i.v | each {|i|
            if $s {
                {value: $i.name, description: $"($i.status) ($i.id)"}
            } else {
                {value: $i.id, description: $"($i.status) ($i.name)"}
            }
        }
    }
    | flatten
}

# TODO: filter by description
export def cmpl-docker-containers-b [] {
    container ps -a
    | from ssv -a
    | each {|i|
        let s = if ($i.STATUS | str starts-with 'Up') { ' ' } else { '!' }
        { value: $i.'CONTAINER ID', description: $"($s) ($i.NAMES)" }
    }
}

export def cmpl-docker-images [] {
    container images
    | from ssv
    | each {|x| $"($x.REPOSITORY):($x.TAG)"}
}

export def cmpl-docker-cp [buffer: string] {
    let argv = $buffer | split row ' '
    let p = if ($argv | length) > 2 { $argv | get 2 } else { $argv | get 1 }
    let container = container ps
        | from ssv -a
        | each {|x| {description: $x.'CONTAINER ID' value: $"($x.NAMES):" }}
    let n = $p | split row ':'
    if $"($n | get 0):" in ($container | get value) {
        container exec ($n | get 0) sh -c $"ls -dp ($n | get 1)*"
        | lines
        | each {|x| $"($n | get 0):($x)"}
    } else {
        let files = do -i {
            ls -a ($"($p)*" | into glob)
            | each {|x| if $x.type == dir { $"($x.name)/"} else { $x.name }}
        }
        $files | append $container
    }
}


export def cmpl-docker-volume [] {
    container volume ls
    | from ssv -a
    | get 'VOLUME NAME'
}

### run
export def cmpl-docker-run-vol [] {
    [
        $"($env.PWD):/world"
        $"($env.PWD):/app"
        $"($env.PWD):/srv"
        $"($env.HOME)/.config/nvim:/etc/nvim"
    ]
}

export def cmpl-docker-run-sshkey [ctx: string, pos: int] {
    ls ~/.ssh/**/*.pub
    | get name
    | path relative-to ~/.ssh
}

export def cmpl-docker-run-proxy [] {
    let hostaddr = do -i { hostname -I | split row ' ' | get 0 }
    [ $"http://($hostaddr):7890" $"http://($hostaddr):" ]
}

export def cmpl-preset [] {
    open $env.CNTRCONFIG | get preset.name
}
