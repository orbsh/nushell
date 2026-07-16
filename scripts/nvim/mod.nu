## neovim configurations in `nvim.lua`
## or https://github.com/orbsh/nvim-taberm

export def nvim-send [message: string --expr] {
    let msg = if $expr {
        [--remote-expr $message]
    } else {
        [--remote-send $message]
    }
    nvim --headless --noplugin --server $env.NVIM ...$msg
}

export def nvim-lua [...expr: string] {
    let var = 'remote_expr_lua_temp_var'
    nvim-send $'<cmd>lua vim.g.($var) = nil; vim.g.($var) = ($expr | str join " ")<cr>'
    nvim-send --expr $'g:($var)'
}

# nvim tcd
export def tcd [path?: string] {
    let after = if ($path | is-empty) {
        $env.PWD
    } else {
        $path
    }
    nvim-send $"<cmd>lua HookPwdChanged\('($after)', '($env.PWD)')<cr>"
}

export-env {
    if ($env.NVIM? | is-not-empty) {
        $env.config.hooks.env_change.PWD ++= [{|before, after|
            nvim-send $"<cmd>lua HookPwdChanged\('($after)', '($before)')<cr>"
        }]
        if (nvim-lua 'vim.go.background') == 'light' {
            let color = $env.config.color_config
            | transpose k v
            | reduce -f {} {|x,a|
                if $x.v == 'white' { $a | insert $x.k 'black' } else { $a }
            }
            $env.config.color_config = $env.config.color_config | merge $color
        }
    }
}

# drop stdout to nvim buf
export def vim-buf [] {
    if ($env.NVIM? | is-empty) {
        echo $in
    } else {
        let c = $in
        let temp = mktemp -t nuvim.XXXXXXXX | str trim
        $c | save -f $temp
        nvim-send $"<cmd>lua ReadTempDrop\('($temp)')<cr>"
    }
}

export def opwd [] {
    nvim-lua 'OppositePwd()'
}

def nve [...file:path --action(-a):string='vsplit'] {
    if ($env.NVIM? | is-empty) {
        nvim ...$file
    } else {
        let af = $file
        | each {|f|
            if ($f | str substring ..<1) in ['/', '~'] {
                $f
            } else {
                $"($env.PWD)/($f)"
            }
        }
        let action = if ($file | is-empty) { $action | str replace -r 'sp.*$' 'new' } else { $action }
        let cmd = $"<cmd>($action) ($af|str join ' ')<cr>"
        nvim-send $cmd
    }
}

export def e [...file:path] { nve ...$file -a vsplit }
export def v [...file:path] { nve ...$file -a vsplit }
export def c [...file:path] { nve ...$file -a split }
export def t [...file:path] { nve ...$file -a tabnew }

export def nvs [--port(-p): int=9999, --host(-h): string='0.0.0.0'] {
    $env.NEOVIDE_SCALE_FACTOR = 1
    print $"(ansi grey)neovim listen on ($host):($port)(ansi reset)"
    nvim --headless --listen $"($host):($port)"
}

export def nvim-gen-service [
    name
    --ev: record = {}
    --port: int = 9999
    --host: string = 'localhost'
    --bin: string = '/usr/local/bin/nvim'
    --sys
    --exec
] {
    let user = whoami
    let ev = {
        HOSTNAME: (hostname)
        NEOVIDE_SCALE_FACTOR: 1
        WAYLAND_DISPLAY: wayland-0
        PREFER_ALT: 1
        SHELL: nu
        TERM: screen-256color
        NVIM_LIGHT: 0
    }
    | merge $ev
    let host = match $host {
        local | localhost => '127.0.0.1'
        all => '0.0.0.0'
        _ => $host
    }
    let cmd = $"($bin) --listen ($host):($port) --headless +'set title titlestring=\\|($name)\\|'"
    use os/systemctl.nu *
    generate-systemd-service $"nvim:($name)" --cmd $cmd --system=$sys --environment $ev --user $user --exec=$exec
    # ~/.config/systemd/user/
}

def cmpl-nvc [] {
    let history = [$nu.cache-dir nvim_history.sqlite] | path join
    let opts = open $history
    | query db 'select cmd, count from nvim_remote_history order by count desc limit 9;'
    | rename value description
    if not ($env.HOME in ($opts | get value)) {[$env.HOME]} else {[]}
    | append $opts
}

export def nvc [
    pattern: string@cmpl-nvc
    ...args: string
    --gui(-g)
    --terminal(-t)
    --verbose(-v)
] {
    let history = [$nu.cache-dir nvim_history.sqlite] | path join
    if not ($history | path exists) {
        "create table if not exists nvim_remote_history (
            cmd text primary key,
            count int default 1,
            recent datetime default (datetime('now', 'localtime'))
        );" | sqlite3 $history
    }
    $"insert into nvim_remote_history\(cmd\) values \('($pattern)'\)
    on conflict\(cmd\) do
    update set count = count + 1,
               recent = datetime\('now', 'localtime'\);"
    | sqlite3 $history
    mut cmd = []
    if $terminal {
        $cmd ++= ['+terminal']
    }
    if $pattern =~ ':[0-9]+$' {
        mut addr = ''
        if ($pattern | str starts-with ':') {
            $addr = $"localhost($pattern)"
        } else {
            $addr = $pattern
        }
        $cmd ++= [--server $addr -- $"+\"set title titlestring=($addr)\""]
    } else if $pattern == ':' {
        $cmd ++= [$"+\"set title titlestring=world\""]
    } else {
        $cmd ++= [$"+\"set title titlestring=($pattern)\"" $pattern -- ...$args]
    }
    if $verbose {
        print ($cmd | str join ' ')
    }
    if $gui {
        let gs = {
            neovide: [--maximized --frame=none --vsync --fork]
        }
        for g in ($gs | transpose prog args) {
            if (which $g.prog | is-not-empty) {
                ^$g.prog ...$g.args ...$cmd
                break
            }
        }
    } else {
        nvim --remote-ui ...$cmd
    }
}

export def cmpl-cwdhist [context] {
    let kw = $context | split row ' ' | last
    use cwdhist *
    cwd history list $kw
    | rename value description
    | { completions: $in, options: { sort: false } }
}

export def cmpl-cwdhist-files [context] {
    let p = $context | argx parse | get -o pos.path
    cd $p
    ls | get name
}

export def nvide [
    path?:string@cmpl-cwdhist
] {
    job spawn {
        if ($path | is-not-empty) {
            cd $path
        }
        $env.NVIM_LIGHT = '1'
        neovide --maximized --frame=none --vsync --fork
    }
}