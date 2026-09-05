use complete.nu *
use base.nu *

# network
export def containers-network-list [
    name?: string@cmpl-docker-network
    --subnet
] {
    if ($name | is-empty) {
        container network ls | from ssv -a
    } else {
        container network inspect $name
        | from json
        | do {
            if $subnet {
                match $env.CNTRCTL {
                    podman => ($in | get subnets.0 )
                    _ => ($in | get IPAM.Config.0)
                }
            } else {
                $in
            }
        }
    }
}

export def containers-network-create [
    name: string
    --driver(-d): string@cmpl-docker-network-driver
] {
    container network create $name
}

export def containers-network-remove [
    network?: string@cmpl-docker-network
    --force(-f)
] {
    if ($network | is-empty) {
        container network prune
    } else {
        container network rm $network ...(if $force { [-f] } else { [] })
    }
}

# list containers
export def container-list [
    container?: string@cmpl-docker-containers
    --all(-a)
] {
    if ($container | is-empty) {
        let fmt = '{"id":"{{.ID}}", "image": "{{.Image}}", "name":"{{.Names}}", "cmd":{{.Command}}, "port":"{{.Ports}}", "status":"{{.Status}}", "created":"{{.CreatedAt}}"}'
        let fmt = if $env.CNTRCTL == 'podman' { $fmt | str replace '{{.Command}}' '"{{.Command}}"' | str replace '{{.CreatedAt}}' '{{.Created}}' } else { $fmt }
        let all = if $all {[-a]} else {[]}
        container ps ...$all --format $fmt
        | lines
        | each {|x|
            let r = $x | from json
            let t = $r.created | date from-human
            let p = $r.port | split row -r '\, *'
            $r
            | upsert port $p
            | upsert created $t
        }
    } else {
        let r = container inspect $container
        | from json
        | get 0

        let image = $r.Image
        let img = container inspect $image
        | from json
        | get 0
        let imgCmd = $img.Config.Cmd?
        let imgEnv = $img.Config.Env?
        | reduce -f {} {|i, a|
            let x = $i | split row '='
            $a | upsert $x.0 $x.1?
        }
        let m = $r.Mounts
        | reduce -f {} {|i, a|
            if $i.Type == 'bind' {
                $a | upsert $i.Source? $i.Destination?
            } else { $a }
        }
        let p = $r.NetworkSettings.Ports? | default {} | transpose k v
        | reduce -f {} {|i, a| $a | upsert $i.k $"($i.v.HostIp?.0?):($i.v.HostPort?.0?)"}

        {
            name: $r.Name?
            hostname: $r.Config.Hostname?
            id: $r.Id
            status: $r.State.Status?
            image: $image
            created: ($r.Created | date from-human)
            ports: $p
            env: $imgEnv
            mounts: $m
            entrypoint: $r.Path?
            cmd: $imgCmd
            args: $r.Args
        }
    }
}

export def parse-img [] {
    let x = $in | split row '/'
    match ($x | length) {
        3 => { reg: $x.0, repo: $x.1, image: $x.2 }
        2 => { repo: $x.0, image: $x.1 }
        _ => { image: $x.0 }
    }
    | each {|x|
        let i = $x.image | split row ':'
        let i = match ($i | length) {
            1 => { image: $i.0, tag: latest }
            2 => { image: $i.0, tag: $i.1 }
        }
        $x | merge $i
    }
}

# list images
export def image-list [
    image?: string@cmpl-docker-images
    --layer
    --history
] {
    if ($image | is-empty) {
        let fmt = '{"id":"{{.ID}}", "repo": "{{.Repository}}", "tag":"{{.Tag}}", "size":"{{.Size}}", "created":"{{.CreatedAt}}"}'
        container images --format $fmt
        | lines
        | each {|x|
            let x = $x | from json
            let name = $"($x.repo):($x.tag)"
            let img = $name | parse-img
            {
                name: $name
                id: $x.id
                created: ($x.created | date from-human)
                size: ($x.size | into filesize)
                reg: $img.reg?
                repo: $img.repo?
                image: $img.image?
                tag: $x.tag?
            }
        }
    } else {
        let r = container inspect $image
            | from json
            | get 0
        let e = $r
            | get -o Config.Env
            | default []
            | reduce -f {} {|i, a|
                let x = $i | split row '='
                $a | upsert $x.0 $x.1?
            }
        let id = if $env.CNTRCTL == 'nerdctl' {
            $r.RepoDigests.0? | split row ':' | get 1 | str substring 0..<12
        } else {
            $r.Id | str substring 0..<12
        }
        let layer = if $layer {
            let l = if $env.CNTRCTL == 'nerdctl' {
                #let root = containerd config dump | from toml | get root
                $r | get RootFS.Layers
            } else {
                $r | get GraphDriver.Data | items {|k,v| $v | split row ':'} | flatten
            }
            {layer: $l}
        } else {
            {}
        }
        let history = if $history {
            {history: $r.History?}
        } else {
            {}
        }

        {
            id: $id
            created: ($r.Created | date from-human)
            author: $r.Author
            arch: $r.Architecture
            os: $r.Os
            size: $r.Size
            labels: $r.Labels?
            user: $r.Config.User?
            env: $e
            ports: $r.Config.ExposedPorts?
            volumes: $r.Config.Volumes?
            workdir: $r.Config.WorkingDir?
            entrypoint: $r.Config.Entrypoint?
            cmd: $r.Config.Cmd?
            ...$layer
            ...$history
        }
    }
}


