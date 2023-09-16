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

# Customize environment
HISTSIZE=
HISTFILESIZE=
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
    export PS1="$TITLE$USER_COLOR\u$AT_COLOR@$HOST_COLOR\H$RESET_COLOR: $CHROOT$DIR_COLOR\w$RESET_COLOR$SCM$PYVENV\n$DOLLAR$BGJOBS "

    # (Re-)enable echo
    stty echo
}
export -f prompt_command
export PROMPT_COMMAND='prompt_command'

# The various non-Bash shells don't not support colours and prompt commands, thus we set a simplified PS1 when calling them
if hash sh &>/dev/null && [[ "$(which sh)" != "$SHELL" ]] ; then
    if [[ "$OSTYPE" == "solaris"* ]] ; then
        # Korn (ksh)
        alias sh="PS1=\"\\\$(echo \\\"\\\${LOGNAME}@\\\$(cat /etc/hostname): \\\${PWD/~(El)\\\${HOME}/\\\~}\\\" && [[ \\\"\\\$LOGNAME\\\" == 'root' ]] && print -n '# ' || print -n '$ ')\" sh"
    elif [[ "$OSTYPE" == "freebsd"* ]] ; then
        # Almquist (ash)
        alias sh="PS1=\"\\u@\\H: \\w \\$ \" sh"
    else
        # Debian Almquist (dash)
        alias sh="PS1=\"\\\$(echo \\\"\\\${LOGNAME}@\\\$(cat /etc/hostname): \\\${PWD}\\\" && \\\$(which test) \\\"\\\${LOGNAME}\\\" == 'root' && echo -n '# ' || echo -n '$ ')\" sh"
    fi
fi
hash zsh &>/dev/null && alias zsh="PS1=\"%B%(!.%F{red}.%F{green})%n%f%b@%B%F{green}%M%f%b: %B%F{blue}%~%f%b"$'\n'"%B%(?.%F{green}.%F{red})%#%f%b \" zsh"

# Add directories to path
for DIR in {/usr/local,/opt/homebrew}/{sbin,bin} $HOME/{.local,.cargo,go}/bin ; do
    [[ -d "$DIR" && ":$PATH:" != *":$DIR:"* ]] && export PATH="$PATH:$DIR"
done

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

# Load bash aliases
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases

# Make less more friendly for non-text input files
hash lesspipe &>/dev/null && eval "$(SHELL=/bin/sh lesspipe)"

# Load thefuck
hash thefuck &>/dev/null && eval "$(thefuck --alias)"

# Load fuzzy finder
if [[ -f ~/.fzf.bash ]] ; then
    source ~/.fzf.bash
else
    if [[ -f /usr/share/fzf/key-bindings.bash ]] ; then
        source /usr/share/fzf/key-bindings.bash
    elif [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]] ; then
        source /usr/share/doc/fzf/examples/key-bindings.bash
    elif [[ -f /usr/local/opt/fzf/shell/key-bindings.bash ]] ; then
        source /usr/local/opt/fzf/shell/key-bindings.bash
    elif [[ -f /opt/homebrew/opt/fzf/shell/key-bindings.bash ]] ; then
        source /opt/homebrew/opt/fzf/shell/key-bindings.bash
    fi
    if [[ -f /usr/share/fzf/completion.bash ]] ; then
        source /usr/share/fzf/key-bindings.bash
    elif [[ -f /usr/share/doc/fzf/examples/completion.bash ]] ; then
        source /usr/share/doc/fzf/examples/completion.bash
    elif [[ -f /usr/local/opt/fzf/shell/completion.bash ]] ; then
        source /usr/local/opt/fzf/shell/completion.bash
    elif [[ -f /opt/homebrew/opt/fzf/shell/completion.bash ]] ; then
        source /opt/homebrew/opt/fzf/shell/completion.bash
    fi
fi

# Load wormhole-william
if hash wormhole-william &>/dev/null ; then
    source <(wormhole-william shell-completion bash)
    if ! hash wormhole &>/dev/null ; then
        alias wormhole=wormhole-william
        source <(wormhole-william shell-completion bash | sed 's/wormhole-william/wormhole/g')
    fi
fi

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
    # Only run a local agent if no GPG agent is being forwarded
    if ! lsof -a -U -F c -- "$(gpgconf --list-dir agent-socket 2>/dev/null)" 2>/dev/null | grep -q ' ^csshd' &>/dev/null ; then
        # Ensure socket directories exist
        if [[ ! -d "$(gpgconf --list-dirs socketdir 2>/dev/null)" ]] && ! gpgconf --list-dirs socketdir 2>/dev/null | grep -qE '^(/var)?/run/user/' ; then
            gpgconf --create-socketdir &>/dev/null
        fi

        # If inside WSL, try using forwarded sockets instead of running our own agents
        if hash wslpath &>/dev/null && [[ -x /mnt/c/Windows/System32/cmd.exe ]] ; then
            USERPROFILE="$(wslpath -a "$(/mnt/c/Windows/System32/cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | sed -e 's/\r//g')" 2>/dev/null)"

            # This uses https://github.com/Lexicality/wsl-relay
            if hash socat &>/dev/null && [[ -x /mnt/c/Windows/wsl-relay.exe ]] ; then
                if [[ ! -S "$(gpgconf --list-dir agent-socket)" ]] ; then
                    socat UNIX-LISTEN:"$(gpgconf --list-dir agent-socket)",fork EXEC:'wsl-relay.exe --input-closes --pipe-closes --gpg',nofork &>/dev/null &
                    disown $!
                fi
            fi

            # This uses https://github.com/benpye/wsl-ssh-pageant
            # Add the following shortcut to your Windows startup:
            # C:\Windows\wsl-ssh-pageant.exe --force --systray --winssh ssh-pageant --wsl %USERPROFILE%\ssh-agent.sock
            if [[ -z "$SSH_AUTH_SOCK" ]] && [[ -f "$USERPROFILE/ssh-agent.sock" ]] ; then
                export SSH_AUTH_SOCK="$USERPROFILE/ssh-agent.sock"
            fi
        else
            # Ensure a local agent is running
            if gpgconf --launch gpg-agent &>/dev/null ; then
                # Configure GPG terminal
                if [[ -z "$GPG_TTY" ]] ; then
                    export GPG_TTY="$(tty)"
                elif [[ ! -c "$GPG_TTY" ]] ; then
                    echo UPDATESTARTUPTTY | gpg-connect-agent &>/dev/null
                fi

                # Set up SSH agent support
                if [[ -z "$SSH_AUTH_SOCK" ]] || echo "$SSH_AUTH_SOCK" | grep -q 'com.apple.launchd' ; then
                    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
                fi
            fi
        fi
    fi
fi

# Set up default locale
[[ -n "$LC_ALL" ]] || export LC_ALL=en_US.UTF-8
[[ -n "$LANG" ]] || export LANG=en_US.UTF-8

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

# Make sure the last command we execute here is successful so we do not
# start each session with an prompt indicating the last command failed.
true
