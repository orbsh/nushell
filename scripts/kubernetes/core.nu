use common.nu *
use conf.nu *
use complete.nu *

def krefine [kind] {
    let obj = $in
    let conf = $env.KUBERNETES_REFINE
    let kind = if $kind in $conf.shortnames {
        $conf.shortnames | get $kind
    } else {
        $kind
    }
    let tg = [cluster_resources cluster_status resources status]
    | reduce -f {} {|i,a|
        let r = $conf | get $i
        if $kind in $r {
            $a | merge ($r | get $kind)
        } else {
            $a
        }
    }
    if ($tg | is-empty) {
        $obj
    } else {
        refine $tg $obj
    }
}


# kubectl apply -f
export def kube-apply-file [file: path] {
    kubectl apply -f $file
}

# kubectl diff -f
export def kube-diff-file [file: path] {
    kubectl diff -f $file
}

# kubectl delete -f
export def kube-delete-file [file: path] {
    kubectl delete -f $file
}

# kubectl apply -k (kustomize)
export def kube-apply-kustomize [file: path] {
    kubectl apply -k $file
}

# kubectl diff -k (kustomize)
export def kube-diff-kustomize [file: path] {
    kubectl diff -k $file
}

# kubectl delete -k (kustomize)
export def kube-delete-kustomize [file: path] {
    kubectl delete -k $file
}

# kubectl kustomize (template)
export def kube-kustomize [file: path] {
    kubectl kustomize $file
}



# kubectl change context
export def --env kube-change-context [
    context: string@cmpl-kube-ctx
    --session(-s)
] {
    if $session {
        let td = '/tmp/kubeconfig'
        if not ($td | path exists) {
            mkdir $td
        }
        let dist = mktemp -p $td $"(history session).XXX"
        kube-conf-export $context | save -fr $dist
        $env.KUBECONFIG = $dist
    } else {
        kubectl config use-context $context
    }
}

# kubectl change namespace
export def kube-change-namespace [namespace: string@cmpl-kube-ns] {
    if not ($namespace in (kubectl get namespace | from ssv -a | get NAME)) {
        if ([no yes] | input list $"namespace '($namespace)' doesn't exist, create it?") in [yes] {
            kubectl create namespace $namespace
        } else {
            return
        }
    }
    kubectl config set-context --current $"--namespace=($namespace)"
}


# kubectl get
export def kube-get [
    kind: string@cmpl-kube-kind
    resource?: string@cmpl-kube-res
    --namespace (-n): string@cmpl-kube-ns
    --jsonpath (-p): string@cmpl-kube-jsonpath
    --selector (-l): string
    --verbose (-v)
    --wide (-w)
    --watch (-W)
    --all (-a)
] {
    mut args = []
    if $all {
        $args ++= [-A]
    } else if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }

    if ($resource | is-empty) {
        if ($selector | is-not-empty) {
            $args ++= [-l $selector]
        }
        if $wide {
            $args ++= [-o wide]
        }
        if $verbose {
            kubectl get -o json ...$args $kind | from json
            | get items
            | krefine $kind
        } else if $watch {
            kubectl get ...$args $kind --watch
        } else {
            kubectl get ...$args $kind | from ssv -a | normalize-column-names
        }
    } else {
        if ($jsonpath | is-empty) {
            let o = kubectl get ...$args $kind $resource -o json | from json
            if $verbose { $o } else { $o | krefine $kind }
        } else {
            kubectl get ...$args $kind $resource $"--output=jsonpath={($jsonpath)}" | from json
        }
    }
}

# kubectl describe
export def kube-describe [
    kind: string@cmpl-kube-kind
    resource: string@cmpl-kube-res
    --namespace (-n): string@cmpl-kube-ns
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    kubectl describe ...$args $kind $resource
}

# kubectl create
export def kube-create [
    kind: string@cmpl-kube-kind
    --namespace (-n): string@cmpl-kube-ns
    name:string
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    kubectl create ...$args $kind $name
}

# kubectl get -o yaml
export def kube-get-as-yaml [
    kind: string@cmpl-kube-kind
    resource: string@cmpl-kube-res
    --namespace (-n): string@cmpl-kube-ns
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    kubectl get ...$args -o yaml $kind $resource
}

