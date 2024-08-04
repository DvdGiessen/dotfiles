#!/bin/bash

# Only run on interactive shells
[[ -z "$PS1" ]] && return
[[ "$-" == *"i"* ]] || return

# Disable echo while we are setting up our shell;
# bash will echo stdin when arriving at the prompt
stty -echo

# Setup serial console size
if [[ "$(tty 2>/dev/null)" =~ ^/dev/term/[abcd] ]] ; then
    # If we're on the serial console, we generally won't know how big our
    # terminal is, so we attempt to ask it using control sequences and resize
    # our pty accordingly
    if MT_OUTPUT="$(/usr/lib/measure_terminal 2>/dev/null)" ; then
        eval "$MT_OUTPUT"
    else
        # We could not read the size, but we should set a 'sane'
        # default as the dimensions of the previous user's terminal
        # persist on the tty device
        export LINES=25
        export COLUMNS=80
    fi
    unset MT_OUTPUT
    stty rows "$LINES" columns "$COLUMNS" &>/dev/null
fi

# Detect and override unsupported terminals
if hash tput &>/dev/null ; then
    if [[ -z "$(tput colors 2>/dev/null)" && "$TERM" =~ -(256)?color$ ]] ; then
        export TERM=xterm
    fi
elif [[ -d /usr/share/terminfo && ! -f "/usr/share/terminfo/${TERM:0:1}/$TERM" ]] ; then
    if [[ "$TERM" =~ -(256)?color$ ]] ; then
        if [[ -f /usr/share/terminfo/x/xterm-256color ]] ; then
            export TERM=xterm-256color
        elif [[ -f /usr/share/terminfo/x/xterm ]] ; then
            export TERM=xterm
        fi
    fi
fi

# Add directories to path
for DIR in {/usr/local,/opt/homebrew}/{sbin,bin} $HOME/{.local,.cargo,go}/bin ; do
    [[ -d "$DIR" && ":$PATH:" != *":$DIR:"* ]] && export PATH="$PATH:$DIR"
done
unset DIR

# Set up preferred locale
export LANGUAGE="en_GB:en_US:en:nl_NL:nl:C"
if hash locale &>/dev/null ; then
    AVAILABLE_LOCALES="$(locale -a 2>/dev/null)"
    PREFERRED_AVAILABLE_LOCALES="$({ echo "$LANGUAGE" | sed -E 's/([a-zA-Z_]+)/\1.utf8:\1.utf-8/g' ; echo "$LANGUAGE" ; } | tr ':' $'\n' | grep -i -E "^($(echo "$AVAILABLE_LOCALES" | sed -E 's/\./\\./g' | tr $'\n' '|' | sed -E 's/\|$/\n/'))\$" | while IFS= read -r PREFERRED_AVAILABLE_LOCALE ; do echo "$AVAILABLE_LOCALES" | grep -i -E "^$(echo "$PREFERRED_AVAILABLE_LOCALE" | sed -E 's/\./\\./g')\$" ; done)"
    if [[ -n "$PREFERRED_AVAILABLE_LOCALES" ]] ; then
        export LANG="$(echo "$PREFERRED_AVAILABLE_LOCALES" | head -n1)"
    fi
    unset PREFERRED_AVAILABLE_LOCALES
    unset AVAILABLE_LOCALES
fi

# Customize bash configuration
if [[ "${BASH_VERSINFO:-0}" -ge 5 ]] || [[ "${BASH_VERSINFO:-0}" -eq 4 && "${BASH_VERSINFO[1]:-0}" -ge 3 ]] ; then
    HISTSIZE=-1
    HISTFILESIZE=-1
else
    HISTSIZE=
    HISTFILESIZE=
fi
HISTCONTROL=ignoreboth
HISTIGNORE='exit:quit'
set -b
shopt -s checkwinsize cdspell extglob histappend histverify lithist

