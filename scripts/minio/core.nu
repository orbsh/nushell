use argx

export def mc-alias [] {
    ^mcli alias ls --json
    | from json -o
    | each {|x|
        {
            value: $"($x.alias)/"
            description: $x.URL
        }
    }
}

export def mc-subkey [] {
    let key = $in | default '' | split row '/'
    if ($key | length) < 2 {
        mc-alias
    } else {
        let k = $key | slice 0..-2 | str join '/'
        mc-ls $k
        | where {|x| $x.type == 'dir'}
        | get key
        | each {|x|
            [$k $x] | path join
        }
    }
}

def gen-cmpl [key] {
    $in | argx parse | get ($key | into cell-path) | mc-subkey
}

export def 'nu-cmp mc-src' [context: string] {
    $context | gen-cmpl [pos src]
}

export def 'nu-cmp mc-dest' [context: string] {
    $context | gen-cmpl [pos dest]
}

export def mc-ls [
    src: string@'nu-cmp mc-src'
] {
    ^mcli ls $src --json
    | from json -o
    | each {|x|
        let t = match $x.type {
            folder => 'dir',
            _ => $x.type
        }
        let modified = $x.lastModified | into datetime
        {
            key: $x.key
            type: $t
            size: $x.size
            modified: $modified
            ver: $x.versionOrdinal
            etag: $x.etag
            url: $x.url
        }
    }
}

export def --wrapped mc-rm [
    src: string@'nu-cmp mc-src'
    ...args
] {
    ^mcli rm ...$args $src
}

export def mc-du [
    src: string@'nu-cmp mc-src'
] {
    ^mcli du $src
}

export def mc-tree [
    src: string@'nu-cmp mc-src'
] {
    ^mcli tree $src
}

export def --wrapped mc-mv [
    src: path@'nu-cmp mc-src'
    dest: path@'nu-cmp mc-dest'
    ...args
] {
    ^mcli mv ...args $src $dest
}

export def --wrapped  mc-cp [
    src: path@'nu-cmp mc-src'
    dest: path@'nu-cmp mc-dest'
    ...args
] {
    ^mcli cp ...$args $src $dest
}

export def --wrapped mc-put [
    src: path
    dest: path@'nu-cmp mc-dest'
    ...args
] {
    ^mcli put ...$args $src $dest
}
