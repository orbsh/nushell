use ../completion.nu *
use ../tag_base.nu *
use argx
use llm *

def cmpl-namer [buffer: string] {
    let text = $buffer | argx parse | get args | tags-group | get other | str join ' '
    if ($text | is-not-empty) {
        let o = do -i { $text | ai-do generating-names zh usual -o }
        $o
        | lines
        | each { $'($in)'}
    }
}

export def snew [
    ...xtags:string@cmpl-tag-3
    --rewrite(-r):string@cmpl-namer
    --parent(-f):int=-1
    --scratch(-s): int@cmpl-scratch-id
] {
    let xtags = if ($rewrite | is-not-empty) {
        let xtags = $xtags | tags-group
        $xtags | update other $rewrite | group-to-tags
    } else {
        $xtags
    }
    scratch-add ...$xtags -f $parent --batch
}


def cmpl-todo-md [] {
    ls **/TODO.md | get name
}

export def scommit [
    ...xtags:string@cmpl-tag-3
    --scratch(-s): int@cmpl-scratch-id
    --file(-f): string@cmpl-todo-md
    --amend(-a)
] {
    scratch-done $scratch
    scratch-edit $scratch
    scratch-list --sort [created] -m ...$xtags | save -f $file
    git add .
    mut a = []
    if $amend { $a ++= [ --amend ] }
    git commit ...$a -m $"(scratch-title $scratch) #($scratch)"
}
