if ($env.PREFER_ALT? | default '0' | into int) > 0 {
    $env.config.keybindings = [
        [name, modifier, keycode, event, mode];
        [
            move_one_word_left,
            control,
            left,
            { edit: movewordleft },
            [ emacs, vi_normal, vi_insert ]
        ],
        [
            move_one_word_right_or_take_history_hint,
            control,
            right,
            {
                until: [
                    { send: historyhintwordcomplete },
                    { edit: movewordright }
                ]
            },
            [ emacs, vi_normal, vi_insert ]
        ],
        [
            move_to_line_start,
            alt,
            char_a,
            { edit: movetolinestart },
            [ emacs, vi_normal, vi_insert ]
        ],
        [
            move_to_line_end_or_take_history_hint,
            alt,
            char_e,
            {
                until: [
                    { send: historyhintcomplete },
                    { edit: movetolineend }
                ]
            },
            [ emacs, vi_normal, vi_insert ]
        ],
        [
            move_down,
            alt,
            char_n,
            {
                until: [
                    { send: menudown }
                    { send: down }
                ]
            },
            [ emacs, vi_normal, vi_insert ]
        ],
        [
            move_up,
            alt,
            char_p,
            {
                until: [
                    { send: menuup }
                    { send: up }
                ]
            },
            [ emacs, vi_normal, vi_insert ]
        ],
        [
            delete_one_word_backward,
            alt,
            char_w,
            { edit: backspaceword },
            [ emacs, vi_insert ]
        ],
        [
            move_left,
            alt,
            char_b,
            {
                until: [
                    { send: menuleft },
                    { edit: movewordleft }
                ]
            },
            emacs
        ],
        [
            move_right_or_take_history_hint,
            alt,
            char_f,
            {
                until: [
                    { send: historyhintcomplete },
                    { send: menuright },
                    { edit: movewordright }
                ]
            },
            emacs
        ],
        [
            cut_word_left,
            alt,
            char_w,
            { edit: cutwordleft },
            emacs
        ],
        [
            cut_line_to_end,
            control,
            char_k,
            { edit: cuttolineend },
            emacs
        ],
        [
            move_one_word_left,
            control,
            char_b,
            { send: left },
            emacs
        ],
        [
            move_one_word_right_or_take_history_hint,
            control,
            char_f,
            {
                until: [
                    { send: historyhintwordcomplete }
                    { send: right }
                ]
            },
            emacs
        ],
    ]
    | reduce -f $env.config.keybindings {|k, a|
        if ($a | any {|r| $r.name == $k.name }) {
            $a
        } else {
            $a | append $k
        }
    }
}