# Customize prompt
prompt_command() {
    local EXIT_STATUS=$?

    # Show if we have any running jobs in the background
    # Do this before anything else, so the output from $(jobs) isn't poluted by this script
    local BGJOBS=""
    if [[ -n "$(jobs)" ]] ; then
        BGJOBS=" (bg:\j)"
    fi

    # Make sure input ends up after the prompt, not before it
    stty -echo

    # Immediately write new history entries instead of at the end of the session
    history -a

    # Determine color based on zone and user
    local RESET_COLOR=""
    local USER_COLOR=""
    local AT_COLOR=""
    local HOST_COLOR=""
    local CHROOT_COLOR=""
    local DIR_COLOR=""
    local SCM_COLOR=""
    local PYVENV_COLOR=""
    local BGJOBS_COLOR=""
    local DOLLAR_COLOR=""
    if [[ -z "${NO_COLOR:-}" && ( -n "$(tput colors 2>/dev/null)" || "$TERM" == 'xterm' || "$TERM" =~ -(256)?color$ ) ]] ; then
        RESET_COLOR="\[\e[m\]"
        if [[ "$(zonename 2>/dev/null)" == "global" ]] ; then
            if [[ "$EUID" -eq 0 ]] ; then
                USER_COLOR="\[\e[41;1;97m\]";
                AT_COLOR="\[\e[41;1;97m\]";
                HOST_COLOR="\[\e[41;1;97m\]";
            else
                USER_COLOR="\[\e[1;31m\]";
                AT_COLOR="\[\e[m\]";
                HOST_COLOR="\[\e[41;1;97m\]";
            fi
        else
            if [[ "$EUID" -eq 0 ]] ; then
                USER_COLOR="\[\e[1;31m\]";
                AT_COLOR="\[\e[m\]";
                HOST_COLOR="\[\e[1;32m\]";
            else
                USER_COLOR="\[\e[1;32m\]";
                AT_COLOR="\[\e[m\]";
                HOST_COLOR="\[\e[1;32m\]";
            fi
        fi
        DIR_COLOR="\[\e[1;34m\]"
        SCM_COLOR="\[\e[1;35m\]"
        PYVENV_COLOR="\[\e[1;33m\]"
        BGJOBS_COLOR="\[\e[1;90m\]"
        DOLLAR_COLOR="\[\e[1;32m\]"
        if [[ "$EXIT_STATUS" -ne 0 ]] ; then
            DOLLAR_COLOR="\[\e[1;31m\]"
        fi
    fi

    # Show current chroot
    local CHROOT="${debian_chroot:-}"
    if [[ -z "$CHROOT" ]] && [[ -r /etc/debian_chroot ]] ; then
        CHROOT="$(cat /etc/debian_chroot)"
    fi
    local NOCOLOR_CHROOT="$CHROOT"
    if [[ -n "$CHROOT" ]] ; then
        CHROOT="$CHROOT_COLOR$CHROOT$RESET_COLOR"
    fi

    # Show versioning info in prompt
    local SCM=""
    local GIT_HEAD=""
    if hash git &>/dev/null && git rev-parse --is-inside-working-tree &>/dev/null && GIT_HEAD="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" ; then
        if [[ "$GIT_HEAD" == "HEAD" ]] && ! GIT_HEAD="$(git describe --tags --exact-match HEAD 2>/dev/null)" ; then
            GIT_HEAD="HEAD"
        fi
        SCM=" $SCM_COLOR<$GIT_HEAD>$RESET_COLOR"
    fi

    # Show current Python virtual environment
    local PYVENV=""
    if [[ -n "$VIRTUAL_ENV" ]] ; then
        PYVENV=" $PYVENV_COLOR($(basename "$VIRTUAL_ENV"))$RESET_COLOR"
    fi

    # Colorize all variables
    if [[ -n "$BGJOBS" ]] ; then
        BGJOBS="$BGJOBS_COLOR$BGJOBS$RESET_COLOR"
    fi

    # Color the prompt based on exit status of the last command
    local DOLLAR="$DOLLAR_COLOR\\\$$RESET_COLOR"

    # If this is an xterm also set the title
    local TITLE=""
    if [[ "$TERM" == "xterm"* ]] || [[ "$TERM" == "rxvt"* ]] ; then
        TITLE="\[\e]0;\u@\H: $NOCOLOR_CHROOT\w\a\]"
    fi

    # Putting it all together
    echo "$TITLE$USER_COLOR\u$AT_COLOR@$HOST_COLOR\H$RESET_COLOR: $CHROOT$DIR_COLOR\w$RESET_COLOR$SCM$PYVENV\n$DOLLAR$BGJOBS "

    # (Re-)enable echo
    stty echo

    # Preserve exit status
    return $EXIT_STATUS
}
PROMPT_COMMAND='PS1="$(prompt_command)"'

