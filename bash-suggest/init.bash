# bash-suggest: gray ghost suggestions + fuzzy list for bash.
# Install: put this as the LAST line of ~/.bashrc:
#   source ~/syshelp/bash-suggest/init.bash
# Off for one shell: BASH_SUGGEST=0 bash
#
# Outer shell: re-exec inside the bash-suggest wrapper (which starts a new
# interactive bash that reads ~/.bashrc again with BASH_SUGGEST=1).
# Inner shell: emit prompt markers, keep history and alias/function names fresh.
# Anything else (non-interactive, no tty, binary missing, BASH_SUGGEST set): no-op.

__bs_bin=${BASH_SUGGEST_BIN:-$HOME/syshelp/bash-suggest/target/release/bash-suggest}

if [[ $- == *i* && -z ${BASH_SUGGEST-} && -t 0 && -t 1 && -x $__bs_bin ]]; then
    exec "$__bs_bin"
fi

if [[ $- == *i* && ${BASH_SUGGEST-} == 1 ]]; then
    __bs_names=${XDG_RUNTIME_DIR:-/tmp}/bash-suggest.$$.names
    __bs_env=${XDG_RUNTIME_DIR:-/tmp}/bash-suggest.$$.env
    __bs_last_names=
    __bs_last_env=

    __bs_prompt() {
        local s=$?
        history -a
        # Re-wrap only when something (a prompt tool, the user) replaced PS1.
        [[ $PS1 == *'133;B'* ]] || PS1='\[\e]133;A\a\]'"$PS1"'\[\e]133;B\a\]'
        # Alias + function names; compgen -V (bash 5.3) avoids a fork per prompt.
        local -a __a __f
        if ((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 503)); then
            compgen -V __a -a
            compgen -V __f -A function
        else
            mapfile -t __a < <(compgen -a)
            mapfile -t __f < <(compgen -A function)
        fi
        local IFS=$'\n' cur
        cur="${__a[*]}"$'\n'"${__f[*]}"
        if [[ $cur != "$__bs_last_names" ]]; then
            printf '%s\n' "$cur" >"$__bs_names"
            __bs_last_names=$cur
        fi
        # HISTFILE and PATH are not visible to the wrapper (not exported / changed in bashrc).
        cur=${HISTFILE-}$'\n'$PATH
        if [[ $cur != "$__bs_last_env" ]]; then
            printf '%s\n' "$cur" >"$__bs_env"
            __bs_last_env=$cur
        fi
        return $s
    }

    # Runs last, after any prompt tool that rebuilds PS1. Keep a string a string:
    # arrays are not exported, and child programs (zoxide doctor) would lose it.
    if [[ ${PROMPT_COMMAND@a} == *a* ]]; then
        [[ " ${PROMPT_COMMAND[*]} " == *" __bs_prompt "* ]] || PROMPT_COMMAND+=(__bs_prompt)
    elif [[ ${PROMPT_COMMAND-} != *__bs_prompt* ]]; then
        __bs_pc=${PROMPT_COMMAND-}
        while [[ $__bs_pc == *[\;\ $'\n'] ]]; do __bs_pc=${__bs_pc%?}; done
        PROMPT_COMMAND=${__bs_pc:+$__bs_pc;}__bs_prompt
        unset __bs_pc
    fi
    [[ ${PS0-} == *'133;C'* ]] || PS0+='\e]133;C\a'
fi
unset __bs_bin
