export def suspend [] {
    sudo bash -c 'echo "mem" > /sys/power/state'
}

def cmp-fs [] {
    let c = ^df -h
    | lines
    | slice 1..
    | split column -r '\s+' fs size used avail percent mount
    | where {|x| ($x.fs | str starts-with '/') and ($x.mount | path split | get 1?) in ['run', 'media'] }
    | each {|x|
        { value: $x.fs, description: $"($x.size)\t($x.mount)" }
    }
    | reverse
    { completions: $c, options: { sort: false, partial: false } }
}

export def eject-disk [fs: string@cmp-fs] {
    print $"(ansi y)Attempting to unmount ($fs)...(ansi reset)"
    let unmount_res = udisksctl unmount -b $fs | complete

    if $unmount_res.exit_code != 0 {
        print $"(ansi r)Error: Target is busy or cannot be unmounted.(ansi reset)"
        print $unmount_res.stderr
        return
    }

    let parent = do -i { lsblk -pdno PKNAME $fs } | lines | first | default "" | str trim
    let disk = if ($parent | is-empty) { $fs } else { $parent }

    # Safety check and interactive power-off
    let is_valid = ($disk | is-not-empty) and ($disk | path exists)

    if $is_valid and ([y n] | input list $"Confirm: Power off and spin down ($disk)?") == 'y' {
        print $"(ansi b)Flushing caches and cutting power...(ansi reset)"
        sync # Essential for Btrfs metadata integrity on HDDs

        let pwr_res = udisksctl power-off -b $disk | complete
        if $pwr_res.exit_code == 0 {
            print $"(ansi g)✅ Success: Hardware stopped. Safe to unplug.(ansi reset)"
        } else {
            print $"(ansi r)Failed to power off: ($pwr_res.stderr)(ansi reset)"
        }
    } else {
        print $"(ansi r)Error: Could not resolve physical device path.(ansi reset)"
    }
}
