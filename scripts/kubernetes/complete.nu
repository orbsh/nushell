use argx
use common.nu *

### ctx
export def kube-config [] {
    let file = if ($env.KUBECONFIG? | is-empty) { $"($env.HOME)/.kube/config" } else { $env.KUBECONFIG | path expand }
    { path: $file, data: (open -r $file | from yaml) }
}

export def cmpl-kube-ctx [] {
    let k = kube-config
    let cache = [$nu.cache-dir 'k8s'] | path join $'($k.path | path basename).json'
    let data = ensure-cache-by-lines $cache $k.path { ||
        let clusters = $k.data | get clusters | select name cluster.server | rename name server
        let data = $k.data
            | get contexts
            | reduce -f {completion:[], mx_ns: 0, mx_cl: 0} {|x, a|
                let ns = if ($x.context.namespace? | is-empty) { '' } else { $x.context.namespace }
                let max_ns = $ns | str length
                let cluster = $"($x.context.user)@($clusters | where name == $x.context.cluster | first | get server)"
                let max_cl = $cluster | str length
                $a
                | upsert mx_ns (if $max_ns > $a.mx_ns { $max_ns } else $a.mx_ns)
                | upsert mx_cl (if $max_cl > $a.mx_cl { $max_cl } else $a.mx_cl)
                | upsert completion ($a.completion | append {value: $x.name, ns: $ns, cluster: $cluster})
            }
        {completion: $data.completion, max: {ns: $data.mx_ns, cluster: $data.mx_cl}}
    }

    $data.completion | each {|x|
        let ns = $x.ns | fill -a l -w $data.max.ns -c ' '
        let cl = $x.cluster | fill -a l -w $data.max.cluster -c ' '
        {value: $x.value, description: $"\t($ns) ($cl)"}
    }
}

export def cmpl-kube-ns [] {
    kubectl get namespaces
    | from ssv -a
    | each {|x|
        {value: $x.NAME, description: $"($x.AGE)\t($x.STATUS)"}
    }
}

export def cmpl-kube-kind [] {
    let ctx = kube-config
    let cache = ([$nu.cache-dir 'k8s-api-resources'] | path join $'($ctx.data.current-context).json')
    ensure-cache-by-lines $cache $ctx.path {||
        kubectl api-resources | from ssv -a
        | each {|x| {value: $x.NAME description: $x.SHORTNAMES} }
        | append (kubectl get crd | from ssv -a | get NAME | wrap value)
    }
}

export def cmpl-kube-res [buffer: string] {
    let ctx = $buffer | argx parse
    let kind = $ctx | get args.0
    let ns = if ($ctx.opt.namespace? | is-empty) { [] } else { [-n $ctx.opt.namespace] }
    kubectl get ...$ns $kind | from ssv -a | get NAME
}

export def cmpl-kube-res-via-name [buffer: string] {
    let ctx = $buffer | argx parse
    let kind = $env.KUBERNETES_RESOURCE_ABBR | get ($ctx.cmd | split row '-' | last)
    let ns = if ($ctx.opt.namespace? | is-empty) { [] } else { [-n $ctx.opt.namespace] }
    kubectl get ...$ns $kind | from ssv -a | get NAME
}

export def cmpl-kube-jsonpath [buffer: string] {
    let ctx = $buffer | argx parse
    let kind = $ctx.args.0
    let res = $ctx.args.1
    let path = $ctx.opt.jsonpath?
    let ns = if ($ctx.opt.namespace? | is-empty) { [] } else { [-n $ctx.opt.namespace] }
    mut r = []
    if ($path | is-empty) {
        if ($buffer | str ends-with '-p ') {
            $r = ['.']
        } else {
            $r = ['']
        }
    } else if ($path | str starts-with '.') {
        let row = $path | split row '.'
        let p = $row  | slice ..-2 | str join '.'
        if ($p | is-empty) {
            $r = ( kubectl get ...$ns -o json $kind $res
                 | from json
                 | columns
                 | each {|x| $'($p).($x)'}
                 )
        } else {
            let m = kubectl get ...$ns $kind $res $"--output=jsonpath={($p)}" | from json
            let l = $row | last
            let c = do -i {$m | get $l}
            if ($c | is-not-empty) and ($c | describe | str substring 0..<5) == 'table' {
                $r = (0..(($c | length) - 1) | each {|x| $'($p).($l)[($x)]'})
            } else {
                $r = ($m | columns | each {|x| $'($p).($x)'})
            }
        }
    } else {
        $r = ['']
    }
    $r
}


