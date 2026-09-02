# env.nu
$env.NU_VENDOR_AUTOLOAD_DIR = [$nu.default-config-dir autoload] | path join

$env.ENV_CONVERSIONS.LD_LIBRARY_PATH = {
    from_string: { |s| if ($s | is-empty) { [] } else { $s | split row (char esep) } }
    to_string: { |v| if ($v | is-empty) { "" } else { $v | path expand | str join (char esep) } }
}

$env.ENV_CONVERSIONS.PATH = {
    from_string: { |s| if ($s | is-empty) { [] } else { $s | split row (char esep) } }
    to_string: { |v| if ($v | is-empty) { "" } else { $v | path expand | str join (char esep) } }
}

def --env merge-path [path] {
    let p = $path
    | each { glob $in }
    | flatten
    | where {|x| $x not-in $env.PATH }
    | reduce -f $env.PATH {|i,a| $a | prepend $i }
    | uniq
    | { PATH: $in }
    | load-env
}

alias py = python3
alias ipy = ipython3
alias js = bun
alias ijs = bun repl

if $nu.os-info.family == 'windows'  {
    $env.HOME = $env.HOMEPATH
} else {
    merge-path [
        /run/wrappers/bin #nixos
        ($env.HOME)/.cargo/bin
        ($env.HOME)/.ghcup/bin
        ($env.HOME)/.local/bin
        ($env.HOME)/.venvs/base/bin
        /opt/*/bin
        ($env.LS_ROOT? | default /opt)/*/bin
    ]
}

for s in ['/usr/local/bin', '/usr/bin'] {
    let p = [$s, 'nu'] | path join
    if (which $p | is-not-empty) {
        $env.SHELL = $p
        break
    }
}
{
    TERM: 'screen-256color'
}
| load-env
