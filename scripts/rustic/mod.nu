def cmpl-rustic-config [] {
    let c = ls *.toml
    let h = [$env.HOME .config rustic] | path join
    let h = if ($h | path exists) {
        ls ([$h '*.toml'] | path join | into glob)
    } else {
        []
    }
    let e = if ('/etc/rustic' | path exists) {
        ls /etc/rustic/*.toml
    } else {
        []
    }
    [...$c ...$h ...$e]
    | get name
    | each { $in | path parse | reject extension | path join }
}

def cmpl-rustic-commands [] {
    [
        { value: "backup", description: "Backup to the repository" }
        { value: "cat", description: "Show raw data of repository files and blobs" }
        { value: "config", description: "Change the repository configuration" }
        { value: "completions", description: "Generate shell completions" }
        { value: "check", description: "Check the repository" }
        { value: "copy", description: "Copy snapshots to other repositories. Note: The target repositories must be given in the config file!" }
        { value: "diff", description: "Compare two snapshots/paths Note that the exclude options only apply for comparison with a local path" }
        { value: "dump", description: "dump the contents of a file in a snapshot to stdout" }
        { value: "forget", description: "Remove snapshots from the repository" }
        { value: "init", description: "Initialize a new repository" }
        { value: "key", description: "Manage keys" }
        { value: "list", description: "List repository files" }
        { value: "ls", description: "List file contents of a snapshot" }
        { value: "merge", description: "Merge snapshots" }
        { value: "snapshots", description: "Show a detailed overview of the snapshots within the repository" }
        { value: "show", description: "config  Show the configuration which has been read from the config file(s)" }
        { value: "prune", description: "Remove unused data or repack repository pack files" }
        { value: "restore", description: "Restore a snapshot/path" }
        { value: "repair", description: "Repair a snapshot/path" }
        { value: "repoinfo", description: "Show general information about the repository" }
        { value: "tag", description: "Change tags of snapshots" }
        { value: "webdav", description: "Start a webdav server which allows to access the repository" }
        { value: "help", description: "Print this message or the help of the given subcommand(s)" }
    ]
}

def 'parse args' [] {
    let c = $in | split row ' ' | slice 1..
    mut ra = ''
    mut opt = {}
    mut rest = []
    for i in $c {
        if ($ra | is-not-empty) {
            $opt = ($opt | insert $ra $i)
            $ra = ''
        } else {
            if ($i | str starts-with '-') {
                let n = $i | parse -r '-+(?<n>.+)' | get 0.n | str replace '-' '_' -a
                $ra = $n
            } else {
                $rest ++= [$i]
            }
        }
    }
    return { opt: $opt, rest: $rest }
}

def cmpl-rustic-snapshots [buffer: string] {
    let c = $buffer | parse args
    let s = if 'P' in $c.opt {
        ^rustic -P $c.opt.P snapshots --json
    } else {
        ^rustic snapshots --json
    }
    let s = $s
    | from json
    | each {|x|
        $x.1 | each {|y|
            let t = char tab
            let id = $y.id | str substring ..7
            let d = $y.time | date from-human | date humanize
            let l = if ($y.label? | is-empty) { '' } else { $"<($y.label)>"}
            {
                value: $id
                description: $"($l)($y.tags)($t)($d)($t)($y.hostname)($t)($y.paths)"
            }
        }
    }
    | flatten

    $s
}

export extern 'main' [
    command: string@cmpl-rustic-commands
    --help
]

export extern 'rustic restore' [
    -P: string@cmpl-rustic-config # Config profile to use. This parses the file `<PROFILE>.toml` in the config directory. [default: "rustic", env: RUSTIC_USE_PROFILE=]
    snapshot: string@cmpl-rustic-snapshots
    dest: path
]

export extern 'rustic ls' [
    -P: string@cmpl-rustic-config # Config profile to use. This parses the file `<PROFILE>.toml` in the config directory. [default: "rustic", env: RUSTIC_USE_PROFILE=]
    snapshot: string@cmpl-rustic-snapshots
]

export extern 'rustic forget' [
    -P: string@cmpl-rustic-config # Config profile to use. This parses the file `<PROFILE>.toml` in the config directory. [default: "rustic", env: RUSTIC_USE_PROFILE=]
    ...snapshot: string@cmpl-rustic-snapshots
    --prune
]

export extern 'rustic backup' [
    -P: string@cmpl-rustic-config # Config profile to use. This parses the file `<PROFILE>.toml` in the config directory. [default: "rustic", env: RUSTIC_USE_PROFILE=]
    src: path
    --stdin-filename: string # Set filename to be used when backing up from stdin
    --as-path: string # Manually set backup path in snapshot
    --with-atime # Save access time for files and directories
    --ignore-devid # Don't save device ID for files and directories
    --no-scan # Don't scan the backup source for its size - this disables ETA estimation for backup
    --json # Output generated snapshot in json format
    --quiet # Don't show any output
    --init # Initialize repository, if it doesn't exist yet
]

export extern 'rustic snapshots' [
    -P: string@cmpl-rustic-config # Config profile to use. This parses the file `<PROFILE>.toml` in the config directory. [default: "rustic", env: RUSTIC_USE_PROFILE=]
    --all
]
