use complete.nu *

def upsert-list [field key value --exclude: list<cell-path>] {
    let i = $in
    mut ix = -1
    for x in ($i | enumerate) {
        if ($x.item | get $field) == $key {
            $ix = $x.index
        }
    }
    if $ix < 0 {
        $i | append $value
    } else {
        let v = if ($exclude | is-empty) {
            $value
        } else {
            let o = $i | get $ix
            $exclude
            | reduce -f $value {|i,a|
                $a | upsert $i ($o | get $i)
            }
        }
        $i | upsert $ix $v
    }
}

export def kube-conf-import [
    name: string@cmpl-kube-ctx
    --update-server
    --cluster: string
    --user: string
    --file(-f): path
] {
    let k = kube-config
    mut d = $k.data
    let i = open -r $file | from yaml
    let ns = $d.contexts | where name == $name
    let ns = if ($ns | is-empty) { 'default' } else { $ns.0.context.namespace }
    let cluster = if ($cluster | is-empty) { $name } else { $cluster }
    let user = if ($user | is-empty) { $name } else { $user }
    let c = {
        context: {
            cluster: $cluster,
            namespace: $ns,
            user: $user
        }
        name: $name,
    }
    let ex = if not $update_server { [$.cluster.server] }
    $d.clusters = $d.clusters | upsert-list name $cluster ($i.clusters.0 | upsert name $cluster) --exclude $ex
    $d.users = $d.users | upsert-list name $user ($i.users.0 | upsert name $user)
    $d.contexts = $d.contexts | upsert-list name $name $c
    $d | to yaml
}

export def kube-conf-delete [name: string@cmpl-kube-ctx] {
    let kc = kube-config
    let d = $kc.data
    let ctx = $d | get contexts | where name == $name | get 0
    let rctx = $d | get contexts | where name != $name
    let user =  if $ctx.context.user in ($rctx | get context.user) {
        $d | get users
    } else {
        $d | get users | where name != $ctx.context.user
    }
    let cluster = if $ctx.context.cluster in ($rctx | get context.cluster) {
        $d | get clusters
    } else {
        $d | get clusters | where name != $ctx.context.cluster
    }
    $d
    | update contexts $rctx
    | update users $user
    | update clusters $cluster
    | to yaml
}

export def kube-conf-export [name: string@cmpl-kube-ctx] {
    let d = (kube-config).data
    let ctx = $d | get contexts | where name == $name | get 0
    let user = $d | get users | where name == $ctx.context.user
    let cluster = $d | get clusters | where name == $ctx.context.cluster
    {
        apiVersion: 'v1',
        current-context: $ctx.name,
        kind: Config,
        clusters: $cluster,
        preferences: {},
        contexts: [$ctx],
        users: $user,
    } | to yaml
}
