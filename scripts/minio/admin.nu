use core.nu *
use argx

export def --env mc-default-target [target:string@mc-alias] {
    $env.MINIO_CLIENT_DEFAULT_TARGET = $target
}

def mctg [] {
    $in | default $env.MINIO_CLIENT_DEFAULT_TARGET?
}

export def mc-users [--target(-t): string@mc-alias] {
    ^mcli admin user list ($target | mctg) --json | from json -o
}

export def mc-user-add [
    accesskey: string
    secretkey: string
    --target(-t): string@mc-alias
] {
    ^mcli admin user add ($target | mctg) $accesskey $secretkey
}

def expand-keys [x, keys, -t: string] {
    $keys
    | each {|k|
        {
            accessKey: $k.accessKey?
            user: $x.user
            type: $t
            expiration: $x.expiration?
        }
    }
}

export def 'mc-accesskey ls' [--target(-t): string@mc-alias] {
    ^mcli admin accesskey ls ($target | mctg) --json
    | from json -o
    | each {|x|
        expand-keys $x $x.stsKeys -t stsKeys
        | append (expand-keys $x $x.svcaccs -t svcaccs)
    }
    | flatten
}

def 'nu-cmp mc-accesskey' [context: string] {
    let target = $context | argx parse | get -o opt.target | mctg
    mc-accesskey ls -t ($target | mctg)
    | each {|x|
        {
            value: $x.accessKey
            description: $"[($x.type)]($x.user)\t($x.expiration)"
        }
    }
}

def mc-accesskey-sub [] {
    [rm info enable disable]
}

export def mc-accesskey [
    sub: string@mc-accesskey-sub
    key: string@'nu-cmp mc-accesskey'
    --target(-t): string@mc-alias
    ...args
] {
    ^mcli admin accesskey $sub ($target | mctg) $key ...$args
}


export def 'mc-accesskey edit' [
    key: string@'nu-cmp mc-accesskey'
    --target(-t): string@mc-alias
    --secret-key: string
    --policy: record
    --name: string
    --description: string
    --expiry-duration: string # TODO: duration
    --expiry: string
    --config-dir: path
    --limit-upload: string
    --limit-download: string
    --custom-header: record
] {
    mut args = []
    if ($secret_key | is-not-empty) { $args ++= [--secret-key $secret_key] }
    if ($policy | is-not-empty) { $args ++= [--policy $policy] }
    if ($name| is-not-empty) { $args ++= [--name $name] }
    if ($description | is-not-empty) { $args ++= [--description $description] }
    if ($expiry_duration | is-not-empty) { $args ++= [--expiry-duration $expiry_duration] }
    if ($expiry | is-not-empty) { $args ++= [--expiry $expiry] }
    if ($config_dir | is-not-empty) { $args ++= [--config-dir $config_dir] }
    if ($limit_upload | is-not-empty) { $args ++= [--limit_upload $limit_upload] }
    if ($limit_download | is-not-empty) { $args ++= [--limit_download $limit_download] }
    if ($custom_header | is-not-empty) { $args ++= [--custom-header $custom_header] }
    ^mcli admin accesskey edit ($target | mctg) $key ...$args
}


export def 'mc-accesskey create' [
    --target(-t): string@mc-alias
    --secret-key: string
    --policy: record
    --name: string
    --description: string
    --expiry-duration: string # TODO: duration
    --expiry: string
    --config-dir: path
    --limit-upload: string
    --limit-download: string
    --custom-header: record
] {
    mut args = []
    if ($secret_key | is-not-empty) { $args ++= [--secret-key $secret_key] }
    if ($policy | is-not-empty) { $args ++= [--policy $policy] }
    if ($name| is-not-empty) { $args ++= [--name $name] }
    if ($description | is-not-empty) { $args ++= [--description $description] }
    if ($expiry_duration | is-not-empty) { $args ++= [--expiry-duration $expiry_duration] }
    if ($expiry | is-not-empty) { $args ++= [--expiry $expiry] }
    if ($config_dir | is-not-empty) { $args ++= [--config-dir $config_dir] }
    if ($limit_upload | is-not-empty) { $args ++= [--limit_upload $limit_upload] }
    if ($limit_download | is-not-empty) { $args ++= [--limit_download $limit_download] }
    if ($custom_header | is-not-empty) { $args ++= [--custom-header $custom_header] }
    ^mcli admin accesskey create ($target | mctg) ...$args
}


export def 'mc-policy ls' [--target(-t): string@mc-alias] {
    ^mcli admin policy ls ($target | mctg) | lines
}

def 'nu-cmp mc-policy' [buffer: string] {
    let t = $buffer | argx parse | get -o opt.target | mctg
    mc-policy ls -t $t
}

def 'mc-info-sub' [] {
    [info rm]

}

export def 'mc-policy create' [
    policy: string@'nu-cmp mc-policy'
    --target(-t): string@mc-alias
    --file: path
    --bucket: string
    --readonly
] {
    if ($file | is-empty) {
        let content = if ($bucket | is-empty) {
            error make {
                msg: '--file and --bucket are not both empty'
            }
        } else {
            if $readonly {
                {
                    Version: "2012-10-17"
                    Statement: [
                        {
                            Effect: Allow
                            Action: [
                                "s3:GetBucketLocation"
                                "s3:GetObject"
                            ]
                            Resource: [$"arn:aws:s3:::($bucket)"]
                        }
                    ]
                }
            } else {
                {
                    Version: "2012-10-17"
                    Statement: [
                        {
                            Effect: Allow
                            Action: [
                                "s3:GetBucketLocation"
                                "s3:ListBucket"
                                "s3:ListBucketMultipartUploads"
                            ]
                            Resource: [$"arn:aws:s3:::($bucket)"]
                        }
                        {
                            Effect: Allow
                            Action: ["s3:*"]
                            Resource: [$"arn:aws:s3:::($bucket)/*"]
                        }
                    ]
                }
            }
        }
        let file = mktemp -t policy.json.XXX
        $content | to json | save -f $file
        ^mcli admin policy create ($target | mctg) $policy $file
        rm -f $file
    } else {
        ^mcli admin policy create ($target | mctg) $policy $file
    }
}

export def 'mc-policy' [
    sub: string@mc-info-sub
    policy: string@'nu-cmp mc-policy'
    --target(-t): string@mc-alias
] {
    ^mcli admin policy $sub ($target | mctg) $policy
}

def 'nu-cmp mc-users' [buffer: string] {
    let t = $buffer | argx parse | get -o opt.target | mctg
    [
        ...(mc-accesskey ls -t $t)
        ...(mc-users -t $t)
    ]
    | get accessKey
}

export def 'mc-policy attach' [
    policy: string@'nu-cmp mc-policy'
    --target(-t): string@mc-alias
    --user: string@'nu-cmp mc-users'
    --group: string
] {
    mut args = []
    if ($user | is-not-empty) { $args ++= [--user $user] }
    if ($group | is-not-empty) { $args ++= [--group $group] }
    ^mcli admin policy attach ($target | mctg) $policy ...$args
}

export def 'mc-policy detach' [
    policy: string@'nu-cmp mc-policy'
    --target(-t): string@mc-alias
    --user: string@'nu-cmp mc-users'
    --group: string
] {
    mut args = []
    if ($user | is-not-empty) { $args ++= [--user $user] }
    if ($group | is-not-empty) { $args ++= [--group $group] }
    ^mcli admin policy detach ($target | mctg) $policy ...$args
}

export def --wrapped 'mc-policy entities' [
    --target(-t): string@mc-alias
    ...args
] {
    ^mcli admin policy entities ...$args ($target | mctg)
}