export def cmpl-kube-nodes [] {
    kubectl get nodes -o wide | from ssv -a
    | each {|x| {value: $x.NAME, description: $"($x.INTERNAL-IP)(char tab)($x.ROLES)"} }
}

export def cmpl-kube-deploys [buffer: string] {
    let ctx = $buffer | argx parse
    mut args = []
    if ($ctx.opt.namespace? | is-not-empty) {
        $args ++= [-n $ctx.opt.namespace]
    }
    kubectl get ...$args deployments | from ssv -a | get NAME
}

export def cmpl-kube-deploys-and-pods [buffer: string] {
    let ctx = $buffer | argx parse
    mut args = []
    if ($ctx.opt.namespace? | is-not-empty) {
        $args ++= [-n $ctx.opt.namespace]
    }
    let all_pods = ($ctx.opt.a? | default false) or ($ctx.opt.all-pods? | default false)
    if $all_pods or ($ctx.pos.pod? | default '' | str ends-with '-') {
        kubectl get ...$args pods | from ssv -a | get NAME
    } else {
        kubectl get ...$args deployments | from ssv -a | get NAME | each {|x| $"($x)-"}
    }
}

export def cmpl-kube-ctns [buffer: string] {
    let ctx = $buffer | argx parse
    mut args = []
    if ($ctx.opt.namespace? | is-not-empty) {
        $args ++= [-n $ctx.opt.namespace]
    }
    let pod = $ctx.args.0
    kubectl get ...$args pod $pod -o jsonpath={.spec.containers[*].name} | split row ' '
}

export def cmpl-port-forward-type [] {
    [pod svc]
}

export def cmpl-kube-port [buffer: string] {
    let ctx = $buffer | argx parse
    let kind = $ctx.args.0
    let ns = if ($ctx.opt.namespace? | is-empty) { [] } else { [-n $ctx.opt.namespace] }
    let res = $ctx.args.1
    if ($kind | str starts-with 's') {
        kubectl get ...$ns svc $res --output=jsonpath="{.spec.ports}"
        | from json
        | each {|x| {value: $x.port  description: $x.name} }
    } else {
        kubectl get ...$ns pods $res --output=jsonpath="{.spec.containers[].ports}"
        | from json
        | each {|x| {value: $x.containerPort description: $x.name?} }
    }
}

export def cmpl-kube-cp [buffer: string] {
    let ctx = $buffer | argx parse
    let p = $ctx.args | last
    mut args = []
    if ($ctx.opt.namespace? | is-not-empty) {
        $args ++= [-n $ctx.opt.namespace]
    }
    if ($ctx.opt.container? | is-not-empty) {
        $args ++= [-c ctx.opt.container]
    }
    let ctn = kubectl get pod ...$args | from ssv -a | each {|x| {description: $x.READY value: $"($x.NAME):" }}
    let n = $p | split row ':'
    if $"($n | get 0):" in ($ctn | get value) {
        kubectl exec ...$args ($n | get 0) -- sh -c $"ls -dp ($n | get 1)*"
        | lines
        | each {|x| $"($n | get 0):($x)"}
    } else {
        let files = do -i { ls -a ($"($p)*" | into glob)
            | each {|x| if $x.type == dir { $"($x.name)/"} else { $x.name }}
        }
        $files | append $ctn
    }
}

export def cmpl-kube-kind-with-image [] {
    [
        deployment daemonset statefulset
        pod replicationcontroller
        cronjob replicaset
    ]
}