# container log
export def container-log [
    container: string@cmpl-docker-containers
    -l: int = 100 # line
] {
    let l = if $l == 0 { [] } else { [--tail $l] }
    container logs -f ...$l $container
}

export def container-log-trunc [
    container: string@cmpl-docker-containers
] {
    if $env.CNTRCTL == 'podman' {
        print -e $'(ansi yellow)podman(ansi dark_gray) isn’t supported(ansi reset)'
    } else {
        let f = container inspect --format='{{.LogPath}}' $container
        truncate -s 0 $f
    }
}

# attach container
export def --wrapped container-attach [
    container: string@cmpl-docker-containers
    ...args
] {
    if ($args | is-empty) {
        let cmd = [
            '/usr/local/bin/nu'
            '/bin/nu'
            '/bin/bash'
            '/bin/sh'
        ]
        | str join ' '
        | $"for sh in ($in); do if [ -e $sh ]; then exec $sh; fi; done"
        container exec -it $container /bin/sh -c $cmd
    } else {
        container exec -it $container ...$args
    }
}


# copy file
export def container-copy-file [
    lhs: path@cmpl-docker-cp
    rhs: path@cmpl-docker-cp
] {
    container cp (expand-exists $lhs) (expand-exists $rhs)
}

# remove container
export def container-remove [
    container: string@cmpl-docker-containers
] {
    let cs = container ps -a | from ssv -a | get NAMES
    if $container in $cs {
        container container rm -f $container
    } else {
        print -e $"(ansi grey)container (ansi yellow)($container)(ansi grey) not exist(ansi reset)"
    }
}

# commit container
export def container-commit [
    container: string@cmpl-docker-containers
    name: string
] {
    container commit $container $name
}

# history
export def container-history [image: string@cmpl-docker-images] {
    container history --no-trunc $image | from ssv -a
}


# save images
export def image-save [...image: string@cmpl-docker-images] {
    container save ...$image
}

# load images
export def image-load [] {
    $in | container load
}

# system prune
export def system-prune [] {
    container system prune -f
}

# system prune all
export def system-prune-all [] {
    container system prune --all --force --volumes
}

# remove image
export def image-remove [
    image: string@cmpl-docker-images
    --force(-f)
] {
    mut args = []
    if $force { $args ++= [--force] }
    container rmi ...$args $image
}

# add new tag
export def image-tag [
    from: string@cmpl-docker-images
    to: string
    --rename(-r)
] {
    container tag $from $to
    print $"(ansi grey)Tagged: ($from) => ($to)(ansi reset)"
    if $rename {
        container rmi $from
    }
}

# push image
export def image-push [
    image: string@cmpl-docker-images
    --tag(-t): string
    -i
] {
    let $insecure = if $i {[--insecure-registry]} else {[]}
    if ($tag | is-empty) {
        container ...$insecure push $image
    } else {
        container tag $image $tag
        do -i {
            container ...$insecure push $tag
        }
        container rmi $tag
    }
}

# pull image
export def image-pull [
    image
    --insecure(-i)
    --rename(-r):string
    --strip:int=0
    --dry-run
] {
    let $insecure = if $insecure {[--insecure-registry]} else {[]}

    let name = if ($rename | is-not-empty) {
        $rename
    } else if $strip > 0 {
        let n = $image | parse-img
        match $strip {
            1 => $"($n.repo)/($n.image):($n.tag)",
            2 => $"($n.image):($n.tag)",
            3 => $"($n.image)"
            _ => $image
        }
    } else {
        ""
    }

    if $dry_run {
        print $name
        return
    }

    container ...$insecure pull $image
    if ($name | is-not-empty) {
        image-tag --rename $image $name
    }
}

