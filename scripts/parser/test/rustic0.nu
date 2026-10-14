use parser *
let b = 'rustic - fast, encrypted, deduplicated backups powered by Rust

Usage: rustic [OPTIONS] <COMMAND>

   
Commands:
  backup       Backup to  
  cat          Show raw


Commands:
  1backup       Backup to
  1cat          Show raw

Commands:
  2backup       Backup to
  2cat          Show raw

'

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

$b | do $parse_rustic
| get val.2.val
| table -e
