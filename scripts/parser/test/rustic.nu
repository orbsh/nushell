use parser *

let parse_rustic = one-by-one main [
    (end-of-line header)
    (space 'x' -l)
    (one-or-more 'body'
        (one-of 'section' [
            (one-by-one 'usage' [
                (cap0 'usage' '(Usage):')
                (lit '' ':')
                (space '')
                (end-of-line 'usage')
            ])
            (one-by-one 'commands' [
                (space '' -l)
                (cap0 'h' '(Commands):')
                (lit '' ':')
                (new-line)
                (one-or-more 'cmd'
                    (one-by-one 'cmd' [
                        (space 'indent')
                        (word 'id')
                        (space 'sep')
                        (end-of-line 'desc')
                    ])
                )
            ])
            (one-by-one 'option' [
                (space '' -l)
                (cap0 'option' '(.+):')
                (lit '' ':')
            ])
        ])
    )
]

rustic --help | complete | get stdout | do $parse_rustic
| get val.2.val
| table -e