### list volume
export def volume-list [] {
    container volume ls | from ssv -a | rename name dir
}

# create volume
export def volume-create [name: string] {
    container volume create $name
}

# inspect volume
export def volume-inspect [name: string@cmpl-docker-volume] {
    container volume inspect $name
}

# remove volume
export def volume-remove [...name: string@cmpl-docker-volume] {
    container volume rm ...$name
}

# dump volume
export def volume-dump [
    name: string@cmpl-docker-volume
    --image(-i): string='debian'
] {
    let id = random chars -l 6
    container ...[
        run --rm
        -v $"($name):/tmp/($id)"
        $image
        sh -c $'cd /tmp/($id); tar -zcf - *'
    ]
}

# restore volume
export def volume-restore [
    name: string@cmpl-docker-volume
    --from(-f): string
    --image(-i): string='debian'
] {
    let id = random chars -l 6
    let src = random chars -l 6
    container ...[
        run --rm
        -v $"($name):/tmp/($id)"
        -v $"(host-path $from):/tmp/($src)"
        $image
        sh -c $'cd /tmp/($id); tar -zxf /tmp/($src)'
    ]
}


export def host-path [path] {
    match ($path | str substring ..<1) {
        '/' => { $path }
        '=' => { $path | str substring 1.. }
        '~' => { [ $env.HOME ($path | str substring 2..) ] | path join }
        '$' => { $env | get ($path | str substring 1..) }
        _   => { [ $env.PWD $path ] | path join }
    }
}

def image-vol [path target --rw] {
    let iv = match $env.CNTRCTL {
        podman => [
            type=image
            $"source=($path)"
            $"destination=($target)"
            $"rw=($rw)"
        ],
        _ => [
            type=image
            $"src=($path)"
            $"dst=($target)"
            $"readonly=(not $rw)"
        ]
    }
    | str join ','
    [ --mount $iv ]
}

def mk-mount [path target] {
    let first = $path | str substring ..<1
    match $first {
        '@' | '^' => {
            image-vol ($path | str substring 1..) $target --rw=($first == '^')
        }
        _ =>  [-v $"(host-path $path):($target)"]
    }
}

export def --env image-volume-register [
    name
    image
    --mount(-m): string
] {
    let m = if ($mount | is-empty) {
        $'/opt/($name)'
    } else {
        $mount
    }
    $env.CNTRLAYER = ($env.CNTRLAYER | upsert $name {
        image: $image
        mount: $m
    })
    image-pull $image
}

