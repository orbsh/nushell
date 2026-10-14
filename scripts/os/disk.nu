def cmpl-df-ex [] {
    [tmpfs overlay devtmpfs efivarfs]
}

export def dfx [-x:list<string>] {
    mut sys_disks = {}
    for i in (sys disks) {
        if $i.device not-in $sys_disks {
            $sys_disks = $sys_disks | insert $i.device ($i | select type removable kind)
        }
    }
    let sys_disks = $sys_disks
    let d = if ($x | is-empty) {
        sudo df -h
        | lines
        | slice 1..
        | where { $in | str starts-with '/' }
    } else {
        let x = $x
        | each { $"--exclude-type=($in)" }
        sudo df -h ...$x
        | lines
        | slice 1..
    }
    $d
    | parse -r '(?<fs>.+?)\s+(?<s>.+?)\s+(?<u>.+?)\s+(?<a>.+?)\s+.+?\s+(?<m>.+)'
    | each {|x|
        let u = $x.u | into filesize
        let a = $x.a | into filesize
        let s = $x.s | into filesize
        let e = $sys_disks | get $x.fs
        {
            filesystem: $x.fs
            size: $s
            used: $u
            availabe: $a
            radio: ($u / ($u + $a))
            mount: $x.m
            ...$e
        }
    }
}
