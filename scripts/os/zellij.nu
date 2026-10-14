export def zellij-session [] {
    zellij list-sessions -n
    | lines
    | parse -r '^(?<name>[\w-]+) \[(?<time>.+)\]( \((?<status>.+)\))?'
    | select name time status
}

def cmpl-zellij-session [] {
    zellij-session
    | each {|x|
        { value: $x.name, describe: $"($x.status) -- ($x.time)" }
    }
}

export def zellij-enter [name: string@cmpl-zellij-session] {
    zellij attach --create $name
}

export def zellij-delete [name: string@cmpl-zellij-session --force(-f)] {
    mut args = []
    if $force { $args ++= [--force] }
    $args ++= [$name]
    zellij delete-session ...$args
}

export def --env zellij-cd [path?: string] {
    if "ZELLIJ" in $env {
        let dir_name = $path | default $env.PWD | path basename
        zellij action rename-tab $dir_name
    }
    if ($path | is-not-empty) {
        cd $path
    }
}

export def notify-zellij [msg?] {
    let tab = zellij action list-clients | lines | get 1 | split row -r '\s+' | get 1 | split row '_' | get 1
    notify-send $env.pwd ($msg | default '')
    sleep 5sec
    print $"go-to-tab ($tab)"
    zellij action go-to-tab $tab
}
