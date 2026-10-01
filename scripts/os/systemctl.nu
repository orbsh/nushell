use argx

def cmpl-systemctl-cmd [] {
    [
        # Unit Commands
        {value: list-sockets, description: "List sockets"}
        {value: list-timers, description: "List timers"}
        {value: list-units, description: "List units"}
        {value: start, description: "Start (activate) one or more units"}
        {value: stop, description: "Stop (deactivate) one or more units"}
        {value: reload, description: "Reload one or more units"}
        {value: restart, description: "Start or restart one or more units"}
        {value: condrestart, description: "Restart one or more units if active"}
        {value: try-restart, description: "Restart one or more units if active"}
        {value: reload-or-restart, description: "Reload one or more units if possible, otherwise start or restart"}
        {value: force-reload, description: "Reload one or more units if possible, otherwise restart if active"}
        {value: try-reload-or-restart, description: "Reload one or more units if possible, otherwise restart if active"}
        {value: isolate, description: "Start one unit and stop all others"}
        {value: kill, description: "Send signal to processes of a unit"}
        {value: is-active, description: "Check whether units are active"}
        {value: is-failed, description: "Check whether units are failed"}
        {value: status, description: "Show runtime status of one or more units"}
        {value: show, description: "Show properties of one or more units/jobs or the manager"}
        {value: cat, description: "Show the source unit files and drop-ins"}
        {value: set-property, description: "Sets one or more properties of a unit"}
        {value: help, description: "Show documentation for specified units"}
        {value: reset-failed, description: "Reset failed state for all, one, or more units"}
        {value: list-dependencies, description: "Show unit dependency tree"}
        {value: clean, description: "Remove configuration, state, cache, logs or runtime data of units"}
        {value: bind, description: "Bind mount a path from the host into a unit's namespace"}
        {value: mount-image, description: "Mount an image from the host into a unit's namespace"}
        # Machine Commands
        {value: list-machines, description: "List the host and all running local containers"}
        # Unit File Commands
        {value: list-unit-files, description: "List installed unit files"}
        {value: enable, description: "Enable one or more unit files"}
        {value: disable, description: "Disable one or more unit files"}
        {value: reenable, description: "Reenable one or more unit files"}
        {value: preset, description: "Enable/disable one or more unit files based on preset configuration"}
        {value: preset-all, description: "Enable/disable all unit files based on preset configuration"}
        {value: is-enabled, description: "Check whether unit files are enabled"}
        {value: mask, description: "Mask one or more units"}
        {value: unmask, description: "Unmask one or more units"}
        {value: link, description: "Link one or more units files into the search path"}
        {value: revert, description: "Revert unit files to their vendor versions"}
        {value: add-wants, description: "Add Wants= dependencies to a unit"}
        {value: add-requires, description: "Add Requires= dependencies to a unit"}
        {value: set-default, description: "Set the default target"}
        {value: get-default, description: "Query the default target"}
        {value: edit, description: "Edit one or more unit files"}
        # Job Commands
        {value: list-jobs, description: "List jobs"}
        {value: cancel, description: "Cancel all, one, or more jobs"}
        # Environment Commands
        {value: show-environment, description: "Dump environment"}
        {value: set-environment, description: "Set one or more environment variables"}
        {value: unset-environment, description: "Unset one or more environment variables"}
        {value: import-environment, description: "Import environment variables set on the client"}
        # Manager State Commands
        {value: daemon-reload, description: "Reload systemd manager configuration"}
        {value: daemon-reexec, description: "Reexecute systemd manager"}
        {value: log-level, description: "Get or set the log level"}
        {value: log-target, description: "Get or set the log target"}
        {value: service-watchdogs, description: "Get or set the state of software watchdogs"}
        # System Commands
        {value: is-system-running, description: "Query overall status of the system"}
        {value: default, description: "Enter system default mode"}
        {value: rescue, description: "Enter system rescue mode"}
        {value: emergency, description: "Enter system emergency mode"}
        {value: halt, description: "Shut down and halt the system"}
        {value: suspend, description: "Suspend the system"}
        {value: poweroff, description: "Shut down and power-off the system"}
        {value: reboot, description: "Shut down and reboot the system"}
        {value: kexec, description: "Shut down and reboot the system with kexec"}
        {value: exit, description: "Ask for user instance termination"}
        {value: switch-root, description: "Change root directory"}
        {value: hibernate, description: "Hibernate the system"}
        {value: hybrid-sleep, description: "Hibernate and suspend the system"}
        {value: suspend-then-hibernate, description: "Suspend the system for a period of time, and then hibernate it"}
    ]
}

