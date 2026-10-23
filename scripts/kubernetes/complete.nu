use argx
use common.nu *

# argx reports a flag typed without a value as a bare `true`; treat that as absent
def opt-str [ctx, field: string] {
    let v = $ctx.opt | get -o $field
    if ($v | describe -d).type == 'string' { $v } else { '' }
}

# follow one jsonpath segment: `name`, `name[0]`, `[0]`, `name[0][1]`
def jsonpath-step [acc, seg: string] {
    let parts = $seg | split row '['
    let head = $parts | first
    let idx = $parts | skip 1 | each {|x| $x | str trim --char ']' }
    let base = if ($head | is-empty) {
        $acc
    } else if ($acc | describe -d).type == 'record' {
        $acc | get -o $head
    } else {
        null
    }
    $idx | reduce -f $base {|i, a| do -i { $a | get -o ($i | into int) } }
}

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
    let cache = [$nu.cache-dir 'k8s-api-resources'] | path join $'($ctx.data.current-context).json'
    ensure-cache-by-lines $cache $ctx.path {||
        kubectl api-resources | from ssv -a
        | each {|x| {value: $x.NAME description: $x.SHORTNAMES} }
        | append (kubectl get crd | from ssv -a | get NAME | wrap value)
    }
}

export def cmpl-kube-res [buffer: string] {
    let ctx = $buffer | argx parse
    let kind = $ctx.args | get -o 0
    # -a means -A here (all namespaces); the -a of cmpl-kube-deploys-and-pods only
    # switches the suggestion form between deployment prefixes and pod names
    let all = $ctx.opt.all? | default false
    let selector = opt-str $ctx selector
    mut args = if $all {
        [-A]
    } else {
        opt-str $ctx namespace | with-flag -n
    }
    if ($selector | is-not-empty) {
        $args ++= [-l $selector]
    }
    let res = kubectl get ...$args $kind | from ssv -a
    if $all {
        $res | each {|x|
            let d = [$x.NAMESPACE? $x.STATUS?] | where {|i| $i | is-not-empty } | str join (char tab)
            {value: $x.NAME, description: $d}
        }
    } else {
        $res | get NAME
    }
}

export def cmpl-kube-jsonpath [buffer: string] {
    let ctx = $buffer | argx parse
    let kind = $ctx.args | get -o 0
    let res = $ctx.args | get -o 1
    let path = opt-str $ctx jsonpath
    let args = if ($ctx.opt.all? | default false) {
        [-A]
    } else {
        opt-str $ctx namespace | with-flag -n
    }

    if ($path | is-empty) {
        return (if ($buffer | str ends-with '-p ') { ['.'] } else { [''] })
    }
    if not ($path | str starts-with '.') {
        return ['']
    }

    # a named resource is one document; without one, take the first item as the
    # structural sample — keys repeat across items and the whole list is not a
    # single JSON value
    let doc = if ($res | is-not-empty) {
        do -i { kubectl get ...$args -o json $kind $res | from json }
    } else {
        do -i { kubectl get ...$args $kind "--output=jsonpath={.items[0]}" | from json }
    }
    if ($doc | is-empty) {
        return ['']
    }

    # walk down to the parent of the segment being typed
    let row = $path | split row '.'
    let parent = $row | slice 1..-2 | reduce -f $doc {|seg, acc| jsonpath-step $acc $seg }
    if ($parent | is-empty) {
        return ['']
    }

    let p = $row | slice ..-2 | str join '.'
    if ($parent | describe -d).type in ['table' 'list'] {
        0..<($parent | length) | each {|i| $'($p)[($i)]' }
    } else {
        $parent | columns | each {|x| $'($p).($x)'}
    }
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
    let ns = opt-str $ctx namespace | with-flag -n
    # kube-log / kube-attach take the pod as the first positional, kube-copy hides
    # it in a <pod>:<path> argument, so prefer whatever carries the ':'
    let remote = $ctx.args | where {|x| ($x | describe -d).type == 'string' and ($x | str contains ':') } | get -o 0
    let pod = if ($remote | is-not-empty) {
        $remote | split row ':' | first
    } else {
        $ctx.args | get -o 0
    }
    if ($pod | is-empty) {
        return []
    }
    kubectl get ...$ns pod $pod -o jsonpath={.spec.containers[*].name} | split row ' '
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
    if ($ctx.args | is-empty) {
        return []
    }
    let p = $ctx.args | last
    let ns = opt-str $ctx namespace | with-flag -n
    # -c belongs to `kubectl exec` only; `kubectl get pod` has no such flag
    let ctn_flag = opt-str $ctx container | with-flag -c
    let ctn = kubectl get pod ...$ns | from ssv -a | each {|x| {description: $x.READY value: $"($x.NAME):" }}
    let n = $p | split row ':'
    if $"($n | get 0):" in ($ctn | get value) {
        kubectl exec ...$ns ...$ctn_flag ($n | get 0) -- sh -c $"ls -dp ($n | get 1)*"
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