# kubectl edit
export def kube-edit [
    kind: string@cmpl-kube-kind
    resource?: string@cmpl-kube-res
    --namespace (-n): string@cmpl-kube-ns
    --selector(-l): string
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    let r = if ($selector | is-empty) { $resource } else {
        let res = kubectl get $kind ...$args -l $selector | from ssv -a | each {|x| $x.NAME}
        if ($res | length) == 1 {
            $res.0
        } else if ($res | length) == 0 {
            return
        } else {
            $res | input list $'select ($kind) '
        }
    }
    kubectl edit ...$args $kind $r
}

# kubectl delete
export def kube-delete [
    kind: string@cmpl-kube-kind
    resource: string@cmpl-kube-res
    --namespace (-n): string@cmpl-kube-ns
    --force(-f)
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    if $force {
        $args ++= [--grace-period=0 --force]
    }
    kubectl delete ...$args $kind $resource
}


# kubectl get nodes
export def kube-get-node [] {
    kubectl get nodes -o wide | from ssv -a
    | rename name status roles age version internal-ip external-ip os kernel runtime
}



# kubectl attach (exec -it)
export def --wrapped kube-attach [
    pod?: string@cmpl-kube-deploys-and-pods
    --namespace (-n): string@cmpl-kube-ns
    --container(-c): string@cmpl-kube-ctns
    --selector(-l): string
    --all-pods(-a) # for completion
    ...args
] {
    let stdin = $in
    let n = if ($namespace | is-empty) { [] } else { [-n $namespace] }
    let pod = if ($selector | is-empty) {
        if ($pod | str ends-with '-') {
            $"deployment/($pod | str trim --char '-' --right)"
        } else {
            $pod
        }
        } else {
        let pods = kubectl get pods ...$n -o wide -l $selector
            | from ssv -a
            | where STATUS == Running
            | select NAME IP NODE
            | rename name ip node
        if ($pods | length) == 1 {
            ($pods.0).name
        } else if ($pods | length) == 0 {
            return
        } else {
            ($pods | input list 'select pod ').name
        }
    }
    let c = if ($container | is-empty) {
        if ($selector | is-empty)  { [] } else {
            let cs = kubectl get pods ...$n $pod --output=jsonpath={.spec.containers[*].name} | split row ' '
            let ctn = if ($cs | length) == 1 {
                $cs.0
            } else {
                $cs | input list 'select container '
            }
            [-c $ctn]
        }
    } else {
        [-c $container]
    }
    let args = if ($args | is-empty) {
        let cmd = [
            '/usr/local/bin/nu'
            '/bin/nu'
            '/bin/bash'
            '/bin/sh'
        ]
        | str join ' '
        | $"for sh in ($in); do if [ -e $sh ]; then exec $sh; fi; done"
        ['/bin/sh' -c $cmd]
    } else {
        $args
    }
    if ($stdin | is-empty) {
        kubectl exec ...$n -it $pod ...$c -- ...$args
    } else {
        $stdin | kubectl exec ...$n -i $pod ...$c -- ...$args
    }
}

# kubectl logs
export def kube-log [
    pod: string@cmpl-kube-deploys-and-pods
    --namespace(-n): string@cmpl-kube-ns
    --container(-c): string@cmpl-kube-ctns
    --follow(-f)
    --previous(-p)
    --all-pods(-a) # for completion
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    if ($container | is-not-empty) {
        $args ++= [-c $container]
    }
    if $follow {
        $args ++= [-f]
    }
    if $previous {
        $args ++= [-p]
    }
    let tg = if ($pod | str ends-with '-') {
            $"deployment/($pod | str substring ..<-1)"
        } else {
            $pod
        }
    kubectl logs ...$args $tg
}

# kubectl port-forward
export def kube-port-forward [
    kind: string@cmpl-port-forward-type
    target: string@cmpl-kube-res
    port: string@cmpl-kube-port
    --local (-l): string
    --namespace (-n): string@cmpl-kube-ns
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    let port = if ($local | is-empty) { $port } else { $"($local):($port)" }
    kubectl port-forward ...$args $"($kind)/($target)" $port
}