# Load iTerm2 shell integration
if [[ -f ~/.iterm2_shell_integration.bash ]] ; then
    export ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX=YES
    source ~/.iterm2_shell_integration.bash
fi

# Load bash completion
if ! shopt -oq posix ; then
    if [[ -f /usr/share/bash-completion/bash_completion ]] ; then
        source /usr/share/bash-completion/bash_completion
    elif [[ -f /etc/bash_completion ]] ; then
        source /etc/bash_completion
    fi
fi

# Load bash completion for Homebrew
if hash brew &>/dev/null ; then
    HOMEBREW_PREFIX="$(brew --prefix)"
    if [[ -r "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh" ]] ; then
        source "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"
    else
        for COMPLETION in "$HOMEBREW_PREFIX/etc/bash_completion.d/"* ; do
            [[ -r "$COMPLETION" ]] && source "$COMPLETION"
        done
    fi
    unset HOMEBREW_PREFIX
fi

# The various non-Bash shells don't not support colours and prompt commands, thus we set a simplified PS1 when calling them
if hash sh &>/dev/null && [[ "$(command -v sh)" != "$SHELL" ]] ; then
    if [[ "$OSTYPE" == "solaris"* ]] ; then
        # Korn (ksh)
        alias sh="PS1=\"\\\$(echo \\\"\\\${LOGNAME}@\\\$(cat /etc/hostname): \\\${PWD/~(El)\\\${HOME}/\\\~}\\\" && [[ \\\"\\\$LOGNAME\\\" == 'root' ]] && print -n '# ' || print -n '$ ')\" sh"
    elif [[ "$OSTYPE" == "freebsd"* ]] ; then
        # Almquist (ash)
        alias sh="PS1=\"\\u@\\H: \\w \\$ \" sh"
    else
        # Debian Almquist (dash)
        alias sh="PS1=\"\\\$(echo \\\"\\\$([ -n \\\"\\\${LOGNAME}\\\" ] && echo \\\"\\\${LOGNAME}\\\" || whoami)@\\\$([ -r /etc/hostname ] && cat /etc/hostname || hostname): \\\$([ -n \\\"\\\${HOME}\\\" ] && [ \\\"\\\${PWD}\\\" = \\\"\\\${HOME}\\\" ] && echo '~' || echo \\\"\\\${PWD}\\\")\\\" && [ \\\"\\\${LOGNAME}\\\" = 'root' ] && echo -n '# ' || echo -n '$ ')\" sh"
    fi
fi
hash zsh &>/dev/null && alias zsh="PS1=\"%B%(!.%F{red}.%F{green})%n%f%b@%B%F{green}%M%f%b: %B%F{blue}%~%f%b"$'\n'"%B%(?.%F{green}.%F{red})%#%f%b \" zsh"

# Load bash aliases
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases

# Aliases for common typos
alias cd..='cd ..'
alias ls-la='ls -la'
alias ls-lah='ls -lah'

# Make less more friendly for non-text input files
hash lesspipe &>/dev/null && eval "$(SHELL=/bin/sh lesspipe)"

# Use bat as man pager if available and supported
if hash man &>/dev/null ; then
    if hash batman &>/dev/null ; then
        alias man=batman
    elif hash bat &>/dev/null && hash col &>/dev/null && [[ "$(head -c2 "$(command -v man 2>/dev/null)" 2>/dev/null)" == "#!" ]] ; then
        export MANPAGER="sh -c 'col -bx | bat -l man -p'"
    fi
