const ID = 'x'

def --env init-db [env_name:string, file:string, hook: closure] {
    let begin = date now
    if $env_name not-in $env {
        {$env_name: $file} | load-env
    }
    if ($file | path exists) { return }
    {_: '.'} | into sqlite -t _ $file
    open $file | query db "DROP TABLE _;"
    do $hook {|s| open $file | query db $s }
    print $"(ansi grey)created database: $env.($env_name), takes ((date now) - $begin)(ansi reset)"
}

def cmpl-dir [] {
    sqlx "select dir as value, group_concat(command, ' | ') as description
        from dirs join commands on id = dir_id group by dir;"
}

def cmpl-cmd [buffer: string] {
    let dir = $buffer | argx parse | get pos.dir
    sqlx $"select command from dirs join commands on id = dir_id where dir = (Q $dir)" | get command
}

export def --env 'project init-registry' [] {
    init-db PROJECT_STATE ([$nu.data-dir 'project.db'] | path join) {|sqlx|
        for s in [
            "CREATE TABLE IF NOT EXISTS dirs (
                id INTEGER PRIMARY KEY,
                dir TEXT NOT NULL UNIQUE
            );"
            "CREATE TABLE IF NOT EXISTS commands (
                dir_id INTEGER NOT NULL,
                command TEXT NOT NULL,
                created TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now')),
                PRIMARY KEY (dir_id, command)
            );"
            "CREATE TABLE IF NOT EXISTS mods (
                dir_id INTEGER NOT NULL,
                mod TEXT NOT NULL,
                members TEXT,
                PRIMARY KEY (dir_id, mod)
            );"
        ] {
            do $sqlx $s
        }
    }
}

# project exec <div> <act> -m [lg [history-utils/backup.nu *]]
export def --wrapped xx [
    dir:string@cmpl-dir
    ...cmd:string@cmpl-cmd
    --prefix:string=$ID
    --mods(-m): list<any>
] {
    cd $dir
    let mods = if ($mods | is-empty) {
        sqlx $"select mod, members from mods join dirs on id = dir_id where dir = (Q $dir)"
        | each {|x| [$x.mod ($x.members | split row ',')] }
    } else {
        let ms = $mods
        | each {|x|
            if ($x | describe -d).type == string {
                [$x, []]
            } else {
                [$x.0, ($x | slice 1..)]
            }
        }
        let qs = $ms | each {|x| $"\((Q $x.0), (Q ($x.1 | str join ','))\)" } | str join ','
        let stmt = $"with x\(mod, members\) as \(VALUES ($qs)\)
            , r as \(select id as dir_id, mod, members from dirs, x where dir = (Q $dir)\)
            insert or replace into mods select * from r"
        sqlx $stmt
        $ms
    }
    | each { $"use ($in.0) ($in.1 | str join ' ')" }

    let cmd = [
        'use project'
        ...$mods
        $'project direnv ($ID)'
        $'overlay use -r ($ID).nu as ($ID) -p'
        $'($ID) ($cmd | str join " ")'
    ]
    | str join '; '

    nu -c $cmd
}

def Q [...t --sep:string=''] {
    let s = $t | str join $sep | str replace -a "'" "''"
    $"'($s)'"
}

def sqlx [s] {
    open $env.PROJECT_STATE | query db $s
}

export def --env 'project register' [
    --mod:string=$ID
    dir?:string
] {
    let dir = if ($dir | is-empty) { $env.PWD } else { $dir }
    | str replace $env.HOME '~'

    let dir_id = sqlx $"insert into dirs \(dir\) values \((Q $dir)\)
        on conflict \(dir\) do update set dir = EXCLUDED.dir returning id;
    " | get 0.id
    let cmds = scope modules | where name == $mod | first | get commands.name
    | each { $"\(($dir_id), (Q $in)\)" } | str join ', '
    sqlx $"insert into commands \(dir_id, command\) values ($cmds)
        on conflict \(dir_id, command\)
        do update set dir_id = EXCLUDED.dir_id, command = EXCLUDED.command"
}

export def 'project unregister' [
    --dir:string
] {
    let dir = if ($dir | is-empty) { $env.PWD } else { $dir }
    sqlx $"delete from commands where dir_id in \(select id from dirs where dir = (Q $dir)\) returning dir_id;"
}
