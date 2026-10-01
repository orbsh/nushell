def cmpl-snapshot [buffer: string] {
    use argx
    let c = $buffer | argx parse
    qemu-img info --out=json ($c.pos.disk | path expand)
    | from json | get snapshots
    | each {|x|
        let date = $x.date-sec * 1000_000_000 | into datetime
        let size = $x.vm-state-size  | into filesize
        {value: $x.name, description: $"($date)(char tab)($size)" }
    }
    | { completions: $in, options: { sort: false, match_description: true } }
}

export def qemu-run [
    disk: path
    --restore: string@cmpl-snapshot
    --core: int = 4
    --mem: int = 4
    --dry-run
    --port: record = {}
    --boot: path
    --iso: list<string> = []
    --usb: list<string> = []
    --bios: path # = /usr/share/OVMF/x64/OVMF.4m.fd
    --readonly
    --clipboard
    --spice
] {
    let net = $port
    | transpose k v
    | each {|x|
        mut l = $x.k | split row ':'
        let p = $l | last
        $l = $l | slice 0..-2
        let o = $l | first | default 'tcp'
        $l = $l | slice 1..
        let a = $l | first
        $"hostfwd=($o):($a):($p)-:($x.v)"
    }
    | prepend user
    | str join ','

    let ext = ($disk | path parse | get extension | str lowercase)
    let interface = if $ext == "qcow2" { "virtio" } else { "sata" }
    let drive = $'file=($disk),if=($interface),format=($ext)'

    let display_arg = if $spice {
        [-display spice-app]
    } else {
        [-display 'sdl,gl=on']
    }

    mut args = [
        -monitor stdio
        -enable-kvm
        -m $'($mem)G'
        -smp $core
        -cpu host
        -vga virtio
        -drive $drive
        -net 'nic,model=virtio' -net $net
        -device virtio-balloon-pci
    ]

    $args ++= $display_arg

    # ====== Smart USB Controller and Peripheral Passthrough Logic ======
    # Initialize USB bus whenever --usb is specified, or when spice is off (which needs usb-tablet)
    let need_usb_bus = (not $spice) or ($usb | is-not-empty)

    if $need_usb_bus {
        $args ++= [-device qemu-xhci] # Fix previous error: provision the USB 3.0 bus first
    }

    if not $spice {
        $args ++= [-device usb-tablet] # Safe mouse mounting in SDL window mode
    }

    if ($restore | is-not-empty) {
      $args ++= [-loadvm $restore]
    }

    # Parse and append user-specified physical USB devices
    if ($usb | is-not-empty) {
        let usb_devices = $usb | each {|dev|
            # Split "045e:028e" into vendorid and productid
            let ids = $dev | split row ':'
            if ($ids | length) == 2 {
                [-device $'usb-host,vendorid=0x(($ids | first)),productid=0x(($ids | last))']
            } else {
                [] # Graceful fallback for malformed IDs
            }
        } | flatten
        $args ++= $usb_devices
    }
    # ==========================================

    if ($bios | is-not-empty) {
        # If a legacy unified BIOS was manually passed, keep the original logic
        $args ++= [-bios $bios]
    } else if ($boot | is-empty) {
        # Core logic: UEFI firmware is only needed for pure disk boot (no --boot flag).
        # If booting from --boot ISO, we must NOT load it to prevent UEFI environment pollution that would break ISO boot!
        let nix_ovmf_sys = "/run/libvirt/nix-ovmf/edk2-x86_64-code.fd"
        let nix_ovmf_local = "/home/master/.qemu/edk2-x86_64-code.fd"

        if not ($nix_ovmf_local | path exists) {
            mkdir ($nix_ovmf_local | path dirname)
            try {
                cp $nix_ovmf_sys $nix_ovmf_local
                chmod 644 $nix_ovmf_local
            } catch {
                error make {msg: "Due to NixOS system permission restrictions, please run the following command manually in your terminal once:\nsudo cp /run/libvirt/nix-ovmf/edk2-x86_64-code.fd /home/master/.qemu/edk2-x86_64-code.fd && sudo chmod 644 /home/master/.qemu/edk2-x86_64-code.fd"}
            }
        }
        # Inject the local firmware without read permission restrictions to enable instant UEFI disk boot
        $args ++= [-pflash $nix_ovmf_local]
    }

    if $readonly {
        $args ++= [-snapshot]
    }

    if ($boot | is-not-empty) {
        $args ++= [
            -drive $'file=($boot),media=cdrom'
            -boot d
        ]
    }

    if ($iso | is-not-empty) {
        let a = $iso | each {|x| [-drive $'file=($x),media=cdrom']} | flatten
        $args ++= $a
    }

    if $clipboard {
        $args ++= [
            -device virtio-serial-pci
            -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0
            -chardev spicevmc,id=spicechannel0,name=vdagent
            -spice port=5900,addr=127.0.0.1,disable-ticketing=on
        ]
    }

    if $dry_run {
        $'qemu-system-x86_64 ($args | str join " ")'
    } else {
        qemu-system-x86_64 ...$args
    }
}

export def qemu-create [
    disk
    --size:int = 60
] {
    let safe_name = if ($disk | str ends-with '.qcow2') { $disk } else { $'($disk).qcow2' }
    qemu-img create -f qcow2 $safe_name $'($size)G'
}

export def qemu-snapshot [
    action: string@[create apply delete list]
    disk: path
    name?: string@cmpl-snapshot
] {
    mut args = []
    $args ++= [(match $action {
        create => '-c'
        apply => '-a'
        delete => '-d'
        list => '-l'
    })]
    $args ++= [$disk]
    if ($name | is-not-empty) {
        $args ++= [$name]
    }
    qemu-img snapshot ...$args
}