export def "ssc services" [user, kw?: string] {
    let kw = if ($kw|is-empty) {
        []
    } else {
        [ $"($kw)*" ]
    }
    systemctl list-units --all ...(if $user {[--user]} else {[]}) ...$kw
    | head -n -5
    | from ssv -a
    | reduce -f [] {|x, a|
        if ($x.UNIT | str ends-with '.service') {
            $a | append { value: ($x.UNIT | str substring ..<-8)
                          description: $x.DESCRIPTION
                          active: ($x.ACTIVE == 'active')
                        }
        } else {
            $a
        }
    }
}

def cmpl-systemctl-x [buffer: string] {
    let ctx = $buffer | argx parse
    let cmd = $ctx.args.1
    let input = $ctx.args.2?
    let user = 'user' in $ctx.opt
    if $cmd in [start stop restart status enable disable] {
        let services = (ssc services $user $input)
        if $cmd == 'status' {
            $services
        } else if $cmd in [start enable] {
            $services | where active == false
        } else if $cmd in [stop restart disable] {
            $services | where active == true
        }
    } else {
        []
    }
}

export def ssc [
    cmd: string@cmpl-systemctl-cmd
    --dry-run
    --now # Start or stop unit after enabling or disabling it
    --force(-f) # When enabling unit files, override existing symlinks
    --user(-u)
    ...x: string@cmpl-systemctl-x
] {
    mut args = []
    if $now { $args = ($args | append [--now]) }
    if $force { $args = ($args | append [--force]) }
    if $dry_run {
        echo $"systemctl ($cmd) ($args) ($x)"
    } else {
        sudo systemctl ...(if $user {[--user]} else {[]}) $cmd ...$args ...$x
    }
}

export def generate-systemd-service [
    name
    --cmd: string
    --system
    --environment: record = {}
    --workdir: string
    --user: string
    --exec
] {
    let workdir = if ($workdir | is-empty) { $env.HOME } else { $workdir }
    let user = if ($user | is-empty) { whoami } else { $user }
    let s = {
        Unit: {
            After: network.target
            Wants: network.target
        }
        Service: {
            ExecReload: '/bin/kill -HUP $MAINPID'
            User: $user
        }
        Install: {
            WantedBy: multi-user.target
        }
    }

    let r = {
        Unit: {
            Description: $"Server Daemon for ($name)"
        }
        Service: {
            Type: simple
            SyslogIdentifier: ($name)
            Restart: always
            RestartSec: 0s
            LimitNOFILE: 'infinity'
            WorkingDirectory: $workdir
            env: $environment
            ExecStart: $cmd
        }
        Install: {
            WantedBy: default.target
        }
    }
    | merge deep (if $system { $s } else { {} })
    | transpose k v
    | each {|i|
        mut r = [$"[($i.k)]"]
        for j in ($i.v | transpose k v) {
            match $j.k {
                env => {
                    for i in ($j.v | transpose k v) {
                        $r ++= [$"Environment=\"($i.k)=($i.v)\""]
                    }
                }
                _ => {
                    $r ++= [($j.k)=($j.v)]
                }
            }
        }
        $r | str join "\n"
    }
    | str join "\n\n"
    if $exec {
        let s = $"($name).service"
        if $system {
            let p = [/etc/systemd/system/ $s] | path join
            $r | save -f $p
            sudo systemctl disable --now $s
            sudo systemctl daemon-reload
            sudo systemctl enable --now $s
        } else {
            let p = [$env.HOME .config systemd user $s] | path join
            $r | save -f $p
            systemctl disable --user --now $s
            systemctl enable --user --now $s
        }

    } else {
        $r
    }
}
