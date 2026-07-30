export def notify-self [msg?] {
    notify-send $env.pwd ($msg | default '')
}

export-env {
    # Minimum command duration that triggers a notification
    $env.NOTIFY_MIN_DURATION = 3sec

    # 1. Record command start time
    $env.config.hooks.pre_execution = [
        { ||
            $env.CMD_START_TIME = (date now)
            $env.LAST_COMMAND = (commandline)
        }
    ]

    # 2. On completion, choose notification method based on environment
    $env.config.hooks.pre_prompt = [
        { ||
            if 'CMD_START_TIME' in $env {
                let d = (date now) - ($env.CMD_START_TIME | into datetime)

                if $d > $env.NOTIFY_MIN_DURATION {
                    let flag = if $env.LAST_EXIT_CODE == 0 { '✔' } else { '✘' }
                    let title = $"[($flag)]($env.LAST_COMMAND | str substring ..20)"
                    let msg = {
                        cwd: $env.PWD
                        command: $env.LAST_COMMAND
                        duration: ($d | into string)
                    }
                    | to yaml

                    # Running inside Neovim/Neovide
                    if 'NVIM' in $env {
                        let is_focused = nvim --headless --noplugin --server $env.NVIM --remote-expr "g:neovide_window_focused"

                        if $is_focused == "0" {
                            # Neovide doesn't recognize OSC sequences, use system notification on Linux
                            # (macOS: use osascript; Windows: use powershell)
                            notify-send $title $msg --icon=utilities-terminal
                        }
                    } else {
                        # Standalone terminal (WezTerm / Ghostty / Windows Terminal)
                        # Send OSC escape sequences, let the terminal handle focus detection
                        print -n $"(ansi osc)9;($msg)\x07"
                        print -n $"(ansi osc)777;notify;Nushell;($msg)\x07"
                        print -n $"(ansi osc)99;i=nu;o=1;d=1;($msg)\x07"
                    }
                }
                hide-env CMD_START_TIME
                hide-env LAST_COMMAND
            }
        }
    ]
}
