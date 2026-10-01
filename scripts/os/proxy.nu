export def common-ips [] {
    let addr = ip-route
    mut r = {
        loopback:  'localhost'
        gateway: $addr.gateway.0
        lan: $addr.src?.0?
    }
    let cn = $addr | where dev =~ '(docker|podman|nerdctl)'
    if ($cn | is-not-empty) {
        $r.container = $cn.src.0
    }
    $r
}

def cmpl-proxys [buffer: string] {
    let pre = $buffer | str substring ('toggle proxy ' | str length)..
    if ($buffer | str ends-with ':') {
        [7890 7891 1080] | each {|x| $"($pre)($x)"}
    } else if ($buffer | str ends-with '/') {
        let a = common-ips | transpose description value
        $a | each {|x|
            $x | update value $"($pre)($x.value):"
        }
    } else {
        ['socks5://' 'socks5h://' 'http://'  'https://']
    }
}

export def --env "toggle proxy" [
    proxy?:string@cmpl-proxys
] {
    let has_set = ($env.https_proxy? | is-not-empty)
    let no_val = ($proxy | is-empty)
    if $has_set and $no_val {
        echo 'hide proxy'
        {
            http_proxy: null
            https_proxy: null
            all_proxy: null
        }
        | load-env
    } else {
        let proxy = if ($proxy | is-empty) {
            'http://127.0.0.1:7890'
        } else {
            $proxy
        }
        echo $'set proxy ($proxy)'
        {
            http_proxy: $proxy
            https_proxy: $proxy
        }
        | load-env
        let p = $proxy | url parse
        let sp = if $p.scheme in ['http', 'https'] {
            $p
            | update scheme socks5
            | update port {|x| ($x.port | into int) + 1 }
            | url join
        } else {
            $p
        }
        $env.all_proxy = $sp
    }
    $env.no_proxy = 'localhost,127.0.0.1'
}
