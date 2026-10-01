def quote [...t] {
    let s = $t | str join '' | str replace -a "'" "''"
    $"'($s)'"
}

export def 'cwd history clean' [keyword] {
    let fr = $"from cwd_history where cwd like (quote '%' $keyword '%');"
    let l = open $env.CWD_HISTORY_FILE | query db $"select * ($fr)"
    if ($l | is-empty) {
        print 'nothing to clean'
    } else {
        print $l
        if ([y n] | input list 'continue? ') == 'y' {
            open $env.CWD_HISTORY_FILE | query db $"delete ($fr)"
        }
    }
}

export def 'cwd history list' [keyword --limit=20] {
    let keyword = quote '%' $keyword '%'
    if $env.CWD_HISTORY_FULL {
        open $nu.history-path | query db $"
            select cwd as value, count\(*\) as count
            from history
            where cwd like ($keyword)
            group by value
            order by count desc
            limit ($limit)
            ;"
    } else {
        open $env.CWD_HISTORY_FILE | query db $"
            select cwd as value, count
            from cwd_history
            where cwd like ($keyword)
            order by count desc
            limit ($limit)
            ;"
    }
}

def init [] {
    if not ($env.CWD_HISTORY_FILE | path exists) {
        {_: '.'} | into sqlite -t _ $env.CWD_HISTORY_FILE
        print $"(ansi grey)created database: $env.CWD_HISTORY_FILE(ansi reset)"
        open $env.CWD_HISTORY_FILE | query db "create table if not exists cwd_history (
            cwd text primary key,
            count int default 1,
            recent datetime default (datetime('now', 'localtime'))
        );"
    }
}

def enter [path] {
    open $env.CWD_HISTORY_FILE
    | query db $"
        insert into cwd_history\(cwd\)
            values \((quote $path)\)
        on conflict\(cwd\)
        do update set
            count = count + 1,
            recent = datetime\('now', 'localtime');"
}

export-env {
    {
        CWD_HISTORY_FULL: false
        CWD_HISTORY_FILE: ($nu.data-dir | path join 'cwd_history.sqlite')
        CWD_HISTORY_BLOCK: []
    }
    | load-env

    init

    $env.config.hooks.env_change.PWD ++= [{|_, dir|
        if $dir == $env.HOME { return }
        if ($env.CWD_HISTORY_BLOCK | any {|x| $dir =~ $x}) { return }
        let suffix = (do --ignore-errors { $dir | path relative-to $env.HOME })
        let path = if ($suffix | is-empty) {
            $dir
        } else {
            ['~', $suffix] | path join
        }
        enter $path
    }]

    $env.config.menus ++= [{
        name: cwdhist_menu
        only_buffer_difference: true
        marker: "| "
        type: {
            layout: list
            page_size: 10
        }
        style: {
            text: green
            selected_text: green_reverse
            description_text: yellow
        }
        source: { |buffer, place|
            #$"[($place.cursor)]($buffer);(char newline)" | save -a ~/.cache/cwdhist.log
            cwd history list ($buffer | split row ' ' | last)
        }
    }]
    $env.config.keybindings ++= [
        {
            name: cwdhist_menu
            modifier: alt
            keycode: char_o
            mode: [emacs, vi_normal, vi_insert]
            event: [
                { send: menu name: cwdhist_menu }
            ]
        }
        {
            name: cwdhist_switching
            modifier: shift_alt
            keycode: char_o
            mode: [emacs, vi_normal, vi_insert]
            event: [
                { send: ExecuteHostCommand, cmd: '$env.CWD_HISTORY_FULL = (not $env.CWD_HISTORY_FULL)' }
            ]
        }
    ]
}
