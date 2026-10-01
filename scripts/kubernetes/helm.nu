use complete.nu *
use common.nu *
use argx

export def record-to-set-json [value] {
    $value | transpose k v
    | each {|x| $"($x.k)=($x.v | to json -r)"}
    | str join ','
}

def cmpl-helm-list [buffer: string] {
    let ctx = $buffer | argx parse
    kube-get-helm -n $ctx.opt.namespace? | each {|x| {value: $x.name  description: $x.updated} }
}

def cmpl-helm-charts [buffer: string] {
    let ctx = $buffer | argx parse
    let path = $ctx | get pos.chart?
    let paths = do -i { ls ($"($path)*/**/Chart.yaml" | into glob) | each { $in.name | path dirname } }
    helm repo list | from ssv -a | rename value description
    | append $paths
}


# helm list and get
export def kube-get-helm [
    name?: string@cmpl-helm-list
    --namespace (-n): string@cmpl-kube-ns
    --manifest (-m)
    --values(-v)
    --all (-a)
] {
    mut args = []
    if ($name | is-empty) {
        if $all {
            $args ++= [--all]
        } else if ($namespace | is-not-empty) {
            $args ++= [-n $namespace]
        }
        helm list ...$args --output json
        | from json
        | update updated {|x|
            $x.updated
            | str substring ..<-4
            | into datetime -f '%Y-%m-%d %H:%M:%S.%f %z'
        }
    } else {
        if ($namespace | is-not-empty) {
            $args ++= [-n $namespace]
        }
        if $manifest {
            helm get manifest $name ...$args
        } else if $values {
            helm get values $name ...$args
        } else {
            helm get notes $name ...$args
        }
    }
}

# helm install or upgrade via values file
export def kube-apply-helm [
    name: string@cmpl-helm-list
    chart: string@cmpl-helm-charts
    valuefile: path
    --values (-v): any
    --namespace (-n): string@cmpl-kube-ns
    --ignore-image (-i) # for kdh
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    let update = $name in (
        helm list ...$args --output json
        | from json | get name
    )
    let act = if $update { [upgrade] } else { [install] }
    if ($values | is-not-empty) {
        $args ++= [--set-json (record-to-set-json $values)]
    }
    helm ...$act $name $chart -f $valuefile ...$args
}

# helm diff
export def kube-diff-helm [
    name: string@cmpl-helm-list
    chart: string@cmpl-helm-charts
    valuefile: path
    --values (-v): any
    --namespace (-n): string@cmpl-kube-ns
    --ignore-image (-i)
    --has-plugin (-h)
    --concurrency: number=2
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    let images = if $ignore_image {
        kubectl get deployment ...$args -o jsonpath='{range .items[*]}{"["}{.metadata.name}{"]"}{range .spec.template.spec.containers[*]}{.name}={.image},{end}{"|+|"}{end}' | split row '|+|'
        | parse -r '\[(?<deploy>.+)\](?<images>.+)'
        | update images {|x|
            $x.images
            | split row ','
            | where { $in | is-not-empty }
            | split column '=' name image
            | reduce -f {} {|i, a| $a | upsert $i.name $i.image }
        }
        | reduce -f {} {|i, a| $a | upsert $i.deploy $i.images }
    } else {
        {}
    }
    if $has_plugin {
        helm diff $name $chart -f $valuefile ...$args
    } else {
        let update = $name in (
            helm list ...$args --output json
            | from json | get name
        )
        if not $update {
            echo "new installation"
            return
        }

        mut args = []
        if ($values | is-not-empty) {
            $args ++= [--set-json (record-to-set-json $values)]
        }
        let target = mktemp -t 'helm.XXX.out.yaml'
        print $"(ansi grey)tmpfile: ($target)(ansi reset)"
        let tg = helm template $name $chart -f $valuefile ...$args
        | from yaml
        let cntr = [spec template spec containers] | into cell-path

        $tg
        | each {|x|
            let n = $x | get -o metadata.name
            let c = $x | get -o $cntr
            if ($x.kind == 'Deployment') and ($n in $images) {
                let i = $images | get $n
                let c = $c | each {|y|
                    if $y.name in $i {
                        $y | update image ($i | get $y.name)
                    } else {
                        $y
                    }
                }
                $x | update $cntr $c
            } else {
                $x
            }
            | to yaml
        }
        | str join $"(char newline)---(char newline)"
        | save -f $target

        kubectl diff -f $target $"--concurrency=($concurrency)"
    }
}

# helm delete
export def kube-delete-helm [
    name: string@cmpl-helm-list
    --namespace (-n): string@cmpl-kube-ns
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    helm uninstall $name ...$args
}

# helm template
export def kube-helm [
    chart: string@cmpl-helm-charts
    valuefile: path
    --values (-v): any
    --namespace (-n): string@cmpl-kube-ns='test'
    --app (-a): string='test'
] {
    mut args = []
    if ($namespace | is-not-empty) {
        $args ++= [-n $namespace]
    }
    if ($values | is-not-empty) {
        $args ++= [--set-json (record-to-set-json $values)]
    }
    let target = $valuefile | split row '.' | slice ..-2 | append [out yaml] | str join '.'
    if (not ($target | path exists)) and (([yes no] | input list $'create ($target)?') in [no]) { return }
    helm template --debug $app $chart -f $valuefile ...$args
    | save -f $target
}