fi

# Load thefuck
hash thefuck &>/dev/null && eval "$(thefuck --alias)"

# Load fuzzy finder
if [[ -f ~/.fzf.bash ]] ; then
    source ~/.fzf.bash
else
    for FZF_SCRIPT in key-bindings.bash completion.bash ; do
        for FZF_PREFIX in {$PREFIX,/usr{,/local},/opt{,/local,/homebrew}}/{opt,share{,/doc}}/fzf/{,examples,shell} ; do
            if [[ -f "${FZF_PREFIX}/${FZF_SCRIPT}" ]] ; then
                source "${FZF_PREFIX}/${FZF_SCRIPT}"
                break
            fi
        done
        unset FZF_PREFIX
    done
    unset FZF_SCRIPT
fi

# Load wormhole implementations
for WORMHOLE_ALTERNATIVE in wormhole-william:shell-completion wormhole-rs:completion ; do
    WORMHOLE_CMD="$(echo "$WORMHOLE_ALTERNATIVE" | cut -d: -f1)"
    WORMHOLE_COMPLETION="$(echo "$WORMHOLE_ALTERNATIVE" | cut -d: -f2)"
    if hash "$WORMHOLE_CMD" &>/dev/null ; then
        source <("$WORMHOLE_CMD" "$WORMHOLE_COMPLETION" bash)
        if ! hash wormhole &>/dev/null ; then
            alias wormhole="$WORMHOLE_CMD"
            source <("$WORMHOLE_CMD" "$WORMHOLE_COMPLETION" bash | sed "s/$WORMHOLE_CMD/wormhole/g")
        fi
    fi
    unset WORMHOLE_CMD
    unset WORMHOLE_COMPLETION
done
unset WORMHOLE_ALTERNATIVE

# Fix Home and End keys on Solaris
if [[ "$OSTYPE" == "solaris"* ]] ; then
    bind '"\e[1~": beginning-of-line'
    bind '"\e[4~": end-of-line'
fi

# Disable bash deprecation warning on Catalina and up
if [[ "$OSTYPE" == "darwin"* ]] ; then
    export BASH_SILENCE_DEPRECATION_WARNING=1
fi

# Set default editor
if hash vim &>/dev/null ; then
    export EDITOR=vim
elif hash vi &>/dev/null ; then
    export EDITOR=vi
fi