# run
export def --wrapped container-create [
    --name: string
    --debug(-x)
    --appimage
    --netadmin
    --user(-u): string
    --master-user(-U)
    --proxy: string@cmpl-docker-run-proxy      # proxy
    --ssh(-s): string@cmpl-docker-run-sshkey   # specify ssh key
    --sshuser: string=root                     # default root
    --mnt(-m): string@cmpl-docker-run-vol      # mnt
    --vols(-v): record                         # { host: container }
    --ports(-p): record                        # { 8080: 80 }
    --envs(-e): record                         # { FOO: BAR }
    --daemon(-d)
    --join(-j): string@cmpl-docker-containers  # join
    --network: string@cmpl-docker-network      # network
    --workdir(-w): string                      # workdir
    --entrypoint: string                       # entrypoint
    --dry-run
    --with-x
    --nvidia:int
    --privileged(-P)
    --image-volumes(-V): list<string>@cmpl-image-vols # image volumes
    --options: list<string>
    image: string@cmpl-docker-images           # image
    ...cmd                                     # command args
] {
    mut args = []

    if ($user | is-not-empty) {
        $args ++= [--user $user]
    } else if $master_user {
        $args ++= [--user 1000]
    }
    if $daemon {
        $args ++= [-d]
    } else {
        $args ++= [--rm -it]
    }
    if $debug {
        $args ++= [--cap-add=SYS_ADMIN --cap-add=SYS_PTRACE --security-opt seccomp=unconfined]
    }
    if $appimage {
        $args ++= [--device /dev/fuse --security-opt apparmor:unconfined]
    }
    if $privileged {
        $args ++= [--privileged]
    }
    if $netadmin {
        $args ++= [--cap-add=NET_ADMIN --device /dev/net/tun]
    }
    if $with_x {
        $args ++= [-e $"DISPLAY=($env.DISPLAY?)" -v /tmp/.X11-unix:/tmp/.X11-unix]
    }

    if ($entrypoint | is-not-empty) {
        $args ++= [--entrypoint $entrypoint]
    }
    if ($mnt | is-not-empty) {
        $args ++= [-v $mnt]
    }
    if ($workdir | is-not-empty) {
        $args ++= [-w $workdir -v $"($env.PWD):($workdir)"]
    }
    if ($vols | is-not-empty) {
        $args ++= $vols | items {|k, v| mk-mount $k $v } | flatten
    }
    if ($image_volumes | is-not-empty) {
        $args ++= $image_volumes
        | each {|x|
            let d = $env.CNTRLAYER | get $x
            image-vol $d.image $d.mount --rw=($d.rw? | default false)
        }
        | flatten
    }
    if ($envs | is-not-empty) {
        $args ++= $envs | items {|k, v| [-e $"($k)=($v)"] } | flatten
    }
    if ($ports | is-not-empty) {
        for i in ($ports | transpose k v) {
            mut is_udp = false
            let p = if ($i.k | str substring (-4).. | str lowercase) == '/udp' {
                $is_udp = true
                $i.k | str substring 0..-5 | into int
            } else {
                $i.k | into int
            }
            let k = port $p
            let v = if $is_udp { $"($i.v)/udp" } else { $"($i.v)" }
            print $"(ansi grey)port: ($k) (if $k == $p {'->'} else {'=>'}) ($v)(ansi reset)"
            $args ++= [-p $"($k):($v)"]
        }
    }
    if ($proxy | is-not-empty) {
        $args ++= [-e $"http_proxy=($proxy)" -e $"https_proxy=($proxy)"]
    }

    if ($ssh | is-not-empty) {
        let sshkey = cat ([$env.HOME .ssh $ssh] | path join) | split row ' ' | get 1
        $args ++= [-e $"ed25519_($sshuser)=($sshkey)"]
    }

    if ($nvidia | is-not-empty) {
        $args ++= if $env.CNTRCTL in ['podman'] {
            if $nvidia == 0 {
                [--device nvidia.com/gpu=all --ipc=host]
            } else {
                [--gpus $nvidia]
            }
        } else {
            [--runtime nvidia --gpus (if $nvidia == 0 { 'all' } else { $nvidia }) --ipc=host]
        }
    }

    if ($join | is-not-empty) {
        let c = $"container:($join)"
        $args ++= [--pid $c --network $c]
        if $env.CNTRCTL in ['podman'] { $args ++= [--uts $c --ipc $c] }
    }
    if ($network | is-not-empty) and ($join | is-empty) {
        $args ++= [--network $network]
    }

    let name = if ($name | is-empty) {
        let img = $image | split row '/' | last | str replace ':' '-'
        let now = date now | format date %m%d%H%M
        $"($img)_($now)"
    } else {
        let c = container-list | where name == $name
        if ($c | is-not-empty) {
            container-remove $name
        }
        $name
    }

    let options = if ($options | is-empty) { [] } else { $options }

    if $dry_run {
        echo ([docker run --name $name $options $args $image $cmd] | flatten | str join ' ')
    } else {
        container run --name $name ...$options ...$args $image ...$cmd
    }
}


export def --wrapped container-preset [
    preset:string@cmpl-preset
    ...cmd
    --vols(-v): any = {}
    --ports(-p): any = {}
    --envs(-e): any = {}
    --proxy: string@cmpl-docker-run-proxy
    --ssh(-s): string@cmpl-docker-run-sshkey
    --debug(-d)
    --privileged(-P)
    --netadmin
    --with-x
    --dry-run
] {
    let c = open $env.CNTRCONFIG | get preset | where name == $preset
    if ($c | is-empty) {
        print $"(ansi grey)Oops!(ansi reset)"
    } else {
        let c = $c.0
        let image = $c.image
        let cmd = if ($cmd | is-empty) { $c.command } else { $cmd }
        (container-create
            --name=$c.container_name?
            --daemon=$c.daemon
            --envs {...$c.environment, ...$envs}
            --vols {...$c.volumes, ...$vols}
            --ports {...$c.ports, ...$ports}
            --workdir=$c.working_dir?
            --debug=$debug
            --privileged=$privileged
            --netadmin=$netadmin
            --with-x=$with_x
            --proxy=$proxy
            --ssh=$ssh
            --dry-run=$dry_run
            --entrypoint=$c.entrypoint?
            --options=$c.options?
            $image ...$cmd)
    }
}