# kubectl cp
export def kube-copy [
    lhs: path@cmpl-kube-cp
    rhs: path@cmpl-kube-cp
    --container (-c): string@cmpl-kube-ctns
    --namespace (-n): string@cmpl-kube-ns
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    if ($container | is-not-empty) {
        $args ++= [-c $container]
    }
    kubectl cp ...$args (expand-exists $lhs) (expand-exists $rhs)
}


def cmpl-num9 [] { 1..9 | each {$in} }
# kubectl scale deployment
export def kube-scale-deployment [
    deployment: string@cmpl-kube-deploys
    num: int@cmpl-num9
    --namespace (-n): string@cmpl-kube-ns
    --reset(-r)
] {
    if $num < 0 {
        "too small"
    } else {
        mut args = []
        if ($namespace | is-not-empty) {
            $args ++= [-n $namespace]
        }
        if $reset {
            kubectl scale ...$args deployments $deployment --replicas 0
        }
        kubectl scale ...$args deployments $deployment --replicas $num
    }
}

# kubectl list image
export def kube-list-image [
    --namespace(-n): string@cmpl-kube-ns
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    kubectl get deployment ...$args -o jsonpath='{range .items[*]}{"["}{.metadata.name}{"]"}{range .spec.template.spec.containers[*]}{.name}={.image},{end}{"|+|"}{end}' | split row '|+|'
    | parse -r '\[(?<deployment>.+)\](?<images>.+)'
    | update images {|x|
        $x.images
        | split row ','
        | where { $in | is-not-empty }
        | split column '=' name image
    }
}

# kubectl set image
export def kube-set-image [
    kind: string@cmpl-kube-kind-with-image
    resource: string@cmpl-kube-res
    --namespace(-n): string@cmpl-kube-ns
    --dry-run
    act?: any
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    let list = kubectl get ...$args $kind $resource -o jsonpath="{.spec.template.spec}"
    | from json
    | get containers
    if ($act | describe -d).type == 'closure' {
        let s = $list
        | update image $act
        | select name image
        | each {|x| $"($x.name)=($x.image)" }
        | str join ' '

        print $"kubectl ($args | str join ' ') set image \"($kind)/($resource)\" ($s)"
        if not $dry_run {
            kubectl ...$args set image $"($kind)/($resource)" $s
        }
    } else {
        $list
    }
}

# kubectl rollout history
export def kube-rollout-history [
    --namespace (-n): string@cmpl-kube-ns
    --revision (-v): int
    deployment: string@cmpl-kube-deploys
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    if ($revision | is-not-empty) {
        $args ++= [ $"--revision=($revision)" ]
    }
    kubectl ...$args rollout history $"deployment/($deployment)"
}

# kubectl rollout undo
export def kube-rollout-undo [
    --namespace (-n): string@cmpl-kube-ns
    --revision (-v): int
    deployment: string@cmpl-kube-deploys
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    if ($revision | is-not-empty) {
        $args ++= [ $"--to-revision=($revision)" ]
    }
    kubectl ...$args rollout undo $"deployment/($deployment)"
}

# kubectl top pod
export def kube-top-pod [
    --namespace (-n): string@cmpl-kube-ns
    --all(-a)
] {
    if $all {
        kubectl top pod -A | from ssv -a | rename namespace name cpu mem
        | each {|x|
            {
                namespace: $x.namespace
                name: $x.name
                cpu: ($x.cpu| str substring ..<-1 | into float)
                mem: ($x.mem | str substring ..<-2 | into float)
            }
        }
    } else {
        mut args = []
        if ($namespace | is-not-empty) {
            $args ++= [-n $namespace]
        }
        kubectl top pod ...$args | from ssv -a | rename name cpu mem
        | each {|x|
            {
                name: $x.name
                cpu: ($x.cpu| str substring ..<-1 | into float)
                mem: ($x.mem | str substring ..<-2 | into float)
            }
        }
    }
}

# kubectl top node
export def kube-top-node [] {
    kubectl top node | from ssv -a | rename name cpu pcpu mem pmem
    | each {|x| {
        name: $x.name
        cpu: ($x.cpu| str substring ..<-1 | into float)
        cpu%: (($x.pcpu| str substring ..<-1 | into float) / 100)
        mem: ($x.mem | str substring ..<-2 | into float)
        mem%: (($x.pmem | str substring ..<-1 | into float) / 100)
    } }
}