# Set up GnuPG
if hash gpg &>/dev/null && hash gpgconf &>/dev/null ; then
    # Only configure local agent if no GPG agent is being forwarded via SSH
    SSHD_PIDS="$(ps -Ao pid=,comm= | awk '$2 ~ /sshd/ { print $1 }' | paste -sd , -)"
    if [[ -z "$SSHD_PIDS" ]] || ! lsof -a -U -F c -p "$SSHD_PIDS" -- "$(gpgconf --list-dir agent-socket 2>/dev/null)" 2>/dev/null | grep -q '^csshd' &>/dev/null ; then
        # Ensure socket directories exist
        if [[ ! -d "$(gpgconf --list-dirs socketdir 2>/dev/null)" ]] && ! gpgconf --list-dirs socketdir 2>/dev/null | grep -qE '^(/var)?/run/user/' ; then
            gpgconf --create-socketdir &>/dev/null
        fi

        # Forward to external agent on some platforms
        if hash okc-gpg &>/dev/null && echo "$SHELL" | grep -q com.termux &>/dev/null ; then
            # If inside Termux, use the OpenKeyChain agents
            alias gpg=okc-gpg
            if ! env | grep '^GIT_CONFIG_KEY_' | grep -q '=gpg.program$' &>/dev/null ; then
                export GIT_CONFIG_KEY_${GIT_CONFIG_COUNT:-0}=gpg.program
                export GIT_CONFIG_VALUE_${GIT_CONFIG_COUNT:-0}=okc-gpg
                export GIT_CONFIG_COUNT=$((${GIT_CONFIG_COUNT:-0} + 1))
            fi

            if hash okc-ssh-agent &>/dev/null && [[ -z "$SSH_AUTH_SOCK" || ! -S "$SSH_AUTH_SOCK" ]] ; then
                eval "$(okc-ssh-agent 2>/dev/null)" &>/dev/null
            fi
        elif hash wslpath &>/dev/null && [[ -x /mnt/c/Windows/System32/cmd.exe && -x /mnt/c/Windows/System32/wsl.exe ]] ; then
            # If inside WSL, try using forwarded sockets instead of running our own agents
            WSLVERSION="$(/mnt/c/Windows/System32/wsl.exe --list --verbose | tr -d '\0\r' | awk -v wdn="$WSL_DISTRO_NAME" '$1=="*"&&$2=wdn{print $4}')"
            USERPROFILE="$(wslpath -a "$(/mnt/c/Windows/System32/cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | sed -e 's/\r//g')" 2>/dev/null)"

            if [[ ! -S "$(gpgconf --list-dir agent-socket)" ]] ; then
                if hash socat &>/dev/null && [[ -x /mnt/c/Windows/wsl-relay.exe ]] ; then
                    # This uses https://github.com/Lexicality/wsl-relay
                    socat UNIX-LISTEN:"$(gpgconf --list-dir agent-socket)",unlink-early,unlink-close,fork EXEC:'/mnt/c/Windows/wsl-relay.exe --input-closes --pipe-closes --gpg',nofork &>/dev/null &
                    disown $!
                elif hash socat &>/dev/null && [[ -x /mnt/c/Windows/wsl2-ssh-bridge.exe ]] ; then
                    # Fallback to using https://github.com/KerickHowlett/wsl2-ssh-bridge
                    socat UNIX-LISTEN:"$(gpgconf --list-dir agent-socket)",unlink-early,unlink-close,fork EXEC:"/mnt/c/Windows/wsl2-ssh-bridge.exe --gpgConfigBasepath $USERPROFILE/AppData/Local/gnupg --gpg S.gpg-agent",nofork &>/dev/null &
                    disown $!
                fi
            fi

            if [[ -z "$SSH_AUTH_SOCK" || ! -S "$SSH_AUTH_SOCK" ]] ; then
                if [[ -S "$USERPROFILE/ssh-agent.sock" ]] ; then
                    # This uses https://github.com/benpye/wsl-ssh-pageant
                    # Add the following shortcut to your Windows startup:
                    # C:\Windows\wsl-ssh-pageant.exe --force --systray --winssh ssh-pageant --wsl %USERPROFILE%\ssh-agent.sock
                    if [[ "$WSLVERSION" == '1' ]] ; then
                        # Use the socket directly
                        export SSH_AUTH_SOCK="$USERPROFILE/ssh-agent.sock"
                    elif hash socat &>/dev/null && [[ -x /mnt/c/Windows/wsl-relay.exe ]] ; then
                        # Use the socket via https://github.com/Lexicality/wsl-relay
                        export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
                        socat UNIX-LISTEN:"$SSH_AUTH_SOCK",unlink-early,unlink-close,fork EXEC:'/mnt/c/Windows/wsl-relay.exe --input-closes //./pipe/ssh-pageant',nofork &>/dev/null &
                        disown $!
                    fi
                elif hash socat &>/dev/null && [[ -x /mnt/c/Windows/wsl2-ssh-bridge.exe ]] ; then
                    # Fallback to using https://github.com/KerickHowlett/wsl2-ssh-bridge
                    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
                    socat UNIX-LISTEN:"$SSH_AUTH_SOCK",unlink-early,unlink-close,fork EXEC:/mnt/c/Windows/wsl2-ssh-bridge.exe,nofork &>/dev/null &
                    disown $!
                fi
            fi
        else
            # Configure terminal GPG uses by default
            export GPG_TTY="$(tty)"

            # Ensure a local agent is running and update its default terminal
            gpg-connect-agent UPDATESTARTUPTTY /bye &>/dev/null &
            disown $!

            # Set up SSH agent support
            if [[ -z "$SSH_AUTH_SOCK" || ! -S "$SSH_AUTH_SOCK" ]] || echo "$SSH_AUTH_SOCK" | grep -q 'com.apple.launchd' ; then
                export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
            fi
        fi
    fi
    unset SSHD_PIDS
