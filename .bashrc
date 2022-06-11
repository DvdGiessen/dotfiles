#!/bin/bash

# Only run on interactive shells
[[ -z "$PS1" ]] && return
[[ "$-" == *"i"* ]] || return

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
    stty rows "$LINES" columns "$COLUMNS" 2>/dev/null
fi

# Customize environment
shopt -s checkwinsize cdspell extglob histappend
export HISTSIZE=500000
export HISTFILESIZE=1000000
export HISTCONTROL=ignoreboth
export HISTIGNORE='[bf]g:clear:history:ls:ls -la:pwd:exit:quit'

# Customize prompt
prompt_command() {
    local EXIT_STATUS=$?

    # Show if we have any running jobs in the background
    # Do this before anything else, so the output from $(jobs) isn't poluted by this script
    local BGJOBS=""
    if [[ -n "$(jobs)" ]]; then
        BGJOBS=" (bg:\j)"
    fi

    # Determine color based on zone and user
    local NO_COLOR=""
    local USER_COLOR=""
    local AT_COLOR=""
    local HOST_COLOR=""
    local CHROOT_COLOR=""
    local DIR_COLOR=""
    local SCM_COLOR=""
    local PYVENV_COLOR=""
    local BGJOBS_COLOR=""
    local DOLLAR_COLOR=""
    if [[ -n "$(tput colors)" ]] ; then
        NO_COLOR="\[\e[m\]"
        if command -v zonename >/dev/null && [[ "$(zonename)" == "global" ]] ; then
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
        if [[ "$EXIT_STATUS" -ne 0 ]]; then
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
        CHROOT="$CHROOT_COLOR$CHROOT$NO_COLOR"
    fi

    # Show versioning info in prompt
    local SCM=""
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-working-tree >/dev/null 2>&1 && git rev-parse --abbrev-ref HEAD &> /dev/null ; then
        SCM=" $SCM_COLOR<$(git rev-parse --abbrev-ref HEAD)>$NO_COLOR"
    fi

    # Show current Python virtual environment
    local PYVENV=""
    if [[ -n "$VIRTUAL_ENV" ]] ; then
        PYVENV=" $PYVENV_COLOR($(basename "$VIRTUAL_ENV"))$NO_COLOR"
    fi

    # Colorize all variables
    if [[ -n "$BGJOBS" ]] ; then
        BGJOBS="$BGJOBS_COLOR$BGJOBS$NO_COLOR"
    fi

    # Color the prompt based on exit status of the last command
    local DOLLAR="$DOLLAR_COLOR\\\$$NO_COLOR"

    # If this is an xterm also set the title
    local TITLE=""
    if [[ "$TERM" == "xterm"* ]] || [[ "$TERM" == "rxvt"* ]] ; then
        TITLE="\[\e]0;\u@\H: $NOCOLOR_CHROOT\w\a\]"
    fi

    # Putting it all together
    export PS1="$TITLE$USER_COLOR\u$AT_COLOR@$HOST_COLOR\H$NO_COLOR: $CHROOT$DIR_COLOR\w$NO_COLOR$SCM$PYVENV\n$DOLLAR$BGJOBS "
}
export -f prompt_command
export PROMPT_COMMAND='prompt_command'

# The various non-Bash shells don't not support colours and prompt commands, thus we set a simplified PS1 when calling it
if [[ "$OSTYPE" == "solaris"* ]] ; then
    # Korn (ksh)
    alias sh="PS1=\"\\\$(echo \\\"\\\${LOGNAME}@\\\$(hostname): \\\${PWD/~(El)\\\${HOME}/\\\~}\\\" && [[ \\\"\\\$LOGNAME\\\" == 'root' ]] && print -n '# ' || print -n '$ ')\" sh"
elif [[ "$OSTYPE" == "freebsd"* ]] ; then
    # Almquist (ash)
    alias sh="PS1=\"\\u@\\H: \\w \\$ \" sh"
else
    # Debian Almquist (dash)
    alias sh="PS1=\"\\\$(echo \\\"\\\${LOGNAME}@\\\$(hostname): \\\${PWD}\\\" && \\\$(which test) \\\"\\\${LOGNAME}\\\" == 'root' && echo -n '# ' || echo -n '$ ')\" sh"
fi

# Load bash completion
if ! shopt -oq posix; then
    if [[ -f /usr/share/bash-completion/bash_completion ]] ; then
        source /usr/share/bash-completion/bash_completion
    elif [[ -f /etc/bash_completion ]] ; then
        source /etc/bash_completion
    fi
fi

# Load bash completion for Homebrew
if type brew &>/dev/null ; then
    HOMEBREW_PREFIX="$(brew --prefix)"
    if [[ -r "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" ]] ; then
        source "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh"
    else
        for COMPLETION in "${HOMEBREW_PREFIX}/etc/bash_completion.d/"* ; do
            [[ -r "${COMPLETION}" ]] && source "${COMPLETION}"
        done
    fi
fi

# Load bash aliases
[[ -f ~/.bash_aliases ]] && source ~/.bash_aliases

# Make less more friendly for non-text input files
[[ -x /usr/bin/lesspipe ]] && eval "$(SHELL=/bin/sh lesspipe)"

# Load thefuck
[[ -x "$(command -v thefuck)" ]] && eval "$(thefuck --alias)"

# Load fuzzy finder
if [[ -f ~/.fzf.bash ]] ; then
    source ~/.fzf.bash
else
    [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]] && source /usr/share/doc/fzf/examples/key-bindings.bash
    [[ -f /usr/share/doc/fzf/examples/completion.bash ]] && source /usr/share/doc/fzf/examples/completion.bash
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

# Load color scheme for ls
if [[ -x /usr/bin/dircolors ]]; then
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

# Completion for our own tools
[[ -f ~/.couplingtools-complete.bash ]] && source ~/.couplingtools-complete.bash

# Add ~/.local/bin to PATH (i.e. for pipx)
[[ -d "$HOME/.local/bin" ]] && export PATH="$PATH:$HOME/.local/bin"

# Use all cores by default for make builds
[[ -x "$(command -v nproc)" ]] && export MAKEFLAGS="-j$(nproc)"

# Dot file management
alias dotgit="$(which git)"' --git-dir="$HOME/.dotgit/" --work-tree="$HOME/"'