fi

# Load color scheme for ls
if hash dircolors &>/dev/null ; then
    if [[ -r ~/.dircolors ]] ; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi
fi

# Use colors in ls
if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "freebsd"* ]] ; then
    alias ls='ls -G'
else
    alias ls='ls --color=auto'
fi

# Use colors in grep
alias grep='grep --color=auto'

# Configure minicom: use Alt as Meta key, enable colors, enable linewrap
export MINICOM='-m -c on -w'

# Completion for our own tools
[[ -f ~/.couplingtools-complete.bash ]] && source ~/.couplingtools-complete.bash

# Set up the Android NDK and SDK if found
if [[ -d "/usr/local/share/android-ndk" ]] ; then
    [[ -z "$ANDROID_NDK_HOME" ]] && export ANDROID_NDK_HOME="/usr/local/share/android-ndk"
    [[ -z "$ANDROID_NDK_ROOT" ]] && export ANDROID_NDK_ROOT="/usr/local/share/android-ndk"
fi
if [[ -d "/usr/local/share/android-sdk" ]] ; then
    [[ -z "$ANDROID_SDK_HOME" ]] && export ANDROID_SDK_HOME="/usr/local/share/android-sdk"
    [[ -z "$ANDROID_SDK_ROOT" ]] && export ANDROID_SDK_ROOT="/usr/local/share/android-sdk"
fi

# Use all cores by default for make builds
hash nproc &>/dev/null && export MAKEFLAGS="-j$(nproc)"

# Alias for modern Docker Compose
if type docker &>/dev/null && docker compose version &>/dev/null ; then
    alias docker-compose="docker compose"
fi

# Use vi as an alias for vim
! hash vi &>/dev/null && hash vim &>/dev/null && alias vi=vim

# Dot file management
hash git &>/dev/null && [[ -d "$HOME/.dotgit" ]] && alias dotgit='git --git-dir="$HOME/.dotgit/" --work-tree="$HOME/"'

# Never run yay as root
if hash yay &>/dev/null && [[ "$(id -u)" == '0' ]] ; then
    yay() {
        echo >&2 'You should not run yay as root!'
    }
fi

# Convert codepage 437 characters used by nethack
if hash nethack &>/dev/null && hash luit &>/dev/null ; then
    alias nethack="luit -encoding 'CP437' nethack"
fi

# Function for sending stdin to the clipboard using a OSC52 escape sequence
if ! hash osc52-copy &>/dev/null ; then
    if hash base64 &>/dev/null ; then
        osc52-copy() {
            printf "\x1B]52;c;"
            cat "${1:--}" | base64 | tr -d '\r\n'
            printf "\x07"
        }
    elif hash uuencode &>/dev/null ; then
        osc52-copy() {
            printf "\x1B]52;c;i"
            cat "${1:--}" | uuencode -m - | sed '1d;$d' | tr -d '\r\n'
            printf "\x07"
        }
    elif hash openssl &>/dev/null ; then
        osc52-copy() {
            printf "\x1B]52;c;"
            cat "${1:--}" | openssl base64 -e | tr -d '\r\n'
            printf "\x07"
        }
    fi
fi

# Alias for QBS on macOS
if ! hash qbs &>/dev/null && [[ -x /Applications/Qt\ Creator.app/Contents/MacOS/qbs ]] ; then
    alias qbs="/Applications/Qt\ Creator.app/Contents/MacOS/qbs"
fi

# Make sure the last command we execute here is successful so we do not
# start each session with an prompt indicating the last command failed.
true
